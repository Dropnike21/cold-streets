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

// --- EXECUTE MANUAL CRIME (V1.4 - HEAT & ARREST UPDATE) ---
router.post('/execute', async (req, res) => {
    const client = await pool.connect();

    try {
        const { user_id, crime_id } = req.body;

        await client.query('BEGIN');

        // 1. Fetch User & Lock Row (Moved up to do all checks in one go)
        const userCheck = await client.query("SELECT * FROM users WHERE user_id = $1 FOR UPDATE", [user_id]);
        if (userCheck.rows.length === 0) {
            await client.query('ROLLBACK');
            return res.status(404).json({ error: "Ghost account." });
        }
        const user = userCheck.rows[0];
        const now = new Date();

        // 2. Cooldown Lockout Check (Updated to use new DB Schema)
        if (user.jail_expires_at && new Date(user.jail_expires_at) > now) {
            await client.query('ROLLBACK');
            return res.status(403).json({ error: "You are locked behind bars." });
        }
        if (user.hospital_expires_at && new Date(user.hospital_expires_at) > now) {
            await client.query('ROLLBACK');
            return res.status(403).json({ error: "You are recovering in the hospital." });
        }

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

        // ==========================================
        // 7. HEAT & AUTOMATIC ARREST CHECK
        // ==========================================
        let currentHeat = parseFloat(user.heat) || 0.0;
        let heatGained = 0.50; // Set to 0.01 per GDD, but keeping at 0.50 for testing visibility

        if (currentHeat + heatGained >= 100.00) {
            // 🚨 BUSTED! 100% Heat Reached. Override normal rolls.
            await client.query(`
                UPDATE users
                SET
                    energy = energy - $1,
                    nerve = nerve - $2,
                    heat = LEAST(heat + 60.00, 100.00), -- +60% Penalty
                    dirty_cash = 0, -- Confiscate Dirty Cash
                    influence = GREATEST(0, influence - 50), -- Public Scandal
                    jail_initial_seconds = 7200, -- 2 Hour Sentence
                    jail_expires_at = NOW() + INTERVAL '7200 seconds',
                    state_reason = 'Arrested by Federal Agents as one of the most wanted.'
                WHERE user_id = $3
            `, [crime.energy_cost, crime.nerve_cost, user_id]);

            await client.query("UPDATE user_crime_records SET total_crimes = total_crimes + 1, total_jailed = total_jailed + 1 WHERE user_id = $1", [user_id]);
            await client.query('COMMIT');

            return res.json({
                status: "jailed",
                arrested: true,
                message: "100% HEAT REACHED! The cops were waiting. You lost all Dirty Cash, 50 Influence, and were sent to state prison."
            });
        }

        // ==========================================
        // 8. DYNAMIC MATH & RNG ENGINE
        // ==========================================
        const playerStat = parseFloat(user[`stat_${crime.req_stat_type.toLowerCase()}`]) || 10.0;
        let successChance = (playerStat / crime.req_stat_value) * 100;
        if (successChance < 5) successChance = 5;   // 5% minimum chance
        if (successChance > 95) successChance = 95; // 95% maximum chance

        const roll = Math.floor(Math.random() * 100) + 1;

        // ==========================================
        // 9. OUTCOME PROCESSING
        // ==========================================
        if (roll <= successChance) {
            // SUCCESS BRANCH
            const payout = Math.floor(Math.random() * (crime.max_payout - crime.min_payout + 1)) + crime.min_payout;
            const expGain = 10;
            const crimeExpGain = 5;

            const updatedUser = await client.query(
                `UPDATE users
                 SET energy = energy - $1,
                     nerve = nerve - $2,
                     dirty_cash = dirty_cash + $3,
                     exp = exp + $4,
                     crime_exp = crime_exp + $5,
                     heat = LEAST(heat + $6, 100.00)
                 WHERE user_id = $7
                 RETURNING dirty_cash, energy, nerve, max_nerve, hp, exp, crime_exp, heat`,
                [crime.energy_cost, crime.nerve_cost, payout, expGain, crimeExpGain, heatGained, user_id]
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

            const playerSpd = parseFloat(user.stat_spd) || 10.0;
            let escapeChance = 33 + ((playerSpd / crime.req_stat_value) * 20);

            if (escapeChance < 10) escapeChance = 10;
            if (escapeChance > 85) escapeChance = 85;

            const remainingRisk = 100 - escapeChance;
            const hospRisk = remainingRisk / 2;

            const failRoll = Math.random() * 100;

            if (failRoll <= escapeChance) {
                // ESCAPED
                const updatedUser = await client.query(
                    "UPDATE users SET energy = energy - $1, nerve = nerve - $2, hp = GREATEST(hp - 10, 1), heat = LEAST(heat + $3, 100.00) WHERE user_id = $4 RETURNING dirty_cash, energy, nerve, max_nerve, hp, heat",
                    [crime.energy_cost, crime.nerve_cost, heatGained, user_id]
                );
                await client.query('COMMIT');

                trackAndCheckAchievement(user_id, 'total_fails', 1, 'user_crime_records');
                trackAndCheckAchievement(user_id, 'total_nerve_spent', crime.nerve_cost, 'user_statistics');

                return res.json({ status: "escaped", message: crime.escape_text, user: updatedUser.rows[0] });

            } else if (failRoll <= (escapeChance + hospRisk)) {
                // HOSPITALIZED
                const updatedUser = await client.query(
                    `UPDATE users
                     SET energy = energy - $1,
                         nerve = nerve - $2,
                         hp = 1,
                         heat = LEAST(heat + $3, 100.00),
                         hospital_expires_at = NOW() + INTERVAL '1 minute',
                         state_reason = $5
                     WHERE user_id = $4
                     RETURNING dirty_cash, energy, nerve, max_nerve, hp, heat`,
                    [crime.energy_cost, crime.nerve_cost, heatGained, user_id, crime.hosp_text]
                );
                await client.query('COMMIT');

                trackAndCheckAchievement(user_id, 'total_fails', 1, 'user_crime_records');
                trackAndCheckAchievement(user_id, 'total_nerve_spent', crime.nerve_cost, 'user_statistics');

                return res.json({ status: "hospitalized", message: crime.hosp_text, user: updatedUser.rows[0] });

            } else {
                // JAILED
                await client.query("UPDATE user_crime_records SET total_jailed = total_jailed + 1 WHERE user_id = $1", [user_id]);
                const updatedUser = await client.query(
                    `UPDATE users
                     SET energy = energy - $1,
                         nerve = nerve - $2,
                         heat = LEAST(heat + $3, 100.00),
                         jail_initial_seconds = 60,
                         jail_expires_at = NOW() + INTERVAL '1 minute',
                         state_reason = $5
                     WHERE user_id = $4
                     RETURNING dirty_cash, energy, nerve, max_nerve, hp, heat`,
                    [crime.energy_cost, crime.nerve_cost, heatGained, user_id, crime.jail_text]
                );
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