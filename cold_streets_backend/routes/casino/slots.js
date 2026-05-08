const express = require('express');
const router = express.Router();
const db = require('../../db');

const TOKEN_COST_PER_SPIN = 1;

const REEL_SYMBOLS = [
    'CHERRY', 'CHERRY', 'CHERRY', 'CHERRY',
    'LEMON', 'LEMON', 'LEMON',
    'GRAPE', 'GRAPE',
    'DIAMOND',
    'CROWN',
    'SKULL', 'SKULL'
];

router.get('/jackpot', async (req, res) => {
    try {
        const jpRes = await db.query("SELECT current_value FROM casino_jackpots WHERE game_id = 'slots_progressive'");
        res.status(200).json({ jackpot: Number(jpRes.rows[0].current_value) });
    } catch (error) {
        res.status(500).json({ error: "Failed to fetch jackpot." });
    }
});

router.post('/spin', async (req, res) => {
    try {
        const userId = Number(req.body.userId);
        const betAmount = Number(req.body.betAmount);

        if (betAmount <= 0) return res.status(400).json({ error: "Bet must be greater than 0." });
        if (isNaN(userId) || isNaN(betAmount)) return res.status(400).json({ error: "Invalid data format." });

        await db.query('BEGIN');

        // 1. Verify Balances
        const userRes = await db.query("SELECT dirty_cash, clean_cash, casino_tokens FROM users WHERE user_id = $1", [userId]);
        if (userRes.rows.length === 0) throw new Error("User not found");

        const user = userRes.rows[0];
        const dirty = Number(user.dirty_cash);
        const clean = Number(user.clean_cash);
        const tokens = Number(user.casino_tokens);

        if (tokens < TOKEN_COST_PER_SPIN) {
            await db.query('ROLLBACK');
            return res.status(400).json({ error: "Out of Casino Tokens!" });
        }
        if ((dirty + clean) < betAmount) {
            await db.query('ROLLBACK');
            return res.status(400).json({ error: "Insufficient Cash." });
        }

        // 2. Deduct Bet
        let dirtyToDeduct = Math.min(dirty, betAmount);
        let cleanToDeduct = betAmount - dirtyToDeduct;

        await db.query(
            "UPDATE users SET casino_tokens = casino_tokens - $1, dirty_cash = dirty_cash - $2, clean_cash = clean_cash - $3 WHERE user_id = $4",
            [TOKEN_COST_PER_SPIN, dirtyToDeduct, cleanToDeduct, userId]
        );

        // 3. Spin the 4 Reels
        const results = [
            REEL_SYMBOLS[Math.floor(Math.random() * REEL_SYMBOLS.length)],
            REEL_SYMBOLS[Math.floor(Math.random() * REEL_SYMBOLS.length)],
            REEL_SYMBOLS[Math.floor(Math.random() * REEL_SYMBOLS.length)],
            REEL_SYMBOLS[Math.floor(Math.random() * REEL_SYMBOLS.length)]
        ];

        const counts = {};
        for (let r of results) {
            counts[r] = (counts[r] || 0) + 1;
        }

        let payoutAmount = 0;
        let isJackpot = false;
        const isCommon = (sym) => ['CHERRY', 'LEMON', 'GRAPE'].includes(sym);

        // --- UPDATED MATH & MULTIPLIERS ---
        if (counts['CROWN'] === 4) {
            isJackpot = true;
            const jpRes = await db.query("SELECT current_value FROM casino_jackpots WHERE game_id = 'slots_progressive'");
            payoutAmount = Number(jpRes.rows[0].current_value);
            await db.query("UPDATE casino_jackpots SET current_value = 10000000 WHERE game_id = 'slots_progressive'");

        } else if (counts['DIAMOND'] === 4) {
            payoutAmount = Math.floor(betAmount * 4);
        } else if (counts['DIAMOND'] === 3) {
            payoutAmount = Math.floor(betAmount * 3);
        } else {
            let commonPairs = 0;
            let commonTrips = 0;
            let commonQuads = 0;

            for (const [sym, count] of Object.entries(counts)) {
                if (isCommon(sym)) {
                    if (count === 4) commonQuads++;
                    else if (count === 3) commonTrips++;
                    else if (count === 2) commonPairs++;
                }
            }

            if (commonQuads === 1) {
                payoutAmount = Math.floor(betAmount * 2.0); // 4 of a kind = 2x
            } else if (commonTrips === 1) {
                payoutAmount = Math.floor(betAmount * 1.8); // 3 of a kind = 1.8x
            } else if (commonPairs === 2) {
                payoutAmount = Math.floor(betAmount * 1.2); // 2 Pairs = 1.2x
            } else if (commonPairs === 1) {
                payoutAmount = Math.floor(betAmount * 0.8); // 1 Pair = 0.8x
            }
        }

        // 4. Distribute Payouts & Feed Jackpot
                let jackpotFeed = 0;

                if (payoutAmount === 0) {
                    // Dead spin: 10% goes to Jackpot
                    jackpotFeed = Math.floor(betAmount * 0.10);
                } else if (payoutAmount < betAmount) {
                    // Partial Win (0.8x): The missing 20% is split!
                    // 10% goes to the Jackpot. 10% vanishes as a hidden server tax.
                    jackpotFeed = Math.floor(betAmount * 0.10);
                }

                // Award clean cash
                if (payoutAmount > 0) {
                    await db.query("UPDATE users SET clean_cash = clean_cash + $1 WHERE user_id = $2", [payoutAmount, userId]);
                }

                // Feed the beast
                if (jackpotFeed > 0) {
                    await db.query("UPDATE casino_jackpots SET current_value = current_value + $1 WHERE game_id = 'slots_progressive'", [jackpotFeed]);
                }

                const newJpRes = await db.query("SELECT current_value FROM casino_jackpots WHERE game_id = 'slots_progressive'");
                let newJackpotTotal = Number(newJpRes.rows[0].current_value);

                await db.query(
                    "INSERT INTO casino_audit (user_id, game_name, bet_amount, payout) VALUES ($1, $2, $3, $4)",
                    [userId, 'Slots', betAmount, payoutAmount]
                );

                await db.query('COMMIT');

                const finalUser = await db.query("SELECT dirty_cash, clean_cash, casino_tokens FROM users WHERE user_id = $1", [userId]);

                res.status(200).json({
                    reels: results,
                    payout: payoutAmount,
                    isJackpot: isJackpot,
                    currentJackpot: newJackpotTotal,
                    updatedBalances: finalUser.rows[0]
                });

            } catch (error) {
                await db.query('ROLLBACK');
                res.status(500).json({ error: "Server error: " + error.message });
            }
        });

        module.exports = router;