const { trackAndCheckAchievement } = require('../../utils/achievement_engine');

// --- 🚨 ADDED: MATH & ENVIRONMENT HELPERS ---
function getCrowdDensity(now) {
    let day = now.getUTCDay(); // 0 is Sun, 1 is Mon
    let hour = now.getUTCHours();
    let progress = now.getUTCMinutes() / 60.0;

    let curve;
    if (day >= 1 && day <= 5) {
        curve = [0.1, 0.1, 0.1, 0.1, 0.1, 0.2, 0.5, 0.8, 0.9, 0.7, 0.5, 0.6, 0.6, 0.5, 0.5, 0.7, 0.9, 0.95, 0.8, 0.5, 0.3, 0.2, 0.1, 0.1];
    } else if (day === 6) {
        curve = [0.1, 0.1, 0.1, 0.1, 0.1, 0.2, 0.3, 0.5, 0.7, 0.8, 0.9, 0.9, 0.9, 0.9, 0.9, 0.9, 0.8, 0.7, 0.8, 0.9, 0.7, 0.5, 0.3, 0.2];
    } else {
        curve = [0.1, 0.1, 0.1, 0.1, 0.1, 0.1, 0.2, 0.4, 0.7, 0.9, 1.0, 0.9, 0.7, 0.6, 0.5, 0.5, 0.4, 0.4, 0.3, 0.2, 0.2, 0.1, 0.1, 0.1];
    }

    let currentHourDensity = curve[hour];
    let nextHourDensity = curve[(hour + 1) % 24];
    return currentHourDensity + ((nextHourDensity - currentHourDensity) * progress);
}

function getDeterministicWeather(secondsSinceEpoch) {
    const chunkSize = 14400;
    const transitionTime = 2400;

    let currentChunk = Math.floor(secondsSinceEpoch / chunkSize);
    let timeInChunk = secondsSinceEpoch % chunkSize;

    function getSeededRandom(seed) {
        return ((seed * 9301) + 49297) % 233280 / 233280.0;
    }

    let prevWeather = getSeededRandom(currentChunk - 1);
    let targetWeather = getSeededRandom(currentChunk);

    if (timeInChunk < transitionTime) {
        let progress = timeInChunk / transitionTime;
        return prevWeather + ((targetWeather - prevWeather) * progress);
    } else {
        return targetWeather;
    }
}

function getCityMeters() {
    let now = new Date();
    let dayOfWeek = now.getUTCDay();
    let secondsInDay = (now.getUTCHours() * 3600) + (now.getUTCMinutes() * 60) + now.getUTCSeconds();
    let secondsInWeek = (dayOfWeek * 86400) + secondsInDay;
    let secondsSinceEpoch = Math.floor(now.getTime() / 1000);

    return {
        'time_of_day': secondsInDay / 86400.0,
        'police_patrol': secondsInDay / 86400.0,
        'municipal_services': secondsInWeek / 604800.0,
        'crowd_density': getCrowdDensity(now),
        'weather_condition': getDeterministicWeather(secondsSinceEpoch)
    };
}

function getDistance(meterType, current, min, max, isCyclical) {
    if (isCyclical && min > max) {
        if (current >= min || current <= max) return 0.0;
    } else {
        if (current >= min && current <= max) return 0.0;
    }

    if (meterType === 'municipal_services') {
        if (current > max) return 1.0;
        return Math.abs(min - current);
    }

    let distToMin = Math.abs(current - min);
    let distToMax = Math.abs(current - max);

    if (isCyclical) {
        if (distToMin > 0.5) distToMin = 1.0 - distToMin;
        if (distToMax > 0.5) distToMax = 1.0 - distToMax;
    }
    return Math.min(distToMin, distToMax);
}

function getMeterScore(meterType, currentPct, spotsArray) {
    let bestScore = 10.0;
    let isCyclical = (meterType === 'time_of_day' || meterType === 'police_patrol' || meterType === 'weather_condition');

    for (let spot of spotsArray) {
        let min = parseFloat(spot[0]);
        let max = parseFloat(spot[1]);

        let distance = getDistance(meterType, currentPct, min, max, isCyclical);
        if (distance === 0.0) return 99.0;

        let maxDist = isCyclical ? 0.5 : 1.0;
        let fractionOutside = distance / maxDist;

        let harshPenalty = Math.pow(fractionOutside, 0.5) * 89.0;
        let score = 99.0 - harshPenalty;

        if (score > bestScore) bestScore = score;
    }
    return Math.max(10.0, Math.min(99.0, bestScore));
}

