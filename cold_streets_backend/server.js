const express = require('express');
const cors = require('cors');
const http = require('node:http');
const pool = require('./db');
const { requireAuthenticatedPlayer } = require('./middleware/playerIdentity');
const requestObservability = require('./middleware/requestObservability');
const { mutationContract } = require('./middleware/mutationContract');
const logger = require('./utils/logger');
const runtimeHealth = require('./utils/runtimeHealth');
const { startStateDurationWorker } = require('./workers/stateDurationWorker');

require('dotenv').config();

const app = express();
app.disable('x-powered-by');
app.disable('etag');
app.set('query parser', 'simple');

const gameplayEnabled = process.env.ENABLE_GAMEPLAY_API === 'true';
runtimeHealth.configure({ gameplayEnabled });

pool.on('error', err => {
    runtimeHealth.markDatabaseFailure();
    logger.error('database_pool_error', logger.errorFields(err));
});

app.use(requestObservability);

app.use((_req, res, next) => {
    res.setHeader('Cache-Control', 'no-store');
    res.setHeader('Pragma', 'no-cache');
    res.setHeader('X-Content-Type-Options', 'nosniff');
    res.setHeader('X-Frame-Options', 'DENY');
    res.setHeader('Referrer-Policy', 'no-referrer');
    res.setHeader(
        'Content-Security-Policy',
        "default-src 'none'; frame-ancestors 'none'; base-uri 'none'"
    );
    res.setHeader(
        'Permissions-Policy',
        'camera=(), microphone=(), geolocation=()'
    );
    if (process.env.NODE_ENV === 'production') {
        res.setHeader(
            'Strict-Transport-Security',
            'max-age=31536000'
        );
    }
    return next();
});

// Browser origins must be explicitly allowlisted. Native Flutter requests do not
// carry an Origin header. Do not expose a wildcard credentialed CORS policy.
const allowedOrigins = new Set((process.env.CORS_ALLOWED_ORIGINS || '')
  .split(',').map(origin => origin.trim()).filter(Boolean));
app.use(cors({
    origin(origin, callback) {
        if (!origin || allowedOrigins.has(origin)) return callback(null, true);
        return callback(null, false);
    },
    methods: ['GET', 'POST', 'OPTIONS'],
    allowedHeaders: [
        'Content-Type',
        'Authorization',
        'Idempotency-Key',
        'X-Request-Id'
    ],
    exposedHeaders: ['X-Request-Id'],
    credentials: false,
    maxAge: 600,
    optionsSuccessStatus: 204
}));
app.use(express.json({
    limit: '64kb',
    strict: true,
    type: ['application/json', 'application/*+json']
}));

// Liveness proves only that the Node process/listener is alive. It deliberately
// does not touch Postgres or reveal gameplay configuration details.
app.get('/healthz', (_req, res) => {
    return res.status(200).json({ status: 'ok' });
});

// Readiness is separate from liveness. When gameplay is intentionally disabled,
// the health-only process is considered ready. When gameplay is enabled, the
// database must answer and every currently enabled authoritative worker must be healthy.
app.get('/readyz', async (req, res) => {
    let databaseProbeOk = null;

    if (gameplayEnabled) {
        let readinessClient;
        let readinessTransaction = false;
        try {
            readinessClient = await pool.connect();
            await readinessClient.query('BEGIN');
            readinessTransaction = true;
            await readinessClient.query("SET LOCAL statement_timeout = '2s'");
            await readinessClient.query("SET LOCAL lock_timeout = '1s'");
            await readinessClient.query('SELECT 1');
            await readinessClient.query('ROLLBACK');
            readinessTransaction = false;

            runtimeHealth.markDatabaseReady();
            databaseProbeOk = true;
        } catch (err) {
            if (readinessClient && readinessTransaction) {
                try { await readinessClient.query('ROLLBACK'); }
                catch (_) {}
            }
            runtimeHealth.markDatabaseFailure();
            databaseProbeOk = false;
            logger.warn('readiness_database_probe_failed', {
                request_id: req.requestId,
                ...logger.errorFields(err)
            });
        } finally {
            if (readinessClient) readinessClient.release();
        }
    }

    const snapshot = runtimeHealth.snapshot();
    const ready = gameplayEnabled
        ? snapshot.ready && databaseProbeOk === true
        : snapshot.ready;

    const workerReadiness = {};
    for (const [name, worker] of Object.entries(snapshot.workers || {})) {
        workerReadiness[name] = {
            started: worker.started === true,
            healthy: worker.healthy === true
        };
    }

    return res.status(ready ? 200 : 503).json({
        status: ready ? 'ready' : 'not_ready',
        gameplay_enabled: snapshot.gameplay_enabled,
        shutting_down: snapshot.shutting_down,
        database_ready: snapshot.database_ready,
        workers: workerReadiness
    });
});

