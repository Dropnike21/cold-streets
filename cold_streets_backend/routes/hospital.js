const express = require('express');
const pool = require('../db');
const router = express.Router();

// ==========================================
// 1. GET PATIENT LIST (WITH PAGINATION)
// ==========================================
router.get('/patients', async (req, res) => {
    try {
        const limit = parseInt(req.query.limit) || 20;
        const page = parseInt(req.query.page) || 1;
        const offset = (page - 1) * limit;

        // 1. Get the total count for pagination math
        const countRes = await pool.query('SELECT COUNT(*) FROM users WHERE hospital_expires_at > NOW()');
        const totalPatients = parseInt(countRes.rows[0].count);
        const totalPages = Math.ceil(totalPatients / limit);

        // 2. Fetch the actual patients (Sorted by longest time remaining first)
        const patientsQuery = `
            SELECT
                user_id, username, level, hospital_expires_at, last_active_at,
                state_reason AS reason -- 👉 Pulling the unified reason
            FROM users
            WHERE hospital_expires_at > NOW()
            ORDER BY hospital_expires_at DESC
            LIMIT $1 OFFSET $2
        `;
        const patientsRes = await pool.query(patientsQuery, [limit, offset]);

        res.json({
            success: true,
            patients: patientsRes.rows,
            pagination: {
                current_page: page,
                total_pages: totalPages == 0 ? 1 : totalPages,
                total_patients: totalPatients
            }
        });
    } catch (err) {
        console.error("Fetch Patients Error:", err.message);
        res.status(500).json({ error: "Failed to load hospital manifest." });
    }
});

// ==========================================
// 2. USE REVIVE SKILL (PLACEHOLDER)
// ==========================================
router.post('/revive', async (req, res) => {
    const client = await pool.connect();

    try {
        const { user_id, target_id } = req.body;
        await client.query('BEGIN');

        // 1. GATEKEEPER: Check if actor actually has the Medical Mastery (Job Rank 5)
        const jobRes = await client.query(`
            SELECT is_mastered FROM user_job_data
            WHERE user_id = $1 AND job_id = 1
        `, [user_id]);

        if (jobRes.rows.length === 0 || !jobRes.rows[0].is_mastered) {
            throw new Error("You do not have the necessary medical licenses to perform a revival.");
        }

        // 2. Verify Target is actually in the hospital
        const targetRes = await client.query("SELECT username, hospital_expires_at FROM users WHERE user_id = $1 FOR UPDATE", [target_id]);
        if (targetRes.rows.length === 0) throw new Error("Patient not found.");
        const target = targetRes.rows[0];

        if (!target.hospital_expires_at || new Date(target.hospital_expires_at) <= new Date()) {
            throw new Error("This patient has already been discharged.");
        }

        // 3. EXECUTE REVIVAL (Clear timer, grant 20 HP)
        await client.query(`
            UPDATE users
            SET hospital_expires_at = NULL, hp = GREATEST(hp, 20), state_reason = NULL
            WHERE user_id = $1
        `, [target_id]);

        await client.query('COMMIT');

        res.json({ success: true, message: `You successfully revived ${target.username}. They have been discharged.` });

    } catch (err) {
        await client.query('ROLLBACK');
        res.status(400).json({ error: err.message || "Revival procedure failed." });
    } finally {
        client.release();
    }
});

module.exports = router;