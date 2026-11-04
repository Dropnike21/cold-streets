const express = require('express');
const { randomInt } = require('node:crypto');
const pool = require('../db');
const router = express.Router();
const { trackAndCheckAchievement } = require('../utils/achievement_engine');
const {
    ActionError, integer, dbInteger, exactJsonAmount, actorId, sendActionError
} = require('../utils/economyValidation');
const {
    requireIdempotencyKey, beginIdempotent, completeIdempotent
} = require('../utils/idempotency');
const { hasEducationUnlock } = require('../utils/educationEntitlements');

const JAIL_FLAT_RATE = '0.01';
const JAIL_MULTIPLIER = '0.0001';
const BREAKOUT_NERVE_COST = 5n;
const BREAKOUT_SUCCESS_PERCENT = 40;

async function lockPlayers(client, ids) {
    const unique = [...new Set(ids.map(String))]
        .sort((a, b) => a.length - b.length || a.localeCompare(b));
    const result = await client.query(
        `SELECT user_id, username, clean_cash, influence, nerve, heat,
                energy, exp, stat_str, stat_def, stat_dex, stat_spd,
                jail_expires_at, jail_initial_seconds
           FROM users
          WHERE user_id = ANY($1::bigint[])
          ORDER BY user_id
          FOR UPDATE`,
        [unique]
    );
    if (result.rowCount !== unique.length) {
        throw new ActionError(404, 'Player or inmate not found.');
    }
    return new Map(result.rows.map(row => [String(row.user_id), row]));
}

// ==========================================
// 1. GET INMATE LIST
// ==========================================
router.get('/inmates', async (_req, res) => {
    try {
        const inmates = await pool.query(
            `SELECT user_id, username, level, jail_expires_at,
                    jail_initial_seconds, state_reason AS reason
               FROM users
              WHERE jail_expires_at > NOW()
              ORDER BY jail_expires_at ASC`
        );
        return res.json({ success: true, inmates: inmates.rows });
    } catch (err) {
        return sendActionError(res, err, 'Jail inmate list failed:');
    }
});

// ==========================================
// 2. PAY BAIL
// Existing gameplay rule retained: $100 Clean Cash per initial sentence minute,
// plus 25 Influence for bailing another player.
// ==========================================
router.post('/bail', async (req, res) => {
    let client, transaction = false;
    try {
        const actor = actorId(req);
        const idempotencyKey = requireIdempotencyKey(req);
        const target = integer(req.body?.target_id, {
            field: 'Target player ID', min: 1n, max: 9223372036854775807n
        }).toString();

        client = await pool.connect();
        await client.query('BEGIN');
        transaction = true;
        const locked = await lockPlayers(client, [actor, target]);
        const payer = locked.get(actor);
        const inmate = locked.get(target);

        const idem = await beginIdempotent(
            client, actor, 'jail.bail', idempotencyKey, { target }
        );
        if (idem.replay) {
            await client.query('COMMIT');
            transaction = false;
            return res.status(idem.status).json(idem.response);
        }

        const stillJailed = inmate.jail_expires_at &&
            new Date(inmate.jail_expires_at).getTime() > Date.now();
        if (!stillJailed) throw new ActionError(409, 'This citizen is already free.');

        const initialSeconds = integer(inmate.jail_initial_seconds ?? 0, {
            field: 'Initial sentence', min: 1n, max: 3153600000n
        });
        const initialMinutes = (initialSeconds + 59n) / 60n;
        const bailCost = initialMinutes * 100n;
        const cleanCash = dbInteger(payer.clean_cash);
        if (cleanCash < bailCost) {
            throw new ActionError(409, 'Insufficient Clean Cash for bail.');
        }
        const influenceReward = actor === target ? 0n : 25n;

        const debit = await client.query(
            `UPDATE users
                SET clean_cash = clean_cash - $1::numeric,
                    influence = influence + $2::numeric
              WHERE user_id = $3 AND clean_cash >= $1::numeric
              RETURNING clean_cash, influence`,
            [bailCost.toString(), influenceReward.toString(), actor]
        );
        if (debit.rowCount !== 1) {
            throw new ActionError(409, 'Payer balance changed before bail.');
        }

        const released = await client.query(
            `UPDATE users
                SET jail_expires_at = NULL,
                    jail_initial_seconds = 0,
                    state_reason = NULL
              WHERE user_id = $1 AND jail_expires_at > NOW()
              RETURNING username`,
            [target]
        );
        if (released.rowCount !== 1) {
            throw new ActionError(409, 'Inmate state changed before bail completed.');
        }

        const response = {
            success: true,
            message: actor === target
                ? 'Bail paid. You have been released.'
                : 'Bail paid for ' + released.rows[0].username + '.',
            bail_cost: exactJsonAmount(bailCost),
            influence_gained: exactJsonAmount(influenceReward),
            clean_cash: exactJsonAmount(dbInteger(debit.rows[0].clean_cash)),
            influence: exactJsonAmount(dbInteger(debit.rows[0].influence))
        };
        await completeIdempotent(client, idem, 200, response);
        await client.query('COMMIT');
        transaction = false;
        return res.json(response);
    } catch (err) {
        if (transaction) {
            try { await client.query('ROLLBACK'); }
            catch (rollback) { console.error('Jail bail rollback:', rollback); }
        }
        return sendActionError(res, err, 'Jail bail failed:');
    } finally {
        if (client) client.release();
    }
});

