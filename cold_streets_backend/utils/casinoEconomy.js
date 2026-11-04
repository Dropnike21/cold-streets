// Charge a casino wager atomically. Caller MUST hold a database transaction
// and must commit/rollback it. This always locks the player's wallet row first.
const { ActionError, integer, dbInteger } = require('./economyValidation');
const MAX_BET = 1000000000000n; // Temporary protection against unbounded wagers.

async function chargeWager(client, userId, value, beforeDebit = null) {
    const bet = integer(value, { field: 'Bet', min: 1n, max: MAX_BET });
    const result = await client.query(
        'SELECT dirty_cash, clean_cash, casino_tokens FROM users WHERE user_id = $1 FOR UPDATE',
        [userId]
    );
    if (result.rowCount !== 1) throw new ActionError(404, 'Player not found.');
    const user = result.rows[0];
    if (beforeDebit) {
        const gate = await beforeDebit({ bet, user });
        if (gate?.replay) return { bet, replay: gate };
    }
    if (dbInteger(user.casino_tokens) < 1n) throw new ActionError(409, 'Out of Casino Tokens.');
    const dirty = dbInteger(user.dirty_cash);
    const clean = dbInteger(user.clean_cash);
    if (dirty + clean < bet) throw new ActionError(409, 'Insufficient Cash.');
    const takeDirty = dirty < bet ? dirty : bet;
    const takeClean = bet - takeDirty;
    const update = await client.query(
        `UPDATE users SET casino_tokens = casino_tokens - 1,
           dirty_cash = dirty_cash - $1::numeric, clean_cash = clean_cash - $2::numeric
         WHERE user_id = $3 AND casino_tokens >= 1
           AND dirty_cash >= $1::numeric AND clean_cash >= $2::numeric
         RETURNING dirty_cash, clean_cash, casino_tokens`,
        [takeDirty.toString(), takeClean.toString(), userId]
    );
    if (update.rowCount !== 1) throw new ActionError(409, 'Wallet changed before bet.');
    return { bet, balances: update.rows[0] };
}

module.exports = { chargeWager };
