const express = require('express');
const pool = require('../db');
const router = express.Router();
const { ActionError, integer, actorId, sendActionError } = require('../utils/economyValidation');
const { requireIdempotencyKey, beginIdempotent, completeIdempotent } = require('../utils/idempotency');
const { hasEducationUnlock } = require('../utils/educationEntitlements');

const REVIVE_ENERGY_COST = 75;
const REVIVE_JOB_NAME = 'City Hospital';
const REVIVE_PASSIVE_DESC =
    'Medical Revive Skill: Unlocks the ability to revive others from the hospital. Cost: 75 Energy.';
const REVIVE_PASSIVE_LOGIC =
    'passive: {ability: revive, energy_cost: 75}';

async function resolveReviveRule(client) {
    const result = await client.query(
        `SELECT job_id, mastery_passive_desc, mastery_logic_json::text AS mastery_logic_json
           FROM jobs_master
          WHERE job_name = $1`,
        [REVIVE_JOB_NAME]
    );
    if (result.rowCount !== 1 ||
        result.rows[0].mastery_passive_desc !== REVIVE_PASSIVE_DESC ||
        !String(result.rows[0].mastery_logic_json || '').includes(REVIVE_PASSIVE_LOGIC)) {
        throw new ActionError(
            409,
            'Medical Revive is paused because its City Hospital source rule changed.'
        );
    }
    return result.rows[0];
}

// ==========================================
// 1. GET PATIENT LIST (WITH PAGINATION)
// ==========================================
router.get('/patients', async (req, res) => {
    try {
        const rawLimit = Number(req.query.limit ?? 20);
        const rawPage = Number(req.query.page ?? 1);
        if (!Number.isInteger(rawLimit) || rawLimit < 1 || rawLimit > 100 ||
            !Number.isInteger(rawPage) || rawPage < 1) {
            throw new ActionError(400, 'Invalid pagination.');
        }
        const offset = (rawPage - 1) * rawLimit;
        const countRes = await pool.query(
            'SELECT COUNT(*) FROM users WHERE hospital_expires_at > NOW()'
        );
        const totalPatients = Number(countRes.rows[0].count);
        const patientsRes = await pool.query(
            `SELECT user_id, username, level, hospital_expires_at,
                    last_active_at, state_reason AS reason
               FROM users
              WHERE hospital_expires_at > NOW()
              ORDER BY hospital_expires_at DESC
              LIMIT $1 OFFSET $2`,
            [rawLimit, offset]
        );
        return res.json({
            success: true,
            patients: patientsRes.rows,
            pagination: {
                current_page: rawPage,
                total_pages: Math.max(1, Math.ceil(totalPatients / rawLimit)),
                total_patients: totalPatients
            }
        });
    } catch (err) {
        return sendActionError(res, err, 'Hospital patient list failed:');
    }
});

// ==========================================
// 2. USE SOURCE-BACKED MEDICAL REVIVE
// ==========================================
router.post('/revive', async (req, res) => {
    let client, transaction = false;
    try {
        const actor = actorId(req);
        const idempotencyKey = requireIdempotencyKey(req);
        const target = integer(req.body?.target_id, {
            field: 'Target player ID', min: 1n, max: 9223372036854775807n
        }).toString();
        if (target === actor) {
            throw new ActionError(400, 'Medical Revive can only be used on another player.');
        }

        client = await pool.connect();
        await client.query('BEGIN');
        transaction = true;

        // Cross-player actions lock all affected users in deterministic ID order
        // before the idempotency row to avoid A->B / B->A deadlocks.
        const users = await client.query(
            `SELECT user_id, username, energy, hp,
                    hospital_expires_at, jail_expires_at,
                    (hospital_expires_at > NOW()) AS is_hospitalized,
                    (jail_expires_at > NOW()) AS is_jailed,
                    (hp > 0) AS has_revivable_hp
               FROM users
              WHERE user_id = ANY($1::bigint[])
              ORDER BY user_id
              FOR UPDATE`,
            [[actor, target]]
        );
        if (users.rowCount !== 2) throw new ActionError(404, 'Player or patient not found.');
        const actorRow = users.rows.find(row => String(row.user_id) === actor);
        const targetRow = users.rows.find(row => String(row.user_id) === target);
        if (!actorRow || !targetRow) throw new Error('Hospital lock set is incomplete.');

        const idem = await beginIdempotent(
            client, actor, 'hospital.revive', idempotencyKey, { target }
        );
        if (idem.replay) {
            await client.query('COMMIT');
            transaction = false;
            return res.status(idem.status).json(idem.response);
        }

        const reviveRule = await resolveReviveRule(client);
        const mastery = await client.query(
            `SELECT 1
               FROM user_job_data
              WHERE user_id = $1
                AND job_id = $2
                AND current_rank = 5
                AND is_mastered = true
              LIMIT 1`,
            [actor, reviveRule.job_id]
        );
        const universityUnlock = await hasEducationUnlock(
            client, actor, 'revive_ally'
        );
        if (!mastery.rowCount && !universityUnlock) {
            throw new ActionError(
                403,
                'Medical Revive requires City Hospital mastery or the Combat Medic Training university unlock.'
            );
        }
        if (targetRow.is_hospitalized !== true) {
            throw new ActionError(409, 'This patient has already been discharged.');
        }
        if (targetRow.is_jailed === true) {
            throw new ActionError(
                409,
                'Revive is paused for this patient because Jail and Hospital state conflict.'
            );
        }
        if (targetRow.has_revivable_hp !== true) {
            throw new ActionError(
                409,
                'Revive is paused for zero-HP patients until the canonical revive HP value is recovered.'
            );
        }

        const energy = await client.query(
            `UPDATE users
                SET energy = energy - $1
              WHERE user_id = $2 AND energy >= $1
              RETURNING energy`,
            [REVIVE_ENERGY_COST, actor]
        );
        if (energy.rowCount !== 1) {
            throw new ActionError(409, 'Medical Revive requires 75 Energy.');
        }
        const revived = await client.query(
            `UPDATE users
                SET hospital_expires_at = NULL,
                    state_reason = NULL
              WHERE user_id = $1
                AND hospital_expires_at > NOW()
                AND NOT COALESCE(jail_expires_at > NOW(), false)
                AND hp > 0
              RETURNING username, hp`,
            [target]
        );
        if (revived.rowCount !== 1) {
            throw new ActionError(409, 'Patient state changed before revival.');
        }

        const response = {
            success: true,
            message: 'Successfully revived ' + revived.rows[0].username + '.',
            energy: energy.rows[0].energy,
            revive_source: mastery.rowCount ? 'city_hospital_mastery' : 'university_revive_ally'
        };
        await completeIdempotent(client, idem, 200, response);
        await client.query('COMMIT');
        transaction = false;
        return res.json(response);
    } catch (err) {
        if (transaction) {
            try { await client.query('ROLLBACK'); } catch (rollback) { console.error('Hospital revive rollback:', rollback); }
        }
        return sendActionError(res, err, 'Hospital revive failed:');
    } finally { if (client) client.release(); }
});

module.exports = router;