const express = require('express');
const pool = require('../db');
const router = express.Router();
const { requireOwnedPlayerParam } = require('../middleware/playerIdentity');
const {
    ActionError, integer, dbInteger, exactJsonAmount, actorId, sendActionError
} = require('../utils/economyValidation');
const {
    requireIdempotencyKey, beginIdempotent, completeIdempotent
} = require('../utils/idempotency');

router.param('user_id', requireOwnedPlayerParam);

const EDUCATION_STATS = new Set(['acu', 'ops', 'pre', 'res']);

function normalizeCourseRewards(raw) {
    if (!raw || typeof raw !== 'object' || Array.isArray(raw)) {
        throw new Error('University reward catalog is invalid.');
    }
    const allowedTop = new Set(['stats', 'perks', 'unlocks']);
    if (Object.keys(raw).some(key => !allowedTop.has(key))) {
        throw new Error('University reward catalog contains an unsupported field.');
    }

    const stats = { acu: 0n, ops: 0n, pre: 0n, res: 0n };
    const sourceStats = raw.stats ?? {};
    if (!sourceStats || typeof sourceStats !== 'object' || Array.isArray(sourceStats)) {
        throw new Error('University stat reward catalog is invalid.');
    }
    for (const [key, value] of Object.entries(sourceStats)) {
        if (!EDUCATION_STATS.has(key)) {
            throw new Error('University reward references an unsupported stat.');
        }
        stats[key] = integer(value, {
            field: 'Course stat reward', min: 0n, max: 1000000000n
        });
    }

    const perks = raw.perks ?? [];
    const unlocks = raw.unlocks ?? [];
    if (!Array.isArray(perks) || !Array.isArray(unlocks)) {
        throw new Error('University entitlement catalog is invalid.');
    }
    return { stats, perks, unlocks };
}

// ==========================================
// 1. GET UNIVERSITY DASHBOARD
// ==========================================
router.get('/:user_id', async (req, res) => {
    try {
        const userId = actorId(req);
        const userRes = await pool.query(
            'SELECT active_course_id, course_expires_at, dirty_cash FROM users WHERE user_id = $1',
            [userId]
        );
        if (userRes.rowCount !== 1) throw new ActionError(404, 'Player not found.');

        const [completedRes, tracksRes, coursesRes] = await Promise.all([
            pool.query(
                'SELECT course_id FROM user_completed_courses WHERE user_id = $1 ORDER BY course_id',
                [userId]
            ),
            pool.query('SELECT * FROM education_tracks_master ORDER BY track_id ASC'),
            pool.query(
                `SELECT course_id, track_id, tier, title, description,
                        cost_dirty_cash, duration_seconds, prerequisite_course_id,
                        rewards_json, rewards_jsonb
                   FROM education_courses_master
                  ORDER BY track_id ASC, course_id ASC`
            )
        ]);

        return res.json({
            success: true,
            dirty_cash: userRes.rows[0].dirty_cash,
            active_course_id: userRes.rows[0].active_course_id,
            course_expires_at: userRes.rows[0].course_expires_at,
            completed_courses: completedRes.rows.map(row => row.course_id),
            tracks: tracksRes.rows,
            courses: coursesRes.rows
        });
    } catch (err) {
        return sendActionError(res, err, 'University dashboard failed:');
    }
});

