const { Pool } = require('pg');
require('dotenv').config();

function parsePort(value, fallback) {
    if (value === undefined || value === '') return fallback;
    if (!/^[0-9]+$/.test(value)) {
        throw new Error('DB_PORT must be an integer TCP port.');
    }
    const parsed = Number(value);
    if (!Number.isInteger(parsed) || parsed < 1 || parsed > 65535) {
        throw new Error('DB_PORT must be between 1 and 65535.');
    }
    return parsed;
}

// Use the Supabase Postgres connection pooler for a hosted Node backend.
// Credentials must stay on the server. Remote connections default to TLS.
const isRemote = Boolean(
    process.env.DB_HOST &&
    process.env.DB_HOST !== 'localhost' &&
    process.env.DB_HOST !== '127.0.0.1'
);

let tlsEnabled;
if (process.env.DB_SSL === undefined || process.env.DB_SSL === '') {
    tlsEnabled = isRemote;
} else if (process.env.DB_SSL === 'true') {
    tlsEnabled = true;
} else if (process.env.DB_SSL === 'false') {
    tlsEnabled = false;
} else {
    throw new Error('DB_SSL must be exactly true or false when set.');
}

if (process.env.NODE_ENV === 'production' && !tlsEnabled) {
    throw new Error('Production PostgreSQL connections require DB_SSL=true.');
}

const pool = new Pool({
    user: process.env.DB_USER,
    password: process.env.DB_PASSWORD,
    host: process.env.DB_HOST,
    port: parsePort(process.env.DB_PORT, 5432),
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
    max: 10,
    maxUses: 5000,
    maxLifetimeSeconds: 300,
    keepAlive: true,
    keepAliveInitialDelayMillis: 10000,
    application_name: 'cold-streets-api'
});

module.exports = pool;
