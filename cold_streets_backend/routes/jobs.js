const express = require('express');
const { createHash } = require('node:crypto');
const router = express.Router();
// Reject URLs referencing any player other than the verified session owner.
const { requireOwnedPlayerParam } = require('../middleware/playerIdentity');
router.param('user_id', requireOwnedPlayerParam);

const pool = require('../db');
const { ActionError, integer, dbInteger, exactJsonAmount, actorId, sendActionError } = require('../utils/economyValidation');
const { requireIdempotencyKey, beginIdempotent, completeIdempotent } = require('../utils/idempotency');
const { refreshUniqueItemDiscoveryAchievements } = require('../utils/achievement_engine');

// Job-special mappings in the legacy route were not source-authoritative:
// job 1 is Armed Forces (not City Hospital), and item IDs 101/102 are weapons,
// not Bandage/Morphine. Keep rank specials unavailable until a canonical
// mapping is reconstructed. City Hospital revive is implemented separately
// from its recovered mastery definition.
const JOB_SPECIALS = {};

const CLEAN_EXIT_RETENTION_PERCENT = 50;
const HEIST_PAYOUT_PER_RANK = 10000n;
const HEIST_HEAT = 100;
const HEIST_BAN_DAYS = 30n;

// Only source/catalog tuples that completed this reconciliation pass may run.
// The hashes bind the private recovered rule values to the catalog metadata
// without copying the recovered payloads into the public repository.
const RECONCILED_MASTERY_ACTIVE = new Map([
    ['7', {
        kind: 'heat_half',
        fingerprint: '9304208fe524581fe4e4d369db73c0b6adc2aa3a3e1432e24c5a2596939bb5f7'
    }],
    ['9', {
        kind: 'item',
        fingerprint: 'af56a29c2a694eccae4803c3303648fc174aa366ce5c153b9b79e29c28e2dea3'
    }]
]);

function sha256(value) {
    return createHash('sha256').update(value).digest('hex');
}

function catalogInteger(value, field, { min = 1n, max = 9223372036854775807n } = {}) {
    try {
        return integer(value, { field, min, max });
    } catch (_err) {
        return null;
    }
}

function parseMasteryActiveRule(raw) {
    if (typeof raw !== 'string' || raw.length < 1 || raw.length > 4096) return null;

    try {
        const parsed = JSON.parse(raw);
        const active = parsed && typeof parsed === 'object' && !Array.isArray(parsed)
            ? parsed.active : null;
        if (!active || typeof active !== 'object' || Array.isArray(active) ||
            active.cost_type !== 'incentives') {
            return null;
        }
        const cost = catalogInteger(active.cost_val, 'Mastery active cost', { max: 1000000n });
        if (cost === null) return null;

        const activeKeys = Object.keys(active).sort();
        if (activeKeys.join(',') === 'cost_type,cost_val,qty,reward_id') {
            const itemId = catalogInteger(active.reward_id, 'Mastery item ID');
            const qty = catalogInteger(active.qty, 'Mastery item quantity', { max: 1000000n });
            if (itemId === null || qty === null) return null;
            return { kind: 'item', cost, itemId, qty };
        }
        if (activeKeys.join(',') === 'cost_type,cost_val,mult,reward_effect' &&
            active.reward_effect === 'heat_wipe' && active.mult === 0.5) {
            return { kind: 'heat_half', cost, effect: 'heat_wipe', mult: '0.5' };
        }
        return null;
    } catch (_err) {
        // Reconstructed jobs_master currently stores legacy pseudo-JSON text.
        // Parse only the narrow active shapes we understand; never eval it.
    }

    const compact = raw.replace(/\s+/g, ' ').trim();
    if ((compact.match(/\bactive\s*:/g) || []).length !== 1) return null;

    const item = compact.match(
        /active\s*:\s*\{\s*cost_type\s*:\s*incentives\s*,\s*cost_val\s*:\s*([0-9]+)\s*,\s*reward_id\s*:\s*([0-9]+)\s*,\s*qty\s*:\s*([0-9]+)\s*\}/
    );
    if (item) {
        const cost = catalogInteger(item[1], 'Mastery active cost', { max: 1000000n });
        const itemId = catalogInteger(item[2], 'Mastery item ID');
        const qty = catalogInteger(item[3], 'Mastery item quantity', { max: 1000000n });
        if (cost === null || itemId === null || qty === null) return null;
        return { kind: 'item', cost, itemId, qty };
    }

    const heat = compact.match(
        /active\s*:\s*\{\s*cost_type\s*:\s*incentives\s*,\s*cost_val\s*:\s*([0-9]+)\s*,\s*reward_effect\s*:\s*heat_wipe\s*,\s*mult\s*:\s*(0?\.50*)\s*\}/
    );
    if (heat) {
        const cost = catalogInteger(heat[1], 'Mastery active cost', { max: 1000000n });
        if (cost === null || Number(heat[2]) !== 0.5) return null;
        return { kind: 'heat_half', cost, effect: 'heat_wipe', mult: '0.5' };
    }
    return null;
}