// --- THE EXECUTION FUNCTION ---
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

        const rawToolReq = reqs.tool_req ? reqs.tool_req.toString().trim().toUpperCase() : "NONE";
        if (rawToolReq !== "NONE" && rawToolReq !== "NULL" && rawToolReq !== "") {
            const toolCheck = await client.query(
                `SELECT ui.quantity FROM user_inventory ui
                 JOIN items_master im ON ui.item_id = im.item_id
                 WHERE ui.user_id = $1 AND UPPER(im.name) = $2`,
                [user.user_id, rawToolReq]
            );
            if (toolCheck.rows.length === 0 || toolCheck.rows[0].quantity < 1) {
                await client.query('ROLLBACK');
                return res.status(400).json({ error: `You need a [${rawToolReq}] to execute this.` });
            }
        }

        const getRandomText = (array) => (array && array.length > 0) ? array[Math.floor(Math.random() * array.length)] : "The streets are silent.";

        // 2. Heat Check
        let currentHeat = parseFloat(user.heat) || 0.0;
        let heatGained = penalties.heat_gen || 0.50;

        if (currentHeat + heatGained >= 100.00) {
            await client.query(`UPDATE users SET nerve = nerve - $1, heat = LEAST(heat + 60.00, 100.00), dirty_cash = 0, influence = GREATEST(0, influence - 50), jail_initial_seconds = 7200, jail_expires_at = NOW() + INTERVAL '7200 seconds', state_reason = 'Arrested by Federal Agents.' WHERE user_id = $2`, [crime.nerve_cost, user.user_id]);
            await client.query("UPDATE user_crime_records SET total_crimes = total_crimes + 1, total_jailed = total_jailed + 1 WHERE user_id = $1", [user.user_id]);
            await client.query('COMMIT');
            return res.json({ status: "jailed", arrested: true, message: "100% HEAT REACHED! The cops were waiting. You lost all Dirty Cash and were sent to state prison." });
        }

        // 3. Math Engine
        const cityMeters = getCityMeters();
        const pSpots = mechanics.p_spots || [[mechanics.p_min || 0.0, mechanics.p_max || 1.0]];
        const sSpots = mechanics.s_spots || [[mechanics.s_min || 0.0, mechanics.s_max || 1.0]];

        const pScore = getMeterScore(mechanics.primary_meter, cityMeters[mechanics.primary_meter] || 0.5, pSpots);
        const sScore = getMeterScore(mechanics.secondary_meter, cityMeters[mechanics.secondary_meter] || 0.5, sSpots);

        const successChance = (pScore + sScore) / 2.0;
        const roll = Math.random() * 100;

        // 4. Outcome Processing
        if (roll <= successChance) {
            const payout = Math.floor(Math.random() * ((rewards.max_cash || 0) - (rewards.min_cash || 0) + 1)) + (rewards.min_cash || 0);

            const updatedUser = await client.query(
                `UPDATE users SET nerve = nerve - $1, dirty_cash = dirty_cash + $2, exp = exp + $3, crime_exp = crime_exp + $4, heat = LEAST(heat + $5, 100.00) WHERE user_id = $6 RETURNING dirty_cash, energy, nerve, max_nerve, hp, exp, crime_exp, heat`,
                [crime.nerve_cost, payout, (rewards.exp || 10), (rewards.crime_exp || 5), heatGained, user.user_id]
            );

            await client.query("UPDATE user_crime_records SET total_crimes = total_crimes + 1, total_successes = total_successes + 1 WHERE user_id = $1", [user.user_id]);
            await client.query('COMMIT');

            trackAndCheckAchievement(user.user_id, 'total_successes', 1, 'user_crime_records');
            return res.json({ status: "success", message: getRandomText(flavor.success), gained_cash: payout, user: updatedUser.rows[0] });

        } else {
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
        console.error("Searching Engine Error:", err.message);
        res.status(500).json({ error: "Hustle engine malfunction." });
    }
}

module.exports = { execute };