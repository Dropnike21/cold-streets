// routes/character.js
const express = require('express');
const pool = require('../db');
const router = express.Router();

// The 5-Year Exponent Formula
const BASE_EXP = 25;
const EXPONENT = 1.7;

function getExpRequirement(level) {
    return Math.floor(BASE_EXP * Math.pow(level, EXPONENT));
}

router.post('/level-up', async (req, res) => {
    const client = await pool.connect();
    try {
        const { user_id, action } = req.body; // action will be 'UPGRADE' or 'HOLD'

        await client.query('BEGIN');

        const userRes = await client.query("SELECT exp, level, max_hp FROM users WHERE user_id = $1 FOR UPDATE", [user_id]);
        if (userRes.rows.length === 0) throw new Error("User not found.");

        const user = userRes.rows[0];
        const cost = getExpRequirement(user.level);

        // ACTION: HOLD
        if (action === 'HOLD') {
            const updatedUser = await client.query(
                "UPDATE users SET level_holding = TRUE WHERE user_id = $1 RETURNING *",
                [user_id]
            );
            await client.query('COMMIT');
            return res.json({ status: "held", user: updatedUser.rows[0] });
        }

        // ACTION: UPGRADE
        if (action === 'UPGRADE') {
            if (user.exp < cost) {
                await client.query('ROLLBACK');
                return res.status(400).json({ error: "Not enough EXP to level up." });
            }

            // Level Up Rewards: Deduct EXP, +1 Level, +50 Max HP, Full HP Heal, un-hold.
            const updatedUser = await client.query(
                `UPDATE users
                 SET exp = exp - $1,
                     level = level + 1,
                     max_hp = max_hp + 50,
                     hp = max_hp + 50,
                     level_holding = FALSE
                 WHERE user_id = $2
                 RETURNING *`,
                [cost, user_id]
            );

            await client.query('COMMIT');
            return res.json({ status: "leveled_up", user: updatedUser.rows[0] });
        }

    } catch (err) {
        await client.query('ROLLBACK');
        console.error("Leveling Error:", err.message);
        res.status(500).json({ error: "Progression system error." });
    } finally {
        client.release();
    }
});

module.exports = router;