// --- 1. GET JOB DASHBOARD (UNIFIED EMPLOYMENT STATUS & DYNAMIC KIOSK DATA) ---
router.get('/:user_id', async (req, res) => {
    try {
        const { user_id } = req.params;

        // 1. Fetch City Job Status
        const userRes = await pool.query('SELECT current_job_id, daily_job_claimed_at FROM users WHERE user_id = $1', [user_id]);
        if (userRes.rows.length === 0) return res.status(404).json({ error: "User not found." });
        const user = userRes.rows[0];

        // 2. Fetch Player Company Status
        const compRes = await pool.query(`
            SELECT ce.company_id, pc.company_name, ce.position_role
            FROM company_employees ce
            JOIN player_companies pc ON ce.company_id = pc.company_id
            WHERE ce.employee_id = $1 AND ce.is_npc = false
        `, [user_id]);

        let privateEmployment = null;
        if (compRes.rows.length > 0) {
            privateEmployment = {
                company_id: compRes.rows[0].company_id,
                company_name: compRes.rows[0].company_name,
                role: compRes.rows[0].position_role
            };
        }

        // 3. Fetch Master Job Data
        const jobsRes = await pool.query('SELECT * FROM jobs_master ORDER BY job_id ASC');
        const ranksRes = await pool.query('SELECT * FROM job_ranks ORDER BY job_id ASC, rank_level ASC');
        const jobDataRes = await pool.query('SELECT * FROM user_job_data WHERE user_id = $1', [user_id]);

        const userJobs = jobDataRes.rows;

        // 4. Map everything together dynamically
        const mappedJobs = jobsRes.rows.map(job => {
            const uData = userJobs.find(uj => uj.job_id === job.job_id);

            // Filter ranks for this specific job
            const jobRanks = ranksRes.rows.filter(r => r.job_id === job.job_id).map(rank => {
                // Attach the hardcoded server special to the dynamic rank data
                const specialData = (JOB_SPECIALS[job.job_id] && JOB_SPECIALS[job.job_id][rank.rank_level])
                    ? JOB_SPECIALS[job.job_id][rank.rank_level]
                    : { name: "None", effect: "No special available.", cost: 0, is_passive: true };

                return {
                    rank_level: rank.rank_level,
                    title: rank.title,
                    daily_pay: rank.daily_pay,
                    daily_incentives: rank.daily_incentives,
                    requirements: {
                        acu: rank.req_acu,
                        ops: rank.req_ops,
                        pre: rank.req_pre,
                        res: rank.req_res
                    },
                    promotion_cost: rank.promotion_incentive_cost,
                    special: specialData
                };
            });

            const mappedRank = uData
                ? dbInteger(uData.current_rank, { field: 'Job rank' })
                : 1n;
            const isCurrent = user.current_job_id === job.job_id;

            return {
                job_id: job.job_id,
                job_name: job.job_name,
                primary_stat: job.primary_stat,
                mastery_passive: job.mastery_passive_desc,
                mastery_active: job.mastery_active_desc,
                is_current: isCurrent,
                current_rank: uData ? uData.current_rank : 1,
                resignation_preview: isCurrent ? {
                    clean_exit_retention_percent: CLEAN_EXIT_RETENTION_PERCENT,
                    heist_payout_dirty_cash:
                        exactJsonAmount(mappedRank * HEIST_PAYOUT_PER_RANK),
                    heist_heat: HEIST_HEAT,
                    heist_ban_days: exactJsonAmount(HEIST_BAN_DAYS)
                } : null,
                incentive_balance: uData ? uData.incentive_balance : 0,
                is_mastered: uData ? uData.is_mastered : false,
                ban_expiry: uData ? uData.ban_expiry : null,
                ranks: jobRanks // <-- NEW: Passes all rank data dynamically
            };
        });

        res.json({
            success: true,
            current_job_id: user.current_job_id,
            last_claimed: user.daily_job_claimed_at,
            private_employment: privateEmployment,
            jobs: mappedJobs
        });
    } catch (err) {
        console.error(err);
        res.status(500).json({ error: "Server error fetching jobs dashboard." });
    }
});

