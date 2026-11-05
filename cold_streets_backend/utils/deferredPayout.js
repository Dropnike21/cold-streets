const { ActionError, integer } = require('./economyValidation');

const ISSUER_PATTERN = /^[a-z][a-z0-9_.-]{1,63}$/;
const SOURCE_REF_PATTERN = /^[A-Za-z0-9][A-Za-z0-9:._\/-]{0,190}$/;
const CURRENCIES = new Set(['dirty_cash', 'clean_cash']);

function nonemptyText(value, field, max) {
    if (typeof value !== 'string') {
        throw new ActionError(500, field + ' is missing.');
    }
    const text = value.trim();
    if (!text || text.length > max) {
        throw new ActionError(500, field + ' is invalid.');
    }
    return text;
}

function payoutCurrency(value) {
    if (!CURRENCIES.has(value)) {
        throw new ActionError(500, 'Deferred payout currency is unsupported.');
    }
    return value;
}

// Server-only helper. Call from the authoritative issuer transaction.
// The caller supplies values derived from server-owned settlement rules,
// never client-provided payout amounts or currencies.
async function issueDeferredPayout(client, {
    recipientUserId,
    issuerType,
    sourceRef,
    sourceLabel,
    amount,
    currency,
    expiresAt,
    metadata = {}
}) {
    const userId = integer(recipientUserId, {
        field: 'Deferred payout recipient',
        min: 1n,
        max: 9007199254740991n
    }).toString();

    const issuer = nonemptyText(issuerType, 'Deferred payout issuer type', 64);
    if (!ISSUER_PATTERN.test(issuer)) {
        throw new ActionError(500, 'Deferred payout issuer type is invalid.');
    }

    const ref = nonemptyText(sourceRef, 'Deferred payout source reference', 191);
    if (!SOURCE_REF_PATTERN.test(ref)) {
        throw new ActionError(500, 'Deferred payout source reference is invalid.');
    }

    const label = nonemptyText(sourceLabel, 'Deferred payout source label', 160);
    const exactAmount = integer(
        typeof amount === 'bigint' ? amount.toString() : amount,
        { field: 'Deferred payout amount', min: 1n }
    );

    const denomination = payoutCurrency(currency);

    if (!expiresAt || Number.isNaN(Date.parse(String(expiresAt)))) {
        throw new ActionError(500, 'Deferred payout expiry is invalid.');
    }
    if (!metadata || typeof metadata !== 'object' || Array.isArray(metadata)) {
        throw new ActionError(500, 'Deferred payout metadata must be an object.');
    }

    const inserted = await client.query(
        `INSERT INTO pending_checks (
            user_id, source, amount, expires_at, status,
            issuer_type, source_ref, payout_currency, metadata_jsonb
         )
         VALUES (
            $1, $2, $3::numeric, $4::timestamptz, 'pending',
            $5, $6, $7, $8::jsonb
         )
         ON CONFLICT (issuer_type, source_ref)
           WHERE source_ref IS NOT NULL
         DO NOTHING
         RETURNING id, user_id, source, amount, expires_at, status,
                   issuer_type, source_ref, payout_currency, created_at`,
        [
            userId,
            label,
            exactAmount.toString(),
            String(expiresAt),
            issuer,
            ref,
            denomination,
            JSON.stringify(metadata)
        ]
    );

    if (inserted.rowCount === 1) {
        return { issued: true, check: inserted.rows[0] };
    }

    const existing = await client.query(
        `SELECT id, user_id, source, amount, expires_at, status,
                issuer_type, source_ref, payout_currency, metadata_jsonb,
                created_at, claimed_at,
                (
                    user_id = $3
                    AND source = $4
                    AND amount = $5::numeric
                    AND expires_at = $6::timestamptz
                    AND payout_currency = $7
                    AND metadata_jsonb = $8::jsonb
                ) AS same_obligation
           FROM pending_checks
          WHERE issuer_type = $1 AND source_ref = $2
          FOR UPDATE`,
        [
            issuer,
            ref,
            userId,
            label,
            exactAmount.toString(),
            String(expiresAt),
            denomination,
            JSON.stringify(metadata)
        ]
    );

    if (existing.rowCount !== 1) {
        throw new ActionError(409, 'Deferred payout source could not be resolved.');
    }

    const row = existing.rows[0];
    if (row.same_obligation !== true) {
        throw new ActionError(
            409,
            'Deferred payout source reference already exists with different settlement data.'
        );
    }
    delete row.same_obligation;

    return { issued: false, check: row };
}

module.exports = {
    issueDeferredPayout,
    payoutCurrency
};