// ==========================================
// 2. ENROLL
// ==========================================
router.post('/enroll', async (req, res) => {
    let client, transaction = false;
    try {
        const userId = actorId(req);
        const idempotencyKey = requireIdempotencyKey(req);
        const courseId = integer(req.body?.course_id, {
            field: 'Course ID', min: 1n, max: 9223372036854775807n
        }).toString();

        client = await pool.connect();
        await client.query('BEGIN');
        transaction = true;

        const userRes = await client.query(
            'SELECT active_course_id, dirty_cash FROM users WHERE user_id = $1 FOR UPDATE',
            [userId]
        );
        if (userRes.rowCount !== 1) throw new ActionError(404, 'Player not found.');

        const idem = await beginIdempotent(
            client, userId, 'university.enroll', idempotencyKey, { courseId }
        );
        if (idem.replay) {
            await client.query('COMMIT');
            transaction = false;
            return res.status(idem.status).json(idem.response);
        }

        if (userRes.rows[0].active_course_id !== null) {
            throw new ActionError(409, 'Finish or drop your current course first.');
        }

        const completed = await client.query(
            'SELECT 1 FROM user_completed_courses WHERE user_id = $1 AND course_id = $2',
            [userId, courseId]
        );
        if (completed.rowCount) {
            throw new ActionError(409, 'You have already completed this course.');
        }

        const courseRes = await client.query(
            `SELECT course_id, title, cost_dirty_cash, duration_seconds,
                    prerequisite_course_id
               FROM education_courses_master
              WHERE course_id = $1`,
            [courseId]
        );
        if (courseRes.rowCount !== 1) throw new ActionError(404, 'Course not found.');
        const course = courseRes.rows[0];

        if (course.prerequisite_course_id !== null) {
            const prerequisite = await client.query(
                `SELECT 1 FROM user_completed_courses
                  WHERE user_id = $1 AND course_id = $2`,
                [userId, course.prerequisite_course_id]
            );
            if (!prerequisite.rowCount) {
                throw new ActionError(409, 'Course prerequisite has not been completed.');
            }
        }

        const cost = dbInteger(course.cost_dirty_cash ?? 0, { field: 'Course tuition' });
        const duration = integer(course.duration_seconds ?? 0, {
            field: 'Course duration', min: 1n, max: 315360000n
        });
        if (cost < 0n) throw new Error('Course catalog contains negative tuition.');
        if (dbInteger(userRes.rows[0].dirty_cash) < cost) {
            throw new ActionError(409, 'Insufficient Dirty Cash for tuition.');
        }

        const enrolled = await client.query(
            `UPDATE users
                SET dirty_cash = dirty_cash - $1::numeric,
                    active_course_id = $2,
                    course_expires_at =
                        NOW() + make_interval(secs => $3::double precision)
              WHERE user_id = $4
                AND active_course_id IS NULL
                AND dirty_cash >= $1::numeric
              RETURNING dirty_cash, active_course_id, course_expires_at`,
            [cost.toString(), courseId, duration.toString(), userId]
        );
        if (enrolled.rowCount !== 1) {
            throw new ActionError(409, 'Enrollment state changed before tuition was charged.');
        }

        const response = {
            success: true,
            message: 'Successfully enrolled in ' + course.title + '.',
            dirty_cash: exactJsonAmount(dbInteger(enrolled.rows[0].dirty_cash)),
            active_course_id: enrolled.rows[0].active_course_id,
            course_expires_at: enrolled.rows[0].course_expires_at
        };
        await completeIdempotent(client, idem, 200, response);
        await client.query('COMMIT');
        transaction = false;
        return res.json(response);
    } catch (err) {
        if (transaction) {
            try { await client.query('ROLLBACK'); }
            catch (rollback) { console.error('University enrollment rollback:', rollback); }
        }
        return sendActionError(res, err, 'University enrollment failed:');
    } finally {
        if (client) client.release();
    }
});

// ==========================================
// 3. DROP OUT
// ==========================================
router.post('/dropout', async (req, res) => {
    let client, transaction = false;
    try {
        const userId = actorId(req);
        const idempotencyKey = requireIdempotencyKey(req);
        client = await pool.connect();
        await client.query('BEGIN');
        transaction = true;

        const user = await client.query(
            'SELECT active_course_id FROM users WHERE user_id = $1 FOR UPDATE',
            [userId]
        );
        if (user.rowCount !== 1) throw new ActionError(404, 'Player not found.');

        const idem = await beginIdempotent(
            client, userId, 'university.dropout', idempotencyKey, {}
        );
        if (idem.replay) {
            await client.query('COMMIT');
            transaction = false;
            return res.status(idem.status).json(idem.response);
        }
        if (user.rows[0].active_course_id === null) {
            throw new ActionError(409, 'You are not enrolled in a course.');
        }

        await client.query(
            `UPDATE users
                SET active_course_id = NULL, course_expires_at = NULL
              WHERE user_id = $1`,
            [userId]
        );
        const response = {
            success: true,
            message: 'Course dropped. Tuition and elapsed study time are forfeited.'
        };
        await completeIdempotent(client, idem, 200, response);
        await client.query('COMMIT');
        transaction = false;
        return res.json(response);
    } catch (err) {
        if (transaction) {
            try { await client.query('ROLLBACK'); }
            catch (rollback) { console.error('University dropout rollback:', rollback); }
        }
        return sendActionError(res, err, 'University dropout failed:');
    } finally {
        if (client) client.release();
    }
});

