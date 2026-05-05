const express = require('express');
const pool = require('../db');
const router = express.Router();
const { trackAndCheckAchievement } = require('../utils/achievement_engine'); // INJECTED ACHIEVEMENT ENGINE

// --- THE NERFED PRISON MATH ---
const JAIL_FLAT_RATE = 0.01; // 5x worse than the normal street gyms
const JAIL_MULTIPLIER = 0.0001; // Terrible percentage scaling

// ==========================================
// 1. GET INMATE LIST
// ==========================================
router.get('/inmates', async (req, res) => {
    try {
        const inmates = await pool.query(`
            SELECT user_id, username, level, jail_expires_at, jail_initial_seconds, state_reason AS reason
            FROM users
            WHERE jail_expires_at > NOW()
            ORDER BY jail_expires_at ASC
        `);
        res.json({ success: true, inmates: inmates.rows });
    } catch (err) {
        console.error("Fetch Inmates Error:", err.message);
        res.status(500).json({ error: "Failed to load inmate manifest." });
    }
});

// ==========================================
// 2. PAY BAIL (CLEAN CASH)
// ==========================================
router.post('/bail', async (req, res) => {
    const client = await pool.connect();

    try {
        const { user_id, target_id } = req.body;
        await client.query('BEGIN');

        // Fetch Payer
        const payerRes = await client.query("SELECT clean_cash FROM users WHERE user_id = $1 FOR UPDATE", [user_id]);
        if (payerRes.rows.length === 0) throw new Error("Payer account not found.");
        const payer = payerRes.rows[0];

        // Fetch Target (Inmate)
        const targetRes = await client.query("SELECT username, jail_expires_at, jail_initial_seconds FROM users WHERE user_id = $1 FOR UPDATE", [target_id]);
        if (targetRes.rows.length === 0) throw new Error("Inmate not found.");
        const target = targetRes.rows[0];

        if (!target.jail_expires_at || new Date(target.jail_expires_at) <= new Date()) {
            throw new Error("This citizen is already free.");
        }

        // Calculate Bail Cost: $100 Clean Cash per initial minute
        const initialMinutes = Math.ceil(target.jail_initial_seconds / 60);
        const bailCost = initialMinutes * 100;

        if (payer.clean_cash < bailCost) {
            throw new Error(`Insufficient Clean Cash. Bail is set at $${bailCost.toLocaleString()}.`);
        }

        const isSelfBail = (parseInt(user_id) === parseInt(target_id));
        const ipReward = isSelfBail ? 0 : 25;

        // Deduct Cash and award IP to Payer
        await client.query(`
            UPDATE users
            SET clean_cash = clean_cash - $1, influence = influence + $2
            WHERE user_id = $3
        `, [bailCost, ipReward, user_id]);

        // Release Target
        await client.query(`
            UPDATE users
            SET jail_expires_at = NULL, jail_initial_seconds = 0
            WHERE user_id = $1
        `, [target_id]);

        await client.query('COMMIT');

        const message = isSelfBail
            ? `You paid your $${bailCost.toLocaleString()} bail and have been released.`
            : `You paid $${bailCost.toLocaleString()} to bail out ${target.username}. Earned +25 IP.`;

        res.json({ success: true, message: message });

    } catch (err) {
        await client.query('ROLLBACK');
        res.status(400).json({ error: err.message || "Bail transaction failed." });
    } finally {
        client.release();
    }
});