// All application routes, including profile provisioning, remain closed unless
// the operator explicitly enables the reviewed gameplay API.
app.use((req, res, next) => {
    if (!gameplayEnabled) {
        return res.status(503).json({
            error: 'Cold Streets API is disabled pending security review.'
        });
    }
    return next();
});

// Apply bounded backpressure before authentication or gameplay handlers can add
// more PostgreSQL work to an already saturated pool.
const MAX_DB_WAITING_REQUESTS = 20;
app.use((req, res, next) => {
    if (pool.waitingCount < MAX_DB_WAITING_REQUESTS) return next();

    res.setHeader('Retry-After', '1');
    logger.warn('database_pool_backpressure', {
        request_id: req.requestId,
        waiting_count: pool.waitingCount,
        total_clients: pool.totalCount,
        idle_clients: pool.idleCount
    });
    return res.status(503).json({
        error: 'Server is temporarily busy. Retry shortly.'
    });
});

// Any active mutation must be registered with an explicit top-level JSON field
// allowlist. Unknown mutation routes fail closed.
app.use(mutationContract);

let workerHandles = [];
let gameplayRuntimeStarted = false;
let gameplayRuntimeStarting = false;
let workerBootstrapRetryTimer = null;
let shutdownStarted = false;

async function bootstrapGameplayRuntime() {
    if (
        !gameplayEnabled ||
        gameplayRuntimeStarted ||
        gameplayRuntimeStarting ||
        shutdownStarted
    ) {
        return;
    }

    gameplayRuntimeStarting = true;
    let client;
    try {
        client = await pool.connect();
        client.release();
        client = null;

        runtimeHealth.markDatabaseReady();

        const stateWorker = startStateDurationWorker();
        workerHandles = [stateWorker];
        gameplayRuntimeStarted = true;

        logger.info('gameplay_runtime_bootstrap_ready', {
            workers: workerHandles.map(handle => handle.name).join(',')
        });
    } catch (err) {
        if (client) client.release();

        runtimeHealth.markDatabaseFailure();
        logger.error(
            'gameplay_runtime_bootstrap_failed',
            logger.errorFields(err)
        );

        if (!shutdownStarted && !workerBootstrapRetryTimer) {
            workerBootstrapRetryTimer = setTimeout(() => {
                workerBootstrapRetryTimer = null;
                void bootstrapGameplayRuntime();
            }, 5000);
            if (typeof workerBootstrapRetryTimer.unref === 'function') {
                workerBootstrapRetryTimer.unref();
            }
        }
    } finally {
        gameplayRuntimeStarting = false;
    }
}

if (gameplayEnabled) {
    const required = [
        'SUPABASE_URL',
        'SUPABASE_PUBLISHABLE_KEY',
        'DB_HOST',
        'DB_USER',
        'DB_PASSWORD',
        'DB_NAME'
    ];
    const missing = required.filter(name => !process.env[name]);
    if (missing.length) {
        throw new Error(
            'Cannot enable game API: missing server configuration ' +
            missing.join(', ')
        );
    }
    if (process.env.NODE_ENV === 'production' && process.env.DB_SSL === 'false') {
        throw new Error('Remote staging requires encrypted database connections.');
    }

    void bootstrapGameplayRuntime();
}

// --- MODULAR ROUTERS ---
const checkPlayerState = require('./utils/stateGatekeeper');

// Supabase profile establishment is authenticated inside the auth router.
app.use('/auth', require('./routes/auth'));

// Fail closed for all other gameplay routes.
app.use(requireAuthenticatedPlayer);

app.use('/inventory', require('./routes/inventory'));
app.use('/info-broker', require('./routes/infoBroker'));
app.use('/cityhall', require('./routes/cityhall'));
app.use('/events', require('./routes/events'));
app.use('/jail', require('./routes/jail'));
app.use('/hospital', require('./routes/hospital'));
app.use('/university', require('./routes/university'));
app.use('/bank', require('./routes/bank'));
app.use('/achievements', require('./routes/achievements'));
app.use('/missions', require('./routes/missions'));
app.use('/trade-network', require('./routes/trade_network'));
app.use('/premium', require('./routes/premium'));