// --- 2. GET INTERVIEW QUESTIONS ---
router.get('/interview/:job_id/:user_id', async (req, res) => {
    let client, transaction = false;
    try {
        const userId = actorId(req);
        const jobId = integer(req.params.job_id, {
            field: 'Job ID',
            min: 1n,
            max: 9223372036854775807n
        }).toString();

        client = await pool.connect();
        await client.query('BEGIN');
        transaction = true;

        // Player lock serializes interview issuance for this actor. A refresh
        // reuses the same live session instead of re-rolling questions.
        const player = await client.query(
            'SELECT current_job_id FROM users WHERE user_id = $1 FOR UPDATE',
            [userId]
        );
        if (player.rowCount !== 1) {
            throw new ActionError(404, 'Player not found.');
        }
        if (player.rows[0].current_job_id !== null) {
            throw new ActionError(
                409,
                'Resign from your current City Job first.'
            );
        }

        const company = await client.query(
            `SELECT position_role
               FROM company_employees
              WHERE employee_id = $1
                AND is_npc = false
              LIMIT 1`,
            [userId]
        );
        if (company.rowCount) {
            throw new ActionError(
                409,
                'Resign from private employment before applying for a City Job.'
            );
        }

        const job = await client.query(
            'SELECT job_id FROM jobs_master WHERE job_id = $1',
            [jobId]
        );
        if (job.rowCount !== 1) {
            throw new ActionError(404, 'Job not found.');
        }

        const ban = await client.query(
            `SELECT (ban_expiry IS NOT NULL AND ban_expiry > NOW()) AS banned
               FROM user_job_data
              WHERE user_id = $1
                AND job_id = $2`,
            [userId, jobId]
        );
        if (ban.rowCount && ban.rows[0].banned === true) {
            throw new ActionError(
                409,
                'You recently failed an interview here. Try again later.'
            );
        }

        const existing = await client.query(
            `SELECT interview_id, question_ids, expires_at
               FROM job_interview_sessions
              WHERE user_id = $1
                AND job_id = $2
                AND consumed_at IS NULL
                AND expires_at > NOW()
              ORDER BY created_at DESC, interview_id DESC
              LIMIT 1
              FOR UPDATE`,
            [userId, jobId]
        );

        if (existing.rowCount === 1) {
            const questionIds = (existing.rows[0].question_ids || [])
                .map(String);
            if (questionIds.length !== 5 ||
                new Set(questionIds).size !== 5) {
                throw new Error(
                    'Persisted interview session has invalid question identity.'
                );
            }

            const questions = await client.query(
                `SELECT question_id, question_text, options_json AS options
                   FROM job_interviews
                  WHERE job_id = $1
                    AND question_id = ANY($2::bigint[])
                  ORDER BY array_position($2::bigint[], question_id)`,
                [jobId, questionIds]
            );
            if (questions.rowCount !== 5) {
                throw new ActionError(
                    503,
                    'Persisted interview questions no longer match the catalog.'
                );
            }

            await client.query('COMMIT');
            transaction = false;
            return res.json({
                success: true,
                interview_id: existing.rows[0].interview_id,
                expires_at: existing.rows[0].expires_at,
                reused_session: true,
                questions: questions.rows
            });
        }

        const questions = await client.query(
            `SELECT question_id, question_text, options_json AS options
               FROM job_interviews
              WHERE job_id = $1
              ORDER BY RANDOM()
              LIMIT 5`,
            [jobId]
        );
        if (questions.rowCount !== 5) {
            throw new ActionError(
                503,
                'Interview catalog is incomplete for this job.'
            );
        }

        const questionIds = questions.rows.map(
            row => String(row.question_id)
        );
        const session = await client.query(
            `INSERT INTO job_interview_sessions (
                user_id, job_id, question_ids
             )
             VALUES ($1, $2, $3::bigint[])
             RETURNING interview_id, expires_at`,
            [userId, jobId, questionIds]
        );
        if (session.rowCount !== 1) {
            throw new Error('Interview session issuance failed.');
        }

        await client.query('COMMIT');
        transaction = false;
        return res.json({
            success: true,
            interview_id: session.rows[0].interview_id,
            expires_at: session.rows[0].expires_at,
            reused_session: false,
            questions: questions.rows
        });
    } catch (err) {
        if (transaction) {
            try { await client.query('ROLLBACK'); }
            catch (rollback) {
                console.error('Interview start rollback:', rollback);
            }
        }
        return sendActionError(res, err, 'Interview start failed:');
    } finally {
        if (client) client.release();
    }
});

// --- 3. SUBMIT INTERVIEW ---

