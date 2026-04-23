// cold_streets_backend/utils/achievement_engine.js
const pool = require('../db');

async function trackAndCheckAchievement(userId, statColumn, incrementValue, targetTable = 'user_statistics') {
    const client = await pool.connect();
    try {
        await client.query('BEGIN');

        // 1. Update the Tracker Table
        let updateQuery = "";
        if (targetTable === 'user_statistics') {
            updateQuery = `
                INSERT INTO user_statistics (user_id, ${statColumn})
                VALUES ($1, $2)
                ON CONFLICT (user_id)
                DO UPDATE SET ${statColumn} = user_statistics.${statColumn} + $2
                RETURNING ${statColumn} AS new_total;
            `;
        } else if (targetTable === 'user_crime_records') {
            updateQuery = `
                UPDATE user_crime_records
                SET ${statColumn} = ${statColumn} + $2
                WHERE user_id = $1
                RETURNING ${statColumn} AS new_total;
            `;
        }

        const updateRes = await client.query(updateQuery, [userId, incrementValue]);
        const newTotal = updateRes.rows[0].new_total;

        // 2. Fetch unearned achievements crossed by this new total
        // Notice we no longer ask the DB for a reward value!
        const checkQuery = `
            SELECT am.achievement_id, am.title
            FROM achievements_master am
            LEFT JOIN user_achievements ua ON am.achievement_id = ua.achievement_id AND ua.user_id = $1
            WHERE am.stat_tracker = $2
            AND am.threshold_value <= $3
            AND ua.achievement_id IS NULL;
        `;
        const achievements = await client.query(checkQuery, [userId, statColumn, newTotal]);

        // 3. Award the Achievements
        for (let ach of achievements.rows) {
            // Unlock it
            await client.query(
                `INSERT INTO user_achievements (user_id, achievement_id) VALUES ($1, $2)`,
                [userId, ach.achievement_id]
            );

            // GRANT EXACTLY +1 CRED (Hardcoded)
            await client.query(
                `UPDATE users SET cred = cred + 1 WHERE user_id = $1`,
                [userId]
            );

            // Log it for the UI Notification Event
            await client.query(
                `INSERT INTO user_events (user_id, event_text) VALUES ($1, $2)`,
                [userId, `Achievement Unlocked: ${ach.title}! You earned +1 Cred.`]
            );
        }

        await client.query('COMMIT');
    } catch (err) {
        await client.query('ROLLBACK');
        console.error("Achievement Engine Error:", err);
    } finally {
        client.release();
    }
}

module.exports = { trackAndCheckAchievement };