const express = require('express');
const { randomInt } = require('node:crypto');
const router = express.Router();
const db = require('../../db');
const { requireOwnedPlayerParam } = require('../../middleware/playerIdentity');
const { ActionError, integer, dbInteger, exactJsonAmount, actorId, sendActionError } = require('../../utils/economyValidation');
router.param('userId', requireOwnedPlayerParam);

const SUITS = ['HEARTS', 'DIAMONDS', 'CLUBS', 'SPADES'];
const getRandomCard = () => ({
    value: randomInt(2, 15), // 2..14 inclusive
    suit: SUITS[randomInt(SUITS.length)]
});
const MAX_BET = 1000000000000n; // Temporary transaction anti-abuse cap; revisit against design.
const MULTIPLIER_SCALE = 1000000n;
const MAX_MULTIPLIER_UNITS = 999999999999n; // NUMERIC(12,6)

function multiplierUnits(value) {
    const text = String(value);
    if (!/^[0-9]+(?:\.[0-9]{1,6})?$/.test(text)) throw new Error('Invalid stored High/Low multiplier.');
    const [whole, fraction = ''] = text.split('.');
    return BigInt(whole) * MULTIPLIER_SCALE + BigInt(fraction.padEnd(6, '0'));
}
function multiplierText(units) {
    return (units / MULTIPLIER_SCALE).toString() + '.' +
        (units % MULTIPLIER_SCALE).toString().padStart(6, '0');
}

router.get('/session/:userId', async (req, res) => {
    try {
        const userId = actorId(req);
        const result = await db.query('SELECT * FROM hilo_sessions WHERE user_id = $1', [userId]);
        return res.json(result.rowCount ? { active: true, session: result.rows[0] } : { active: false });
    } catch (err) { return sendActionError(res, err, 'High/Low session error:'); }
});

router.post('/start', async (req, res) => {
    let client, active = false;
    try {
        const userId = actorId(req);
        const bet = integer(req.body?.betAmount, { field: 'Bet', min: 1n, max: MAX_BET });
        client = await db.connect();
        await client.query('BEGIN');
        active = true;
        const wallet = await client.query(
            'SELECT dirty_cash, clean_cash, casino_tokens FROM users WHERE user_id = $1 FOR UPDATE',
            [userId]
        );
        if (!wallet.rowCount) throw new ActionError(404, 'Player not found.');
        const user = wallet.rows[0];
        if (dbInteger(user.casino_tokens) < 1n) throw new ActionError(409, 'Out of Casino Tokens.');
        const dirty = dbInteger(user.dirty_cash), clean = dbInteger(user.clean_cash);
        if (dirty + clean < bet) throw new ActionError(409, 'Insufficient Cash.');
        const existing = await client.query('SELECT 1 FROM hilo_sessions WHERE user_id = $1', [userId]);
        if (existing.rowCount) throw new ActionError(409, 'Finish your active game first.');

        const dirtyDebit = dirty < bet ? dirty : bet;
        const cleanDebit = bet - dirtyDebit;
        const updated = await client.query(
            `UPDATE users SET casino_tokens = casino_tokens - 1,
                 dirty_cash = dirty_cash - $1::numeric, clean_cash = clean_cash - $2::numeric
             WHERE user_id = $3 AND casino_tokens >= 1
               AND dirty_cash >= $1::numeric AND clean_cash >= $2::numeric
             RETURNING dirty_cash, clean_cash, casino_tokens`,
            [dirtyDebit.toString(), cleanDebit.toString(), userId]
        );
        if (updated.rowCount !== 1) throw new ActionError(409, 'Wallet changed before wager.');
        const card = getRandomCard();
        await client.query(
            'INSERT INTO hilo_sessions (user_id, bet_amount, current_card_value, current_card_suit) VALUES ($1, $2::numeric, $3, $4)',
            [userId, bet.toString(), card.value, card.suit]
        );
        await client.query('COMMIT');
        active = false;
        return res.json({ card, updatedBalances: updated.rows[0] });
    } catch (err) {
        if (active) try { await client.query('ROLLBACK'); } catch (rollback) { console.error('High/Low start rollback:', rollback); }
        return sendActionError(res, err, 'High/Low start error:');
    } finally { if (client) client.release(); }
});