router.post('/interview/submit', async (req, res) => {
    let client, transaction = false;
    try {
        const userId = actorId(req);
        const idempotencyKey = requireIdempotencyKey(req);
        const interviewId = req.body?.interview_id;
        if (typeof interviewId !== 'string' ||
            !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(interviewId)) {
            throw new ActionError(400, 'Invalid interview session.');
        }

        const answers = req.body?.answers;
        if (!Array.isArray(answers) || answers.length !== 5) {
            throw new ActionError(
                400,
                'Exactly five interview answers are required.'
            );
        }

        const normalized = answers.map(answer => ({
            questionId: integer(answer?.question_id, {
                field: 'Question ID',
                min: 1n,
                max: 9223372036854775807n
            }).toString(),
            selectedIndex: Number(answer?.selected_index)
        }));

        if (normalized.some(answer =>
            !Number.isInteger(answer.selectedIndex) ||
            answer.selectedIndex < 0 ||
            answer.selectedIndex > 3)) {
            throw new ActionError(400, 'Invalid interview answer index.');
        }
        if (new Set(normalized.map(answer => answer.questionId)).size !== 5) {
            throw new ActionError(
                400,
                'Interview questions must be answered once each.'
            );
        }

        const canonicalAnswers = [...normalized].sort((a, b) => {
            const aId = BigInt(a.questionId);
            const bId = BigInt(b.questionId);
            return aId < bId ? -1 : aId > bId ? 1 : 0;
        });

        client = await pool.connect();
        await client.query('BEGIN');
        transaction = true;

        // Replay must be resolved before employment/session-state checks,
        // otherwise a successful retry would look already employed/consumed.
        const player = await client.query(
            'SELECT current_job_id FROM users WHERE user_id = $1 FOR UPDATE',
            [userId]
        );
        if (player.rowCount !== 1) {
            throw new ActionError(404, 'Player not found.');
        }

        const idem = await beginIdempotent(
            client,
            userId,
            'jobs.interview_submit',
            idempotencyKey,
            {
                interviewId: interviewId.toLowerCase(),
                answers: canonicalAnswers
            }
        );
        if (idem.replay) {
            await client.query('COMMIT');
            transaction = false;
            return res.status(idem.status).json(idem.response);
        }

        if (player.rows[0].current_job_id !== null) {
            throw new ActionError(
                409,
                'You are already employed in a City Job.'
            );
        }

        const company = await client.query(
            `SELECT 1
               FROM company_employees
              WHERE employee_id = $1
                AND is_npc = false
              LIMIT 1`,
            [userId]
        );
        if (company.rowCount) {
            throw new ActionError(
                409,
                'You are already employed in the private sector.'
            );
        }

        const session = await client.query(
            `SELECT job_id, question_ids
               FROM job_interview_sessions
              WHERE interview_id = $1::uuid
                AND user_id = $2
                AND consumed_at IS NULL
                AND expires_at > NOW()
              FOR UPDATE`,
            [interviewId, userId]
        );
        if (session.rowCount !== 1) {
            throw new ActionError(
                409,
                'Interview session expired or already submitted.'
            );
        }

        const jobId = String(session.rows[0].job_id);
        const issued = new Set(
            (session.rows[0].question_ids || []).map(String)
        );
        if (issued.size !== 5 ||
            normalized.some(answer => !issued.has(answer.questionId))) {
            throw new ActionError(
                400,
                'Answers do not match the issued interview.'
            );
        }

        const questions = await client.query(
            `SELECT question_id, correct_index
               FROM job_interviews
              WHERE job_id = $1
                AND question_id = ANY($2::bigint[])`,
            [jobId, [...issued]]
        );
        if (questions.rowCount !== 5) {
            throw new Error('Interview catalog changed during session.');
        }

        const correct = new Map(
            questions.rows.map(row => [
                String(row.question_id),
                Number(row.correct_index)
            ])
        );
        const correctCount = normalized.reduce(
            (score, answer) =>
                score +
                (correct.get(answer.questionId) === answer.selectedIndex ? 1 : 0),
            0
        );
        const passed = correctCount >= 4;

        const consumed = await client.query(
            `UPDATE job_interview_sessions
                SET consumed_at = NOW()
              WHERE interview_id = $1::uuid
                AND user_id = $2
                AND consumed_at IS NULL
              RETURNING consumed_at`,
            [interviewId, userId]
        );
        if (consumed.rowCount !== 1) {
            throw new ActionError(
                409,
                'Interview session changed before settlement.'
            );
        }

        if (passed) {
            const employed = await client.query(
                `UPDATE users
                    SET current_job_id = $1
                  WHERE user_id = $2
                    AND current_job_id IS NULL
                  RETURNING current_job_id`,
                [jobId, userId]
            );
            if (employed.rowCount !== 1) {
                throw new ActionError(
                    409,
                    'Employment state changed before interview settlement.'
                );
            }

            await client.query(
                `INSERT INTO user_job_data (
                    user_id, job_id, current_rank, ban_expiry
                 )
                 VALUES ($1, $2, 1, NULL)
                 ON CONFLICT (user_id, job_id)
                 DO UPDATE SET ban_expiry = NULL`,
                [userId, jobId]
            );
        } else {
            await client.query(
                `INSERT INTO user_job_data (user_id, job_id, ban_expiry)
                 VALUES ($1, $2, NOW() + INTERVAL '24 hours')
                 ON CONFLICT (user_id, job_id)
                 DO UPDATE SET ban_expiry = NOW() + INTERVAL '24 hours'`,
                [userId, jobId]
            );
        }

        const response = {
            success: true,
            passed,
            score: correctCount,
            message: passed
                ? "Welcome to the team. Don't be late."
                : 'We went with another candidate. Try again in 24 hours.'
        };

        await completeIdempotent(client, idem, 200, response);
        await client.query('COMMIT');
        transaction = false;
        return res.status(200).json(response);
    } catch (err) {
        if (transaction) {
            try { await client.query('ROLLBACK'); }
            catch (rollback) {
                console.error('Interview submit rollback:', rollback);
            }
        }
        return sendActionError(res, err, 'Interview submission failed:');
    } finally {
        if (client) client.release();
    }
});

