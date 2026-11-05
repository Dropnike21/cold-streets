const { randomInt } = require('node:crypto');
const pool = require('../db');
const logger = require('../utils/logger');
const runtimeHealth = require('../utils/runtimeHealth');
const {
    getCrewCrimeRule,
    ownsRequiredTool
} = require('../utils/crewCrimeCatalog');

const CREW_STATS = ['str', 'def', 'dex', 'spd', 'acu', 'ops', 'pre', 'res'];
const CASUALTY_SCALE = 1000000;
const DEFAULT_POLL_MS = 5000;
const DEFAULT_BATCH_LIMIT = 50;
const WORKER_NAME = 'crew_crime';

function chooseTwoDistinctStats() {
    const first = randomInt(0, CREW_STATS.length);
    let second = randomInt(0, CREW_STATS.length - 1);
    if (second >= first) second += 1;
    return [CREW_STATS[first], CREW_STATS[second]];
}

async function pauseInvalidAssignment(client, crew, reason) {
    await client.query(
        `DELETE FROM crew_crime_assignments WHERE crew_id = $1`,
        [crew.crew_id]
    );
    await client.query(
        `UPDATE user_crew
            SET assignment = 'UNASSIGNED',
                current_domain = 'IDLE'
          WHERE crew_id = $1 AND user_id = $2`,
        [crew.crew_id, crew.user_id]
    );
    await client.query(
        `INSERT INTO user_events (user_id, event_text, event_type)
         VALUES ($1, $2, 'crew_automation_paused')`,
        [
            crew.user_id,
            crew.npc_name + ' was recalled from crime automation: ' + reason
        ]
    );
}

