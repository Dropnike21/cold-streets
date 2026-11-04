const express = require('express');
const { randomInt } = require('node:crypto');
const router = express.Router();
const db = require('../../db');
const { actorId, dbInteger, exactJsonAmount, sendActionError } = require('../../utils/economyValidation');
const { chargeWager } = require('../../utils/casinoEconomy');

const REEL_SYMBOLS = [
    'CHERRY', 'CHERRY', 'CHERRY', 'CHERRY',
    'LEMON', 'LEMON', 'LEMON',
    'GRAPE', 'GRAPE',
    'DIAMOND', 'CROWN', 'SKULL', 'SKULL'
];
const JACKPOT_GAME = 'slots_progressive';
const JACKPOT_RESET = 10000000n;
const isCommon = value => ['CHERRY', 'LEMON', 'GRAPE'].includes(value);

router.get('/jackpot', async (req, res) => {
    try {
        const result = await db.query('SELECT current_value FROM casino_jackpots WHERE game_id = $1', [JACKPOT_GAME]);
        if (result.rowCount !== 1) throw new Error('Progressive jackpot is not configured.');
        return res.json({ jackpot: exactJsonAmount(dbInteger(result.rows[0].current_value)) });
    } catch (err) { return sendActionError(res, err, 'Slots jackpot fetch:'); }
});

router.post('/spin', async (req, res) => {
    let client, transaction = false;
    try {
        const userId = actorId(req);
        client = await db.connect();
        await client.query('BEGIN');
        transaction = true;
        const { bet } = await chargeWager(client, userId, req.body?.betAmount);

        // Lock the progressive jackpot before resolving any spin. Two wins
        // cannot both collect the old jackpot.
        const jackpot = await client.query(
            'SELECT current_value FROM casino_jackpots WHERE game_id = $1 FOR UPDATE',
            [JACKPOT_GAME]
        );
        if (jackpot.rowCount !== 1) throw new Error('Progressive jackpot is not configured.');
        const currentJackpot = dbInteger(jackpot.rows[0].current_value);
        const reels = Array.from({ length: 4 }, () => REEL_SYMBOLS[randomInt(REEL_SYMBOLS.length)]);
        const counts = {};
        for (const symbol of reels) counts[symbol] = (counts[symbol] || 0) + 1;

        let payout = 0n;
        let isJackpot = false;
        if (counts.CROWN === 4) {
            isJackpot = true;
            payout = currentJackpot;
        } else if (counts.DIAMOND === 4) {
            payout = bet * 4n;
        } else if (counts.DIAMOND === 3) {
            payout = bet * 3n;
        } else {
            let pairs = 0, triples = 0, quads = 0;
            for (const [symbol, count] of Object.entries(counts)) {
                if (!isCommon(symbol)) continue;
                if (count === 4) quads++;
                else if (count === 3) triples++;
                else if (count === 2) pairs++;
            }
            if (quads === 1) payout = bet * 2n;
            else if (triples === 1) payout = bet * 18n / 10n;
            else if (pairs === 2) payout = bet * 12n / 10n;
            else if (pairs === 1) payout = bet * 8n / 10n;
        }

        const feed = payout < bet ? bet / 10n : 0n;
        const newJackpot = (isJackpot ? JACKPOT_RESET : currentJackpot) + feed;
        await client.query(
            'UPDATE casino_jackpots SET current_value = $1::numeric WHERE game_id = $2',
            [newJackpot.toString(), JACKPOT_GAME]
        );
        const wallet = await client.query(
            'UPDATE users SET clean_cash = clean_cash + $1::numeric WHERE user_id = $2 RETURNING dirty_cash, clean_cash, casino_tokens',
            [payout.toString(), userId]
        );
        if (wallet.rowCount !== 1) throw new Error('Casino account disappeared during spin.');
        await client.query(
            "INSERT INTO casino_audit (user_id, game_name, bet_amount, payout) VALUES ($1, 'Slots', $2::numeric, $3::numeric)",
            [userId, bet.toString(), payout.toString()]
        );
        await client.query('COMMIT');
        transaction = false;
        return res.json({
            reels,
            payout: exactJsonAmount(payout),
            isJackpot,
            currentJackpot: exactJsonAmount(newJackpot),
            updatedBalances: wallet.rows[0]
        });
    } catch (err) {
        if (transaction) {
            try { await client.query('ROLLBACK'); } catch (rollback) { console.error('Slots rollback failed:', rollback); }
        }
        return sendActionError(res, err, 'Slots spin failed:');
    } finally { if (client) client.release(); }
});

module.exports = router;