// --- 4. CLAIM DAILY CITY JOB PAY ---
router.post('/claim-daily', async (req, res) => {
    let client, transaction = false;
    try {
        const userId = actorId(req);
        const idempotencyKey = requireIdempotencyKey(req);

        client = await pool.connect();
        await client.query('BEGIN');
        transaction = true;

        const userRes = await client.query(
            `SELECT current_job_id, daily_job_claimed_at
               FROM users
              WHERE user_id = $1
              FOR UPDATE`,
            [userId]
        );
        if (userRes.rowCount !== 1) throw new ActionError(404, 'Player not found.');
        const jobId = userRes.rows[0].current_job_id;
        if (!jobId) throw new ActionError(409, 'You are not employed in a City Job.');

        const idem = await beginIdempotent(
            client,
            userId,
            'jobs.claim_daily',
            idempotencyKey,
            { jobId: String(jobId) }
        );
        if (idem.replay) {
            await client.query('COMMIT');
            transaction = false;
            return res.status(idem.status).json(idem.response);
        }

        const lastClaimed = userRes.rows[0].daily_job_claimed_at;
        if (lastClaimed) {
            const eligible = await client.query(
                'SELECT ($1::timestamptz <= NOW() - INTERVAL \'24 hours\') AS eligible',
                [lastClaimed]
            );
            if (!eligible.rows[0].eligible) {
                throw new ActionError(409, 'Daily City Job pay is not ready yet.');
            }
        }

        const jobDataRes = await client.query(
            `SELECT current_rank, incentive_balance
               FROM user_job_data
              WHERE user_id = $1 AND job_id = $2
              FOR UPDATE`,
            [userId, jobId]
        );
        if (jobDataRes.rowCount !== 1) throw new Error('Job progress row missing.');
        const rankLevel = Number(jobDataRes.rows[0].current_rank);
        if (!Number.isInteger(rankLevel) || rankLevel < 1 || rankLevel > 5) {
            throw new Error('Invalid City Job rank.');
        }

        const rankRes = await client.query(
            `SELECT daily_pay, daily_incentives
               FROM job_ranks
              WHERE job_id = $1 AND rank_level = $2`,
            [jobId, rankLevel]
        );
        if (rankRes.rowCount !== 1) throw new Error('City Job rank catalog row missing.');

        const pay = dbInteger(rankRes.rows[0].daily_pay, { field: 'Daily City Job pay' });
        const incentives = integer(rankRes.rows[0].daily_incentives, {
            field: 'Daily Job Incentives', min: 0n, max: 1000000n
        });
        if (pay < 0n) throw new Error('City Job catalog contains negative daily pay.');

        const paid = await client.query(
            `UPDATE users
                SET clean_cash = clean_cash + $1::numeric,
                    daily_job_claimed_at = NOW()
              WHERE user_id = $2
                AND current_job_id = $3
                AND (
                    daily_job_claimed_at IS NULL
                    OR daily_job_claimed_at <= NOW() - INTERVAL '24 hours'
                )
              RETURNING clean_cash, daily_job_claimed_at`,
            [pay.toString(), userId, jobId]
        );
        if (paid.rowCount !== 1) {
            throw new ActionError(409, 'Daily City Job pay is not ready or employment changed.');
        }

        const jobData = await client.query(
            `UPDATE user_job_data
                SET incentive_balance = incentive_balance + $1::bigint
              WHERE user_id = $2 AND job_id = $3 AND current_rank = $4
              RETURNING incentive_balance`,
            [incentives.toString(), userId, jobId, rankLevel]
        );
        if (jobData.rowCount !== 1) {
            throw new ActionError(409, 'Job progress changed before daily settlement.');
        }

        const response = {
            success: true,
            message: 'Daily City Job pay collected.',
            clean_cash: exactJsonAmount(dbInteger(paid.rows[0].clean_cash)),
            daily_pay: exactJsonAmount(pay),
            incentives_gained: exactJsonAmount(incentives),
            incentive_balance: jobData.rows[0].incentive_balance,
            claimed_at: paid.rows[0].daily_job_claimed_at
        };
        await completeIdempotent(client, idem, 200, response);
        await client.query('COMMIT');
        transaction = false;
        return res.json(response);
    } catch (err) {
        if (transaction) {
            try { await client.query('ROLLBACK'); }
            catch (rollback) { console.error('Daily job settlement rollback:', rollback); }
        }
        return sendActionError(res, err, 'Daily City Job settlement failed:');
    } finally {
        if (client) client.release();
    }
});

// --- 4. PROMOTE ---

