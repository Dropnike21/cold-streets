const express = require('express');
const pool = require('../db');
const router = express.Router();

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
    const client = await pool.connect();

    try {
        const { user_id, contact, action_type } = req.body;
        await client.query('BEGIN');

        const userRes = await client.query("SELECT * FROM users WHERE user_id = $1 FOR UPDATE", [user_id]);
        if (userRes.rows.length === 0) throw new Error("Ghost account.");

        let user = userRes.rows[0];
        let expMap = user.contact_exp || { anonymous: 1, kevin: 0, uncle_john: 0 };

        // ----------------------------------------
                // ANONYMOUS: VERIFY TUTORIAL COMPLETION
                // ----------------------------------------
                if (contact === 'anonymous' && action_type === 'VERIFY') {
                    let currentRep = parseInt(expMap.anonymous) || 1;

                    const missionRes = await client.query("SELECT * FROM missions_master WHERE contact_name = 'anonymous' AND rep_req = $1", [currentRep]);
                    if (missionRes.rows.length === 0) {
                        await client.query('ROLLBACK');
                        return res.status(400).json({ error: "No active mission found to verify." });
                    }

                    const mission = missionRes.rows[0];
                    const rewards = mission.rewards_json || {};

                    // 🚨 ADDED PARSING FOR ALL REWARD TYPES
                    let addDirty = parseInt(rewards.dirty_cash) || 0;
                    let addCrimeExp = parseInt(rewards.crime_exp) || 0;
                    let addNerve = parseInt(rewards.nerve) || 0;
                    let addEnergy = parseInt(rewards.energy) || 0;

                    // Advance the Story (+1 Rep)
                    expMap.anonymous = currentRep + 1;

                    const updatedUser = await client.query(
                        `UPDATE users
                         SET dirty_cash = dirty_cash + $1,
                             crime_exp = crime_exp + $2,
                             nerve = nerve + $3,
                             energy = energy + $4,
                             contact_exp = $5
                         WHERE user_id = $6 RETURNING *`,
                        [addDirty, addCrimeExp, addNerve, addEnergy, expMap, user_id]
                    );

                    await client.query('COMMIT');
                    return res.json({ message: "Payment transferred. Rep increased.", user: updatedUser.rows[0] });
                }

        // ----------------------------------------
        // KEVIN: PROCEDURALLY GENERATE CONTRACT
        // ----------------------------------------
        if (contact === 'kevin' && action_type === 'REQUEST') {
            // Generate a random dynamic hustle based on their level
            let reqCrimes = Math.floor(Math.random() * 5) + 3;
            let payout = (Math.floor(Math.random() * 500) + 500) * user.level;

            const newContract = {
                fixer: "kevin",
                reqs: { crimes: reqCrimes, gym: 10 },
                progress: { crimes: 0, gym: 0 },
                reward_cash: payout
            };

            const updatedUser = await client.query(
                "UPDATE users SET active_contract = $1 WHERE user_id = $2 RETURNING *",
                [newContract, user_id]
            );

            await client.query('COMMIT');
            return res.json({ message: "Contract downloaded.", user: updatedUser.rows[0] });
        }

        // ----------------------------------------
        // KEVIN: CONTRACT TURN-INS AND ABORTS
        // ----------------------------------------
        if (contact === 'kevin' && (action_type === 'TURN_IN' || action_type === 'PARTIAL' || action_type === 'ABORT')) {
            let activeContract = user.active_contract;
            if (!activeContract || activeContract.fixer !== 'kevin') {
                await client.query('ROLLBACK');
                return res.status(400).json({ error: "You don't have an active contract." });
            }

            let currentRep = parseInt(expMap.kevin) || 0;
            let cashReward = 0;

            if (action_type === 'TURN_IN') {
                expMap.kevin = currentRep + 2;
                cashReward = parseInt(activeContract.reward_cash) || 0;
            } else if (action_type === 'PARTIAL') {
                expMap.kevin = Math.max(0, currentRep - 1); // -1 Penalty, floor at 0
                cashReward = Math.floor((parseInt(activeContract.reward_cash) || 0) * 0.25); // 25% payout
            } else if (action_type === 'ABORT') {
                expMap.kevin = Math.max(0, currentRep - 2); // -2 Penalty
                cashReward = 0;
            }

            const updatedUser = await client.query(
                `UPDATE users
                 SET dirty_cash = dirty_cash + $1, contact_exp = $2, active_contract = NULL
                 WHERE user_id = $3 RETURNING *`,
                [cashReward, expMap, user_id]
            );

            await client.query('COMMIT');
            return res.json({ message: "Contract cleared.", user: updatedUser.rows[0] });
        }

        await client.query('ROLLBACK');
        return res.status(400).json({ error: "Invalid action." });

    } catch (err) {
        await client.query('ROLLBACK');
        console.error("Mission Action Error:", err.message);
        res.status(500).json({ error: "Server malfunction." });
    } finally {
        client.release();
    }
});

module.exports = router;