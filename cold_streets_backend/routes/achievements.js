const express = require('express');
const pool = require('../db');
const router = express.Router();

router.get('/:user_id', async (req, res) => {
    try {
        const { user_id } = req.params;

        const achQuery = `
            SELECT
                am.achievement_id AS id,
                am.title,
                am.description AS desc,
                am.category,
                am.threshold_value AS max,
                am.stat_tracker,
                ua.unlocked_at,
                CASE WHEN ua.achievement_id IS NOT NULL THEN true ELSE false END AS unlocked
            FROM achievements_master am
            LEFT JOIN user_achievements ua ON am.achievement_id = ua.achievement_id AND ua.user_id = $1
        `;

        // 🔥 THE OPTIMIZATION: Fire all 3 database queries concurrently!
        const [
            { rows: achievements },
            { rows: stats },
            { rows: crimes }
        ] = await Promise.all([
            pool.query(achQuery, [user_id]),
            pool.query('SELECT * FROM user_statistics WHERE user_id = $1', [user_id]),
            pool.query('SELECT * FROM user_crime_records WHERE user_id = $1', [user_id])
        ]);

        const userStats = { ...(stats[0] || {}), ...(crimes[0] || {}) };

        const mappedAchievements = achievements.map(ach => {
            let cur = Number(userStats[ach.stat_tracker]) || 0;
            if (cur > ach.max) cur = ach.max;

            return {
                id: ach.id,
                title: ach.title,
                desc: ach.desc,
                category: ach.category.toUpperCase(),
                reward: 1, // HARDCODED TO 1 FOR FLUTTER
                max: Number(ach.max),
                cur: ach.unlocked ? Number(ach.max) : cur,
                unlocked: ach.unlocked,
                unlocked_at: ach.unlocked_at
            };
        });

        res.json({ success: true, achievements: mappedAchievements });
    } catch (err) {
        console.error("Fetch Achievements Error:", err.message);
        res.status(500).json({ error: "Failed to load achievements." });
    }
});

module.exports = router;