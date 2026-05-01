const express = require('express');
const router = express.Router();
const pool = require('../db');

// --- GET FRONT PAGE DATA ---
router.get('/frontpage', async (req, res) => {
    try {
        // 1. Fetch Latest System News (Limit 5)
        const newsRes = await pool.query(`
            SELECT headline, category, created_at
            FROM system_news
            ORDER BY created_at DESC LIMIT 5
        `);

        // 2. Fetch Active Bounties with Target info (Limit 10)
        const bountiesRes = await pool.query(`
            SELECT b.bounty_id, b.reward_cash, b.is_anonymous, b.created_at,
                   t.username AS target_username, t.level AS target_level,
                   p.username AS placed_by_username
            FROM bounties b
            JOIN users t ON b.target_user_id = t.user_id
            JOIN users p ON b.placed_by_user_id = p.user_id
            ORDER BY b.reward_cash DESC LIMIT 10
        `);

        // 3. Fetch Active Classified Ads (Not expired)
        const classifiedsRes = await pool.query(`
            SELECT c.ad_text, c.expires_at, u.username
            FROM classified_ads c
            JOIN users u ON c.user_id = u.user_id
            WHERE c.expires_at > NOW()
            ORDER BY c.expires_at ASC
        `);

        res.json({
            success: true,
            news: newsRes.rows,
            bounties: bountiesRes.rows,
            classifieds: classifiedsRes.rows
        });
    } catch (err) {
        console.error("Info Broker Error:", err);
        res.status(500).json({ error: "Server error fetching Info Broker data." });
    }
});

// --- POST CLASSIFIED AD ---
router.post('/classifieds', async (req, res) => {
    const { user_id, ad_text } = req.body;
    const client = await pool.connect();

    try {
        await client.query('BEGIN');

        if (!ad_text || ad_text.trim().length === 0 || ad_text.length > 150) {
             throw new Error("Ad text must be between 1 and 150 characters.");
        }

        // Calculate Cost: e.g., $10 Clean Cash per character
        const cost = ad_text.length * 10;

        // Deduct Cash
        const userRes = await client.query('UPDATE users SET clean_cash = clean_cash - $1 WHERE user_id = $2 AND clean_cash >= $1 RETURNING clean_cash', [cost, user_id]);

        if (userRes.rowCount === 0) {
            throw new Error(`Insufficient Clean Cash. This ad costs $${cost}.`);
        }

        // Insert Ad (expires in 24 hours)
        await client.query(`
            INSERT INTO classified_ads (user_id, ad_text, expires_at)
            VALUES ($1, $2, NOW() + INTERVAL '24 hours')
        `, [user_id, ad_text.trim()]);

        await client.query('COMMIT');
        res.json({ success: true, message: `Ad posted successfully for $${cost}.` });

    } catch (err) {
        await client.query('ROLLBACK');
        res.status(400).json({ error: err.message || "Failed to post ad." });
    } finally {
        client.release();
    }
});
// --- POST A NEW BOUNTY ---
router.post('/bounty', async (req, res) => {
    const { user_id, target_username, reward_cash, is_anonymous } = req.body;
    const client = await pool.connect();

    try {
        await client.query('BEGIN');

        const reward = parseInt(reward_cash);
        if (isNaN(reward) || reward < 500) throw new Error("Bounties must be at least $500 Dirty Cash.");

        // 1. Find Target User
        const targetRes = await client.query('SELECT user_id FROM users WHERE username = $1', [target_username.trim()]);
        if (targetRes.rows.length === 0) throw new Error("Target user not found.");
        const targetId = targetRes.rows[0].user_id;

        if (targetId === parseInt(user_id)) throw new Error("You cannot put a hit on yourself.");

        // 2. Check and Deduct Funds (Dirty Cash for underworld hits)
        const userRes = await client.query('UPDATE users SET dirty_cash = dirty_cash - $1 WHERE user_id = $2 AND dirty_cash >= $1 RETURNING dirty_cash', [reward, user_id]);
        if (userRes.rowCount === 0) throw new Error("Insufficient Dirty Cash.");

        // 3. Insert Bounty
        await client.query(`
            INSERT INTO bounties (target_user_id, placed_by_user_id, reward_cash, is_anonymous)
            VALUES ($1, $2, $3, $4)
        `, [targetId, user_id, reward, is_anonymous]);

        await client.query('COMMIT');
        res.json({ success: true, message: `Hit contract placed on ${target_username} for $${reward.toLocaleString()}.` });

    } catch (err) {
        await client.query('ROLLBACK');
        res.status(400).json({ error: err.message || "Failed to post bounty." });
    } finally {
        client.release();
    }
});

module.exports = router;