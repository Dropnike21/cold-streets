// File Path: cold_streets_backend/routes/auth.js

const express = require('express');
const bcrypt = require('bcrypt');
const pool = require('../db');
const router = express.Router();

// ==========================================
// REGISTER ROUTE (WITH EMAIL & TRANSACTIONS)
// ==========================================
router.post('/register', async (req, res) => {
    const client = await pool.connect();

    try {
        const { username, password } = req.body;
        const email = req.body.email.toLowerCase();

        // 1. Check if Email or Username is taken
        const userCheck = await client.query(
            "SELECT * FROM users WHERE email = $1 OR username = $2",
            [email, username]
        );

        if (userCheck.rows.length > 0) {
            const existingUser = userCheck.rows[0];
            if (existingUser.email === email) return res.status(400).json({ error: "Email already registered." });
            if (existingUser.username === username) return res.status(400).json({ error: "That street name is taken." });
        }

        // 2. Hash the password
        const salt = await bcrypt.genSalt(10);
        const hashedPassword = await bcrypt.hash(password, salt);

        // --- BEGIN TRANSACTION ---
        await client.query('BEGIN');

        // 3. Create the Main User Record (NOW WITH 10.00 DEFAULT STATS)
                const newUserQuery = await client.query(
                    `INSERT INTO users (
                        email, username, password_hash, role,
                        stat_str, stat_def, stat_dex, stat_spd, stat_acu, stat_ops, stat_pre, stat_res
                    ) VALUES (
                        $1, $2, $3, $4,
                        10, 10, 10, 10, 10, 10, 10, 10
                    ) RETURNING
                        user_id, username, dirty_cash, clean_cash, level, hp, energy, nerve, max_nerve,
                        stat_str, stat_def, stat_dex, stat_spd, stat_acu, stat_ops, stat_pre, stat_res`,
                    [email, username, hashedPassword, 'player']
                );

        const newUser = newUserQuery.rows[0];
        const newUserId = newUser.user_id;

        // 4. Generate all the linked Relational Tables
        await client.query("INSERT INTO user_equipment (user_id) VALUES ($1)", [newUserId]);
        await client.query("INSERT INTO user_crime_records (user_id) VALUES ($1)", [newUserId]);
        await client.query("INSERT INTO user_properties (user_id) VALUES ($1)", [newUserId]);

        // FIX: Give them the default Gym #1 (Playground Park)
        await client.query("INSERT INTO user_gym_stats (user_id, active_gym_id, gym_exp) VALUES ($1, 1, 0)", [newUserId]);
        await client.query("INSERT INTO user_owned_gyms (user_id, gym_id) VALUES ($1, 1)", [newUserId]);

        // 5. Inject their first event
        await client.query(
            "INSERT INTO user_events (user_id, event_text) VALUES ($1, $2)",
            [newUserId, "Welcome to Cold Streets. Trust no one, build your empire."]
        );

        // --- COMMIT TRANSACTION ---
        await client.query('COMMIT');

        res.json({ message: "Welcome to the Syndicate.", user: newUser });

    } catch (err) {
        await client.query('ROLLBACK');
        console.error("Registration Fatal Error:", err.message);
        res.status(500).json({ error: "Server encountered a fatal error during registration." });
    } finally {
        client.release();
    }
});

// ==========================================
// 3-WAY LOGIN ROUTE (EMAIL, USERNAME, OR ID)
// ==========================================
router.post('/login', async (req, res) => {
    try {
        const { login_id, password } = req.body;
        const searchId = login_id.toLowerCase();

        const userCheck = await pool.query(
            "SELECT * FROM users WHERE LOWER(email) = $1 OR LOWER(username) = $1 OR user_id::text = $1",
            [searchId]
        );

        if (userCheck.rows.length === 0) {
            return res.status(401).json({ error: "Invalid credentials. Ghost account." });
        }

        const user = userCheck.rows[0];
        const validPassword = await bcrypt.compare(password, user.password_hash);

        if (!validPassword) {
            return res.status(401).json({ error: "Invalid credentials. Wrong password." });
        }

        res.json({
            message: "Authentication successful.",
            user: {
                user_id: user.user_id,
                username: user.username,
                role: user.role,
                level: user.level,
                dirty_cash: user.dirty_cash,
                clean_cash: user.clean_cash,
                energy: user.energy,
                nerve: user.nerve,
                max_nerve: user.max_nerve,
                hp: user.hp,

                stat_str: user.stat_str,
                stat_def: user.stat_def,
                stat_dex: user.stat_dex,
                stat_spd: user.stat_spd,

                stat_acu: user.stat_acu,
                stat_ops: user.stat_ops,
                stat_pre: user.stat_pre,
                stat_res: user.stat_res
            }
        });
    } catch (err) {
        console.error("Login Error:", err.message);
        res.status(500).json({ error: "Server encountered a fatal error." });
    }
});

// ==========================================
// LIVE TELEMETRY SYNC
// ==========================================
router.get('/status/:user_id', async (req, res) => {
    try {
        const { user_id } = req.params;

        const userQuery = await pool.query(
            "SELECT dirty_cash, energy, nerve, max_nerve, hp, level FROM users WHERE user_id = $1",
            [user_id]
        );
        if (userQuery.rows.length === 0) return res.status(404).json({ error: "Ghost account." });

        const cdQuery = await pool.query(
            "SELECT type, EXTRACT(EPOCH FROM (expires_at - NOW())) AS seconds_left FROM user_cooldowns WHERE user_id = $1 AND expires_at > NOW()",
            [user_id]
        );

        res.json({
            user: userQuery.rows[0],
            cooldowns: cdQuery.rows
        });

    } catch (err) {
        console.error("Status Sync Error:", err.message);
        res.status(500).json({ error: "Sync failed." });
    }
});

module.exports = router;