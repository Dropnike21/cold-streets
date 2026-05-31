const { trackAndCheckAchievement } = require('../../utils/achievement_engine');

// Helper to calculate if the current time is inside a window (handles midnight wrap-around)
function isInsideWindow(progress, window) {
    if (!window || window.length !== 2) return false;
    const start = window[0];
    const end = window[1];

    if (start > end) {
        // Wrap-around logic (e.g., 0.95 to 0.05)
        return progress >= start || progress <= end;
    } else {
        // Normal logic (e.g., 0.10 to 0.15)
        return progress >= start && progress <= end;
    }
}

async function execute(client, user, crime, req, res) {
    try {
        const reqs = crime.requirements_json || {};
        const rewards = crime.rewards_json || {};
        const penalties = crime.penalties_json || {};
        const flavor = crime.flavor_text_json || {};
        const mechanics = crime.mechanics_json || {};

        // 1. Resource & Tool Check
        if (user.nerve < crime.nerve_cost) {
            await client.query('ROLLBACK');
            return res.status(400).json({ error: "Not enough Nerve." });
        }

        const toolReq = reqs.tool_req;
        if (toolReq !== undefined && toolReq !== "NONE" && toolReq !== "NULL" && toolReq !== "") {
            let toolQuery = `SELECT ui.quantity, im.name FROM user_inventory ui JOIN items_master im ON ui.item_id = im.item_id WHERE ui.user_id = $1 AND `;
            let param;

            // Allow looking up tools by ID (e.g., 371) or by Name
            if (!isNaN(toolReq)) {
                toolQuery += `im.item_id = $2`;
                param = parseInt(toolReq);
            } else {
                toolQuery += `UPPER(im.name) = $2`;
                param = toolReq.toString().trim().toUpperCase();
            }

            const toolCheck = await client.query(toolQuery, [user.user_id, param]);
            if (toolCheck.rows.length === 0 || toolCheck.rows[0].quantity < 1) {
                await client.query('ROLLBACK');
                return res.status(400).json({ error: `You lack the required tool to bypass this security.` });
            }
        }

        const getRandomText = (array) => (array && array.length > 0) ? array[Math.floor(Math.random() * array.length)] : "The job is done.";

        // 2. Heat Check
        let currentHeat = parseFloat(user.heat) || 0.0;
        let heatGained = penalties.heat_gen || 0.75;

        if (currentHeat + heatGained >= 100.00) {
            await client.query(`UPDATE users SET nerve = nerve - $1, heat = LEAST(heat + 60.00, 100.00), dirty_cash = 0, influence = GREATEST(0, influence - 50), jail_initial_seconds = 7200, jail_expires_at = NOW() + INTERVAL '7200 seconds', state_reason = 'Arrested by Federal Agents.' WHERE user_id = $2`, [crime.nerve_cost, user.user_id]);
            await client.query("UPDATE user_crime_records SET total_crimes = total_crimes + 1, total_jailed = total_jailed + 1 WHERE user_id = $1", [user.user_id]);
            await client.query('COMMIT');
            return res.json({ status: "jailed", arrested: true, message: "100% HEAT REACHED! The cops were waiting. You lost all Dirty Cash and were sent to state prison." });
        }

        // 3. THE SHOPLIFTING MATH ENGINE (Synced with UTC Master Clock)
        const now = new Date();
        const secondsInDay = (now.getUTCHours() * 3600) + (now.getUTCMinutes() * 60) + now.getUTCSeconds();
        const timeProgress = secondsInDay / 86400.0;

        let cctvScore = 99.0;
        let guardScore = 99.0;

        if (mechanics.has_cctv) {
            if (isInsideWindow(timeProgress, mechanics.cctv_reboot)) {
                cctvScore = 99.0; // Cameras blind
            } else {
                cctvScore = 15.0; // Cameras recording! High penalty.
            }
        }

        if (mechanics.has_guards) {
            if (isInsideWindow(timeProgress, mechanics.guard_break)) {
                guardScore = 99.0; // On Break
            } else if (isInsideWindow(timeProgress, mechanics.guard_swap)) {
                guardScore = 60.0; // Shift Swap
            } else {
                guardScore = 10.0; // On Duty! Max Penalty.
            }
        }

        const successChance = (cctvScore + guardScore) / 2.0;
        const roll = Math.random() * 100;

        // 4. Outcome Processing
        if (roll <= successChance) {
            // SUCCESS
            const payout = Math.floor(Math.random() * ((rewards.max_cash || 0) - (rewards.min_cash || 0) + 1)) + (rewards.min_cash || 0);

            // Give item loot if it procs
            const lootData = rewards.loot || {};
            if (lootData.item_id && lootData.chance) {
                const lootRoll = Math.random() * 100;
                if (lootRoll <= lootData.chance) {
                    await client.query(
                        `INSERT INTO user_inventory (user_id, item_id, quantity) VALUES ($1, $2, $3)
                         ON CONFLICT (user_id, item_id) DO UPDATE SET quantity = user_inventory.quantity + EXCLUDED.quantity`,
                        [user.user_id, lootData.item_id, lootData.qty || 1]
                    );
                }
            }

            const updatedUser = await client.query(
                `UPDATE users SET nerve = nerve - $1, dirty_cash = dirty_cash + $2, exp = exp + $3, crime_exp = crime_exp + $4, heat = LEAST(heat + $5, 100.00) WHERE user_id = $6 RETURNING dirty_cash, energy, nerve, max_nerve, hp, exp, crime_exp, heat`,
                [crime.nerve_cost, payout, (rewards.skill_exp || 10), (rewards.crime_exp || 5), heatGained, user.user_id]
            );

            await client.query("UPDATE user_crime_records SET total_crimes = total_crimes + 1, total_successes = total_successes + 1 WHERE user_id = $1", [user.user_id]);
            await client.query('COMMIT');
            trackAndCheckAchievement(user.user_id, 'total_successes', 1, 'user_crime_records');

            return res.json({ status: "success", message: getRandomText(flavor.success), gained_cash: payout, user: updatedUser.rows[0] });
        } else {
            // FAILURE / ESCAPE LOGIC
            await client.query("UPDATE user_crime_records SET total_crimes = total_crimes + 1, total_fails = total_fails + 1 WHERE user_id = $1", [user.user_id]);

            const playerSpd = parseFloat(user.stat_spd) || 10.0;
            let escapeChance = 33 + ((playerSpd / ((crime.req_skill_level * 10) || 10)) * 20);
            escapeChance = Math.max(10, Math.min(85, escapeChance));
            const failRoll = Math.random() * 100;

            if (failRoll <= escapeChance) {
                const updatedUser = await client.query("UPDATE users SET nerve = nerve - $1, hp = GREATEST(hp - 10, 1), heat = LEAST(heat + $2, 100.00) WHERE user_id = $3 RETURNING dirty_cash, energy, nerve, max_nerve, hp, heat", [crime.nerve_cost, heatGained, user.user_id]);
                await client.query('COMMIT');
                return res.json({ status: "escaped", message: getRandomText(flavor.fail), user: updatedUser.rows[0] });
            } else if (failRoll <= (escapeChance + ((100 - escapeChance) / 2))) {
                const hospSeconds = penalties.hosp_time || 60;
                const textHosp = getRandomText(flavor.hosp);
                const updatedUser = await client.query(`UPDATE users SET nerve = nerve - $1, hp = 1, heat = LEAST(heat + $2, 100.00), hospital_expires_at = NOW() + INTERVAL '${hospSeconds} seconds', state_reason = $4 WHERE user_id = $3 RETURNING dirty_cash, energy, nerve, max_nerve, hp, heat`, [crime.nerve_cost, heatGained, user.user_id, textHosp]);
                await client.query('COMMIT');
                return res.json({ status: "hospitalized", message: textHosp, user: updatedUser.rows[0] });
            } else {
                const jailSeconds = penalties.jail_time || 60;
                const textJail = getRandomText(flavor.jail);
                await client.query("UPDATE user_crime_records SET total_jailed = total_jailed + 1 WHERE user_id = $1", [user.user_id]);
                const updatedUser = await client.query(`UPDATE users SET nerve = nerve - $1, heat = LEAST(heat + $2, 100.00), jail_initial_seconds = $5, jail_expires_at = NOW() + INTERVAL '${jailSeconds} seconds', state_reason = $4 WHERE user_id = $3 RETURNING dirty_cash, energy, nerve, max_nerve, hp, heat`, [crime.nerve_cost, heatGained, user.user_id, textJail, jailSeconds]);
                await client.query('COMMIT');
                return res.json({ status: "jailed", message: textJail, user: updatedUser.rows[0] });
            }
        }
    } catch (err) {
        await client.query('ROLLBACK');
        console.error("Shoplifting Engine Error:", err.message);
        res.status(500).json({ error: "Hustle engine malfunction." });
    }
}

module.exports = { execute };