// ==========================================
// 3. BREAKOUT
// Existing placeholder balance rule retained at 40% pending gameplay balancing.
// RNG is now cryptographically sourced and the result is idempotent.
// ==========================================
router.post('/breakout', async (req, res) => {
    let client, transaction = false;
    try {
        const actor = actorId(req);
        const idempotencyKey = requireIdempotencyKey(req);
        const target = integer(req.body?.target_id, {
            field: 'Target player ID', min: 1n, max: 9223372036854775807n
        }).toString();

        client = await pool.connect();
        await client.query('BEGIN');
        transaction = true;
        const locked = await lockPlayers(client, [actor, target]);
        const actorRow = locked.get(actor);
        const inmate = locked.get(target);

        const idem = await beginIdempotent(
            client, actor, 'jail.breakout', idempotencyKey, { target }
        );
        if (idem.replay) {
            await client.query('COMMIT');
            transaction = false;
            return res.status(idem.status).json(idem.response);
        }

        if (dbInteger(actorRow.nerve, { field: 'Nerve' }) < BREAKOUT_NERVE_COST) {
            throw new ActionError(409, 'Not enough Nerve to attempt a breakout.');
        }
        if (!inmate.jail_expires_at ||
            new Date(inmate.jail_expires_at).getTime() <= Date.now()) {
            throw new ActionError(409, 'This citizen is already free.');
        }

        const selfEscape = actor === target;
        if (!selfEscape) {
            const actorIsJailed = actorRow.jail_expires_at &&
                new Date(actorRow.jail_expires_at).getTime() > Date.now();
            if (actorIsJailed) {
                throw new ActionError(
                    409,
                    'Only a free player can attempt to bust another inmate out.'
                );
            }
            const canBustOut = await hasEducationUnlock(client, actor, 'jail_bust_out');
            if (!canBustOut) {
                throw new ActionError(
                    403,
                    'Juris Doctor education is required to bust another inmate out.'
                );
            }
        }

        const success = randomInt(1, 101) <= BREAKOUT_SUCCESS_PERCENT;
        let response;

        if (success) {
            const nerve = await client.query(
                `UPDATE users
                    SET nerve = nerve - $1::numeric
                  WHERE user_id = $2 AND nerve >= $1::numeric
                  RETURNING nerve, heat, jail_expires_at`,
                [BREAKOUT_NERVE_COST.toString(), actor]
            );
            if (nerve.rowCount !== 1) throw new ActionError(409, 'Nerve changed before breakout.');

            const release = await client.query(
                `UPDATE users
                    SET jail_expires_at = NULL,
                        jail_initial_seconds = 0,
                        state_reason = NULL
                  WHERE user_id = $1 AND jail_expires_at > NOW()
                  RETURNING username`,
                [target]
            );
            if (release.rowCount !== 1) {
                throw new ActionError(409, 'Inmate state changed before breakout.');
            }
            response = {
                success: true,
                escaped: selfEscape,
                message: selfEscape
                    ? 'You successfully broke out.'
                    : 'Successfully broke out ' + release.rows[0].username + '.',
                nerve: nerve.rows[0].nerve
            };
        } else {
            const penalty = await client.query(
                `UPDATE users
                    SET nerve = nerve - $1::numeric,
                        heat = LEAST(heat + 20::numeric, 100::numeric),
                        jail_initial_seconds =
                            CASE WHEN jail_expires_at > NOW()
                                 THEN jail_initial_seconds + 3600
                                 ELSE 3600 END,
                        jail_expires_at =
                            CASE WHEN jail_expires_at > NOW()
                                 THEN jail_expires_at + INTERVAL '1 hour'
                                 ELSE NOW() + INTERVAL '1 hour' END,
                        state_reason = 'Caught during a jailbreak attempt.'
                  WHERE user_id = $2 AND nerve >= $1::numeric
                  RETURNING nerve, heat, jail_expires_at, jail_initial_seconds`,
                [BREAKOUT_NERVE_COST.toString(), actor]
            );
            if (penalty.rowCount !== 1) {
                throw new ActionError(409, 'Nerve changed before breakout penalty.');
            }
            response = {
                success: false,
                arrested: !(actorRow.jail_expires_at &&
                    new Date(actorRow.jail_expires_at).getTime() > Date.now()),
                message: selfEscape
                    ? 'Breakout failed. Heat and one hour were added to your sentence.'
                    : 'Breakout failed. You were arrested and penalized.',
                nerve: penalty.rows[0].nerve,
                heat: penalty.rows[0].heat,
                jail_expires_at: penalty.rows[0].jail_expires_at
            };
        }

        await completeIdempotent(client, idem, 200, response);
        await client.query('COMMIT');
        transaction = false;
        return res.json(response);
    } catch (err) {
        if (transaction) {
            try { await client.query('ROLLBACK'); }
            catch (rollback) { console.error('Jail breakout rollback:', rollback); }
        }
        return sendActionError(res, err, 'Jail breakout failed:');
    } finally {
        if (client) client.release();
    }
});

