const express = require('express');
const router = express.Router();
const db = require('../../db');

const PERYA_COLORS = ['RED', 'BLUE', 'YELLOW', 'GREEN', 'PINK', 'WHITE'];
const TOKEN_COST_PER_ROLL = 1;

router.post('/roll', async (req, res) => {
    try {
        const userId = Number(req.body.userId);
        const betAmount = Number(req.body.betAmount);
        const chosenColor = req.body.chosenColor;

        if (!PERYA_COLORS.includes(chosenColor)) return res.status(400).json({ error: "Invalid color." });
        if (betAmount <= 0) return res.status(400).json({ error: "Bet must be greater than 0." });
        if (isNaN(userId) || isNaN(betAmount)) return res.status(400).json({ error: "Invalid data format." });

        await db.query('BEGIN');

        // 1. Verify User Balance & Tokens
        const userRes = await db.query("SELECT dirty_cash, clean_cash, casino_tokens FROM users WHERE user_id = $1", [userId]);
        if (userRes.rows.length === 0) {
            await db.query('ROLLBACK');
            return res.status(404).json({ error: "User not found" });
        }

        const user = userRes.rows[0];
        const dirty = Number(user.dirty_cash);
        const clean = Number(user.clean_cash);
        const tokens = Number(user.casino_tokens);

        if (tokens < TOKEN_COST_PER_ROLL) {
            await db.query('ROLLBACK');
            return res.status(400).json({ error: "Out of Casino Tokens! Come back tomorrow." });
        }

        if ((dirty + clean) < betAmount) {
            await db.query('ROLLBACK');
            return res.status(400).json({ error: "Insufficient Cash to place this bet." });
        }

        // 2. Deduct 1 Token AND the Cash Bet
        let dirtyToDeduct = Math.min(dirty, betAmount);
        let cleanToDeduct = betAmount - dirtyToDeduct;

        await db.query(
            "UPDATE users SET casino_tokens = casino_tokens - $1, dirty_cash = dirty_cash - $2, clean_cash = clean_cash - $3 WHERE user_id = $4",
            [TOKEN_COST_PER_ROLL, dirtyToDeduct, cleanToDeduct, userId]
        );

        // 3. Roll the 3 Dice
        const results = [
            PERYA_COLORS[Math.floor(Math.random() * PERYA_COLORS.length)],
            PERYA_COLORS[Math.floor(Math.random() * PERYA_COLORS.length)],
            PERYA_COLORS[Math.floor(Math.random() * PERYA_COLORS.length)]
        ];

        // 4. Calculate Matches
        let matches = 0;
        for (let r of results) {
            if (r === chosenColor) matches++;
        }

        // 5. Calculate Payout (Always in Clean Cash)
                let payoutAmount = 0;
                if (matches > 0) {
                    let multiplier = matches + 1;
                    payoutAmount = betAmount * multiplier;
                    await db.query("UPDATE users SET clean_cash = clean_cash + $1 WHERE user_id = $2", [payoutAmount, userId]);
                }

                // 🚨 NEW: Log to the Casino Audit Ledger
                await db.query(
                    "INSERT INTO casino_audit (user_id, game_name, bet_amount, payout) VALUES ($1, $2, $3, $4)",
                    [userId, 'Perya', betAmount, payoutAmount]
                );

                await db.query('COMMIT');

        // Fetch updated balances to send back to the app
        const finalUser = await db.query("SELECT dirty_cash, clean_cash, casino_tokens FROM users WHERE user_id = $1", [userId]);

        res.status(200).json({
            dice: results,
            matches: matches,
            payout: payoutAmount,
            updatedBalances: finalUser.rows[0]
        });

    } catch (error) {
        await db.query('ROLLBACK');
        console.error("Perya Roll Error:", error);
        // We now send the exact error message back so you can see it if it fails!
        res.status(500).json({ error: "Server error: " + error.message });
    }
});

module.exports = router;