const express = require('express');
const router = express.Router();
// Reject URLs referencing any player other than the verified session owner.
const { requireOwnedPlayerParam } = require('../middleware/playerIdentity');
router.param('user_id', requireOwnedPlayerParam);

const pool = require('../db');
const { recordGymTrainingAchievement } = require('../utils/achievement_engine');
const { ActionError, integer, dbInteger, actorId, sendActionError } = require('../utils/economyValidation');
const { recordAnonymousGymTraining } = require('../utils/anonymousTutorial');
const { requireIdempotencyKey, beginIdempotent, completeIdempotent } = require('../utils/idempotency');

// The Level 1 safety net for the Hybrid Math Engine
const GLOBAL_FLAT_RATE = 0.05;

async function ensureStarterGym(userId) {
    let client;
    let transaction = false;
    try {
        client = await pool.connect();
        await client.query('BEGIN');
        transaction = true;

        const actor = await client.query(
            'SELECT user_id FROM users WHERE user_id = $1 FOR UPDATE',
            [userId]
        );
        if (actor.rowCount !== 1) {
            throw new ActionError(404, 'Player not found.');
        }

        await client.query(
            `INSERT INTO user_gym_stats (
                user_id, gym_exp, active_gym_id, daily_gym_fee
             )
             VALUES ($1, 0, 1, 0)
             ON CONFLICT (user_id) DO NOTHING`,
            [userId]
        );
        await client.query(
            `INSERT INTO user_owned_gyms (user_id, gym_id)
             VALUES ($1, 1)
             ON CONFLICT (user_id, gym_id) DO NOTHING`,
            [userId]
        );

        const seeded = await client.query(
            'SELECT gym_exp, active_gym_id FROM user_gym_stats WHERE user_id = $1',
            [userId]
        );
        if (seeded.rowCount !== 1) {
            throw new Error('Starter gym provisioning failed.');
        }

        await client.query('COMMIT');
        transaction = false;
        return seeded;
    } catch (err) {
        if (transaction) {
            try { await client.query('ROLLBACK'); }
            catch (rollback) { console.error('Starter gym rollback:', rollback); }
        }
        throw err;
    } finally {
        if (client) client.release();
    }
}

// --- 1. FETCH GYM DASHBOARD ---
router.get('/:user_id', async (req, res) => {
    try {
        const { user_id } = req.params;
        let gymStatsRes = await pool.query('SELECT gym_exp, active_gym_id FROM user_gym_stats WHERE user_id = $1', [user_id]);

        // Deterministic, conflict-safe provisioning for the source-backed
        // Level 1 starter gym. Concurrent dashboard reads cannot duplicate it.
        if (gymStatsRes.rows.length === 0) {
            gymStatsRes = await ensureStarterGym(user_id);
        }

        const { gym_exp, active_gym_id } = gymStatsRes.rows[0];
        const ownedRes = await pool.query('SELECT gym_id FROM user_owned_gyms WHERE user_id = $1', [user_id]);
        const ownedGymIds = ownedRes.rows.map(row => row.gym_id);
        const masterRes = await pool.query('SELECT * FROM gyms_master ORDER BY gym_id ASC');

        const mappedGyms = masterRes.rows.map(gym => {
            return {
                id: gym.gym_id,
                name: gym.gym_name,
                zone: gym.zone,
                desc: gym.description,
                str_percent: parseFloat(gym.str_percent),
                def_percent: parseFloat(gym.def_percent),
                dex_percent: parseFloat(gym.dex_percent),
                spd_percent: parseFloat(gym.spd_percent),
                str_action: gym.str_action || 'lifted weights',
                def_action: gym.def_action || 'hit the heavy bag',
                dex_action: gym.dex_action || 'practiced form',
                spd_action: gym.spd_action || 'ran laps',
                unlock_cost: parseInt(gym.unlock_cost),
                daily_fee: parseInt(gym.daily_fee),
                unlock_exp_req: parseInt(gym.unlock_exp_req),
                is_owned: ownedGymIds.includes(gym.gym_id)
            };
        });

        res.json({ success: true, gym_exp, active_gym_id, gyms: mappedGyms });
    } catch (err) {
        console.error(err);
        res.status(500).json({ error: "Server error fetching gym data." });
    }
});

