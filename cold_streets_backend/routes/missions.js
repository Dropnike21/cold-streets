const express = require('express');
const pool = require('../db');
const { randomInt } = require('node:crypto');
const { ActionError, integer, actorId, sendActionError, exactJsonAmount } = require('../utils/economyValidation');
const { assertKevinContractComplete } = require('../utils/missionProgress');
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

        const userRes = await pool.query("SELECT contact_exp, active_contract FROM users WHERE user_id = $1", [user_id]);
        if (userRes.rows.length === 0) return res.status(404).json({ error: "User not found." });

        const user = userRes.rows[0];
        const expMap = user.contact_exp || { anonymous: 1, kevin: 0, uncle_john: 0 };
        const rep = parseInt(expMap[contact]) || 0;

        if (contact === 'anonymous') {
            // Fetch the specific story step from the database!
            const missionRes = await pool.query("SELECT * FROM missions_master WHERE contact_name = 'anonymous' AND rep_req = $1", [rep]);

            if (missionRes.rows.length > 0) {
                return res.json({ status: "active", mission: missionRes.rows[0] });
            } else {
                // If no mission exists (e.g., they hit level 51 and we only have 50 missions)
                return res.json({
                    status: "completed",
                    mission: {
                        title: "END OF THE LINE",
                        message: "I've taught you all I can. A guy named Kevin is looking for reliable muscle. Check your contact list, his number should be in there now.",
                        objective_text: "No further objectives.",
                        reward_text: "None."
                    }
                });
            }
        }

        if (contact === 'kevin') {
            return res.json({
                status: user.active_contract?.fixer === 'kevin' ? 'active' : 'available',
                contract: user.active_contract?.fixer === 'kevin' ? user.active_contract : null,
                reputation: rep
            });
        }

        return res.json({ status: "unknown", message: "Contact logic not built." });

    } catch (err) {
        console.error("Mission Fetch Error:", err.message);
        res.status(500).json({ error: "Comms error." });
    }
});

// ==========================================
// 2. MISSION ACTION ENGINE (Verify, Abort, Request)
// ==========================================
router.post('/action', async (req, res) => {
    let client, transaction = false;
    try {
        const userId = actorId(req);
        const { contact, action_type: actionType } = req.body || {};

        // The recovered tutorial catalog has empty reqs_json for every step,
        // and no route currently records authoritative completion evidence.
        // Awarding rewards from an unaudited client "VERIFY" would be a
        // repeatable reward exploit. Do not invent objectives as a workaround.
        if (contact === 'anonymous' && actionType === 'VERIFY') {
            throw new ActionError(503, 'Tutorial completion verification is temporarily disabled pending server-side progress tracking.');
        }
        // PARTIAL still has no source-backed completion threshold or payout
        // rule beyond the old unsafe client-triggered endpoint, so it remains
        // disabled. TURN_IN is now backed by server-recorded crime/gym progress.
        if (contact === 'kevin' && actionType === 'PARTIAL') {
            throw new ActionError(503, 'Partial contract settlement is paused pending an explicit design rule.');
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
                throw new ActionError(409, 'An active contract must be completed or aborted before requesting another.');
            }
            const level = integer(user.level, { field: 'Player level', min: 1n, max: 1000000n });
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
            if (updated.rowCount !== 1) throw new ActionError(409, 'Contract changed before settlement.');
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
            'UPDATE users SET contact_exp = $1::jsonb, active_contract = NULL WHERE user_id = $2 RETURNING *',
            [JSON.stringify(contactExp), userId]
        );
        await client.query('COMMIT');
        transaction = false;
        return res.json({ message: 'Contract aborted. Reputation penalty applied.', user: updated.rows[0] });
    } catch (error) {
        if (transaction) {
            try { await client.query('ROLLBACK'); } catch (rollback) { console.error('Mission rollback failed:', rollback); }
        }
        return sendActionError(res, error, 'Mission action failure:');
    } finally {
        if (client) client.release();
    }
});

module.exports = router;
