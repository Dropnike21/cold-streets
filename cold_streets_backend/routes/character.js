const logger = require('../utils/logger');
const express = require('express');
const pool = require('../db');
const router = express.Router();
const {
    ActionError, dbInteger, actorId, sendActionError
} = require('../utils/economyValidation');
const {
    requireIdempotencyKey, beginIdempotent, completeIdempotent
} = require('../utils/idempotency');
const { unlockAchievementsForValue } = require('../utils/achievement_engine');

const BASE_EXP = 25;
const EXPONENT = 1.7;

function getExpRequirement(level) {
    if (!Number.isSafeInteger(level) || level < 1 || level > 1000000) {
        throw new Error('Player level is outside supported progression range.');
    }
    const requirement = Math.floor(BASE_EXP * Math.pow(level, EXPONENT));
    if (!Number.isSafeInteger(requirement) || requirement < 1) {
        throw new Error('EXP requirement is outside exact integer range.');
    }
    return BigInt(requirement);
}

router.post('/level-up', async (req, res) => {
    let client, transaction = false;
    try {
        const userId = actorId(req);
        const idempotencyKey = requireIdempotencyKey(req);
        const action = req.body?.action;
        if (!['UPGRADE', 'HOLD'].includes(action)) {
            throw new ActionError(400, 'Invalid level action.');
        }

        client = await pool.connect();
        await client.query('BEGIN');
        transaction = true;
        const userRes = await client.query(
            'SELECT exp, level FROM users WHERE user_id = $1 FOR UPDATE',
            [userId]
        );
        if (userRes.rowCount !== 1) throw new ActionError(404, 'Player not found.');
        const user = userRes.rows[0];

        const idem = await beginIdempotent(
            client, userId, 'character.level_up', idempotencyKey, { action }
        );
        if (idem.replay) {
            await client.query('COMMIT');
            transaction = false;
            return res.status(idem.status).json(idem.response);
        }

        let response;
        if (action === 'HOLD') {
            const updated = await client.query(
                `UPDATE users SET level_holding = true
                  WHERE user_id = $1
                  RETURNING *`,
                [userId]
            );
            response = { status: 'held', user: updated.rows[0] };
        } else {
            const cost = getExpRequirement(Number(user.level));
            if (dbInteger(user.exp, { field: 'Player EXP' }) < cost) {
                throw new ActionError(409, 'Not enough EXP to level up.');
            }
            const updated = await client.query(
                `UPDATE users
                    SET exp = exp - $1::numeric,
                        level = level + 1,
                        max_hp = max_hp + 50,
                        hp = max_hp + 50,
                        level_holding = false
                  WHERE user_id = $2 AND exp >= $1::numeric
                  RETURNING *`,
                [cost.toString(), userId]
            );
            if (updated.rowCount !== 1) {
                throw new ActionError(409, 'EXP changed before level-up.');
            }
            await unlockAchievementsForValue(
                client, userId, 'player_level', updated.rows[0].level
            );
            response = { status: 'leveled_up', user: updated.rows[0] };
        }

        await completeIdempotent(client, idem, 200, response);
        await client.query('COMMIT');
        transaction = false;
        return res.json(response);
    } catch (err) {
        if (transaction) {
            try { await client.query('ROLLBACK'); }
            catch (rollback) { logger.error('level_up_rollback_failed', logger.errorFields(rollback)); }
        }
        return sendActionError(res, err, 'Character progression failed:');
    } finally {
        if (client) client.release();
    }
});

module.exports = router;
