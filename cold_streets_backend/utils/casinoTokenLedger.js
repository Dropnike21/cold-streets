const {
    ActionError,
    integer,
    dbInteger
} = require('./economyValidation');

const BASE_DAILY_TOKEN_SPEND_CAP = 100n;
const VIP_DAILY_TOKEN_BONUS = 50n;
const MAX_DAILY_TOKEN_SPEND_CAP = BASE_DAILY_TOKEN_SPEND_CAP + VIP_DAILY_TOKEN_BONUS;
const RECONCILED_TOKEN_ENGINES = new Set([
    'perya',
    'slots',
    'high_low'
]);

function normalizeGameKey(value) {
    if (typeof value !== 'string' || !RECONCILED_TOKEN_ENGINES.has(value)) {
        throw new ActionError(
            503,
            'This Casino token game is not reconciled for authoritative spending.'
        );
    }
    return value;
}

function normalizeSourceRef(value) {
    if (typeof value !== 'string') {
        throw new Error('Casino token spend source reference must be server-owned.');
    }
    const ref = value.trim();
    if (ref.length < 1 || ref.length > 200) {
        throw new Error('Casino token spend source reference is invalid.');
    }
    return ref;
}

async function getCasinoTokenStatus(client, userId) {
    const [wallet, usage] = await Promise.all([
        client.query(
            'SELECT casino_tokens, vip_status_active FROM users WHERE user_id = $1',
            [userId]
        ),
        client.query(
            `SELECT CURRENT_DATE::text AS day_key,
                    COALESCE(SUM(token_amount), 0)::bigint AS spent_today
               FROM casino_token_spend_ledger
              WHERE user_id = $1
                AND spent_at >= CURRENT_DATE
                AND spent_at < CURRENT_DATE + INTERVAL '1 day'`,
            [userId]
        )
    ]);

    if (wallet.rowCount !== 1) {
        throw new ActionError(404, 'Player not found.');
    }

    const balance = dbInteger(wallet.rows[0].casino_tokens, {
        field: 'Casino Token balance'
    });
    const spentToday = dbInteger(usage.rows[0].spent_today, {
        field: 'Casino Tokens spent today'
    });
    const vipActive = wallet.rows[0].vip_status_active === true;
    const dailyCap = vipActive
        ? MAX_DAILY_TOKEN_SPEND_CAP
        : BASE_DAILY_TOKEN_SPEND_CAP;
    if (balance < 0n || spentToday < 0n || spentToday > dailyCap) {
        throw new Error('Casino token accounting is outside source-backed bounds.');
    }

    return {
        balance,
        vipActive,
        baseDailyCap: BASE_DAILY_TOKEN_SPEND_CAP,
        vipDailyBonus: vipActive ? VIP_DAILY_TOKEN_BONUS : 0n,
        dailyCap,
        spentToday,
        remainingToday: dailyCap - spentToday,
        dayKey: usage.rows[0].day_key
    };
}

async function reserveCasinoTokenSpend(client, {
    userId,
    gameKey,
    tokenAmount,
    sourceRef
}) {
    const game = normalizeGameKey(gameKey);
    const amount = integer(tokenAmount, {
        field: 'Casino Token spend',
        min: 1n,
        max: MAX_DAILY_TOKEN_SPEND_CAP
    });
    const ref = normalizeSourceRef(sourceRef);

    // Lock order for future token games: authenticated player -> replay ledger.
    const player = await client.query(
        'SELECT casino_tokens, vip_status_active FROM users WHERE user_id = $1 FOR UPDATE',
        [userId]
    );
    if (player.rowCount !== 1) {
        throw new ActionError(404, 'Player not found.');
    }

    const existing = await client.query(
        `SELECT game_key, token_amount, spent_at
           FROM casino_token_spend_ledger
          WHERE user_id = $1 AND source_ref = $2`,
        [userId, ref]
    );
    if (existing.rowCount > 1) {
        throw new Error('Casino token replay ledger uniqueness was violated.');
    }
    if (existing.rowCount === 1) {
        const row = existing.rows[0];
        if (row.game_key !== game ||
            dbInteger(row.token_amount, { field: 'Recorded Casino Token spend' }) !== amount) {
            throw new ActionError(
                409,
                'Casino token spend replay data does not match the original obligation.'
            );
        }
        const status = await getCasinoTokenStatus(client, userId);
        return {
            replay: true,
            spend: row,
            status
        };
    }

    const usage = await client.query(
        `SELECT COALESCE(SUM(token_amount), 0)::bigint AS spent_today
           FROM casino_token_spend_ledger
          WHERE user_id = $1
            AND spent_at >= CURRENT_DATE
            AND spent_at < CURRENT_DATE + INTERVAL '1 day'`,
        [userId]
    );
    const spentToday = dbInteger(usage.rows[0].spent_today, {
        field: 'Casino Tokens spent today'
    });
    const dailyCap = player.rows[0].vip_status_active === true
        ? MAX_DAILY_TOKEN_SPEND_CAP
        : BASE_DAILY_TOKEN_SPEND_CAP;
    if (spentToday < 0n || spentToday > dailyCap) {
        throw new Error('Casino token daily spend ledger is outside source limit.');
    }
    if (spentToday + amount > dailyCap) {
        throw new ActionError(
            409,
            'Casino Token daily spend cap exceeded.'
        );
    }

    const balance = dbInteger(player.rows[0].casino_tokens, {
        field: 'Casino Token balance'
    });
    if (balance < amount) {
        throw new ActionError(409, 'Not enough Casino Tokens.');
    }

    const debit = await client.query(
        `UPDATE users
            SET casino_tokens = casino_tokens - $1::bigint
          WHERE user_id = $2
            AND casino_tokens >= $1::bigint
          RETURNING casino_tokens`,
        [amount.toString(), userId]
    );
    if (debit.rowCount !== 1) {
        throw new ActionError(
            409,
            'Casino Token balance changed before spend settlement.'
        );
    }

    const inserted = await client.query(
        `INSERT INTO casino_token_spend_ledger (
            user_id, game_key, token_amount, source_ref
         )
         VALUES ($1, $2, $3::bigint, $4)
         RETURNING spend_id, game_key, token_amount, source_ref, spent_at`,
        [userId, game, amount.toString(), ref]
    );
    if (inserted.rowCount !== 1) {
        throw new Error('Casino token spend ledger insertion failed.');
    }

    return {
        replay: false,
        spend: inserted.rows[0],
        status: {
            balance: dbInteger(debit.rows[0].casino_tokens, {
                field: 'Casino Token balance'
            }),
            spentToday: spentToday + amount,
            vipActive: player.rows[0].vip_status_active === true,
            dailyCap,
            remainingToday: dailyCap - spentToday - amount
        }
    };
}

module.exports = {
    BASE_DAILY_TOKEN_SPEND_CAP,
    VIP_DAILY_TOKEN_BONUS,
    MAX_DAILY_TOKEN_SPEND_CAP,
    RECONCILED_TOKEN_ENGINES,
    getCasinoTokenStatus,
    reserveCasinoTokenSpend
};
