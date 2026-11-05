const express = require('express');
const pool = require('../db');
const { randomInt } = require('node:crypto');
const {
    ActionError, integer, actorId, sendActionError, exactJsonAmount
} = require('../utils/economyValidation');
const {
    requireIdempotencyKey, beginIdempotent, completeIdempotent
} = require('../utils/idempotency');
const { assertKevinContractComplete } = require('../utils/missionProgress');
const {
    anonymousRep,
    assertReconciledMission,
    loadCurrentAnonymousMission,
    lockProgress,
    recordAnonymousVisit,
    assertAnonymousMissionComplete,
    rewardDeltas
} = require('../utils/anonymousTutorial');
const router = express.Router();

// Reject URLs referencing any player other than the verified session owner.
const { requireOwnedPlayerParam } = require('../middleware/playerIdentity');
router.param('user_id', requireOwnedPlayerParam);

// ==========================================
// 1. FETCH CURRENT MISSION DETAILS
// ==========================================
router.get('/details/:user_id/:contact', async (req, res) => {
    try {
        const { user_id, contact } = req.params;

        const userRes = await pool.query(
            'SELECT contact_exp, active_contract FROM users WHERE user_id = $1',
            [user_id]
        );
        if (userRes.rows.length === 0) {
            return res.status(404).json({ error: 'User not found.' });
        }

        const user = userRes.rows[0];

        if (contact === 'anonymous') {
            const rep = anonymousRep(user.contact_exp);
            const missionRes = await pool.query(
                `SELECT id, contact_name, rep_req, title, message, objective_text,
                        reward_text, reqs_json, rewards_json
                   FROM missions_master
                  WHERE contact_name = 'anonymous' AND rep_req = $1
                  LIMIT 2`,
                [rep]
            );

            if (missionRes.rowCount === 0) {
                return res.json({
                    status: 'completed',
                    mission: {
                        title: 'END OF THE LINE',
                        message: 'Anonymous has no further reconciled mission data.',
                        objective_text: 'No further objectives.',
                        reward_text: 'None.'
                    },
                    progress: {},
                    verification_available: false
                });
            }
            if (missionRes.rowCount !== 1) {
                throw new ActionError(503, 'Anonymous mission catalog is ambiguous.');
            }

            const mission = missionRes.rows[0];

            // Reps 1-6 are the six recovered guided tutorial steps. Rep 7 is
            // deliberately non-settling: reward_text says None while the
            // stored reward payload contains Clean Cash, and the Kevin unlock
            // threshold conflicts with the current client.
            if (rep > 6) {
                return res.json({
                    status: 'paused',
                    mission,
                    progress: {},
                    verification_available: false,
                    reason: 'Terminal Anonymous progression requires canonical source reconciliation.'
                });
            }

            assertReconciledMission(mission, rep);
            const progressRes = await pool.query(
                `SELECT status, progress_jsonb, completed_at
                   FROM user_mission_progress
                  WHERE user_id = $1 AND mission_id = $2`,
                [user_id, mission.id]
            );
            const progress = progressRes.rows[0]?.progress_jsonb || {};

            return res.json({
                status: 'active',
                mission,
                progress,
                progress_status: progressRes.rows[0]?.status || 'active',
                verification_available: true
            });
        }

        const expMap = user.contact_exp || { anonymous: 1, kevin: 0, uncle_john: 0 };
        const rep = Number(expMap[contact]) || 0;

        if (contact === 'kevin') {
            return res.json({
                status: user.active_contract?.fixer === 'kevin' ? 'active' : 'available',
                contract: user.active_contract?.fixer === 'kevin' ? user.active_contract : null,
                reputation: rep
            });
        }

        return res.json({ status: 'unknown', message: 'Contact logic not built.' });
    } catch (err) {
        return sendActionError(res, err, 'Mission fetch failed:');
    }
});

