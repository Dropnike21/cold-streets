const { createHash } = require('node:crypto');
const { ActionError, integer, dbInteger } = require('./economyValidation');

// Source-backed catalog keys. These are logical achievement trackers, not SQL
// column names. Keep the mapping explicit so catalog strings can never become
// dynamic SQL identifiers.
const TRACKER_FINGERPRINTS = Object.freeze({
    gym_trains: '8ee92e728cedc162e62bd7feb8d2f6f1',
    crimes_successful: '01b96511878f1afa4f88591ee99364e7',
    player_level: '333212151aba8634b4672f695298b121',
    courses_completed: 'b057568304caf960a3f75c6f84cc963e',
    unique_items_found: '453804215f82daa77f8d8a003adf8842'
});

const SUPPORTED_TRACKERS = Object.freeze(Object.keys(TRACKER_FINGERPRINTS));

function exactProgress(value, field) {
    if (typeof value === 'bigint') return value;
    return integer(value, {
        field,
        min: 0n,
        max: 999999999999999999999999n
    });
}

function catalogFingerprint(rows) {
    const serialized = rows.map(row => [
        row.achievement_id,
        row.title,
        row.description,
        row.category,
        row.stat_tracker,
        row.threshold_value,
        row.rarity
    ].map(value => String(value ?? '')).join('|')).join('\n');
    return createHash('md5').update(serialized).digest('hex');
}

async function loadTrackerCatalog(client, trackerKey) {
    if (!Object.prototype.hasOwnProperty.call(TRACKER_FINGERPRINTS, trackerKey)) {
        throw new ActionError(
            503,
            'This achievement tracker is not yet backed by authoritative server telemetry.'
        );
    }

    const result = await client.query(
        `SELECT achievement_id, title, description, category, stat_tracker,
                threshold_value, rarity
           FROM achievements_master
          WHERE stat_tracker = $1
          ORDER BY achievement_id`,
        [trackerKey]
    );

    if (result.rowCount !== 25 ||
        catalogFingerprint(result.rows) !== TRACKER_FINGERPRINTS[trackerKey]) {
        throw new ActionError(
            503,
            'Achievement catalog data changed and requires re-reconciliation.'
        );
    }
    return result.rows;
}

async function unlockAchievementsForValue(client, userId, trackerKey, currentValue) {
    const current = exactProgress(currentValue, 'Achievement progress');
    const catalog = await loadTrackerCatalog(client, trackerKey);
    const unlocked = [];

    for (const achievement of catalog) {
        const threshold = dbInteger(
            achievement.threshold_value,
            { field: 'Achievement threshold' }
        );
        if (threshold < 1n) {
            throw new Error('Achievement threshold must be positive.');
        }
        if (threshold > current) break;

        const inserted = await client.query(
            `INSERT INTO user_achievements (user_id, achievement_id)
             VALUES ($1, $2)
             ON CONFLICT (user_id, achievement_id) DO NOTHING
             RETURNING achievement_id, unlocked_at`,
            [userId, achievement.achievement_id]
        );
        if (inserted.rowCount !== 1) continue;

        await client.query(
            'INSERT INTO user_events (user_id, event_text) VALUES ($1, $2)',
            [userId, `Achievement Unlocked: ${achievement.title}.`]
        );
        unlocked.push({
            achievement_id: achievement.achievement_id,
            title: achievement.title,
            unlocked_at: inserted.rows[0].unlocked_at
        });
    }

    return unlocked;
}

async function recordGymTrainingAchievement(client, userId, energySpent) {
    const energy = exactProgress(energySpent, 'Gym Energy spent');
    if (energy < 1n) throw new Error('Successful Gym training must spend Energy.');

    const totals = await client.query(
        `INSERT INTO user_statistics
           (user_id, total_gym_trains, total_energy_spent)
         VALUES ($1, 1, $2::bigint)
         ON CONFLICT (user_id)
         DO UPDATE SET
           total_gym_trains = user_statistics.total_gym_trains + 1,
           total_energy_spent = user_statistics.total_energy_spent + $2::bigint
         RETURNING total_gym_trains, total_energy_spent`,
        [userId, energy.toString()]
    );
    if (totals.rowCount !== 1) {
        throw new Error('Gym achievement telemetry could not be persisted.');
    }

    await unlockAchievementsForValue(
        client,
        userId,
        'gym_trains',
        totals.rows[0].total_gym_trains
    );
    return totals.rows[0];
}

async function refreshUniqueItemDiscoveryAchievements(client, userId) {
    const total = await client.query(
        `SELECT COUNT(*)::bigint AS total
           FROM user_item_discoveries
          WHERE user_id = $1`,
        [userId]
    );
    if (total.rowCount !== 1) {
        throw new Error('Unique item discovery telemetry could not be resolved.');
    }

    await unlockAchievementsForValue(
        client,
        userId,
        'unique_items_found',
        total.rows[0].total
    );
    return total.rows[0].total;
}

module.exports = {
    SUPPORTED_TRACKERS,
    unlockAchievementsForValue,
    recordGymTrainingAchievement,
    refreshUniqueItemDiscoveryAchievements
};
