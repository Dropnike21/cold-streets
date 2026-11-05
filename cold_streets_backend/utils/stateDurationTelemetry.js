const { ActionError } = require('./economyValidation');
const { unlockAchievementsForValue } = require('./achievement_engine');

const VALID_STATES = new Set(['jail', 'hospital']);

function requireState(value) {
    if (!VALID_STATES.has(value)) {
        throw new Error('Unsupported player state telemetry type.');
    }
    return value;
}

function requireSource(value, field) {
    if (typeof value !== 'string' || value.trim() === '') {
        throw new Error(field + ' must be a non-empty server value.');
    }
    return value.trim();
}

async function beginStateEpisode(client, {
    userId,
    stateType,
    scheduledEndAt,
    sourceType,
    sourceRef
}) {
    const state = requireState(stateType);
    const source = requireSource(sourceType, 'State source type');
    const ref = requireSource(String(sourceRef ?? ''), 'State source reference');

    const existing = await client.query(
        `SELECT episode_id, state_type, scheduled_end_at
           FROM user_state_episodes
          WHERE user_id = $1
            AND ended_at IS NULL
          FOR UPDATE`,
        [userId]
    );

    if (existing.rowCount > 1) {
        throw new Error('Multiple open state episodes violate telemetry integrity.');
    }

    if (existing.rowCount === 1) {
        const closed = await client.query(
            `UPDATE user_state_episodes
                SET ended_at = scheduled_end_at,
                    end_reason = 'expired'
              WHERE episode_id = $1
                AND ended_at IS NULL
                AND scheduled_end_at <= NOW()
              RETURNING episode_id`,
            [existing.rows[0].episode_id]
        );
        if (closed.rowCount !== 1) {
            throw new ActionError(
                409,
                'A live player-state episode already exists; refusing to overwrite telemetry.'
            );
        }
    }

    const future = await client.query(
        'SELECT $1::timestamptz > NOW() AS valid',
        [scheduledEndAt]
    );
    if (future.rows[0]?.valid !== true) {
        throw new ActionError(
            409,
            'Player-state admission expiry must be in the future.'
        );
    }

    const inserted = await client.query(
        `INSERT INTO user_state_episodes (
            user_id, state_type, started_at, scheduled_end_at,
            source_type, source_ref
         )
         VALUES ($1, $2, NOW(), $3::timestamptz, $4, $5)
         RETURNING episode_id, state_type, started_at, scheduled_end_at`,
        [userId, state, scheduledEndAt, source, ref]
    );
    if (inserted.rowCount !== 1) {
        throw new Error('Player-state episode could not be recorded.');
    }
    return inserted.rows[0];
}

async function endStateEpisode(client, {
    userId,
    stateType,
    endReason
}) {
    const state = requireState(stateType);
    const reason = requireSource(endReason, 'State end reason');

    const open = await client.query(
        `SELECT episode_id, scheduled_end_at
           FROM user_state_episodes
          WHERE user_id = $1
            AND state_type = $2
            AND ended_at IS NULL
          FOR UPDATE`,
        [userId, state]
    );
    if (open.rowCount !== 1) {
        throw new ActionError(
            409,
            'Player-state telemetry does not match the active state.'
        );
    }

    const ended = await client.query(
        `UPDATE user_state_episodes
            SET ended_at = LEAST(NOW(), scheduled_end_at),
                end_reason = $2
          WHERE episode_id = $1
            AND ended_at IS NULL
          RETURNING episode_id, ended_at, end_reason`,
        [open.rows[0].episode_id, reason]
    );
    if (ended.rowCount !== 1) {
        throw new Error('Player-state episode changed before release.');
    }
    return ended.rows[0];
}

async function getStateDurationProgress(client, userId) {
    const result = await client.query(
        `SELECT
            FLOOR(
              COALESCE(SUM(
                CASE WHEN state_type = 'jail' THEN
                  GREATEST(
                    EXTRACT(EPOCH FROM (
                      LEAST(COALESCE(ended_at, NOW()), scheduled_end_at)
                      - started_at
                    )),
                    0
                  )
                ELSE 0 END
              ), 0) / 86400
            )::bigint AS days_in_jail,
            FLOOR(
              COALESCE(SUM(
                CASE WHEN state_type = 'hospital' THEN
                  GREATEST(
                    EXTRACT(EPOCH FROM (
                      LEAST(COALESCE(ended_at, NOW()), scheduled_end_at)
                      - started_at
                    )),
                    0
                  )
                ELSE 0 END
              ), 0) / 3600
            )::bigint AS hospital_hours
           FROM user_state_episodes
          WHERE user_id = $1`,
        [userId]
    );

    return {
        days_in_jail: result.rows[0]?.days_in_jail ?? '0',
        hospital_hours: result.rows[0]?.hospital_hours ?? '0'
    };
}

async function refreshStateDurationAchievements(client, userId) {
    const progress = await getStateDurationProgress(client, userId);
    await unlockAchievementsForValue(
        client, userId, 'days_in_jail', progress.days_in_jail
    );
    await unlockAchievementsForValue(
        client, userId, 'hospital_hours', progress.hospital_hours
    );
    return progress;
}

module.exports = {
    beginStateEpisode,
    endStateEpisode,
    getStateDurationProgress,
    refreshStateDurationAchievements
};
