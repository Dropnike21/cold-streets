const express = require('express');
const cors = require('cors');
const bcrypt = require('bcrypt');
const pool = require('./db');
require('dotenv').config();

const app = express();

app.use(cors());
app.use(express.json());

// Check Database Connection
pool.connect()
  .then(() => console.log("🟢 SYSTEM ONLINE: Connected to Shadow Logistics Database."))
  .catch(err => console.error("🔴 CRITICAL ERROR: Database connection failed.", err.message));

// --- API ROUTES ---

// REGISTER ROUTE
app.post('/register', async (req, res) => {
    try {
        const { username, password } = req.body;

        // 1. Check if user exists
        const userCheck = await pool.query("SELECT * FROM users WHERE username = $1", [username]);
        if (userCheck.rows.length > 0) {
            return res.status(400).json({ error: "Username already taken on the streets." });
        }

        // 2. Encrypt the password
        const salt = await bcrypt.genSalt(10);
        const hashedPassword = await bcrypt.hash(password, salt);

        // 3. Insert into database as 'admin'
        const newUser = await pool.query(
            "INSERT INTO users (username, password_hash, role) VALUES ($1, $2, $3) RETURNING user_id, username, role, dirty_cash, hp",
            [username, hashedPassword, 'admin']
        );

        res.json({
            message: "Welcome to the Syndicate.",
            user: newUser.rows[0]
        });

    } catch (err) {
        console.error(err.message);
        res.status(500).json({ error: "Server encountered a fatal error." });
    }
});

// Start Server
const PORT = process.env.PORT || 3000;
app.listen(PORT, () => {
    console.log(`🔌 Node API running on http://localhost:${PORT}`);
});