const express = require('express');
const pool = require('../db');
const router = express.Router();
const { trackAndCheckAchievement } = require('../utils/achievement_engine'); // INJECTED ACHIEVEMENT ENGINE

// --- FETCH CRIME LIST ---
router.get('/list', async (req, res) => {
    try {
        const crimes = await pool.query("SELECT * FROM crimes_master ORDER BY req_stat_value ASC");
        res.json(crimes.rows);
    } catch (err) {
        console.error("Fetch Crimes Error:", err.message);
        res.status(500).json({ error: "Failed to load Job Board." });
    }
});

// --- EXECUTE MANUAL CRIME (V1.3 FIXED) ---
router.post('/execute', async (req, res) => {
    const client = await pool.connect();

    try {
        const { user_id, crime_id } = req.body;

        await client.query('BEGIN');

        // 1. Cooldown Lockout Check
        const cooldownCheck = await client.query("SELECT * FROM user_cooldowns WHERE user_id = $1 AND expires_at > NOW()", [user_id]);
        if (cooldownCheck.rows.length > 0) {
            await client.query('ROLLBACK');
            const activeCd = cooldownCheck.rows[0].type;
            const reason = cooldownCheck.rows[0].reason || "Unknown";
            return res.status(403).json({ error: activeCd === 'hospital' ? `You are in the hospital. Reason: ${reason}` : `You are locked behind bars. Reason: ${reason}` });
        }

        // 2. Fetch User & Lock Row
        const userCheck = await client.query("SELECT * FROM users WHERE user_id = $1 FOR UPDATE", [user_id]);
        if (userCheck.rows.length === 0) {
            await client.query('ROLLBACK');
            return res.status(404).json({ error: "Ghost account." });
        }
        const user = userCheck.rows[0];

        // 3. HP Lockout
        if (user.hp < 25) {
            await client.query('ROLLBACK');
            return res.status(403).json({ error: "You are too weak. Wait for the hospital or heal up to 25 HP first." });
        }

        // 4. Fetch Crime Details
        const crimeCheck = await client.query("SELECT * FROM crimes_master WHERE crime_id = $1", [crime_id]);
        if (crimeCheck.rows.length === 0) {
            await client.query('ROLLBACK');
            return res.status(404).json({ error: "Crime not found." });
        }
        const crime = crimeCheck.rows[0];

        // 5. Resource Check
        if (user.energy < crime.energy_cost) { await client.query('ROLLBACK'); return res.status(400).json({ error: "Not enough Energy." }); }
        if (user.nerve < crime.nerve_cost) { await client.query('ROLLBACK'); return res.status(400).json({ error: "Not enough Nerve." }); }

        // 6. TOOL VERIFICATION
        const rawToolReq = crime.tool_req ? crime.tool_req.trim().toUpperCase() : "NONE";
        const isToolActuallyRequired = rawToolReq !== "NONE" && rawToolReq !== "NULL" && rawToolReq !== "";

        if (isToolActuallyRequired) {
            const toolCheck = await client.query(
                `SELECT ui.quantity FROM user_inventory ui
                 JOIN items_master im ON ui.item_id = im.item_id
                 WHERE ui.user_id = $1 AND UPPER(im.name) = $2`,
                [user_id, rawToolReq]
            );

            if (toolCheck.rows.length === 0 || toolCheck.rows[0].quantity < 1) {
                await client.query('ROLLBACK');
                return res.status(400).json({ error: `You need a [${crime.tool_req}] to execute this hustle.` });
            }
        }

        // 7. Dynamic Math & RNG Engine
        const playerStat = parseFloat(user[`stat_${crime.req_stat_type}`]) || 10.0;
        let successChance = (playerStat / crime.req_stat_value) * 100;
        if (successChance < 5) successChance = 5;   // 5% minimum chance
        if (successChance > 95) successChance = 95; // 95% maximum chance

        const roll = Math.floor(Math.random() * 100) + 1;

        // 8. OUTCOME PROCESSING
        if (roll <= successChance) {
            // SUCCESS BRANCH (Restored from the missing block)
            const payout = Math.floor(Math.random() * (crime.max_payout - crime.min_payout + 1)) + crime.min_payout;
            const expGain = 10;
            const crimeExpGain = 5;

            const updatedUser = await client.query(
                "UPDATE users SET energy = energy - $1, nerve = nerve - $2, dirty_cash = dirty_cash + $3, exp = exp + $4, crime_exp = crime_exp + $5 WHERE user_id = $6 RETURNING dirty_cash, energy, nerve, max_nerve, hp, exp, crime_exp",
                [crime.energy_cost, crime.nerve_cost, payout, expGain, crimeExpGain, user_id]
            );

            await client.query("UPDATE user_crime_records SET total_crimes = total_crimes + 1, total_successes = total_successes + 1 WHERE user_id = $1", [user_id]);

            await client.query('COMMIT');

            // --- INJECTED ACHIEVEMENT ENGINE ---
            trackAndCheckAchievement(user_id, 'total_successes', 1, 'user_crime_records');
            trackAndCheckAchievement(user_id, 'total_nerve_spent', crime.nerve_cost, 'user_statistics');
            trackAndCheckAchievement(user_id, 'lifetime_dirty_cash', payout, 'user_statistics');

            return res.json({ status: "success", message: crime.success_text, gained_cash: payout, user: updatedUser.rows[0] });

        } else {
            // FAILURE BRANCHES (With Dynamic Speed Mitigation)
            await client.query("UPDATE user_crime_records SET total_crimes = total_crimes + 1, total_fails = total_fails + 1 WHERE user_id = $1", [user_id]);

            // Calculate Escape Chance based on Player Speed vs Crime Difficulty
            const playerSpd = parseFloat(user.stat_spd) || 10.0;
            let escapeChance = 33 + ((playerSpd / crime.req_stat_value) * 20);

            // Hard Cap: Minimum 10% chance to escape, Maximum 85% chance to escape
            if (escapeChance < 10) escapeChance = 10;
            if (escapeChance > 85) escapeChance = 85;

            // Split the remaining percentage between Hospital and Jail
            const remainingRisk = 100 - escapeChance;
            const hospRisk = remainingRisk / 2;

            const failRoll = Math.random() * 100;

            if (failRoll <= escapeChance) {
                // ESCAPED
                const updatedUser = await client.query("UPDATE users SET energy = energy - $1, nerve = nerve - $2, hp = GREATEST(hp - 10, 1) WHERE user_id = $3 RETURNING dirty_cash, energy, nerve, max_nerve, hp", [crime.energy_cost, crime.nerve_cost, user_id]);
                await client.query('COMMIT');

                trackAndCheckAchievement(user_id, 'total_fails', 1, 'user_crime_records');
                trackAndCheckAchievement(user_id, 'total_nerve_spent', crime.nerve_cost, 'user_statistics');

                return res.json({ status: "escaped", message: crime.escape_text, user: updatedUser.rows[0] });

            } else if (failRoll <= (escapeChance + hospRisk)) {
                // HOSPITALIZED
                const updatedUser = await client.query("UPDATE users SET energy = energy - $1, nerve = nerve - $2, hp = 1 WHERE user_id = $3 RETURNING dirty_cash, energy, nerve, max_nerve, hp", [crime.energy_cost, crime.nerve_cost, user_id]);
                await client.query("INSERT INTO user_cooldowns (user_id, type, expires_at, reason) VALUES ($1, 'hospital', NOW() + INTERVAL '1 minute', 'Botched a street hustle.')", [user_id]);
                await client.query('COMMIT');

                trackAndCheckAchievement(user_id, 'total_fails', 1, 'user_crime_records');
                trackAndCheckAchievement(user_id, 'total_nerve_spent', crime.nerve_cost, 'user_statistics');

                return res.json({ status: "hospitalized", message: crime.hosp_text, user: updatedUser.rows[0] });

            } else {
                // JAILED
                await client.query("UPDATE user_crime_records SET total_jailed = total_jailed + 1 WHERE user_id = $1", [user_id]);
                const updatedUser = await client.query("UPDATE users SET energy = energy - $1, nerve = nerve - $2 WHERE user_id = $3 RETURNING dirty_cash, energy, nerve, max_nerve, hp", [crime.energy_cost, crime.nerve_cost, user_id]);
                await client.query("INSERT INTO user_cooldowns (user_id, type, expires_at, reason) VALUES ($1, 'jail', NOW() + INTERVAL '1 minute', 'Busted by the police.')", [user_id]);
                await client.query('COMMIT');

                trackAndCheckAchievement(user_id, 'total_fails', 1, 'user_crime_records');
                trackAndCheckAchievement(user_id, 'total_nerve_spent', crime.nerve_cost, 'user_statistics');

                return res.json({ status: "jailed", message: crime.jail_text, user: updatedUser.rows[0] });
            }
        }
    } catch (err) {
        await client.query('ROLLBACK');
        console.error("Crime Error:", err.message);
        res.status(500).json({ error: "Hustle engine malfunction." });
    } finally {
        client.release();
    }
});

module.exports = router;