const express = require('express');
const router = express.Router();
const pool = require('../db');
const {
    ActionError, integer, dbInteger, exactJsonAmount, actorId, sendActionError
} = require('../utils/economyValidation');
const {
    requireIdempotencyKey, beginIdempotent, completeIdempotent
} = require('../utils/idempotency');

const CLASSIFIED_COST_PER_CHARACTER = 10n;
const MIN_BOUNTY = 500n;

// --- GET FRONT PAGE DATA ---
router.get('/frontpage', async (_req, res) => {
    try {
        const [newsRes, bountiesRes, classifiedsRes] = await Promise.all([
            pool.query(
                `SELECT headline, category, created_at
                   FROM system_news
                  ORDER BY created_at DESC
                  LIMIT 5`
            ),
            pool.query(
                `SELECT b.id AS bounty_id,
                        b.reward_cash,
                        b.is_anonymous,
                        b.created_at,
                        t.username AS target_username,
                        t.level AS target_level,
                        CASE WHEN b.is_anonymous THEN NULL
                             ELSE p.username END AS placed_by_username
                   FROM bounties b
                   JOIN users t ON b.target_user_id = t.user_id
                   JOIN users p ON b.placed_by_user_id = p.user_id
                  ORDER BY b.reward_cash DESC
                  LIMIT 10`
            ),
            pool.query(
                `SELECT c.id AS ad_id, c.ad_text, c.expires_at, u.username
                   FROM classified_ads c
                   JOIN users u ON c.user_id = u.user_id
                  WHERE c.expires_at > NOW()
                  ORDER BY c.expires_at ASC`
            )
        ]);

        return res.json({
            success: true,
            news: newsRes.rows,
            bounties: bountiesRes.rows,
            classifieds: classifiedsRes.rows
        });
    } catch (err) {
        return sendActionError(res, err, 'Info Broker front page failed:');
    }
});

// --- POST CLASSIFIED AD ---
router.post('/classifieds', async (req, res) => {
    let client, transaction = false;
    try {
        const userId = actorId(req);
        const idempotencyKey = requireIdempotencyKey(req);
        if (typeof req.body?.ad_text !== 'string') {
            throw new ActionError(400, 'Ad text is required.');
        }
        const adText = req.body.ad_text.trim();
        if (adText.length < 1 || adText.length > 150) {
            throw new ActionError(400, 'Ad text must be between 1 and 150 characters.');
        }
        const cost = BigInt(adText.length) * CLASSIFIED_COST_PER_CHARACTER;

        client = await pool.connect();
        await client.query('BEGIN');
        transaction = true;
        const player = await client.query(
            'SELECT clean_cash FROM users WHERE user_id = $1 FOR UPDATE',
            [userId]
        );
        if (player.rowCount !== 1) throw new ActionError(404, 'Player not found.');

        const idem = await beginIdempotent(
            client, userId, 'info_broker.classified', idempotencyKey, { adText }
        );
        if (idem.replay) {
            await client.query('COMMIT');
            transaction = false;
            return res.status(idem.status).json(idem.response);
        }
        if (dbInteger(player.rows[0].clean_cash) < cost) {
            throw new ActionError(409, 'Insufficient Clean Cash.');
        }

        const debit = await client.query(
            `UPDATE users
                SET clean_cash = clean_cash - $1::numeric
              WHERE user_id = $2 AND clean_cash >= $1::numeric
              RETURNING clean_cash`,
            [cost.toString(), userId]
        );
        if (debit.rowCount !== 1) throw new ActionError(409, 'Balance changed before ad purchase.');

        const ad = await client.query(
            `INSERT INTO classified_ads (user_id, ad_text, expires_at)
             VALUES ($1, $2, NOW() + INTERVAL '24 hours')
             RETURNING id, expires_at`,
            [userId, adText]
        );

        const response = {
            success: true,
            message: 'Classified ad posted.',
            ad_id: ad.rows[0].id,
            expires_at: ad.rows[0].expires_at,
            cost: exactJsonAmount(cost),
            clean_cash: exactJsonAmount(dbInteger(debit.rows[0].clean_cash))
        };
        await completeIdempotent(client, idem, 200, response);
        await client.query('COMMIT');
        transaction = false;
        return res.json(response);
    } catch (err) {
        if (transaction) {
            try { await client.query('ROLLBACK'); }
            catch (rollback) { console.error('Classified rollback:', rollback); }
        }
        return sendActionError(res, err, 'Classified purchase failed:');
    } finally {
        if (client) client.release();
    }
});

