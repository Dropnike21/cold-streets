const express = require('express');
const router = express.Router();
const pool = require('../db');

// The Level 1 safety net for the Hybrid Math Engine
const GLOBAL_FLAT_RATE = 0.05;

// --- 1. FETCH GYM DASHBOARD ---
router.get('/:user_id', async (req, res) => {
    try {
        const { user_id } = req.params;
        let gymStatsRes = await pool.query('SELECT gym_exp, active_gym_id FROM user_gym_stats WHERE user_id = $1', [user_id]);

        // Auto-seed Level 1 Gym for new users
        if (gymStatsRes.rows.length === 0) {
            await pool.query('INSERT INTO user_gym_stats (user_id, gym_exp, active_gym_id, daily_gym_fee) VALUES ($1, 0, 1, 0)', [user_id]);
            await pool.query('INSERT INTO user_owned_gyms (user_id, gym_id) VALUES ($1, 1)', [user_id]);
            gymStatsRes = await pool.query('SELECT gym_exp, active_gym_id FROM user_gym_stats WHERE user_id = $1', [user_id]);
        }

        const { gym_exp, active_gym_id } = gymStatsRes.rows[0];
        const ownedRes = await pool.query('SELECT gym_id FROM user_owned_gyms WHERE user_id = $1', [user_id]);
        const ownedGymIds = ownedRes.rows.map(row => row.gym_id);
        const masterRes = await pool.query('SELECT * FROM gyms_master ORDER BY gym_id ASC');

        const mappedGyms = masterRes.rows.map(gym => {
            return {
                id: gym.gym_id,
                name: gym.gym_name,
                zone: gym.zone,
                desc: gym.description,
                str_percent: parseFloat(gym.str_percent),
                def_percent: parseFloat(gym.def_percent),
                dex_percent: parseFloat(gym.dex_percent),
                spd_percent: parseFloat(gym.spd_percent),
                str_action: gym.str_action || 'lifted weights',
                def_action: gym.def_action || 'hit the heavy bag',
                dex_action: gym.dex_action || 'practiced form',
                spd_action: gym.spd_action || 'ran laps',
                unlock_cost: parseInt(gym.unlock_cost),
                daily_fee: parseInt(gym.daily_fee),
                unlock_exp_req: parseInt(gym.unlock_exp_req),
                is_owned: ownedGymIds.includes(gym.gym_id)
            };
        });

        res.json({ success: true, gym_exp, active_gym_id, gyms: mappedGyms });
    } catch (err) {
        console.error(err);
        res.status(500).json({ error: "Server error fetching gym data." });
    }
});

// --- 2. PURCHASE A GYM ---
router.post('/purchase', async (req, res) => {
    const { user_id, gym_id } = req.body;
    try {
        await pool.query('BEGIN');
        const ownedCheck = await pool.query('SELECT 1 FROM user_owned_gyms WHERE user_id = $1 AND gym_id = $2', [user_id, gym_id]);
        if (ownedCheck.rows.length > 0) { await pool.query('ROLLBACK'); return res.status(400).json({ error: "Already owned." }); }

        const gymRes = await pool.query('SELECT unlock_cost FROM gyms_master WHERE gym_id = $1', [gym_id]);
        if (gymRes.rows.length === 0) { await pool.query('ROLLBACK'); return res.status(404).json({ error: "Gym not found." }); }

        const cost = gymRes.rows[0].unlock_cost;
        const userRes = await pool.query('SELECT dirty_cash FROM users WHERE user_id = $1 FOR UPDATE', [user_id]);
        if (userRes.rows[0].dirty_cash < cost) { await pool.query('ROLLBACK'); return res.status(400).json({ error: "Insufficient dirty cash." }); }

        await pool.query('UPDATE users SET dirty_cash = dirty_cash - $1 WHERE user_id = $2', [cost, user_id]);
        await pool.query('INSERT INTO user_owned_gyms (user_id, gym_id) VALUES ($1, $2)', [user_id, gym_id]);
        await pool.query('UPDATE user_gym_stats SET active_gym_id = $1 WHERE user_id = $2', [gym_id, user_id]);

        const updatedUser = await pool.query('SELECT * FROM users WHERE user_id = $1', [user_id]);
        await pool.query('COMMIT');
        res.json({ success: true, message: "Membership activated!", user: updatedUser.rows[0] });
    } catch (err) {
        await pool.query('ROLLBACK');
        res.status(500).json({ error: "Server error during purchase." });
    }
});

