const express = require('express');
const cors = require('cors');
const pool = require('./db');
const { requireAuthenticatedPlayer } = require('./middleware/playerIdentity');
const requestObservability = require('./middleware/requestObservability');
const logger = require('./utils/logger');
const runtimeHealth = require('./utils/runtimeHealth');
const { startCrewCrimeWorker } = require('./workers/crewCrimeWorker');
const { startStateDurationWorker } = require('./workers/stateDurationWorker');

require('dotenv').config();

const app = express();
const gameplayEnabled = process.env.ENABLE_GAMEPLAY_API === 'true';
runtimeHealth.configure({ gameplayEnabled });

pool.on('error', err => {
    runtimeHealth.markDatabaseFailure();
    logger.error('database_pool_error', logger.errorFields(err));
});

app.use(requestObservability);

// Browser origins must be explicitly allowlisted. Native Flutter requests do not
// carry an Origin header. Do not expose a wildcard credentialed CORS policy.
const allowedOrigins = new Set((process.env.CORS_ALLOWED_ORIGINS || '')
  .split(',').map(origin => origin.trim()).filter(Boolean));
app.use(cors({
    origin(origin, callback) {
        if (!origin || allowedOrigins.has(origin)) return callback(null, true);
        return callback(null, false);
    },
    allowedHeaders: [
        'Content-Type',
        'Authorization',
        'Idempotency-Key',
        'X-Request-Id'
    ],
    exposedHeaders: ['X-Request-Id']
}));
app.use(express.json({ limit: '64kb' }));

// Liveness proves only that the Node process/listener is alive. It deliberately
// does not touch Postgres or reveal gameplay configuration details.
app.get('/healthz', (_req, res) => {
    return res.status(200).json({ status: 'ok' });
});

// Readiness is separate from liveness. When gameplay is intentionally disabled,
// the health-only process is considered ready. When gameplay is enabled, the
// database must answer and both authoritative workers must be started/healthy.
app.get('/readyz', async (req, res) => {
    let databaseProbeOk = null;

    if (gameplayEnabled) {
        try {
            await pool.query({
                text: 'SELECT 1',
                query_timeout: 2000
            });
            runtimeHealth.markDatabaseReady();
            databaseProbeOk = true;
        } catch (err) {
            runtimeHealth.markDatabaseFailure();
            databaseProbeOk = false;
            logger.warn('readiness_database_probe_failed', {
                request_id: req.requestId,
                ...logger.errorFields(err)
            });
        }
    }

    const snapshot = runtimeHealth.snapshot();
    const ready = gameplayEnabled
        ? snapshot.ready && databaseProbeOk === true
        : snapshot.ready;

    return res.status(ready ? 200 : 503).json({
        status: ready ? 'ready' : 'not_ready',
        ...snapshot
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

let workerHandles = [];

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

    pool.connect()
      .then(client => {
          client.release();
          runtimeHealth.markDatabaseReady();
          logger.info('database_bootstrap_ready');

          const crewWorker = startCrewCrimeWorker();
          const stateWorker = startStateDurationWorker();
          workerHandles = [crewWorker, stateWorker];

          logger.info('workers_started', {
              workers: workerHandles.map(handle => handle.name).join(',')
          });
      })
      .catch(err => {
          runtimeHealth.markDatabaseFailure();
          logger.error('database_bootstrap_failed', logger.errorFields(err));
      });
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
let shutdownStarted = false;

async function shutdown(signal, exitCode = 0) {
    if (shutdownStarted) return;
    shutdownStarted = true;
    runtimeHealth.markShuttingDown();

    logger.info('shutdown_started', { signal });

    for (const handle of workerHandles) {
        if (handle?.timer) clearInterval(handle.timer);
        if (handle?.name) runtimeHealth.markWorkerStopped(handle.name);
    }

    const forceTimer = setTimeout(() => {
        logger.error('shutdown_forced', { signal });
        process.exit(1);
    }, 10000);
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

server = app.listen(PORT, '0.0.0.0', () => {
    logger.info('listener_started', {
        port: Number(PORT),
        gameplay_enabled: gameplayEnabled
    });
});
