const express = require('express');
const pool = require('../db');
const router = express.Router();

router.get('/list', async (req, res) => {
    try {
        const crimes = await pool.query("SELECT * FROM crimes_master ORDER BY req_stat_value ASC");
        res.json(crimes.rows);
    } catch (err) {
        console.error("Fetch Crimes Error:", err.message);
        res.status(500).json({ error: "Failed to load Job Board." });
    }
});

router.post('/execute', async (req, res) => {
    try {
        const { user_id, crime_id } = req.body;

        // 1. Check if player is locked in Hospital or Jail
                const cooldownCheck = await pool.query("SELECT * FROM user_cooldowns WHERE user_id = $1 AND expires_at > NOW()", [user_id]);
                if (cooldownCheck.rows.length > 0) {
                    // FIXED: Narrative text update for hospital vs jail
                    const activeCd = cooldownCheck.rows[0].type;
                    if (activeCd === 'hospital') {
                        return res.status(403).json({ error: "You are still lying in a hospital bed. You cannot do this activity yet." });
                    } else {
                        return res.status(403).json({ error: "You are locked behind bars. Do your time." });
                    }
                }

        const userCheck = await pool.query("SELECT * FROM users WHERE user_id = $1", [user_id]);
        if (userCheck.rows.length === 0) return res.status(404).json({ error: "Ghost account." });
        const user = userCheck.rows[0];

        // 2. HP Lockout Check (< 25 HP)
        if (user.hp < 25) {
            return res.status(403).json({ error: "You are too weak. Wait for the hospital or heal up to 25 HP first." });
        }

        const crimeCheck = await pool.query("SELECT * FROM crimes_master WHERE crime_id = $1", [crime_id]);
        if (crimeCheck.rows.length === 0) return res.status(404).json({ error: "Crime not found." });
        const crime = crimeCheck.rows[0];

        if (user.energy < crime.energy_cost) return res.status(400).json({ error: "Not enough Energy." });
        if (user.nerve < crime.nerve_cost) return res.status(400).json({ error: "Not enough Nerve." });

        const playerStat = user[`stat_${crime.req_stat_type}`] || 10;
        let successChance = (playerStat / crime.req_stat_value) * 100;
        if (successChance < 5) successChance = 5;
        if (successChance > 95) successChance = 95;

        const roll = Math.floor(Math.random() * 100) + 1;

        if (roll <= successChance) {
            const payout = Math.floor(Math.random() * (crime.max_payout - crime.min_payout + 1)) + crime.min_payout;
            const updatedUser = await pool.query(
                "UPDATE users SET energy = energy - $1, nerve = nerve - $2, dirty_cash = dirty_cash + $3 WHERE user_id = $4 RETURNING dirty_cash, energy, nerve, max_nerve, hp",
                [crime.energy_cost, crime.nerve_cost, payout, user_id]
            );
            return res.json({ status: "success", message: crime.success_text, gained_cash: payout, user: updatedUser.rows[0] });
        } else {
            const failRoll = Math.floor(Math.random() * 100) + 1;

            if (failRoll <= 33) {
                // ESCAPED (-10 HP)
                const updatedUser = await pool.query("UPDATE users SET energy = energy - $1, nerve = nerve - $2, hp = GREATEST(hp - 10, 1) WHERE user_id = $3 RETURNING dirty_cash, energy, nerve, max_nerve, hp", [crime.energy_cost, crime.nerve_cost, user_id]);
                return res.json({ status: "escaped", message: crime.escape_text, user: updatedUser.rows[0] });
            } else if (failRoll <= 66) {
                // HOSPITALIZED (Drops to 1 HP, 1 Minute Cooldown)
                const updatedUser = await pool.query("UPDATE users SET energy = energy - $1, nerve = nerve - $2, hp = 1 WHERE user_id = $3 RETURNING dirty_cash, energy, nerve, max_nerve, hp", [crime.energy_cost, crime.nerve_cost, user_id]);
                await pool.query("INSERT INTO user_cooldowns (user_id, type, expires_at) VALUES ($1, 'hospital', NOW() + INTERVAL '1 minute')", [user_id]);
                return res.json({ status: "hospitalized", message: crime.hosp_text, user: updatedUser.rows[0] });
            } else {
                // JAILED (1 Minute Cooldown for MVP testing)
                const updatedUser = await pool.query("UPDATE users SET energy = energy - $1, nerve = nerve - $2 WHERE user_id = $3 RETURNING dirty_cash, energy, nerve, max_nerve, hp", [crime.energy_cost, crime.nerve_cost, user_id]);
                await pool.query("INSERT INTO user_cooldowns (user_id, type, expires_at) VALUES ($1, 'jail', NOW() + INTERVAL '1 minute')", [user_id]);
                return res.json({ status: "jailed", message: crime.jail_text, user: updatedUser.rows[0] });
            }
        }
    } catch (err) {
        console.error("Crime Error:", err.message);
        res.status(500).json({ error: "Hustle engine malfunction." });
    }
});

module.exports = router;