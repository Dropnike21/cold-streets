// cold_streets_backend/routes/events.js
const express = require('express');
const pool = require('../db');
const router = express.Router();

// 1. Fetch Events with Pagination
router.get('/:user_id', async (req, res) => {
    try {
        const { user_id } = req.params;
        const limit = parseInt(req.query.limit) || 20; // Default to 20
        const offset = parseInt(req.query.offset) || 0; // Default to 0

        const query = `
            SELECT event_id, event_text, event_type, is_read, created_at
            FROM user_events
            WHERE user_id = $1
            ORDER BY created_at DESC
            LIMIT $2 OFFSET $3
        `;
        const { rows } = await pool.query(query, [user_id, limit, offset]);

        // Get unread count for the notification bell in the Hub
        const unreadQuery = `SELECT COUNT(*) FROM user_events WHERE user_id = $1 AND is_read = false`;
        const unreadRes = await pool.query(unreadQuery, [user_id]);

        res.json({
            success: true,
            events: rows,
            unread_count: parseInt(unreadRes.rows[0].count)
        });
    } catch (err) {
        console.error("Fetch Events Error:", err);
        res.status(500).json({ error: "Failed to load events." });
    }
});

// 2. Mark All Events as Read
router.post('/mark_read', async (req, res) => {
    try {
        const { user_id } = req.body;
        await pool.query('UPDATE user_events SET is_read = true WHERE user_id = $1 AND is_read = false', [user_id]);
        res.json({ success: true });
    } catch (err) {
        res.status(500).json({ error: "Failed to mark events as read." });
    }
});

module.exports = router;