// ==========================================
// 4. GRADUATE
// ==========================================
router.post('/graduate', async (req, res) => {
    let client, transaction = false;
    try {
        const userId = actorId(req);
        const idempotencyKey = requireIdempotencyKey(req);
        client = await pool.connect();
        await client.query('BEGIN');
        transaction = true;

        const userRes = await client.query(
            `SELECT active_course_id, course_expires_at
               FROM users WHERE user_id = $1 FOR UPDATE`,
            [userId]
        );
        if (userRes.rowCount !== 1) throw new ActionError(404, 'Player not found.');

        const idem = await beginIdempotent(
            client, userId, 'university.graduate', idempotencyKey, {}
        );
        if (idem.replay) {
            await client.query('COMMIT');
            transaction = false;
            return res.status(idem.status).json(idem.response);
        }

        const activeCourseId = userRes.rows[0].active_course_id;
        if (activeCourseId === null) {
            throw new ActionError(409, 'You are not enrolled in a course.');
        }
        const maturity = await client.query(
            'SELECT ($1::timestamptz <= NOW()) AS complete',
            [userRes.rows[0].course_expires_at]
        );
        if (!maturity.rows[0].complete) {
            throw new ActionError(409, 'Coursework is not complete yet.');
        }

        const courseRes = await client.query(
            `SELECT course_id, title, rewards_jsonb
               FROM education_courses_master
              WHERE course_id = $1`,
            [activeCourseId]
        );
        if (courseRes.rowCount !== 1) throw new Error('Active course catalog row is missing.');
        const course = courseRes.rows[0];
        const rewards = normalizeCourseRewards(course.rewards_jsonb);

        const completion = await client.query(
            `INSERT INTO user_completed_courses (user_id, course_id)
             VALUES ($1, $2)
             ON CONFLICT DO NOTHING
             RETURNING course_id`,
            [userId, activeCourseId]
        );
        if (completion.rowCount !== 1) {
            throw new ActionError(409, 'This course was already completed.');
        }

        const updatedUser = await client.query(
            `UPDATE users
                SET active_course_id = NULL,
                    course_expires_at = NULL,
                    stat_acu = stat_acu + $1::numeric,
                    stat_ops = stat_ops + $2::numeric,
                    stat_pre = stat_pre + $3::numeric,
                    stat_res = stat_res + $4::numeric
              WHERE user_id = $5 AND active_course_id = $6
              RETURNING *`,
            [
                rewards.stats.acu.toString(),
                rewards.stats.ops.toString(),
                rewards.stats.pre.toString(),
                rewards.stats.res.toString(),
                userId,
                activeCourseId
            ]
        );
        if (updatedUser.rowCount !== 1) {
            throw new ActionError(409, 'Course enrollment changed before graduation.');
        }

        const response = {
            success: true,
            message: 'Course completed: ' + course.title + '.',
            applied_stats: {
                acu: exactJsonAmount(rewards.stats.acu),
                ops: exactJsonAmount(rewards.stats.ops),
                pre: exactJsonAmount(rewards.stats.pre),
                res: exactJsonAmount(rewards.stats.res)
            },
            recorded_entitlements: {
                perks: rewards.perks,
                unlocks: rewards.unlocks
            },
            user: updatedUser.rows[0]
        };
        await completeIdempotent(client, idem, 200, response);
        await client.query('COMMIT');
        transaction = false;
        return res.json(response);
    } catch (err) {
        if (transaction) {
            try { await client.query('ROLLBACK'); }
            catch (rollback) { console.error('University graduation rollback:', rollback); }
        }
        return sendActionError(res, err, 'University graduation failed:');
    } finally {
        if (client) client.release();
    }
});

module.exports = router;
