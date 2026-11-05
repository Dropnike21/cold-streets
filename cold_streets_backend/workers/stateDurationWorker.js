const pool = require('../db');
const logger = require('../utils/logger');
const runtimeHealth = require('../utils/runtimeHealth');
const {
    refreshStateDurationAchievements
} = require('../utils/stateDurationTelemetry');

const DEFAULT_POLL_MS = 5000;
const DEFAULT_BATCH_LIMIT = 50;
const WORKER_NAME = 'state_duration';

async function settleOneDueStateEpisode() {
    const client = await pool.connect();
    let transaction = false;
    try {
        await client.query('BEGIN');
        transaction = true;

        const due = await client.query(
            `SELECT episode_id, user_id, state_type, scheduled_end_at
               FROM user_state_episodes
              WHERE ended_at IS NULL
                AND scheduled_end_at <= NOW()
              ORDER BY scheduled_end_at ASC, episode_id ASC
              FOR UPDATE SKIP LOCKED
              LIMIT 1`
        );

        if (due.rowCount === 0) {
            await client.query('COMMIT');
            transaction = false;
            return false;
        }

        const episode = due.rows[0];
        const closed = await client.query(
            `UPDATE user_state_episodes
                SET ended_at = scheduled_end_at,
                    end_reason = 'expired'
              WHERE episode_id = $1
                AND ended_at IS NULL
              RETURNING episode_id`,
            [episode.episode_id]
        );
        if (closed.rowCount !== 1) {
            throw new Error('Due state episode changed before settlement.');
        }

        await refreshStateDurationAchievements(client, episode.user_id);

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

async function settleDueStateEpisodeBatch(limit = DEFAULT_BATCH_LIMIT) {
    let settled = 0;
    while (settled < limit) {
        const found = await settleOneDueStateEpisode();
        if (!found) break;
        settled += 1;
    }
    return settled;
}

function startStateDurationWorker({
    pollMs = DEFAULT_POLL_MS,
    batchLimit = DEFAULT_BATCH_LIMIT
} = {}) {
    let running = false;
    let stopping = false;
    runtimeHealth.markWorkerStarted(WORKER_NAME);

    const poll = async () => {
        if (running || stopping) return;
        running = true;
        try {
            let settled = 0;
            while (!stopping && settled < batchLimit) {
                const found = await settleOneDueStateEpisode();
                if (!found) break;
                settled += 1;
            }
            if (!stopping) {
                runtimeHealth.markWorkerPollSuccess(WORKER_NAME, settled);
                if (settled > 0) {
                    logger.info('worker_batch_settled', {
                        worker: WORKER_NAME,
                        settled_count: settled
                    });
                }
            }
        } catch (err) {
            if (!stopping) {
                runtimeHealth.markWorkerPollFailure(WORKER_NAME);
                logger.error('worker_poll_failed', {
                    worker: WORKER_NAME,
                    ...logger.errorFields(err)
                });
            }
        } finally {
            running = false;
        }
    };

    const timer = setInterval(poll, pollMs);
    if (typeof timer.unref === 'function') timer.unref();

    const stop = () => {
        if (stopping) return;
        stopping = true;
        clearInterval(timer);
        runtimeHealth.markWorkerStopped(WORKER_NAME);
    };

    return { name: WORKER_NAME, poll, timer, stop };
}

module.exports = {
    settleOneDueStateEpisode,
    settleDueStateEpisodeBatch,
    startStateDurationWorker
};
