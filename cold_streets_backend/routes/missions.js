const express = require('express');
const pool = require('../db');
const {
    ActionError, integer, actorId, sendActionError, exactJsonAmount
} = require('../utils/economyValidation');
const {
    requireIdempotencyKey, beginIdempotent, completeIdempotent
} = require('../utils/idempotency');
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
        const userId = actorId(req);
        const contact = String(req.params.contact || '').toLowerCase();

        const userRes = await pool.query(
            'SELECT contact_exp, active_contract FROM users WHERE user_id = $1',
            [userId]
        );
        if (userRes.rowCount !== 1) {
            throw new ActionError(404, 'Player not found.');
        }

        const user = userRes.rows[0];
        const rep = anonymousRep(user.contact_exp);

        if (contact === 'anonymous') {
            if (rep <= 6) {
                const missionRes = await pool.query(
                    `SELECT id, contact_name, rep_req, title, message, objective_text,
                            reward_text, reqs_json, rewards_json
                       FROM missions_master
                      WHERE contact_name = 'anonymous' AND rep_req = $1
                      LIMIT 2`,
                    [rep]
                );

                if (missionRes.rowCount !== 1) {
                    throw new ActionError(
                        503,
                        'Anonymous mission catalog is incomplete or ambiguous.'
                    );
                }

                const mission = missionRes.rows[0];
                assertReconciledMission(mission, rep);

                const progressRes = await pool.query(
                    `SELECT status, progress_jsonb, completed_at
                       FROM user_mission_progress
                      WHERE user_id = $1 AND mission_id = $2`,
                    [userId, mission.id]
                );

                return res.json({
                    status: 'active',
                    mission,
                    progress: progressRes.rows[0]?.progress_jsonb || {},
                    progress_status: progressRes.rows[0]?.status || 'active',
                    verification_available: true,
                    anonymous_reputation: rep,
                    kevin_contact_available: false
                });
            }

            // The recovered catalog has one terminal row at rep 7. Its prose
            // clearly hands the player to Kevin, but reward_text says None
            // while rewards_json contains 1000 Clean Cash. Treat it as an
            // informational handoff only: no VERIFY and no reward settlement.
            const terminalRes = await pool.query(
                `SELECT id, contact_name, rep_req, title, message, objective_text,
                        reward_text, reqs_json, rewards_json
                   FROM missions_master
                  WHERE contact_name = 'anonymous' AND rep_req = 7
                  LIMIT 2`
            );
            if (terminalRes.rowCount !== 1) {
                throw new ActionError(
                    503,
                    'Anonymous terminal handoff catalog is incomplete or ambiguous.'
                );
            }

            const terminal = terminalRes.rows[0];
            if (
                String(terminal.id) !== '11' ||
                String(terminal.contact_name) !== 'anonymous' ||
                Number(terminal.rep_req) !== 7 ||
                String(terminal.title) !== 'END OF THE LINE' ||
                String(terminal.objective_text) !==
                    'No further objectives. Request a contract from Kevin.' ||
                String(terminal.reward_text) !== 'None'
            ) {
                throw new ActionError(
                    503,
                    'Anonymous terminal handoff changed and requires source reconciliation.'
                );
            }

            return res.json({
                status: 'handoff',
                mission: terminal,
                progress: {},
                verification_available: false,
                reward_settlement_available: false,
                anonymous_reputation: rep,
                kevin_contact_available: true,
                reason:
                    'Anonymous progression ends here. Kevin contract rules are not source-reconciled.'
            });
        }

        if (contact === 'kevin') {
            if (rep < 7) {
                return res.status(403).json({
                    status: 'locked',
                    reputation: Number(user.contact_exp?.kevin || 0),
                    anonymous_reputation: rep,
                    unlock_requirement: 'Complete the six reconciled Anonymous tutorial missions.'
                });
            }

            return res.json({
                status: 'paused',
                reputation: Number(user.contact_exp?.kevin || 0),
                anonymous_reputation: rep,
                contract_available: false,
                contract: null,
                legacy_active_contract_present:
                    user.active_contract?.fixer === 'kevin',
                reason:
                    'Kevin is unlocked by the Anonymous rep-7 handoff, but contract objectives, payouts, and reputation rules are not source-reconciled.'
            });
        }

        return res.json({
            status: 'unknown',
            message: 'Contact logic is not source-reconciled.'
        });
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

        if (contact === 'kevin') {
            // Kevin has no recovered mission rows and no mission sheet source.
            // The old random generator (crime count, gym count, reward curve,
            // reputation gains/penalties) is therefore not authoritative.
            // Do not create, advance, settle, abort, or pay those contracts.
            if (!['REQUEST', 'TURN_IN', 'PARTIAL', 'ABORT'].includes(actionType)) {
                throw new ActionError(400, 'Unsupported Kevin action.');
            }

            throw new ActionError(
                503,
                'Kevin contracts are paused until objectives, rewards, and reputation semantics are recovered from an authoritative source.'
            );
        }

        throw new ActionError(400, 'Unsupported mission action.');
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
