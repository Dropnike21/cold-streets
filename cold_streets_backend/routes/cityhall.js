const express = require('express');
const router = express.Router();
const pool = require('../db');

// --- 1. GET ALL LEADERBOARDS ---
router.get('/leaderboards', async (req, res) => {
    const client = await pool.connect();

    try {
        // 1. HALL OF RECORDS: Highest Level (Fully Public)
        const levelRes = await client.query(`
            SELECT username, level
            FROM users
            ORDER BY level DESC, exp DESC
            LIMIT 50
        `);

        // 2. HALL OF RECORDS: Veterans (Fully Public)
        const veteranRes = await client.query(`
            SELECT username, created_at
            FROM users
            WHERE created_at IS NOT NULL
            ORDER BY created_at ASC
            LIMIT 50
        `);

        // 3. IRS WATCHLIST: Net Worth (Redacted Names, Public Syndicate)
        // NOTE: We calculate (dirty_cash + clean_cash). We will just return syndicate_id for now
        // until the full Factions module is built.
        const irsRes = await client.query(`
            SELECT
                '[REDACTED]' AS username,
                syndicate_id,
                (dirty_cash + clean_cash) AS net_worth
            FROM users
            ORDER BY net_worth DESC
            LIMIT 50
        `);

        // 4. THREAT MATRIX: Battle Stats (Fully Redacted)
        // We do the math on the server so the client never sees the raw stats of rivals.
        const threatRes = await client.query(`
            SELECT
                '[REDACTED]' AS username,
                (stat_str + stat_def + stat_dex + stat_spd) AS total_stats
            FROM users
            ORDER BY total_stats DESC
            LIMIT 50
        `);

        res.json({
            success: true,
            records_level: levelRes.rows,
            records_veterans: veteranRes.rows,
            irs_watchlist: irsRes.rows,
            threat_matrix: threatRes.rows
        });

    } catch (err) {
        console.error("Leaderboard Error:", err);
        res.status(500).json({ error: "Server error fetching leaderboards." });
    } finally {
        client.release();
    }
});

module.exports = router;