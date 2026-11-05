const express = require('express');
const pool = require('../db');
const router = express.Router();
const { requireOwnedPlayerParam } = require('../middleware/playerIdentity');
const { SUPPORTED_TRACKERS } = require('../utils/achievement_engine');
const { dbInteger } = require('../utils/economyValidation');

router.param('user_id', requireOwnedPlayerParam);

const TRACKABLE = new Set(SUPPORTED_TRACKERS);

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
            LEFT JOIN user_achievements ua
              ON am.achievement_id = ua.achievement_id
             AND ua.user_id = $1
            ORDER BY am.achievement_id
        `;

        const [
            { rows: achievements },
            { rows: stats },
            { rows: crimes },
            { rows: users },
            { rows: courses },
            { rows: discoveries }
        ] = await Promise.all([
            pool.query(achQuery, [user_id]),
            pool.query(
                'SELECT total_gym_trains FROM user_statistics WHERE user_id = $1',
                [user_id]
            ),
            pool.query(
                'SELECT total_successes FROM user_crime_records WHERE user_id = $1',
                [user_id]
            ),
            pool.query('SELECT level FROM users WHERE user_id = $1', [user_id]),
            pool.query(
                'SELECT COUNT(*)::bigint AS total FROM user_completed_courses WHERE user_id = $1',
                [user_id]
            ),
            pool.query(
                'SELECT COUNT(*)::bigint AS total FROM user_item_discoveries WHERE user_id = $1',
                [user_id]
            )
        ]);

        if (users.length !== 1) {
            return res.status(404).json({ error: 'Player not found.' });
        }

        const progressByTracker = {
            gym_trains: stats[0]?.total_gym_trains ?? '0',
            crimes_successful: crimes[0]?.total_successes ?? '0',
            player_level: users[0].level ?? 1,
            courses_completed: courses[0]?.total ?? '0',
            unique_items_found: discoveries[0]?.total ?? '0'
        };

        const mappedAchievements = achievements.map(ach => {
            const maxExact = dbInteger(
                ach.max,
                { field: 'Achievement threshold' }
            );
            if (maxExact < 1n || maxExact > BigInt(Number.MAX_SAFE_INTEGER)) {
                throw new Error('Achievement threshold is outside the supported display range.');
            }

            const trackingAvailable = TRACKABLE.has(ach.stat_tracker);
            const rawCurrentExact = trackingAvailable
                ? dbInteger(
                    progressByTracker[ach.stat_tracker] ?? 0,
                    { field: 'Achievement progress' }
                )
                : 0n;
            if (rawCurrentExact < 0n) {
                throw new Error('Achievement progress cannot be negative.');
            }

            const shownExact = ach.unlocked || rawCurrentExact > maxExact
                ? maxExact
                : rawCurrentExact;
            const max = Number(maxExact);
            const current = Number(shownExact);

            return {
                id: ach.id,
                title: ach.title,
                desc: ach.desc,
                category: String(ach.category || 'Misc').toUpperCase(),
                stat_tracker: ach.stat_tracker,
                max,
                cur: current,
                unlocked: ach.unlocked,
                unlocked_at: ach.unlocked_at,
                tracking_available: trackingAvailable
            };
        });

        return res.json({
            success: true,
            supported_trackers: SUPPORTED_TRACKERS,
            achievements: mappedAchievements
        });
    } catch (err) {
        console.error('Fetch Achievements Error:', err.message);
        return res.status(500).json({ error: 'Failed to load achievements.' });
    }
});

module.exports = router;
