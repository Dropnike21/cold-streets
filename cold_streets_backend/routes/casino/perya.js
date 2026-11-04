const express = require('express');
const { randomInt } = require('node:crypto');
const router = express.Router();
const db = require('../../db');
const { actorId, exactJsonAmount, sendActionError, ActionError } = require('../../utils/economyValidation');
const { chargeWager } = require('../../utils/casinoEconomy');
const { requireIdempotencyKey, beginIdempotent, completeIdempotent } = require('../../utils/idempotency');

const PERYA_COLORS = ['RED', 'BLUE', 'YELLOW', 'GREEN', 'PINK', 'WHITE'];

router.post('/roll', async (req, res) => {
    let client, transaction = false;
    try {
        const userId = actorId(req);
        const idempotencyKey = requireIdempotencyKey(req);
        const chosenColor = req.body?.chosenColor;
        if (typeof chosenColor !== 'string' || !PERYA_COLORS.includes(chosenColor)) {
            throw new ActionError(400, 'Invalid color.');
        }

        client = await db.connect();
        await client.query('BEGIN');
        transaction = true;
        const wager = await chargeWager(
            client, userId, req.body?.betAmount,
            async ({ bet }) => beginIdempotent(
                client, userId, 'casino.perya_roll', idempotencyKey,
                { betAmount: bet.toString(), chosenColor }
            )
        );
        if (wager.replay) {
            await client.query('COMMIT');
            transaction = false;
            return res.status(wager.replay.status).json(wager.replay.response);
        }
        const bet = wager.bet;

        const dice = Array.from({ length: 3 }, () => PERYA_COLORS[randomInt(PERYA_COLORS.length)]);
        const matches = dice.filter(color => color === chosenColor).length;
        // One hit 2x, two hits 3x, three hits 4x.
        const payout = matches ? bet * BigInt(matches + 1) : 0n;

        const balances = await client.query(
            'UPDATE users SET clean_cash = clean_cash + $1::numeric WHERE user_id = $2 RETURNING dirty_cash, clean_cash, casino_tokens',
            [payout.toString(), userId]
        );
        if (balances.rowCount !== 1) throw new Error('Casino account disappeared during roll.');
        await client.query(
            "INSERT INTO casino_audit (user_id, game_name, bet_amount, payout) VALUES ($1, 'Perya', $2::numeric, $3::numeric)",
            [userId, bet.toString(), payout.toString()]
        );
        const response = {
            dice,
            matches,
            payout: exactJsonAmount(payout),
            updatedBalances: balances.rows[0]
        };
        await completeIdempotent(client, wager.idempotency, 200, response);
        await client.query('COMMIT');
        transaction = false;
        return res.json(response);
    } catch (error) {
        if (transaction) {
            try { await client.query('ROLLBACK'); } catch (rollback) { console.error('Perya rollback failed:', rollback); }
        }
        return sendActionError(res, error, 'Perya roll error:');
    } finally { if (client) client.release(); }
});

module.exports = router;