// --- POST A NEW BOUNTY ---
router.post('/bounty', async (req, res) => {
    let client, transaction = false;
    try {
        const userId = actorId(req);
        const idempotencyKey = requireIdempotencyKey(req);
        const reward = integer(req.body?.reward_cash, {
            field: 'Bounty reward', min: MIN_BOUNTY
        });
        if (typeof req.body?.target_username !== 'string' ||
            !req.body.target_username.trim()) {
            throw new ActionError(400, 'Target username is required.');
        }
        if (typeof req.body?.is_anonymous !== 'boolean') {
            throw new ActionError(400, 'is_anonymous must be a boolean.');
        }
        const targetUsername = req.body.target_username.trim();

        client = await pool.connect();
        await client.query('BEGIN');
        transaction = true;
        const player = await client.query(
            'SELECT dirty_cash FROM users WHERE user_id = $1 FOR UPDATE',
            [userId]
        );
        if (player.rowCount !== 1) throw new ActionError(404, 'Player not found.');

        const idem = await beginIdempotent(
            client, userId, 'info_broker.bounty', idempotencyKey,
            {
                targetUsername,
                reward: reward.toString(),
                anonymous: req.body.is_anonymous
            }
        );
        if (idem.replay) {
            await client.query('COMMIT');
            transaction = false;
            return res.status(idem.status).json(idem.response);
        }

        const targetRes = await client.query(
            'SELECT user_id, username FROM users WHERE username = $1',
            [targetUsername]
        );
        if (targetRes.rowCount !== 1) throw new ActionError(404, 'Target user not found.');
        const targetId = String(targetRes.rows[0].user_id);
        if (targetId === userId) throw new ActionError(400, 'You cannot place a bounty on yourself.');
        if (dbInteger(player.rows[0].dirty_cash) < reward) {
            throw new ActionError(409, 'Insufficient Dirty Cash.');
        }

        const debit = await client.query(
            `UPDATE users
                SET dirty_cash = dirty_cash - $1::numeric
              WHERE user_id = $2 AND dirty_cash >= $1::numeric
              RETURNING dirty_cash`,
            [reward.toString(), userId]
        );
        if (debit.rowCount !== 1) throw new ActionError(409, 'Balance changed before bounty placement.');

        const bounty = await client.query(
            `INSERT INTO bounties
               (target_user_id, placed_by_user_id, reward_cash, is_anonymous)
             VALUES ($1, $2, $3::numeric, $4)
             RETURNING id`,
            [targetId, userId, reward.toString(), req.body.is_anonymous]
        );

        const response = {
            success: true,
            message: 'Bounty placed on ' + targetRes.rows[0].username + '.',
            bounty_id: bounty.rows[0].id,
            reward_cash: exactJsonAmount(reward),
            dirty_cash: exactJsonAmount(dbInteger(debit.rows[0].dirty_cash))
        };
        await completeIdempotent(client, idem, 200, response);
        await client.query('COMMIT');
        transaction = false;
        return res.json(response);
    } catch (err) {
        if (transaction) {
            try { await client.query('ROLLBACK'); }
            catch (rollback) { console.error('Bounty rollback:', rollback); }
        }
        return sendActionError(res, err, 'Bounty placement failed:');
    } finally {
        if (client) client.release();
    }
});

module.exports = router;
