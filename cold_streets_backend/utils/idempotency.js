const { createHash } = require('node:crypto');
const { ActionError } = require('./economyValidation');

const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function requireIdempotencyKey(req) {
    const raw = req.get('Idempotency-Key');
    if (typeof raw !== 'string' || !UUID_PATTERN.test(raw)) {
        throw new ActionError(400, 'A valid Idempotency-Key UUID is required.');
    }
    return raw.toLowerCase();
}

function stableSerialize(value) {
    if (value === null || typeof value === 'string' ||
        typeof value === 'number' || typeof value === 'boolean') {
        return JSON.stringify(value);
    }
    if (Array.isArray(value)) {
        return '[' + value.map(stableSerialize).join(',') + ']';
    }
    if (value && typeof value === 'object') {
        const keys = Object.keys(value).sort();
        return '{' + keys.map(key =>
            JSON.stringify(key) + ':' + stableSerialize(value[key])
        ).join(',') + '}';
    }
    throw new Error('Unsupported idempotency payload value.');
}

function requestHash(payload) {
    return createHash('sha256').update(stableSerialize(payload)).digest('hex');
}

// Call only after the authenticated player's row is locked. This keeps the
// global lock order consistent: player -> idempotency -> action resources.
async function beginIdempotent(client, userId, scope, key, payload) {
    const hash = requestHash(payload);
    const inserted = await client.query(
        `INSERT INTO economic_idempotency
           (user_id, action_scope, idempotency_key, request_hash)
         VALUES ($1, $2, $3::uuid, $4)
         ON CONFLICT DO NOTHING
         RETURNING user_id`,
        [userId, scope, key, hash]
    );
    if (inserted.rowCount === 1) {
        return { replay: false, userId, scope, key, hash };
    }

    const existing = await client.query(
        `SELECT request_hash, response_status, response_json, completed_at
           FROM economic_idempotency
          WHERE user_id = $1 AND action_scope = $2
            AND idempotency_key = $3::uuid
          FOR UPDATE`,
        [userId, scope, key]
    );
    if (existing.rowCount !== 1) {
        throw new ActionError(409, 'Idempotency record could not be resolved.');
    }
    const row = existing.rows[0];
    if (row.request_hash !== hash) {
        throw new ActionError(409, 'Idempotency-Key was already used with different request data.');
    }
    if (!row.completed_at || row.response_status === null || row.response_json === null) {
        throw new ActionError(409, 'The original request is still incomplete.');
    }
    return {
        replay: true,
        status: Number(row.response_status),
        response: row.response_json
    };
}

async function completeIdempotent(client, context, status, response) {
    if (!context || context.replay) throw new Error('Cannot complete an idempotency replay.');
    if (!Number.isInteger(status) || status < 200 || status > 299) {
        throw new Error('Only successful economic responses may be committed to idempotency ledger.');
    }
    const updated = await client.query(
        `UPDATE economic_idempotency
            SET response_status = $1,
                response_json = $2::jsonb,
                completed_at = NOW()
          WHERE user_id = $3 AND action_scope = $4
            AND idempotency_key = $5::uuid
            AND request_hash = $6
            AND completed_at IS NULL
          RETURNING user_id`,
        [status, JSON.stringify(response), context.userId, context.scope,
         context.key, context.hash]
    );
    if (updated.rowCount !== 1) {
        throw new Error('Economic idempotency completion failed.');
    }
}

module.exports = {
    requireIdempotencyKey,
    beginIdempotent,
    completeIdempotent
};
