const express = require('express');
const pool = require('../db');
const router = express.Router();
const { requireOwnedPlayerParam } = require('../middleware/playerIdentity');
const { ActionError, actorId, sendActionError } = require('../utils/economyValidation');

router.param('user_id', requireOwnedPlayerParam);

router.get('/:user_id', async (req, res) => {
    try {
        const userId = actorId(req);
        const limit = Number(req.query.limit ?? 20);
        const offset = Number(req.query.offset ?? 0);
        if (!Number.isInteger(limit) || limit < 1 || limit > 100 ||
            !Number.isInteger(offset) || offset < 0 || offset > 1000000) {
            throw new ActionError(400, 'Invalid event pagination.');
        }

        const [events, unread] = await Promise.all([
            pool.query(
                `SELECT event_id, event_text, event_type, is_read, created_at
                   FROM user_events
                  WHERE user_id = $1
                  ORDER BY created_at DESC
                  LIMIT $2 OFFSET $3`,
                [userId, limit, offset]
            ),
            pool.query(
                'SELECT COUNT(*) FROM user_events WHERE user_id = $1 AND is_read = false',
                [userId]
            )
        ]);

        return res.json({
            success: true,
            events: events.rows,
            unread_count: Number(unread.rows[0].count)
        });
    } catch (err) {
        return sendActionError(res, err, 'Event fetch failed:');
    }
});

// Marking false -> true is intrinsically idempotent; no financial replay ledger
// is required. Actor identity is derived from the verified session.
router.post('/mark_read', async (req, res) => {
    try {
        const userId = actorId(req);
        const result = await pool.query(
            `UPDATE user_events
                SET is_read = true
              WHERE user_id = $1 AND is_read = false
              RETURNING event_id`,
            [userId]
        );
        return res.json({ success: true, marked_read: result.rowCount });
    } catch (err) {
        return sendActionError(res, err, 'Mark events read failed:');
    }
});

module.exports = router;