async function settleOneDueCrewCrime() {
    const client = await pool.connect();
    let transaction = false;
    try {
        await client.query('BEGIN');
        transaction = true;

        const due = await client.query(
            `SELECT crew_id, crime_id, next_tick_at
               FROM crew_crime_assignments
              WHERE next_tick_at <= NOW()
              ORDER BY next_tick_at ASC, crew_id ASC
              FOR UPDATE SKIP LOCKED
              LIMIT 1`
        );
        if (due.rowCount === 0) {
            await client.query('COMMIT');
            transaction = false;
            return false;
        }

        const schedule = due.rows[0];
        const crewRes = await client.query(
            `SELECT crew_id, user_id, npc_name, assignment, current_domain,
                    cur_str, max_str, cur_def, max_def, cur_dex, max_dex,
                    cur_spd, max_spd, cur_acu, max_acu, cur_ops, max_ops,
                    cur_pre, max_pre, cur_res, max_res
               FROM user_crew
              WHERE crew_id = $1
              FOR UPDATE`,
            [schedule.crew_id]
        );
        if (crewRes.rowCount !== 1) {
            await client.query(
                'DELETE FROM crew_crime_assignments WHERE crew_id = $1',
                [schedule.crew_id]
            );
            await client.query('COMMIT');
            transaction = false;
            return true;
        }
        const crew = crewRes.rows[0];

        const userRes = await client.query(
            'SELECT dirty_cash FROM users WHERE user_id = $1 FOR UPDATE',
            [crew.user_id]
        );
        if (userRes.rowCount !== 1) {
            throw new Error('Crew owner is missing.');
        }

        let rule;
        try {
            rule = await getCrewCrimeRule(client, {
                crimeId: String(schedule.crime_id)
            });
        } catch (err) {
            if (err && err.status === 409) {
                await pauseInvalidAssignment(
                    client,
                    crew,
                    'the current crime catalog no longer has complete automation semantics.'
                );
                await client.query('COMMIT');
                transaction = false;
                return true;
            }
            throw err;
        }

        if (crew.current_domain !== 'CRIMES' || crew.assignment !== rule.title) {
            if (crew.current_domain === 'CRIMES') {
                await pauseInvalidAssignment(
                    client,
                    crew,
                    'the persisted schedule no longer matches the crew assignment.'
                );
            } else {
                await client.query(
                    'DELETE FROM crew_crime_assignments WHERE crew_id = $1',
                    [crew.crew_id]
                );
            }
            await client.query('COMMIT');
            transaction = false;
            return true;
        }

        const hasTool = await ownsRequiredTool(
            client,
            String(crew.user_id),
            rule,
            { lock: true }
        );
        if (!hasTool) {
            await client.query(
                `UPDATE crew_crime_assignments
                    SET next_tick_at = NOW() +
                            ($1::bigint * INTERVAL '1 second'),
                        updated_at = NOW()
                  WHERE crew_id = $2`,
                [rule.automationSeconds, crew.crew_id]
            );
            await client.query('COMMIT');
            transaction = false;
            return true;
        }

        const casualty = rule.casualtyPpm > 0 &&
            randomInt(0, CASUALTY_SCALE) < rule.casualtyPpm;
        if (casualty) {
            await client.query(
                `INSERT INTO user_events (user_id, event_text, event_type)
                 VALUES ($1, $2, 'crew_casualty')`,
                [
                    crew.user_id,
                    crew.npc_name + ' was permanently lost while automating ' +
                        rule.title + '.'
                ]
            );
            // ON DELETE CASCADE removes the persisted schedule in the same
            // transaction. A fatal loop is not a successful loop, so it pays
            // no cash and grants no stat growth.
            await client.query(
                'DELETE FROM user_crew WHERE crew_id = $1 AND user_id = $2',
                [crew.crew_id, crew.user_id]
            );
            await client.query('COMMIT');
            transaction = false;
            return true;
        }

        const [statA, statB] = chooseTwoDistinctStats();
        await client.query(
            `UPDATE user_crew
                SET cur_${statA} = LEAST(cur_${statA} + 1, max_${statA}),
                    cur_${statB} = LEAST(cur_${statB} + 1, max_${statB})
              WHERE crew_id = $1 AND user_id = $2`,
            [crew.crew_id, crew.user_id]
        );

        await client.query(
            `UPDATE users
                SET dirty_cash = dirty_cash + $1::numeric
              WHERE user_id = $2`,
            [rule.averageCash, crew.user_id]
        );

        await client.query(
            `UPDATE crew_crime_assignments
                SET last_tick_at = NOW(),
                    next_tick_at = NOW() +
                        ($1::bigint * INTERVAL '1 second'),
                    updated_at = NOW()
              WHERE crew_id = $2`,
            [rule.automationSeconds, crew.crew_id]
        );

        await client.query('COMMIT');
        transaction = false;
        return true;
    } catch (err) {
        if (transaction) {
            try { await client.query('ROLLBACK'); }
            catch (rollback) {
                logger.error('worker_rollback_failed', {
                    worker: WORKER_NAME,
                    ...logger.errorFields(rollback)
                });
            }
        }
        throw err;
    } finally {
        client.release();
    }
}

async function settleDueCrewCrimeBatch(limit = DEFAULT_BATCH_LIMIT) {
    let settled = 0;
    while (settled < limit) {
        const found = await settleOneDueCrewCrime();
        if (!found) break;
        settled += 1;
    }
    return settled;
}

function startCrewCrimeWorker({
    pollMs = DEFAULT_POLL_MS,
    batchLimit = DEFAULT_BATCH_LIMIT
} = {}) {
    let running = false;
    runtimeHealth.markWorkerStarted(WORKER_NAME);

    const poll = async () => {
        if (running) return;
        running = true;
        try {
            const settled = await settleDueCrewCrimeBatch(batchLimit);
            runtimeHealth.markWorkerPollSuccess(WORKER_NAME, settled);
            if (settled > 0) {
                logger.info('worker_batch_settled', {
                    worker: WORKER_NAME,
                    settled_count: settled
                });
            }
        } catch (err) {
            runtimeHealth.markWorkerPollFailure(WORKER_NAME);
            logger.error('worker_poll_failed', {
                worker: WORKER_NAME,
                ...logger.errorFields(err)
            });
        } finally {
            running = false;
        }
    };

    const timer = setInterval(poll, pollMs);
    if (typeof timer.unref === 'function') timer.unref();
    return { name: WORKER_NAME, poll, timer };
}

module.exports = {
    settleOneDueCrewCrime,
    settleDueCrewCrimeBatch,
    startCrewCrimeWorker
};