router.post('/promote', async (req, res) => {
    let client, transaction = false;
    try {
        const userId = actorId(req);
        const idempotencyKey = requireIdempotencyKey(req);
        client = await pool.connect();
        await client.query('BEGIN');
        transaction = true;
        const userRes = await client.query(
            `SELECT current_job_id, stat_acu, stat_ops, stat_pre, stat_res
               FROM users WHERE user_id = $1 FOR UPDATE`,
            [userId]
        );
        if (userRes.rowCount !== 1) throw new ActionError(404, 'Player not found.');
        const user = userRes.rows[0];
        if (!user.current_job_id) throw new ActionError(409, 'You are unemployed.');

        const idem = await beginIdempotent(
            client, userId, 'jobs.promote', idempotencyKey,
            { jobId: String(user.current_job_id) }
        );
        if (idem.replay) {
            await client.query('COMMIT');
            transaction = false;
            return res.status(idem.status).json(idem.response);
        }

        const jobDataRes = await client.query(
            `SELECT current_rank, incentive_balance
               FROM user_job_data
              WHERE user_id = $1 AND job_id = $2
              FOR UPDATE`,
            [userId, user.current_job_id]
        );
        if (jobDataRes.rowCount !== 1) throw new Error('Job progress row missing.');
        const jobData = jobDataRes.rows[0];
        if (Number(jobData.current_rank) >= 5) throw new ActionError(409, 'You are already at maximum rank.');

        const nextRankLevel = Number(jobData.current_rank) + 1;
        const rankRes = await client.query(
            `SELECT req_acu, req_ops, req_pre, req_res, promotion_incentive_cost
               FROM job_ranks
              WHERE job_id = $1 AND rank_level = $2`,
            [user.current_job_id, nextRankLevel]
        );
        if (rankRes.rowCount !== 1) throw new Error('Promotion rank catalog row missing.');
        const rank = rankRes.rows[0];
        const requirements = {
            acu: Number(rank.req_acu || 0),
            ops: Number(rank.req_ops || 0),
            pre: Number(rank.req_pre || 0),
            res: Number(rank.req_res || 0)
        };
        const stats = {
            acu: Number(user.stat_acu),
            ops: Number(user.stat_ops),
            pre: Number(user.stat_pre),
            res: Number(user.stat_res)
        };
        if (Object.entries(requirements).some(([key, required]) =>
            !Number.isFinite(required) || !Number.isFinite(stats[key]) || stats[key] < required)) {
            throw new ActionError(409, 'Working Stats do not meet the next rank requirements.');
        }
        const cost = dbInteger(rank.promotion_incentive_cost || 0, { field: 'Promotion cost' });
        const balance = BigInt(jobData.incentive_balance);
        if (balance < cost) throw new ActionError(409, 'Not enough Job Points for promotion.');

        const promoted = await client.query(
            `UPDATE user_job_data
                SET current_rank = current_rank + 1,
                    incentive_balance = incentive_balance - $1::bigint,
                    is_mastered = CASE WHEN current_rank + 1 = 5 THEN true ELSE false END
              WHERE user_id = $2 AND job_id = $3
                AND current_rank = $4 AND incentive_balance >= $1::bigint
              RETURNING current_rank, incentive_balance, is_mastered`,
            [cost.toString(), userId, user.current_job_id, jobData.current_rank]
        );
        if (promoted.rowCount !== 1) throw new ActionError(409, 'Job progress changed before promotion.');

        const response = {
            success: true,
            message: 'Promoted to Rank ' + nextRankLevel + '.',
            current_rank: promoted.rows[0].current_rank,
            incentive_balance: promoted.rows[0].incentive_balance,
            is_mastered: promoted.rows[0].is_mastered
        };
        await completeIdempotent(client, idem, 200, response);
        await client.query('COMMIT');
        transaction = false;
        return res.json(response);
    } catch (err) {
        if (transaction) {
            try { await client.query('ROLLBACK'); } catch (rollback) { console.error('Promotion rollback:', rollback); }
        }
        return sendActionError(res, err, 'Promotion failed:');
    } finally { if (client) client.release(); }
});

// --- 5. RESIGN FROM JOB (CLEAN EXIT VS HEIST) ---