// Any route below this line is blocked while the authenticated player is in a
// source-backed Jail/Hospital state unless explicitly allowed by the gatekeeper.
app.use(checkPlayerState);

app.use('/character', require('./routes/character'));
app.use('/crimes', require('./routes/crimes'));
app.use('/market', require('./routes/market'));
app.use('/syndicate', require('./routes/syndicate'));
app.use('/gym', require('./routes/gym'));
app.use('/jobs', require('./routes/jobs'));

// Mount the specific audit route before the generic companies router so no
// future parameterized company route can shadow it.
app.use(
    '/companies/supply-chain-audit',
    require('./routes/company_supply_chain_audit')
);
app.use('/companies', require('./routes/companies'));
app.use('/company-management', require('./routes/company_management'));
app.use('/credit-broker', require('./routes/credit_broker'));
app.use('/real-estate', require('./routes/realEstate'));
app.use('/casino', require('./routes/casino'));

// Legacy single-process Vital/market timers are permanently retired.
if (process.env.ENABLE_UNSAFE_LEGACY_TIMERS === 'true') {
    throw new Error(
        'ENABLE_UNSAFE_LEGACY_TIMERS is retired. Legacy Vital/restock writers cannot be enabled.'
    );
}

// Explicit JSON 404 and final error boundary. Never return stack traces,
// database errors, tokens, request bodies, or private player data.
app.use((req, res) => {
    return res.status(404).json({ error: 'Route not found.' });
});

app.use((err, req, res, _next) => {
    logger.error('unhandled_request_error', {
        request_id: req.requestId,
        ...logger.errorFields(err)
    });
    const candidate = Number(err?.status || err?.statusCode);
    const status = Number.isInteger(candidate) && candidate >= 400 && candidate < 500
        ? candidate
        : 500;
    return res.status(status).json({
        error: status === 400
            ? 'Invalid request.'
            : status === 413
                ? 'Request body is too large.'
                : 'Internal server error.'
    });
});

const PORT = process.env.PORT || 3000;
let server = null;

async function shutdown(signal, exitCode = 0) {
    if (shutdownStarted) return;
    shutdownStarted = true;
    runtimeHealth.markShuttingDown();

    logger.info('shutdown_started', { signal });

    if (workerBootstrapRetryTimer) {
        clearTimeout(workerBootstrapRetryTimer);
        workerBootstrapRetryTimer = null;
    }

    for (const handle of workerHandles) {
        if (handle?.timer) clearInterval(handle.timer);
        if (handle?.name) runtimeHealth.markWorkerStopped(handle.name);
    }

    const forceTimer = setTimeout(() => {
        logger.error('shutdown_forced', { signal });
        process.exit(1);
    }, 25000);
    if (typeof forceTimer.unref === 'function') forceTimer.unref();

    const finish = async (serverError) => {
        let finalCode = serverError ? 1 : exitCode;
        if (serverError) {
            logger.error('listener_close_failed', logger.errorFields(serverError));
        }
        try {
            await pool.end();
        } catch (err) {
            finalCode = 1;
            logger.error('database_pool_close_failed', logger.errorFields(err));
        }
        clearTimeout(forceTimer);
        logger.info('shutdown_complete', { signal, exit_code: finalCode });
        process.exit(finalCode);
    };

    if (server) {
        server.close(error => {
            void finish(error);
        });
    } else {
        await finish(null);
    }
}

process.once('SIGTERM', () => {
    void shutdown('SIGTERM', 0);
});
process.once('SIGINT', () => {
    void shutdown('SIGINT', 0);
});
process.once('uncaughtException', err => {
    logger.error('uncaught_exception', logger.errorFields(err));
    void shutdown('uncaughtException', 1);
});
process.once('unhandledRejection', reason => {
    const error = reason instanceof Error ? reason : new Error(String(reason));
    logger.error('unhandled_rejection', logger.errorFields(error));
    void shutdown('unhandledRejection', 1);
});

server = http.createServer({
    maxHeaderSize: 16 * 1024,
    headersTimeout: 10000,
    requestTimeout: 20000,
    keepAliveTimeout: 5000,
    connectionsCheckingInterval: 5000,
    requireHostHeader: true
}, app);

server.maxHeadersCount = 100;
server.maxRequestsPerSocket = 500;
server.setTimeout(30000, socket => {
    socket.destroy();
});

server.listen(PORT, '0.0.0.0', () => {
    logger.info('listener_started', {
        port: Number(PORT),
        gameplay_enabled: gameplayEnabled
    });
});