// ==========================================
// 4. PRISON YARD
// ==========================================
router.post('/gym/train', async (req, res) => {
    let client, transaction = false;
    let userId, energySpent;
    try {
        userId = actorId(req);
        const idempotencyKey = requireIdempotencyKey(req);
        energySpent = integer(req.body?.energy_spent, {
            field: 'Energy spent', min: 1n, max: 10000n
        });

        client = await pool.connect();
        await client.query('BEGIN');
        transaction = true;

        const userRes = await client.query(
            `SELECT energy, jail_expires_at
               FROM users
              WHERE user_id = $1
              FOR UPDATE`,
            [userId]
        );
        if (userRes.rowCount !== 1) throw new ActionError(404, 'Player not found.');

        const idem = await beginIdempotent(
            client, userId, 'jail.gym_train', idempotencyKey,
            { energySpent: energySpent.toString() }
        );
        if (idem.replay) {
            await client.query('COMMIT');
            transaction = false;
            return res.status(idem.status).json(idem.response);
        }

        if (!userRes.rows[0].jail_expires_at ||
            new Date(userRes.rows[0].jail_expires_at).getTime() <= Date.now()) {
            throw new ActionError(403, 'Prison-yard training is only available while jailed.');
        }
        if (dbInteger(userRes.rows[0].energy, { field: 'Energy' }) < energySpent) {
            throw new ActionError(409, 'Not enough Energy.');
        }

        const gainRes = await client.query(
            `SELECT ROUND(
                ((((stat_str + stat_def + stat_dex + stat_spd) / 4::numeric)
                    * $1::numeric) + $2::numeric)
                    * $3::numeric / 4::numeric,
                2
             ) AS split_gain
               FROM users
              WHERE user_id = $4`,
            [JAIL_MULTIPLIER, JAIL_FLAT_RATE, energySpent.toString(), userId]
        );
        const splitGain = gainRes.rows[0]?.split_gain;
        if (splitGain === null || splitGain === undefined) {
            throw new Error('Could not calculate prison-yard gain.');
        }
        const expGain = energySpent * 5n;

        const updated = await client.query(
            `UPDATE users
                SET energy = energy - $1::numeric,
                    exp = exp + $2::numeric,
                    stat_str = stat_str + $3::numeric,
                    stat_def = stat_def + $3::numeric,
                    stat_dex = stat_dex + $3::numeric,
                    stat_spd = stat_spd + $3::numeric
              WHERE user_id = $4
                AND energy >= $1::numeric
                AND jail_expires_at > NOW()
              RETURNING *`,
            [energySpent.toString(), expGain.toString(), String(splitGain), userId]
        );
        if (updated.rowCount !== 1) {
            throw new ActionError(409, 'Player state changed before prison-yard training.');
        }

        const response = {
            success: true,
            message: 'Prison-yard training completed.',
            gained_per_stat: String(splitGain),
            user: updated.rows[0]
        };
        await completeIdempotent(client, idem, 200, response);
        await client.query('COMMIT');
        transaction = false;

        trackAndCheckAchievement(userId, 'total_gym_trains', 1, 'user_statistics');
        trackAndCheckAchievement(
            userId, 'total_energy_spent', Number(energySpent), 'user_statistics'
        );
        return res.json(response);
    } catch (err) {
        if (transaction) {
            try { await client.query('ROLLBACK'); }
            catch (rollback) { console.error('Jail gym rollback:', rollback); }
        }
        return sendActionError(res, err, 'Jail gym training failed:');
    } finally {
        if (client) client.release();
    }
});

module.exports = router;