router.post('/quit', async (req, res) => {
    let client, transaction = false;
    try {
        const userId = actorId(req);
        const idempotencyKey = requireIdempotencyKey(req);
        const exitType = req.body?.exit_type;
        if (!['clean', 'heist'].includes(exitType)) throw new ActionError(400, 'Invalid exit strategy.');

        client = await pool.connect();
        await client.query('BEGIN');
        transaction = true;
        const userRes = await client.query(
            'SELECT current_job_id FROM users WHERE user_id = $1 FOR UPDATE', [userId]
        );
        if (userRes.rowCount !== 1) throw new ActionError(404, 'Player not found.');
        const jobId = userRes.rows[0].current_job_id;
        if (!jobId) throw new ActionError(409, 'You are already unemployed.');

        const idem = await beginIdempotent(
            client, userId, 'jobs.quit', idempotencyKey,
            { jobId: String(jobId), exitType }
        );
        if (idem.replay) {
            await client.query('COMMIT');
            transaction = false;
            return res.status(idem.status).json(idem.response);
        }

        const jobDataRes = await client.query(
            `SELECT current_rank, incentive_balance
               FROM user_job_data
              WHERE user_id = $1 AND job_id = $2
              FOR UPDATE`,
            [userId, jobId]
        );
        if (jobDataRes.rowCount !== 1) throw new Error('Job progress row missing.');
        const jobData = jobDataRes.rows[0];
        let response;

        if (exitType === 'clean') {
            await client.query(
                `UPDATE user_job_data
                    SET incentive_balance = FLOOR(incentive_balance / 2)
                  WHERE user_id = $1 AND job_id = $2`,
                [userId, jobId]
            );
            await client.query(
                'UPDATE users SET current_job_id = NULL WHERE user_id = $1',
                [userId]
            );
            response = {
                success: true,
                message: 'Clean exit completed. 50% of Job Points were retained.'
            };
        } else {
            const rank = integer(jobData.current_rank, {
                field: 'Job rank', min: 1n, max: 100n
            });
            const payout = rank * HEIST_PAYOUT_PER_RANK;
            await client.query(
                `UPDATE user_job_data
                    SET incentive_balance = 0,
                        ban_expiry = NOW() +
                            ($3::bigint * INTERVAL '1 day')
                  WHERE user_id = $1 AND job_id = $2`,
                [userId, jobId, HEIST_BAN_DAYS.toString()]
            );
            const wallet = await client.query(
                `UPDATE users
                    SET current_job_id = NULL,
                        dirty_cash = dirty_cash + $1::numeric,
                        heat = $2
                  WHERE user_id = $3
                  RETURNING dirty_cash, heat`,
                [payout.toString(), HEIST_HEAT, userId]
            );
            response = {
                success: true,
                message: 'Heist resignation completed. Maximum heat and 30-day job ban applied.',
                payout: exactJsonAmount(payout),
                dirty_cash: wallet.rows[0].dirty_cash,
                heat: wallet.rows[0].heat,
                ban_days: exactJsonAmount(HEIST_BAN_DAYS)
            };
        }
        await completeIdempotent(client, idem, 200, response);
        await client.query('COMMIT');
        transaction = false;
        return res.json(response);
    } catch (err) {
        if (transaction) {
            try { await client.query('ROLLBACK'); } catch (rollback) { console.error('Job resignation rollback:', rollback); }
        }
        return sendActionError(res, err, 'Job resignation failed:');
    } finally { if (client) client.release(); }
});

