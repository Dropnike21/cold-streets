const { Pool } = require('pg');
require('dotenv').config();

// Use the Supabase Postgres connection pooler for a hosted Node backend.
// Credentials must stay on the server. DB_SSL=true requires verified TLS;
// DB_SSL=false is suitable only for a trusted local development database.
const isRemote = Boolean(process.env.DB_HOST && process.env.DB_HOST !== 'localhost' && process.env.DB_HOST !== '127.0.0.1');
const tlsEnabled = process.env.DB_SSL === 'true' ||
    (process.env.DB_SSL === undefined && isRemote);

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
    max: 10,
    maxUses: 5000,
    maxLifetimeSeconds: 300,
    keepAlive: true,
    keepAliveInitialDelayMillis: 10000,
    application_name: 'cold-streets-api'
});

module.exports = pool;
