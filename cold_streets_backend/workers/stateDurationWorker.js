const pool = require('../db');
const {
    refreshStateDurationAchievements
} = require('../utils/stateDurationTelemetry');

const DEFAULT_POLL_MS = 5000;
const DEFAULT_BATCH_LIMIT = 50;

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
                console.error('State duration rollback failed:', rollback.message);
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

    const poll = async () => {
        if (running) return;
        running = true;
        try {
            await settleDueStateEpisodeBatch(batchLimit);
        } catch (err) {
            console.error('State duration worker error:', err.message);
        } finally {
            running = false;
        }
    };

    const timer = setInterval(poll, pollMs);
    if (typeof timer.unref === 'function') timer.unref();
    return { poll, timer };
}

module.exports = {
    settleOneDueStateEpisode,
    settleDueStateEpisodeBatch,
    startStateDurationWorker
};