// --- 6. CAREER MASTERY ACTIVE ---
router.post('/mastery/activate', async (req, res) => {
    let client, transaction = false;
    try {
        const userId = actorId(req);
        const idempotencyKey = requireIdempotencyKey(req);

        if (!req.body || typeof req.body !== 'object' || Array.isArray(req.body)) {
            throw new ActionError(400, 'A job_id is required.');
        }
        const bodyKeys = Object.keys(req.body);
        if (bodyKeys.some(key => key !== 'job_id')) {
            throw new ActionError(400, 'Mastery activation accepts only job_id.');
        }
        const jobId = integer(req.body.job_id, {
            field: 'Job ID', min: 1n, max: 9223372036854775807n
        }).toString();

        const reconciliation = RECONCILED_MASTERY_ACTIVE.get(jobId);
        if (!reconciliation) {
            throw new ActionError(
                503,
                'This mastery active is paused pending canonical reward reconciliation.'
            );
        }

        client = await pool.connect();
        await client.query('BEGIN');
        transaction = true;

        // Global economic lock order: authenticated player -> idempotency ->
        // job balance -> catalog/reward row.
        const player = await client.query(
            'SELECT current_job_id FROM users WHERE user_id = $1 FOR UPDATE',
            [userId]
        );
        if (player.rowCount !== 1) throw new ActionError(404, 'Player not found.');

        const idem = await beginIdempotent(
            client,
            userId,
            'jobs.mastery_active',
            idempotencyKey,
            { jobId }
        );
        if (idem.replay) {
            await client.query('COMMIT');
            transaction = false;
            return res.status(idem.status).json(idem.response);
        }

        const currentJobId = player.rows[0].current_job_id;
        if (currentJobId === null || String(currentJobId) !== jobId) {
            throw new ActionError(
                409,
                'Rejoin this City Job before spending its frozen Job Incentives.'
            );
        }

        const jobDataRes = await client.query(
            `SELECT current_rank, incentive_balance, is_mastered
               FROM user_job_data
              WHERE user_id = $1 AND job_id = $2
              FOR UPDATE`,
            [userId, jobId]
        );
        if (jobDataRes.rowCount !== 1 ||
            jobDataRes.rows[0].is_mastered !== true ||
            Number(jobDataRes.rows[0].current_rank) !== 5) {
            throw new ActionError(409, 'Career Mastery has not been earned for this job.');
        }

        const masterRes = await client.query(
            `SELECT mastery_logic_json, mastery_active_desc
               FROM jobs_master
              WHERE job_id = $1
              FOR SHARE`,
            [jobId]
        );
        if (masterRes.rowCount !== 1) {
            throw new ActionError(503, 'Mastery rule catalog is unavailable.');
        }

        const active = parseMasteryActiveRule(masterRes.rows[0].mastery_logic_json);
        if (!active || active.kind !== reconciliation.kind) {
            throw new ActionError(503, 'Mastery rule no longer matches its reconciled shape.');
        }

        let fingerprint;
        if (active.kind === 'item') {
            const itemRes = await client.query(
                `SELECT item_id, name, category, sub_category
                   FROM items_master
                  WHERE item_id = $1
                  FOR SHARE`,
                [active.itemId.toString()]
            );
            if (itemRes.rowCount !== 1) {
                throw new ActionError(503, 'Mastery item is missing from the canonical catalog.');
            }
            const item = itemRes.rows[0];
            fingerprint = sha256(
                'job=' + jobId +
                '|logic=' + String(masterRes.rows[0].mastery_logic_json) +
                '|desc=' + String(masterRes.rows[0].mastery_active_desc) +
                '|kind=item' +
                '|cost=' + active.cost.toString() +
                '|item=' + String(item.item_id) +
                '|qty=' + active.qty.toString() +
                '|name=' + String(item.name) +
                '|category=' + String(item.category) +
                '|sub=' + String(item.sub_category)
            );
        } else {
            fingerprint = sha256(
                'job=' + jobId +
                '|logic=' + String(masterRes.rows[0].mastery_logic_json) +
                '|desc=' + String(masterRes.rows[0].mastery_active_desc) +
                '|kind=heat_half' +
                '|cost=' + active.cost.toString() +
                '|effect=' + active.effect +
                '|mult=' + active.mult
            );
        }

        if (fingerprint !== reconciliation.fingerprint) {
            throw new ActionError(
                503,
                'Mastery reward source/catalog data changed and requires re-reconciliation.'
            );
        }

        const balance = dbInteger(jobDataRes.rows[0].incentive_balance, {
            field: 'Job Incentive balance'
        });
        if (balance < active.cost) {
            throw new ActionError(409, 'Not enough Job Incentives for this mastery active.');
        }

        const spent = await client.query(
            `UPDATE user_job_data
                SET incentive_balance = incentive_balance - $1::bigint
              WHERE user_id = $2 AND job_id = $3
                AND current_rank = 5
                AND is_mastered = true
                AND incentive_balance >= $1::bigint
              RETURNING incentive_balance`,
            [active.cost.toString(), userId, jobId]
        );
        if (spent.rowCount !== 1) {
            throw new ActionError(409, 'Mastery balance changed before settlement.');
        }

        let response;
        if (active.kind === 'item') {
            const inventory = await client.query(
                `INSERT INTO user_inventory (user_id, item_id, quantity)
                 VALUES ($1, $2, $3::bigint)
                 ON CONFLICT (user_id, item_id)
                 DO UPDATE SET quantity = user_inventory.quantity + EXCLUDED.quantity
                 RETURNING quantity`,
                [userId, active.itemId.toString(), active.qty.toString()]
            );
            if (inventory.rowCount !== 1) throw new Error('Mastery inventory settlement failed.');

            const uniqueItemsFound = await refreshUniqueItemDiscoveryAchievements(
                client,
                userId
            );

            response = {
                success: true,
                reward_type: 'item',
                item_id: exactJsonAmount(active.itemId),
                quantity_granted: exactJsonAmount(active.qty),
                inventory_quantity: exactJsonAmount(dbInteger(
                    inventory.rows[0].quantity,
                    { field: 'Inventory quantity' }
                )),
                unique_items_found: exactJsonAmount(dbInteger(
                    uniqueItemsFound,
                    { field: 'Unique item discoveries' }
                )),
                incentive_cost: exactJsonAmount(active.cost),
                incentive_balance: exactJsonAmount(dbInteger(
                    spent.rows[0].incentive_balance,
                    { field: 'Job Incentive balance' }
                ))
            };
        } else {
            const heat = await client.query(
                `UPDATE users
                    SET heat = heat / 2
                  WHERE user_id = $1
                  RETURNING heat`,
                [userId]
            );
            if (heat.rowCount !== 1) throw new Error('Mastery Heat settlement failed.');

            response = {
                success: true,
                reward_type: 'heat_reduction',
                heat: heat.rows[0].heat,
                incentive_cost: exactJsonAmount(active.cost),
                incentive_balance: exactJsonAmount(dbInteger(
                    spent.rows[0].incentive_balance,
                    { field: 'Job Incentive balance' }
                ))
            };
        }

        await completeIdempotent(client, idem, 200, response);
        await client.query('COMMIT');
        transaction = false;
        return res.json(response);
    } catch (err) {
        if (transaction) {
            try { await client.query('ROLLBACK'); }
            catch (rollback) { console.error('Mastery activation rollback:', rollback); }
        }
        return sendActionError(res, err, 'Career Mastery activation failed:');
    } finally {
        if (client) client.release();
    }
});

// --- 7. JOB SPECIALS EXCHANGE ---

router.post('/exchange', (_req, res) => {
    // Legacy rank specials referenced the wrong job and item IDs. Re-enable
    // only after the canonical source mapping is reconstructed.
    return res.status(503).json({
        error: 'Job-point exchanges are paused pending canonical special-item mapping.'
    });
});

module.exports = router;