// --- 3. ACTIVATE AN OWNED GYM ---
router.post('/activate', async (req, res) => {
    const { user_id, gym_id } = req.body;
    try {
        const ownedCheck = await pool.query('SELECT 1 FROM user_owned_gyms WHERE user_id = $1 AND gym_id = $2', [user_id, gym_id]);
        if (ownedCheck.rows.length === 0) return res.status(403).json({ error: "You do not own this gym." });

        await pool.query('UPDATE user_gym_stats SET active_gym_id = $1 WHERE user_id = $2', [gym_id, user_id]);
        res.json({ success: true, message: "Active gym switched." });
    } catch (err) {
        res.status(500).json({ error: "Server error switching gyms." });
    }
});

// --- 4. BULK TRAIN (V1.1 HYBRID ENGINE) ---
router.post('/train', async (req, res) => {
    const { user_id, stat_type, energy_spent, gym_id } = req.body;
    const validStats = ['str', 'def', 'dex', 'spd'];
    if (!validStats.includes(stat_type)) return res.status(400).json({ error: "Invalid stat." });

    const statColumn = `stat_${stat_type}`;
    const percentColumn = `${stat_type}_percent`;

    try {
        await pool.query('BEGIN');
        const userRes = await pool.query(`SELECT energy, exp, ${statColumn} FROM users WHERE user_id = $1 FOR UPDATE`, [user_id]);
        if (userRes.rows.length === 0) throw new Error("User not found.");

        const currentEnergy = userRes.rows[0].energy;
        let currentStat = parseFloat(userRes.rows[0][statColumn]);

        if (currentEnergy < energy_spent || energy_spent < 1) {
            await pool.query('ROLLBACK');
            return res.status(400).json({ error: "Not enough energy." });
        }

        let gymPercentRate = 0;
        const gymRes = await pool.query(`SELECT ${percentColumn} FROM gyms_master WHERE gym_id = $1`, [gym_id]);
        if (gymRes.rows.length > 0 && gymRes.rows[0][percentColumn] !== null) {
            gymPercentRate = parseFloat(gymRes.rows[0][percentColumn]);
        }

        // External modifiers (Properties, Perks). Hard-capped at 10% max bonus per GDD.
        // NOTE: Stubbed until Property tables are active.
        let externalBonus = 0.0;
        if (externalBonus > 0.10) {
            externalBonus = 0.10;
        }
        const totalMultiplier = 1.0 + externalBonus;

        // V1.1 THE HYBRID MATH FORMULA
        // Stat Gain = ((Current Stat * Gym Percent Rate) + Global Flat Rate) * Total Multiplier * Energy Spent
        const rawGain = ((currentStat * gymPercentRate) + GLOBAL_FLAT_RATE) * totalMultiplier * energy_spent;
        const totalStatGain = rawGain.toFixed(2);

        const playerExpGain = 5 * energy_spent;
        const gymExpGain = 1 * energy_spent;

        const updateQuery = `
            UPDATE users SET energy = energy - $1, exp = exp + $2, ${statColumn} = ${statColumn} + $3
            WHERE user_id = $4 RETURNING *;
        `;
        const updatedUser = await pool.query(updateQuery, [energy_spent, playerExpGain, parseFloat(totalStatGain), user_id]);
        const gymExpUpdate = `UPDATE user_gym_stats SET gym_exp = gym_exp + $1 WHERE user_id = $2 RETURNING gym_exp;`;
        const expRes = await pool.query(gymExpUpdate, [gymExpGain, user_id]);

        let userPayload = updatedUser.rows[0];
        userPayload.gym_exp = expRes.rows[0].gym_exp;

        await pool.query('COMMIT');
        res.json({ success: true, gained: totalStatGain, user: userPayload });
    } catch (err) {
        await pool.query('ROLLBACK');
        console.error(err);
        res.status(500).json({ error: "Server error during training." });
    }
});

module.exports = router;