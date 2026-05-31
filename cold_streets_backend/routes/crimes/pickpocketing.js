// crimes/pickpocketing.js
const { trackAndCheckAchievement } = require('../../utils/achievement_engine');

async function listTargets(client, res) {
    try {
        const crimes = await client.query("SELECT * FROM crimes_master WHERE sub_category = 'Pickpocketing' ORDER BY id ASC");
        // We now just send the raw templates. The DB holds their specific activities!
        res.json({ templates: crimes.rows });
    } catch (err) {
        console.error("Pickpocket List Error:", err.message);
        res.status(500).json({ error: "Failed to load crowd data." });
    }
}

async function execute(client, user, crime, req, res) {
    try {
        const rewards = crime.rewards_json || {};
        const penalties = crime.penalties_json || {};
        const flavor = crime.flavor_text_json || {};
        const mechanics = crime.mechanics_json || {};

        // The app tells us WHICH activity the target was doing when the player attacked
        const activityName = req.body.activity_name;

        if (user.nerve < crime.nerve_cost) {
            await client.query('ROLLBACK');
            return res.status(400).json({ error: "Not enough Nerve." });
        }

        const getRandomText = (array) => (array && array.length > 0) ? array[Math.floor(Math.random() * array.length)] : "The job is done.";

        let currentHeat = parseFloat(user.heat) || 0.0;
        let heatGained = penalties.heat_gen || 0.25;

        if (currentHeat + heatGained >= 100.00) {
            await client.query(`UPDATE users SET nerve = nerve - $1, heat = LEAST(heat + 60.00, 100.00), dirty_cash = 0, influence = GREATEST(0, influence - 50), jail_initial_seconds = 7200, jail_expires_at = NOW() + INTERVAL '7200 seconds', state_reason = 'Arrested by Federal Agents.' WHERE user_id = $2`, [crime.nerve_cost, user.user_id]);
            await client.query("UPDATE user_crime_records SET total_crimes = total_crimes + 1, total_jailed = total_jailed + 1 WHERE user_id = $1", [user.user_id]);
            await client.query('COMMIT');
            return res.json({ status: "jailed", arrested: true, message: "100% HEAT REACHED! The cops were waiting. You lost all Dirty Cash and were sent to state prison." });
        }

        // --- MATH ENGINE: Securely looking up the exact modifier ---
        const activitiesList = mechanics.activities || [];
        const matchedActivity = activitiesList.find(a => a.name === activityName);

        // If they send a fake activity, default to 0 bonus
        const activityMod = matchedActivity ? (parseFloat(matchedActivity.mod) || 0.0) : 0.0;

        const nerveCost = parseFloat(crime.nerve_cost) || 1.0;
        let baseChance = 95.0 - (nerveCost * 0.8);

        let finalChance = baseChance + activityMod;
        finalChance = Math.max(5.0, Math.min(99.0, finalChance));

        const roll = Math.random() * 100;

        if (roll <= finalChance) {
            // SUCCESS
            const payout = Math.floor(Math.random() * ((rewards.max_cash || 0) - (rewards.min_cash || 0) + 1)) + (rewards.min_cash || 0);

            const lootData = rewards.loot || {};
            if (lootData && lootData.item_id && lootData.chance) {
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

            const flavorText = (Math.random() * 100 <= 5) ? getRandomText(flavor.crit) : getRandomText(flavor.success);
            return res.json({ status: "success", message: flavorText, gained_cash: payout, user: updatedUser.rows[0] });

        } else {
            // FAILURE
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
        console.error("Pickpocketing Engine Error:", err.message);
        res.status(500).json({ error: "Hustle engine malfunction." });
    }
}

module.exports = { execute, listTargets };