// --- 2. PURCHASE A GYM ---
router.post('/purchase', async (req, res) => {
    let client, transaction = false;
    try {
        const userId = actorId(req);
        const gymId = integer(req.body?.gym_id, { field: 'Gym ID', min: 1n, max: 9223372036854775807n }).toString();
        client = await pool.connect();
        await client.query('BEGIN');
        transaction = true;

        // User-first lock order matches bank, market, property and casino routes.
        const user = await client.query(
            'SELECT dirty_cash FROM users WHERE user_id = $1 FOR UPDATE', [userId]
        );
        if (user.rowCount !== 1) throw new ActionError(404, 'Player not found.');
        const owned = await client.query(
            'SELECT 1 FROM user_owned_gyms WHERE user_id = $1 AND gym_id = $2',
            [userId, gymId]
        );
        if (owned.rowCount) throw new ActionError(409, 'Gym already owned.');

        const gym = await client.query(
            'SELECT unlock_cost FROM gyms_master WHERE gym_id = $1', [gymId]
        );
        if (gym.rowCount !== 1) throw new ActionError(404, 'Gym not found.');
        const cost = dbInteger(gym.rows[0].unlock_cost ?? 0, { field: 'Gym unlock cost' });
        if (cost < 0n) throw new Error('Gym catalog has negative unlock cost.');
        if (dbInteger(user.rows[0].dirty_cash) < cost) throw new ActionError(409, 'Insufficient Dirty Cash.');

        const debit = await client.query(
            'UPDATE users SET dirty_cash = dirty_cash - $1::numeric WHERE user_id = $2 AND dirty_cash >= $1::numeric RETURNING *',
            [cost.toString(), userId]
        );
        if (debit.rowCount !== 1) throw new ActionError(409, 'Wallet changed before gym purchase.');
        await client.query(
            'INSERT INTO user_owned_gyms (user_id, gym_id) VALUES ($1, $2)',
            [userId, gymId]
        );
        await client.query(
            'UPDATE user_gym_stats SET active_gym_id = $1 WHERE user_id = $2',
            [gymId, userId]
        );

        await client.query('COMMIT');
        transaction = false;
        return res.json({ success: true, message: 'Membership activated!', user: debit.rows[0] });
    } catch (err) {
        if (transaction) {
            try { await client.query('ROLLBACK'); } catch (rollback) { console.error('Gym purchase rollback:', rollback); }
        }
        return sendActionError(res, err, 'Gym purchase failed:');
    } finally { if (client) client.release(); }
});

// --- 3. ACTIVATE AN OWNED GYM ---
router.post('/activate', async (req, res) => {
    try {
        const userId = actorId(req);
        const gymId = integer(req.body?.gym_id, {
            field: 'Gym ID', min: 1n, max: 9223372036854775807n
        }).toString();
        const owned = await pool.query(
            'SELECT 1 FROM user_owned_gyms WHERE user_id = $1 AND gym_id = $2',
            [userId, gymId]
        );
        if (!owned.rowCount) throw new ActionError(403, 'You do not own this gym.');
        const updated = await pool.query(
            'UPDATE user_gym_stats SET active_gym_id = $1 WHERE user_id = $2 RETURNING active_gym_id',
            [gymId, userId]
        );
        if (updated.rowCount !== 1) throw new Error('Gym statistics row missing.');
        return res.json({ success: true, message: 'Active gym switched.', active_gym_id: updated.rows[0].active_gym_id });
    } catch (err) {
        return sendActionError(res, err, 'Gym activation failed:');
    }
});