// ==========================================
// 2. RECORD AN AUTHENTICATED TUTORIAL NAVIGATION EVENT
// ==========================================
// Navigation objectives inherently originate in the client UI. The server does
// not accept completion booleans or arbitrary progress amounts: it accepts one
// fixed visit key, verifies that key is required by the actor's CURRENT
// reconciled mission, and persists the observation idempotently.
router.post('/tutorial/visit', async (req, res) => {
    let client, transaction = false;
    try {
        const userId = actorId(req);
        if (!req.body || typeof req.body !== 'object' || Array.isArray(req.body) ||
            Object.keys(req.body).some(key => key !== 'visit')) {
            throw new ActionError(400, 'Tutorial visit accepts only a visit key.');
        }
        const visit = req.body.visit;

        client = await pool.connect();
        await client.query('BEGIN');
        transaction = true;

        const player = await client.query(
            'SELECT contact_exp FROM users WHERE user_id = $1 FOR UPDATE',
            [userId]
        );
        if (player.rowCount !== 1) throw new ActionError(404, 'Player not found.');

        const progress = await recordAnonymousVisit(
            client, userId, player.rows[0].contact_exp, visit
        );

        await client.query('COMMIT');
        transaction = false;
        return res.json({ success: true, progress });
    } catch (error) {
        if (transaction) {
            try { await client.query('ROLLBACK'); }
            catch (rollback) { console.error('Tutorial visit rollback failed:', rollback); }
        }
        return sendActionError(res, error, 'Tutorial visit failed:');
    } finally {
        if (client) client.release();
    }
});

