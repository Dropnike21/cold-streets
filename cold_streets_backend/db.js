const { Pool } = require('pg');
require('dotenv').config();

// Use the Supabase Postgres connection pooler for a hosted Node backend.
// Credentials must stay on the server. DB_SSL=true requires verified TLS;
// DB_SSL=false is suitable only for a trusted local development database.
const isRemote = Boolean(process.env.DB_HOST && process.env.DB_HOST !== 'localhost' && process.env.DB_HOST !== '127.0.0.1');
const tlsEnabled = process.env.DB_SSL === 'true' ||
    (process.env.DB_SSL === undefined && isRemote);

// Keep the application pool deliberately small when using Supabase's shared
// pooler. Once all clients are checked out, node-postgres queues pool.connect()
// calls in memory. The HTTP layer sheds new gameplay requests before that queue
// can grow without bound.
const DB_POOL_MAX = 10;
const DB_POOL_MAX_WAITING = 20;

const pool = new Pool({
    user: process.env.DB_USER,
    password: process.env.DB_PASSWORD,
    host: process.env.DB_HOST,
    port: process.env.DB_PORT ? Number(process.env.DB_PORT) : 5432,
    database: process.env.DB_NAME || 'postgres',
    ssl: tlsEnabled ? { rejectUnauthorized: true } : false,

    // Bound pool acquisition, server execution, lock waits, and abandoned
    // transactions independently. Statement timeout is deliberately shorter
    // than the client-side query timeout so PostgreSQL gets the first chance
    // to cancel work cleanly.
    connectionTimeoutMillis: 5000,
    statement_timeout: 15000,
    query_timeout: 20000,
    lock_timeout: 5000,
    idle_in_transaction_session_timeout: 15000,

    idleTimeoutMillis: 30000,
    max: DB_POOL_MAX,
    maxUses: 5000,
    maxLifetimeSeconds: 300,
    keepAlive: true,
    keepAliveInitialDelayMillis: 10000,
    application_name: 'cold-streets-api'
});

function capacitySnapshot() {
    return {
        total: pool.totalCount,
        idle: pool.idleCount,
        waiting: pool.waitingCount,
        max: DB_POOL_MAX,
        waiting_limit: DB_POOL_MAX_WAITING
    };
}

function isOverloaded() {
    return pool.totalCount >= DB_POOL_MAX &&
        pool.idleCount === 0 &&
        pool.waitingCount >= DB_POOL_MAX_WAITING;
}

// Preserve the historical `require('./db') -> Pool` contract while exposing a
// small, read-only operational surface for readiness/load shedding.
Object.defineProperties(pool, {
    coldStreetsCapacity: {
        value: Object.freeze({ capacitySnapshot, isOverloaded }),
        enumerable: false,
        writable: false,
        configurable: false
    }
});

module.exports = pool;
