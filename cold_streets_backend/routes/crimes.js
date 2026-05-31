// routes/crimes.js
const express = require('express');
const pool = require('../db');
const router = express.Router();

// --- IMPORT YOUR SPECIFIC CRIME MODULES HERE ---
const searchingEngine = require('./crimes/searching_engine');
const shopliftingEngine = require('./crimes/shoplifting');
const pickpocketEngine = require('./crimes/pickpocketing');

router.get('/list', async (req, res) => {
    const type = req.query.type;

    // 🚨 THIS IS THE MISSING PIECE! 🚨
    // Catch Pickpocketing requests and route to the custom fetcher
    if (type === 'pickpocketing') {
        const client = await pool.connect();
        try {
            return await pickpocketEngine.listTargets(client, res);
        } finally {
            client.release();
        }
    }

    // Default Fetcher (Used by The Streets Job Board and Shoplifting)
    try {
        const crimes = await pool.query("SELECT * FROM crimes_master ORDER BY req_skill_level ASC, id ASC");
        res.json(crimes.rows);
    } catch (err) {
        console.error("Fetch Crimes Error:", err.message);
        res.status(500).json({ error: "Failed to load Job Board." });
    }
});

router.post('/execute', async (req, res) => {
    const client = await pool.connect();

    try {
        const { user_id, crime_id } = req.body;

        await client.query('BEGIN');

        // 1. Universal Checks (Valid User, Jail, Hospital, HP)
        const userCheck = await client.query("SELECT * FROM users WHERE user_id = $1 FOR UPDATE", [user_id]);
        if (userCheck.rows.length === 0) {
            await client.query('ROLLBACK');
            return res.status(404).json({ error: "Ghost account." });
        }
        const user = userCheck.rows[0];
        const now = new Date();

        if (user.jail_expires_at && new Date(user.jail_expires_at) > now) {
            await client.query('ROLLBACK');
            return res.status(403).json({ error: "You are locked behind bars." });
        }
        if (user.hospital_expires_at && new Date(user.hospital_expires_at) > now) {
            await client.query('ROLLBACK');
            return res.status(403).json({ error: "You are recovering in the hospital." });
        }
        if (user.hp < 25) {
            await client.query('ROLLBACK');
            return res.status(403).json({ error: "You are too weak. Heal up to 25 HP first." });
        }

        // 2. Fetch the Crime
        const crimeCheck = await client.query("SELECT * FROM crimes_master WHERE id = $1", [crime_id]);
        if (crimeCheck.rows.length === 0) {
            await client.query('ROLLBACK');
            return res.status(404).json({ error: "Crime not found." });
        }
        const crime = crimeCheck.rows[0];

        // 3. THE ROUTER SWITCH
        switch (crime.sub_category) {
            case 'Searching':
                return await searchingEngine.execute(client, user, crime, req, res);

            case 'Shoplifting':
                return await shopliftingEngine.execute(client, user, crime, req, res);

            case 'Pickpocketing':
                return await pickpocketEngine.execute(client, user, crime, req, res);

            default:
                await client.query('ROLLBACK');
                return res.status(400).json({ error: "Crime mechanics not yet implemented for this category." });
        }

    } catch (err) {
        await client.query('ROLLBACK');
        console.error("Master Crime Router Error:", err.message);
        res.status(500).json({ error: "Server malfunction." });
    } finally {
        client.release();
    }
});

module.exports = router;