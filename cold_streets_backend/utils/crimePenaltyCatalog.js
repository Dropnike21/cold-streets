const { ActionError } = require('./economyValidation');

function positiveCatalogInteger(value, field) {
    const raw = String(value ?? '').trim();
    if (!/^[0-9]+$/.test(raw)) {
        throw new ActionError(409, field + ' is missing or invalid in the crime catalog.');
    }
    const parsed = BigInt(raw);
    if (parsed <= 0n) {
        throw new ActionError(409, field + ' must be positive in the crime catalog.');
    }
    return raw;
}

function nonnegativeCatalogDecimal(value, field) {
    const raw = String(value ?? '').trim();
    if (!/^[0-9]+(?:\.[0-9]+)?$/.test(raw)) {
        throw new ActionError(409, field + ' is missing or invalid in the crime catalog.');
    }
    return raw;
}

function getCrimePenaltyRule(crime) {
    const penalties = crime?.penalties_json;
    if (!penalties || typeof penalties !== 'object' || Array.isArray(penalties)) {
        throw new ActionError(409, 'Crime penalty rules are missing from the catalog.');
    }
    return {
        heatGen: nonnegativeCatalogDecimal(penalties.heat_gen, 'Crime Heat generation'),
        jailSeconds: positiveCatalogInteger(penalties.jail_time, 'Crime jail time'),
        hospitalSeconds: positiveCatalogInteger(penalties.hosp_time, 'Crime hospital time')
    };
}

async function assertRequiredCrimeTool(client, userId, crime) {
    const reqs = crime?.requirements_json;
    if (reqs == null) return null;
    if (typeof reqs !== 'object' || Array.isArray(reqs)) {
        throw new ActionError(409, 'Crime requirements are malformed in the catalog.');
    }

    const raw = reqs.tool_req;
    if (raw == null || raw === '' || raw === 'NONE' || raw === 'NULL') return null;

    const itemId = positiveCatalogInteger(raw, 'Crime tool requirement');
    const result = await client.query(
        `SELECT im.item_id, im.name
           FROM items_master im
           JOIN user_inventory ui
             ON ui.item_id = im.item_id
            AND ui.user_id = $1
            AND ui.quantity > 0
          WHERE im.item_id = $2::bigint
          FOR UPDATE OF ui`,
        [userId, itemId]
    );
    if (result.rowCount !== 1) {
        const item = await client.query(
            'SELECT name FROM items_master WHERE item_id = $1::bigint',
            [itemId]
        );
        if (item.rowCount !== 1) {
            throw new ActionError(
                409,
                'Crime tool requirement points to a missing catalog item.'
            );
        }
        throw new ActionError(409, 'Required tool is not present in the player inventory.');
    }
    return { itemId, name: result.rows[0].name };
}

async function getFederalMaximumJailSeconds(client) {
    const result = await client.query(
        `SELECT COUNT(*) FILTER (
                    WHERE NOT (
                        penalties_json->>'jail_time' ~ '^[0-9]+$'
                        AND (penalties_json->>'jail_time')::bigint > 0
                    )
                )::bigint AS invalid_rows,
                MAX((penalties_json->>'jail_time')::bigint)
                    FILTER (
                        WHERE penalties_json->>'jail_time' ~ '^[0-9]+$'
                          AND (penalties_json->>'jail_time')::bigint > 0
                    ) AS max_jail_seconds
           FROM crimes_master`
    );
    if (result.rowCount !== 1 ||
        BigInt(result.rows[0].invalid_rows) !== 0n ||
        result.rows[0].max_jail_seconds == null) {
        throw new ActionError(
            409,
            'Federal arrest is paused because the crime jail catalog is incomplete.'
        );
    }
    return String(result.rows[0].max_jail_seconds);
}

async function applyFederalArrest(client, { userId, nerveCost }) {
    const jailSeconds = await getFederalMaximumJailSeconds(client);
    const result = await client.query(
        `UPDATE users
            SET nerve = nerve - $1::numeric,
                heat = 100,
                dirty_cash = 0,
                influence = GREATEST(0, influence - 50),
                jail_initial_seconds = $2::bigint,
                jail_expires_at = NOW() + ($2::bigint * INTERVAL '1 second'),
                hospital_expires_at = NULL,
                state_reason = 'Arrested by Federal Agents.'
          WHERE user_id = $3
          RETURNING dirty_cash, energy, nerve, max_nerve, hp, heat,
                    influence, jail_initial_seconds, jail_expires_at`,
        [String(nerveCost), jailSeconds, userId]
    );
    if (result.rowCount !== 1) throw new Error('Federal arrest target disappeared.');
    return result.rows[0];
}

async function applyCrimeHospitalization(client, {
    userId, nerveCost, heatGen, hospitalSeconds, reason
}) {
    const result = await client.query(
        `UPDATE users
            SET nerve = nerve - $1::numeric,
                hp = 1,
                heat = LEAST(heat + $2::numeric, 100),
                hospital_expires_at = NOW() + ($3::bigint * INTERVAL '1 second'),
                jail_expires_at = NULL,
                jail_initial_seconds = 0,
                state_reason = $4
          WHERE user_id = $5
          RETURNING dirty_cash, energy, nerve, max_nerve, hp, heat,
                    hospital_expires_at`,
        [String(nerveCost), heatGen, hospitalSeconds, reason, userId]
    );
    if (result.rowCount !== 1) throw new Error('Hospitalization target disappeared.');
    return result.rows[0];
}

async function applyCrimeJail(client, {
    userId, nerveCost, heatGen, jailSeconds, reason
}) {
    const result = await client.query(
        `UPDATE users
            SET nerve = nerve - $1::numeric,
                heat = LEAST(heat + $2::numeric, 100),
                jail_initial_seconds = $3::bigint,
                jail_expires_at = NOW() + ($3::bigint * INTERVAL '1 second'),
                hospital_expires_at = NULL,
                state_reason = $4
          WHERE user_id = $5
          RETURNING dirty_cash, energy, nerve, max_nerve, hp, heat,
                    jail_initial_seconds, jail_expires_at`,
        [String(nerveCost), heatGen, jailSeconds, reason, userId]
    );
    if (result.rowCount !== 1) throw new Error('Jail target disappeared.');
    return result.rows[0];
}

module.exports = {
    getCrimePenaltyRule,
    assertRequiredCrimeTool,
    getFederalMaximumJailSeconds,
    applyFederalArrest,
    applyCrimeHospitalization,
    applyCrimeJail
};