router.post('/guess', async (req, res) => {
    let client, active = false;
    try {
        const userId = actorId(req);
        const guess = req.body?.guess;
        if (!['HIGH', 'LOW', 'SAME'].includes(guess)) throw new ActionError(400, 'Invalid guess.');
        client = await db.connect();
        await client.query('BEGIN');
        active = true;
        const result = await client.query('SELECT * FROM hilo_sessions WHERE user_id = $1 FOR UPDATE', [userId]);
        if (!result.rowCount) throw new ActionError(409, 'No active game found.');
        const session = result.rows[0];
        const nextCard = getRandomCard();
        const win = (guess === 'HIGH' && nextCard.value > session.current_card_value) ||
            (guess === 'LOW' && nextCard.value < session.current_card_value) ||
            (guess === 'SAME' && nextCard.value === session.current_card_value);
        if (win) {
            const units = multiplierUnits(session.current_multiplier) +
                (guess === 'SAME' ? 5000000n : 300000n);
            if (units > MAX_MULTIPLIER_UNITS) throw new ActionError(409, 'Multiplier limit reached. Cash out.');
            const streak = Number(session.current_streak) + 1;
            const nextMultiplier = multiplierText(units);
            await client.query(
                `UPDATE hilo_sessions SET current_multiplier = $1::numeric,
                   current_streak = $2, current_card_value = $3,
                   current_card_suit = $4 WHERE user_id = $5`,
                [nextMultiplier, streak, nextCard.value, nextCard.suit, userId]
            );
            await client.query('COMMIT');
            active = false;
            return res.json({ status: 'WIN', nextCard, newMultiplier: Number(nextMultiplier), newStreak: streak });
        }
        const wager = dbInteger(session.bet_amount);
        const feed = wager / 10n;
        await client.query('DELETE FROM hilo_sessions WHERE user_id = $1', [userId]);
        const jackpot = await client.query(
            "UPDATE casino_jackpots SET current_value = current_value + $1::numeric WHERE game_id = 'slots_progressive' RETURNING current_value",
            [feed.toString()]
        );
        if (jackpot.rowCount !== 1) throw new Error('Progressive jackpot is not configured.');
        await client.query(
            "INSERT INTO casino_audit (user_id, game_name, bet_amount, payout) VALUES ($1, 'HighLow', $2::numeric, 0)",
            [userId, wager.toString()]
        );
        await client.query('COMMIT');
        active = false;
        return res.json({ status: 'LOSS', nextCard });
    } catch (err) {
        if (active) try { await client.query('ROLLBACK'); } catch (rollback) { console.error('High/Low guess rollback:', rollback); }
        return sendActionError(res, err, 'High/Low guess error:');
    } finally { if (client) client.release(); }
});

router.post('/cashout', async (req, res) => {
    let client, active = false;
    try {
        const userId = actorId(req);
        client = await db.connect();
        await client.query('BEGIN');
        active = true;
        // Wallet first, then session: same order as /start.
        const wallet = await client.query('SELECT user_id FROM users WHERE user_id = $1 FOR UPDATE', [userId]);
        if (!wallet.rowCount) throw new ActionError(404, 'Player not found.');
        const session = await client.query(
            'SELECT bet_amount, current_multiplier FROM hilo_sessions WHERE user_id = $1 FOR UPDATE',
            [userId]
        );
        if (!session.rowCount) throw new ActionError(409, 'No active game found.');
        const wager = dbInteger(session.rows[0].bet_amount);
        const payout = wager * multiplierUnits(session.rows[0].current_multiplier) / MULTIPLIER_SCALE;
        // Consume session and grant prize within ONE transaction; repeat cashout
        // requests cannot claim a second payout after session deletion.
        await client.query('DELETE FROM hilo_sessions WHERE user_id = $1', [userId]);
        const updated = await client.query(
            'UPDATE users SET clean_cash = clean_cash + $1::numeric WHERE user_id = $2 RETURNING dirty_cash, clean_cash, casino_tokens',
            [payout.toString(), userId]
        );
        await client.query(
            "INSERT INTO casino_audit (user_id, game_name, bet_amount, payout) VALUES ($1, 'HighLow', $2::numeric, $3::numeric)",
            [userId, wager.toString(), payout.toString()]
        );
        await client.query('COMMIT');
        active = false;
        return res.json({ payout: exactJsonAmount(payout), updatedBalances: updated.rows[0] });
    } catch (err) {
        if (active) try { await client.query('ROLLBACK'); } catch (rollback) { console.error('High/Low payout rollback:', rollback); }
        return sendActionError(res, err, 'High/Low cashout error:');
    } finally { if (client) client.release(); }
});

module.exports = router;
