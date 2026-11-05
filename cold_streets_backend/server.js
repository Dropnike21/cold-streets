const express = require('express');
const cors = require('cors');
const pool = require('./db');
const { requireAuthenticatedPlayer } = require('./middleware/playerIdentity');
const { startCrewCrimeWorker } = require('./workers/crewCrimeWorker');
const { startStateDurationWorker } = require('./workers/stateDurationWorker');

require('dotenv').config();

const app = express();

// Browser origins must be explicitly allowlisted. Native Flutter requests do not
// carry an Origin header. Do not expose a wildcard credentialed CORS policy.
const allowedOrigins = new Set((process.env.CORS_ALLOWED_ORIGINS || '')
  .split(',').map(origin => origin.trim()).filter(Boolean));
app.use(cors({
    origin(origin, callback) {
        if (!origin || allowedOrigins.has(origin)) return callback(null, true);
        return callback(null, false);
    },
    allowedHeaders: ['Content-Type', 'Authorization', 'Idempotency-Key']
}));
app.use(express.json({ limit: '64kb' }));

// All application routes, including profile provisioning, remain closed
// unless the operator explicitly enables the staging API after security review.
// /healthz is liveness-only and does not expose secrets or database state.
const gameplayEnabled = process.env.ENABLE_GAMEPLAY_API === 'true';
app.get('/healthz', (_req, res) => res.status(200).json({ status: 'ok' }));
app.use((_req, res, next) => {
    if (!gameplayEnabled) {
        return res.status(503).json({ error: 'Cold Streets API is disabled pending security review.' });
    }
    return next();
});

if (gameplayEnabled) {
    const required = ['SUPABASE_URL', 'SUPABASE_PUBLISHABLE_KEY',
        'DB_HOST', 'DB_USER', 'DB_PASSWORD', 'DB_NAME'];
    const missing = required.filter(name => !process.env[name]);
    if (missing.length) {
        throw new Error('Cannot enable game API: missing server configuration ' + missing.join(', '));
    }
    if (process.env.NODE_ENV === 'production' && process.env.DB_SSL === 'false') {
        throw new Error('Remote staging requires encrypted database connections.');
    }
    pool.connect()
      .then(client => {
          client.release();
          console.log('Cold Streets staging database connection established.');
          startCrewCrimeWorker();
          console.log('Crew crime scheduler started.');
          startStateDurationWorker();
          console.log('State duration telemetry worker started.');
      })
      .catch(err => console.error('Staging database connection failed:', err.message));
}

// --- MODULAR ROUTERS ---
const checkPlayerState = require('./utils/stateGatekeeper');

// 🟢 WHITELISTED ROUTES (Can be accessed anywhere)
app.use('/auth', require('./routes/auth'));

// Fail closed for ALL gameplay routes, including previously "whitelisted"
// menus (inventory, banking, jail, hospital, missions, etc.). A public route
// with a client-supplied player ID must never bypass verified authentication.
app.use(requireAuthenticatedPlayer);

app.use('/inventory', require('./routes/inventory')); // Allows using medical/lawyer items
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


// 🛑 THE STATE GATEKEEPER
// Any route placed below this line will be BLOCKED if the player is in Jail or Hospital.
app.use(checkPlayerState);

// 🔴 RESTRICTED ROUTES (Must be free to access)
app.use('/character', require('./routes/character'));
app.use('/crimes', require('./routes/crimes'));
app.use('/market', require('./routes/market'));
app.use('/syndicate', require('./routes/syndicate'));
app.use('/gym', require('./routes/gym')); // The normal gym
app.use('/jobs', require('./routes/jobs'));
// Mount the specific audit route before the generic companies router so no
// future parameterized company route can shadow it.
app.use('/companies/supply-chain-audit', require('./routes/company_supply_chain_audit'));
app.use('/companies', require('./routes/companies'));
app.use('/company-management', require('./routes/company_management'));
app.use('/credit-broker', require('./routes/credit_broker'));
app.use('/real-estate', require('./routes/realEstate'));
app.use('/casino', require('./routes/casino')); // This loads the hub!



// Legacy single-process Vital/market timers are permanently retired.
// Authoritative background mutation must use persisted, multi-replica-safe
// workers with row locking and source-reconciled settlement rules.
if (process.env.ENABLE_UNSAFE_LEGACY_TIMERS === 'true') {
    throw new Error(
        'ENABLE_UNSAFE_LEGACY_TIMERS is retired. Legacy Vital/restock writers cannot be enabled.'
    );
}

// Start Server
const PORT = process.env.PORT || 3000;
app.listen(PORT, '0.0.0.0', () => {
    console.log(`Cold Streets Node listener started on port ${PORT}; gameplay routes ${gameplayEnabled ? 'enabled' : 'disabled'}.`);
});