// ==========================================
// 3. MISSION ACTION ENGINE (Verify, Abort, Request)
// ==========================================
router.post('/action', async (req, res) => {
    let client, transaction = false;
    try {
        const userId = actorId(req);
        const { contact, action_type: actionType } = req.body || {};

        if (contact === 'anonymous' && actionType === 'VERIFY') {
            const idempotencyKey = requireIdempotencyKey(req);

            client = await pool.connect();
            await client.query('BEGIN');
            transaction = true;

            // Lock order: authenticated player -> idempotency -> mission
            // progress. The mission/catalog row is read-only.
            const player = await client.query(
                'SELECT contact_exp FROM users WHERE user_id = $1 FOR UPDATE',
                [userId]
            );
            if (player.rowCount !== 1) throw new ActionError(404, 'Player not found.');

            const rep = anonymousRep(player.rows[0].contact_exp);
            const idem = await beginIdempotent(
                client,
                userId,
                'missions.anonymous_verify',
                idempotencyKey,
                { rep }
            );
            if (idem.replay) {
                await client.query('COMMIT');
                transaction = false;
                return res.status(idem.status).json(idem.response);
            }

            const { mission, rule } = await loadCurrentAnonymousMission(
                client, userId, player.rows[0].contact_exp
            );
            const progressRow = await lockProgress(client, userId, mission.id);
            if (progressRow.status !== 'active') {
                throw new ActionError(409, 'This Anonymous mission is already completed.');
            }
            assertAnonymousMissionComplete(rule, progressRow.progress_jsonb);

            const reward = rewardDeltas(rule);
            const nextRep = rep + 1;
            const updated = await client.query(
                `UPDATE users
                    SET dirty_cash = dirty_cash + $1::numeric,
                        clean_cash = clean_cash + $2::numeric,
                        energy = energy + $3::numeric,
                        nerve = nerve + $4::numeric,
                        contact_exp = jsonb_set(
                            contact_exp,
                            '{anonymous}',
                            to_jsonb($5::bigint),
                            true
                        )
                  WHERE user_id = $6
                    AND COALESCE(contact_exp->>'anonymous', '1') = $7
                  RETURNING *`,
                [
                    reward.dirtyCash.toString(),
                    reward.cleanCash.toString(),
                    reward.energy.toString(),
                    reward.nerve.toString(),
                    String(nextRep),
                    userId,
                    String(rep)
                ]
            );
            if (updated.rowCount !== 1) {
                throw new ActionError(409, 'Anonymous reputation changed before settlement.');
            }

            const completed = await client.query(
                `UPDATE user_mission_progress
                    SET status = 'completed',
                        completed_at = NOW(),
                        updated_at = NOW()
                  WHERE user_id = $1 AND mission_id = $2
                    AND status = 'active'
                  RETURNING mission_id`,
                [userId, mission.id]
            );
            if (completed.rowCount !== 1) {
                throw new ActionError(409, 'Anonymous mission completion state changed.');
            }

            const response = {
                message: 'Objective verified. Anonymous reputation increased.',
                completed_mission_id: mission.id,
                anonymous_reputation: nextRep,
                rewards: {
                    dirty_cash: exactJsonAmount(reward.dirtyCash),
                    clean_cash: exactJsonAmount(reward.cleanCash),
                    energy: exactJsonAmount(reward.energy),
                    nerve: exactJsonAmount(reward.nerve)
                },
                user: updated.rows[0]
            };

            await completeIdempotent(client, idem, 200, response);
            await client.query('COMMIT');
            transaction = false;
            return res.json(response);
        }

        // PARTIAL still has no source-backed completion threshold or payout
        // rule beyond the old unsafe client-triggered endpoint, so it remains
        // disabled. TURN_IN is backed by server-recorded crime/gym progress.
        if (contact === 'kevin' && actionType === 'PARTIAL') {
            throw new ActionError(
                503,
                'Partial contract settlement is paused pending an explicit design rule.'
            );
        }
        if (contact !== 'kevin' || !['REQUEST', 'TURN_IN', 'ABORT'].includes(actionType)) {
            throw new ActionError(400, 'Unsupported mission action.');
        }

        client = await pool.connect();
        await client.query('BEGIN');
        transaction = true;
        const player = await client.query(
            'SELECT level, contact_exp, active_contract FROM users WHERE user_id = $1 FOR UPDATE',
            [userId]
        );
        if (player.rowCount !== 1) throw new ActionError(404, 'Player not found.');
        const user = player.rows[0];

        if (actionType === 'REQUEST') {
            if (user.active_contract !== null) {
                throw new ActionError(
                    409,
                    'An active contract must be completed or aborted before requesting another.'
                );
            }
            const level = integer(user.level, {
                field: 'Player level', min: 1n, max: 1000000n
            });
            const reqCrimes = randomInt(3, 8);
            const reward = BigInt(randomInt(500, 1000)) * level;
            const contract = {
                fixer: 'kevin',
                reqs: { crimes: reqCrimes, gym: 10 },
                progress: { crimes: 0, gym: 0 },
                reward_cash: reward.toString()
            };
            const updated = await client.query(
                'UPDATE users SET active_contract = $1::jsonb WHERE user_id = $2 RETURNING *',
                [JSON.stringify(contract), userId]
            );
            await client.query('COMMIT');
            transaction = false;
            return res.json({ message: 'Contract downloaded.', user: updated.rows[0] });
        }

        const current = user.active_contract;
        if (!current || current.fixer !== 'kevin') {
            throw new ActionError(409, 'No active Kevin contract.');
        }
        const contactExp = user.contact_exp && typeof user.contact_exp === 'object'
            ? { ...user.contact_exp }
            : { anonymous: 1, kevin: 0, uncle_john: 0 };
        const existingRep = Number(contactExp.kevin) || 0;

        if (actionType === 'TURN_IN') {
            assertKevinContractComplete(current);
            const reward = integer(current.reward_cash, {
                field: 'Contract reward', min: 0n, max: 999999999999999999999999n
            });
            contactExp.kevin = existingRep + 2;
            const updated = await client.query(
                `UPDATE users
                 SET dirty_cash = dirty_cash + $1::numeric,
                     contact_exp = $2::jsonb,
                     active_contract = NULL
                 WHERE user_id = $3 AND active_contract IS NOT NULL
                 RETURNING *`,
                [reward.toString(), JSON.stringify(contactExp), userId]
            );
            if (updated.rowCount !== 1) {
                throw new ActionError(409, 'Contract changed before settlement.');
            }
            await client.query('COMMIT');
            transaction = false;
            return res.json({
                message: 'Contract completed. Payment transferred.',
                payout: exactJsonAmount(reward),
                user: updated.rows[0]
            });
        }

        contactExp.kevin = Math.max(0, existingRep - 2);
        const updated = await client.query(
            `UPDATE users
                SET contact_exp = $1::jsonb,
                    active_contract = NULL
              WHERE user_id = $2
              RETURNING *`,
            [JSON.stringify(contactExp), userId]
        );
        await client.query('COMMIT');
        transaction = false;
        return res.json({
            message: 'Contract aborted. Reputation penalty applied.',
            user: updated.rows[0]
        });
    } catch (error) {
        if (transaction) {
            try { await client.query('ROLLBACK'); }
            catch (rollback) { console.error('Mission rollback failed:', rollback); }
        }
        return sendActionError(res, error, 'Mission action failure:');
    } finally {
        if (client) client.release();
    }
});

module.exports = router;
