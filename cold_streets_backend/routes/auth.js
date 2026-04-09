const express = require('express');
const bcrypt = require('bcrypt');
const pool = require('../db'); // Notice the '../' to go up one folder
const router = express.Router();

// REGISTER ROUTE
router.post('/register', async (req, res) => {
    try {
        const { username, password } = req.body;
        const email = req.body.email.toLowerCase();

        const userCheck = await pool.query(
            "SELECT * FROM users WHERE email = $1 OR username = $2",
            [email, username]
        );

        if (userCheck.rows.length > 0) {
            const existingUser = userCheck.rows[0];
            if (existingUser.email === email) return res.status(400).json({ error: "Email already registered." });
            if (existingUser.username === username) return res.status(400).json({ error: "That street name is taken." });
        }

        const salt = await bcrypt.genSalt(10);
        const hashedPassword = await bcrypt.hash(password, salt);

        const newUser = await pool.query(
            "INSERT INTO users (email, username, password_hash, role) VALUES ($1, $2, $3, $4) RETURNING user_id, username, email, role, dirty_cash, hp",
            [email, username, hashedPassword, 'player']
        );

        res.json({ message: "Welcome to the Syndicate.", user: newUser.rows[0] });
    } catch (err) {
        console.error(err.message);
        res.status(500).json({ error: "Server encountered a fatal error." });
    }
});

// LOGIN ROUTE
router.post('/login', async (req, res) => {
    try {
        const { password } = req.body;
        const email = req.body.email.toLowerCase();

        const userCheck = await pool.query("SELECT * FROM users WHERE email = $1", [email]);

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
                dirty_cash: user.dirty_cash,
                energy: user.energy,
                nerve: user.nerve,
                max_nerve: user.max_nerve,
                hp: user.hp
            }
        });
    } catch (err) {
        console.error("Login Error:", err.message);
        res.status(500).json({ error: "Server encountered a fatal error." });
    }
});

// --- LIVE TELEMETRY SYNC ---
router.get('/status/:user_id', async (req, res) => {
    try {
        const { user_id } = req.params;

        const userQuery = await pool.query(
            "SELECT dirty_cash, energy, nerve, max_nerve, hp FROM users WHERE user_id = $1",
            [user_id]
        );
        if (userQuery.rows.length === 0) return res.status(404).json({ error: "Ghost account." });

        // FIXED: Removed LIMIT 1 so we get ALL active cooldowns as an array
        const cdQuery = await pool.query(
            "SELECT type, EXTRACT(EPOCH FROM (expires_at - NOW())) AS seconds_left FROM user_cooldowns WHERE user_id = $1 AND expires_at > NOW()",
            [user_id]
        );

        res.json({
            user: userQuery.rows[0],
            cooldowns: cdQuery.rows // Returns an array
        });

    } catch (err) {
        console.error("Status Sync Error:", err.message);
        res.status(500).json({ error: "Sync failed." });
    }
});
module.exports = router;