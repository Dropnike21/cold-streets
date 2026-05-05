const express = require('express');
const pool = require('../db');
const router = express.Router();

// ==========================================
// 1. GET UNIVERSITY DASHBOARD
// ==========================================
router.get('/:user_id', async (req, res) => {
    try {
        const { user_id } = req.params;

        const userRes = await pool.query('SELECT active_course_id, course_expires_at, dirty_cash FROM users WHERE user_id = $1', [user_id]);
        if (userRes.rows.length === 0) return res.status(404).json({ error: "User not found." });
        const user = userRes.rows[0];

        const completedRes = await pool.query('SELECT course_id FROM user_completed_courses WHERE user_id = $1', [user_id]);
        const completedIds = completedRes.rows.map(r => r.course_id);

        const tracksRes = await pool.query('SELECT * FROM education_tracks_master ORDER BY track_id ASC');
        const coursesRes = await pool.query('SELECT * FROM education_courses_master ORDER BY track_id ASC, course_id ASC');

        res.json({
            success: true,
            dirty_cash: user.dirty_cash,
            active_course_id: user.active_course_id,
            course_expires_at: user.course_expires_at,
            completed_courses: completedIds,
            tracks: tracksRes.rows,
            courses: coursesRes.rows
        });

    } catch (err) {
        console.error("University Fetch Error:", err.message);
        res.status(500).json({ error: "Failed to load University data." });
    }
});

// ==========================================
// 2. ENROLL IN A COURSE
// ==========================================
router.post('/enroll', async (req, res) => {
    const client = await pool.connect();
    try {
        const { user_id, course_id } = req.body;
        await client.query('BEGIN');

        const userRes = await client.query('SELECT active_course_id, dirty_cash FROM users WHERE user_id = $1 FOR UPDATE', [user_id]);
        const user = userRes.rows[0];
        if (user.active_course_id) throw new Error("You are already enrolled in a course. You must drop out or finish it first.");

        const courseRes = await client.query('SELECT * FROM education_courses_master WHERE course_id = $1', [course_id]);
        if (courseRes.rows.length === 0) throw new Error("Course not found.");
        const course = courseRes.rows[0];

        if (course.prerequisite_course_id) {
            const prereqCheck = await client.query('SELECT 1 FROM user_completed_courses WHERE user_id = $1 AND course_id = $2', [user_id, course.prerequisite_course_id]);
            if (prereqCheck.rows.length === 0) throw new Error("You do not meet the prerequisites for this course.");
        }

        if (user.dirty_cash < course.cost_dirty_cash) throw new Error(`Insufficient funds. Tuition is $${course.cost_dirty_cash}.`);

        await client.query(`
            UPDATE users
            SET dirty_cash = dirty_cash - $1,
                active_course_id = $2,
                course_expires_at = NOW() + INTERVAL '1 second' * $3
            WHERE user_id = $4
        `, [course.cost_dirty_cash, course_id, course.duration_seconds, user_id]);

        await client.query('COMMIT');
        res.json({ success: true, message: `Successfully enrolled in ${course.title}. Hit the books.` });

    } catch (err) {
        await client.query('ROLLBACK');
        res.status(400).json({ error: err.message });
    } finally {
        client.release();
    }
});

// ==========================================
// 3. THE DROP OUT PENALTY
// ==========================================
router.post('/dropout', async (req, res) => {
    try {
        const { user_id } = req.body;
        await pool.query('UPDATE users SET active_course_id = NULL, course_expires_at = NULL WHERE user_id = $1', [user_id]);
        res.json({ success: true, message: "You dropped out. Tuition and time invested have been forfeited." });
    } catch (err) {
        res.status(500).json({ error: "Failed to process drop out." });
    }
});

// ==========================================
// 4. GRADUATE & CLAIM STATS
// ==========================================
router.post('/graduate', async (req, res) => {
    const client = await pool.connect();
    try {
        const { user_id } = req.body;
        await client.query('BEGIN');

        const userRes = await client.query('SELECT active_course_id, course_expires_at FROM users WHERE user_id = $1 FOR UPDATE', [user_id]);
        const user = userRes.rows[0];

        if (!user.active_course_id) throw new Error("You are not enrolled in any courses.");
        if (new Date(user.course_expires_at) > new Date()) throw new Error("You haven't finished your coursework yet.");

        const courseId = user.active_course_id;
        const courseRes = await client.query('SELECT * FROM education_courses_master WHERE course_id = $1', [courseId]);
        const course = courseRes.rows[0];

        const validStats = ['str', 'def', 'dex', 'spd', 'acu', 'ops', 'pre', 'res'];
        let updateQuery = `UPDATE users SET active_course_id = NULL, course_expires_at = NULL`;

        if (course.reward_stat_1 && validStats.includes(course.reward_stat_1.toLowerCase())) {
            updateQuery += `, stat_${course.reward_stat_1.toLowerCase()} = stat_${course.reward_stat_1.toLowerCase()} + ${course.reward_amount_1}`;
        }
        if (course.reward_stat_2 && validStats.includes(course.reward_stat_2.toLowerCase())) {
            updateQuery += `, stat_${course.reward_stat_2.toLowerCase()} = stat_${course.reward_stat_2.toLowerCase()} + ${course.reward_amount_2}`;
        }
        updateQuery += ` WHERE user_id = $1 RETURNING *`;

        const updatedUser = await client.query(updateQuery, [user_id]);
        await client.query('INSERT INTO user_completed_courses (user_id, course_id) VALUES ($1, $2)', [user_id, courseId]);

        await client.query('COMMIT');
        res.json({
            success: true,
            message: `Course Completed! You gained massive knowledge in ${course.title}.`,
            user: updatedUser.rows[0]
        });

    } catch (err) {
        await client.query('ROLLBACK');
        res.status(400).json({ error: err.message });
    } finally {
        client.release();
    }
});

module.exports = router;