// ==========================================
// 3. BREAKOUT (NERVE & RNG)
// ==========================================
router.post('/breakout', async (req, res) => {
    const client = await pool.connect();

    try {
        const { user_id, target_id } = req.body;
        const nerveCost = 5; // Flat nerve cost for breakout attempts

        await client.query('BEGIN');

        // Fetch Actor
        const actorRes = await client.query("SELECT nerve, heat, jail_expires_at FROM users WHERE user_id = $1 FOR UPDATE", [user_id]);
        if (actorRes.rows.length === 0) throw new Error("Actor account not found.");
        const actor = actorRes.rows[0];

        if (actor.nerve < nerveCost) throw new Error("Not enough Nerve to attempt a breakout.");

        // Fetch Target
        const targetRes = await client.query("SELECT username, jail_expires_at FROM users WHERE user_id = $1 FOR UPDATE", [target_id]);
        if (targetRes.rows.length === 0) throw new Error("Inmate not found.");
        const target = targetRes.rows[0];

        if (!target.jail_expires_at || new Date(target.jail_expires_at) <= new Date()) {
            throw new Error("This citizen is already free.");
        }

        const isEscape = (parseInt(user_id) === parseInt(target_id));

        // Breakout Math: Flat 40% chance for now.
        const successChance = 40;
        const roll = Math.floor(Math.random() * 100) + 1;

        if (roll <= successChance) {
            // SUCCESS
            await client.query("UPDATE users SET nerve = nerve - $1 WHERE user_id = $2", [nerveCost, user_id]);
            await client.query("UPDATE users SET jail_expires_at = NULL, jail_initial_seconds = 0 WHERE user_id = $1", [target_id]);

            await client.query('COMMIT');

            const message = isEscape
                ? "You successfully broke out of your cell! Keep a low profile."
                : `You successfully broke ${target.username} out of state prison!`;

            res.json({ success: true, message: message });

        } else {
            // FAILURE: +20% Heat and +1 Hour Jail Time to the ACTOR
            const oneHourInterval = "INTERVAL '1 hour'";
            const isActorAlreadyJailed = actor.jail_expires_at && new Date(actor.jail_expires_at) > new Date();

            let jailUpdateSql = isActorAlreadyJailed
                ? `jail_expires_at = jail_expires_at + ${oneHourInterval}, jail_initial_seconds = jail_initial_seconds + 3600`
                : `jail_expires_at = NOW() + ${oneHourInterval}, jail_initial_seconds = 3600`;

            await client.query(`
                UPDATE users
                SET nerve = nerve - $1,
                    heat = LEAST(heat + 20.00, 100.00),
                    ${jailUpdateSql}
                WHERE user_id = $2
            `, [nerveCost, user_id]);

            await client.query('COMMIT');

            const message = isEscape
                ? "The guards caught you trying to escape. +20% Heat and +1 Hour added to your sentence."
                : `You were caught trying to bust out ${target.username}. You have been arrested! +20% Heat and a 1 Hour sentence.`;

            res.json({ success: false, arrested: !isActorAlreadyJailed, message: message });
        }

    } catch (err) {
        await client.query('ROLLBACK');
        res.status(400).json({ error: err.message || "Breakout attempt failed." });
    } finally {
        client.release();
    }
});

// ==========================================
// 4. THE PRISON YARD (NERFED GYM)
// ==========================================
// NOTE: Since this is in the /jail router, the endpoint is now: POST /jail/gym/train
router.post('/gym/train', async (req, res) => {
    const client = await pool.connect();

    try {
        const { user_id, energy_spent } = req.body;

        await client.query('BEGIN');

        // Fetch User & Verify Incarceration
        const userRes = await client.query(`
            SELECT energy, exp, stat_str, stat_def, stat_dex, stat_spd, jail_expires_at
            FROM users WHERE user_id = $1 FOR UPDATE
        `, [user_id]);

        if (userRes.rows.length === 0) throw new Error("User not found.");
        const user = userRes.rows[0];

        // 🚨 SECURITY: Ensure they are ACTUALLY in jail to use this!
        if (!user.jail_expires_at || new Date(user.jail_expires_at) <= new Date()) {
            await client.query('ROLLBACK');
            return res.status(403).json({ error: "You are not an inmate. Get out of the prison yard." });
        }

        if (user.energy < energy_spent || energy_spent < 1) {
            await client.query('ROLLBACK');
            return res.status(400).json({ error: "Not enough energy." });
        }

        // The Prison Yard Math (Splits evenly across all 4 stats)
        const currentStr = parseFloat(user.stat_str);
        const currentDef = parseFloat(user.stat_def);
        const currentDex = parseFloat(user.stat_dex);
        const currentSpd = parseFloat(user.stat_spd);

        // We use their average stat to calculate the baseline gain
        const avgStat = (currentStr + currentDef + currentDex + currentSpd) / 4.0;

        // Calculate Base Gain for exactly 1 Energy
        const baseGainPerEnergy = (avgStat * JAIL_MULTIPLIER) + JAIL_FLAT_RATE;

        // Total raw gain for the energy spent
        const totalStatGain = baseGainPerEnergy * energy_spent;

        // Split exactly 4 ways per the GDD
        const splitGain = (totalStatGain / 4.0).toFixed(2);

        // Inmates get standard Player EXP, but NO Gym EXP
        const playerExpGain = 5 * energy_spent;

        // Apply the split gains
        const updateQuery = `
            UPDATE users
            SET
                energy = energy - $1,
                exp = exp + $2,
                stat_str = stat_str + $3,
                stat_def = stat_def + $3,
                stat_dex = stat_dex + $3,
                stat_spd = stat_spd + $3
            WHERE user_id = $4
            RETURNING *;
        `;

        const updatedUser = await client.query(updateQuery, [energy_spent, playerExpGain, parseFloat(splitGain), user_id]);

        await client.query('COMMIT');

        // --- INJECTED ACHIEVEMENT ENGINE FIRE AND FORGET ---
        trackAndCheckAchievement(user_id, 'total_gym_trains', 1, 'user_statistics');
        trackAndCheckAchievement(user_id, 'total_energy_spent', energy_spent, 'user_statistics');

        res.json({
            success: true,
            message: `You pushed iron in the yard. Gained +${splitGain} to all stats.`,
            gained_per_stat: splitGain,
            user: updatedUser.rows[0]
        });

    } catch (err) {
        await client.query('ROLLBACK');
        console.error("Jail Gym Error:", err.message);
        res.status(500).json({ error: "Server error during yard workout." });
    } finally {
        client.release();
    }
});

module.exports = router;