// --- 4. BULK TRAIN ---
router.post('/train', async (req, res) => {
    const validStats = ['str', 'def', 'dex', 'spd'];
    const statType = req.body?.stat_type;
    if (!validStats.includes(statType)) return res.status(400).json({ error: 'Invalid stat.' });

    let client, transaction = false;
    let userId, energySpent;
    try {
        userId = actorId(req);
        energySpent = integer(req.body?.energy_spent, {
            field: 'Energy spent', min: 1n, max: 10000n
        });
        const gymId = integer(req.body?.gym_id, {
            field: 'Gym ID', min: 1n, max: 9223372036854775807n
        }).toString();
        const statColumn = 'stat_' + statType;
        const percentColumn = statType + '_percent';

        client = await pool.connect();
        await client.query('BEGIN');
        transaction = true;
        const user = await client.query(
            'SELECT energy, exp, ' + statColumn + ' FROM users WHERE user_id = $1 FOR UPDATE',
            [userId]
        );
        if (user.rowCount !== 1) throw new ActionError(404, 'Player not found.');

        const gymState = await client.query(
            'SELECT active_gym_id FROM user_gym_stats WHERE user_id = $1 FOR UPDATE',
            [userId]
        );
        if (gymState.rowCount !== 1 || String(gymState.rows[0].active_gym_id) !== gymId) {
            throw new ActionError(409, 'Train only at your active gym.');
        }
        const owned = await client.query(
            'SELECT 1 FROM user_owned_gyms WHERE user_id = $1 AND gym_id = $2',
            [userId, gymId]
        );
        if (!owned.rowCount) throw new ActionError(403, 'You do not own this gym membership.');

        const energy = Number(user.rows[0].energy);
        const energyNumber = Number(energySpent);
        if (!Number.isFinite(energy) || energy < energyNumber) {
            throw new ActionError(409, 'Not enough energy.');
        }
        const gym = await client.query(
            'SELECT ' + percentColumn + ' FROM gyms_master WHERE gym_id = $1',
            [gymId]
        );
        if (gym.rowCount !== 1) throw new ActionError(404, 'Gym catalog row missing.');

        const currentStat = Number(user.rows[0][statColumn]);
        const gymRate = Number(gym.rows[0][percentColumn] ?? 0);
        if (!Number.isFinite(currentStat) || !Number.isFinite(gymRate) || gymRate < 0) {
            throw new Error('Gym catalog or player stat is invalid.');
        }
        const baseGain = (currentStat * gymRate) + GLOBAL_FLAT_RATE;
        const totalStatGain = Number((baseGain * energyNumber).toFixed(2));
        const playerExpGain = 5 * energyNumber;
        const gymExpGain = energyNumber;

        const updatedUser = await client.query(
            `UPDATE users
             SET energy = energy - $1,
                 exp = exp + $2,
                 ${statColumn} = ${statColumn} + $3
             WHERE user_id = $4 AND energy >= $1
             RETURNING *`,
            [energyNumber, playerExpGain, totalStatGain, userId]
        );
        if (updatedUser.rowCount !== 1) throw new ActionError(409, 'Energy changed before training.');
        const exp = await client.query(
            'UPDATE user_gym_stats SET gym_exp = gym_exp + $1 WHERE user_id = $2 RETURNING gym_exp',
            [gymExpGain, userId]
        );
        if (exp.rowCount !== 1) throw new Error('Gym statistics row missing.');

        // Contract "gym" means one successful server-side training action,
        // independent of how much energy was spent in that action.
        await recordAnonymousGymTraining(client, userId, statType, energySpent.toString());
        await recordGymTrainingAchievement(client, userId, energySpent.toString());
        await client.query('COMMIT');
        transaction = false;

        const payload = updatedUser.rows[0];
        payload.gym_exp = exp.rows[0].gym_exp;
        return res.json({ success: true, gained: totalStatGain.toFixed(2), user: payload });
    } catch (err) {
        if (transaction) {
            try { await client.query('ROLLBACK'); } catch (rollback) { console.error('Gym train rollback:', rollback); }
        }
        return sendActionError(res, err, 'Gym training failed:');
    } finally { if (client) client.release(); }
});

module.exports = router;