const { ActionError, integer } = require('./economyValidation');

const RULES = new Map([
    [1, {
        missionId: '3',
        title: 'GET YOUR BEARINGS',
        requirements: { visits: ['vitals', 'assets'] },
        rewards: { dirty_cash: 500 }
    }],
    [2, {
        missionId: '4',
        title: 'KNOW YOUR STASH',
        requirements: { visits: ['inventory', 'properties', 'achievements'] },
        rewards: { dirty_cash: 100, nerve: 50 }
    }],
    [3, {
        missionId: '5',
        title: 'FIRST BLOOD',
        requirements: {
            visits: ['crime_searching', 'crime_shoplifting', 'crime_pickpocketing'],
            successful_crimes: 20
        },
        rewards: { energy: 700 }
    }],
    [4, {
        missionId: '6',
        title: 'IRON AND BLOOD',
        requirements: {
            visits: ['gym'],
            energy_by_stat: { str: 150, def: 150, dex: 150, spd: 150 }
        },
        rewards: { clean_cash: 500 }
    }],
    [5, {
        missionId: '9',
        title: 'FOLLOW THE MONEY',
        requirements: { visits: ['bank', 'real_estate'] },
        rewards: { clean_cash: 1000 }
    }],
    [6, {
        missionId: '10',
        title: 'INTO THE SHADOWS',
        requirements: { visits: ['credit_broker', 'casino'] },
        rewards: { dirty_cash: 2000 }
    }]
]);

const CRIME_VISITS = new Map([
    ['Searching', 'crime_searching'],
    ['Shoplifting', 'crime_shoplifting'],
    ['Pickpocketing', 'crime_pickpocketing']
]);

function stableSerialize(value) {
    if (value === null || typeof value === 'string' ||
        typeof value === 'number' || typeof value === 'boolean') {
        return JSON.stringify(value);
    }
    if (Array.isArray(value)) {
        return '[' + value.map(stableSerialize).join(',') + ']';
    }
    if (value && typeof value === 'object') {
        const keys = Object.keys(value).sort();
        return '{' + keys.map(key =>
            JSON.stringify(key) + ':' + stableSerialize(value[key])
        ).join(',') + '}';
    }
    throw new Error('Unsupported tutorial catalog value.');
}

function anonymousRep(contactExp) {
    const raw = contactExp && typeof contactExp === 'object'
        ? contactExp.anonymous ?? 1
        : 1;
    return Number(integer(raw, {
        field: 'Anonymous reputation', min: 1n, max: 1000000n
    }));
}

function assertReconciledMission(mission, rep) {
    const rule = RULES.get(rep);
    if (!rule) {
        throw new ActionError(
            503,
            'This Anonymous mission is paused pending canonical progression reconciliation.'
        );
    }
    if (!mission ||
        String(mission.id) !== rule.missionId ||
        String(mission.title) !== rule.title ||
        Number(mission.rep_req) !== rep ||
        String(mission.contact_name) !== 'anonymous' ||
        stableSerialize(mission.reqs_json || {}) !== stableSerialize(rule.requirements) ||
        stableSerialize(mission.rewards_json || {}) !== stableSerialize(rule.rewards)) {
        throw new ActionError(
            503,
            'Anonymous mission catalog data changed and requires re-reconciliation.'
        );
    }
    return rule;
}

async function loadCurrentAnonymousMission(client, userId, contactExp = null) {
    let resolvedContactExp = contactExp;
    if (!resolvedContactExp) {
        const player = await client.query(
            'SELECT contact_exp FROM users WHERE user_id = $1',
            [userId]
        );
        if (player.rowCount !== 1) throw new ActionError(404, 'Player not found.');
        resolvedContactExp = player.rows[0].contact_exp;
    }
    const rep = anonymousRep(resolvedContactExp);
    const result = await client.query(
        `SELECT id, contact_name, rep_req, title, message, objective_text,
                reward_text, reqs_json, rewards_json
           FROM missions_master
          WHERE contact_name = 'anonymous' AND rep_req = $1
          LIMIT 2`,
        [rep]
    );
    if (result.rowCount !== 1) {
        throw new ActionError(
            503,
            'Anonymous mission catalog is incomplete or ambiguous for this reputation.'
        );
    }
    const mission = result.rows[0];
    const rule = assertReconciledMission(mission, rep);
    return { rep, mission, rule };
}

async function lockProgress(client, userId, missionId) {
    await client.query(
        `INSERT INTO user_mission_progress
           (user_id, mission_id, status, progress_jsonb)
         VALUES ($1, $2, 'active', '{}'::jsonb)
         ON CONFLICT (user_id, mission_id) DO NOTHING`,
        [userId, missionId]
    );
    const result = await client.query(
        `SELECT status, progress_jsonb, completed_at
           FROM user_mission_progress
          WHERE user_id = $1 AND mission_id = $2
          FOR UPDATE`,
        [userId, missionId]
    );
    if (result.rowCount !== 1) throw new Error('Tutorial progress row could not be resolved.');
    return result.rows[0];
}

function normalizeProgress(progress) {
    if (!progress || typeof progress !== 'object' || Array.isArray(progress)) return {};
    return JSON.parse(JSON.stringify(progress));
}

async function saveProgress(client, userId, missionId, progress) {
    const result = await client.query(
        `UPDATE user_mission_progress
            SET progress_jsonb = $1::jsonb,
                updated_at = NOW()
          WHERE user_id = $2 AND mission_id = $3
            AND status = 'active'
          RETURNING progress_jsonb`,
        [JSON.stringify(progress), userId, missionId]
    );
    if (result.rowCount !== 1) {
        throw new ActionError(409, 'Anonymous mission progress is already completed.');
    }
    return result.rows[0].progress_jsonb;
}

async function recordAnonymousVisit(client, userId, contactExp, visit) {
    if (typeof visit !== 'string' || visit.length < 1 || visit.length > 64) {
        throw new ActionError(400, 'Invalid tutorial visit.');
    }
    const { mission, rule } = await loadCurrentAnonymousMission(client, userId, contactExp);
    const allowed = Array.isArray(rule.requirements.visits)
        ? rule.requirements.visits
        : [];
    if (!allowed.includes(visit)) {
        throw new ActionError(409, 'This visit is not part of the current Anonymous objective.');
    }

    const row = await lockProgress(client, userId, mission.id);
    if (row.status === 'completed') {
        throw new ActionError(409, 'This Anonymous mission is already completed.');
    }
    const progress = normalizeProgress(row.progress_jsonb);
    progress.visits = progress.visits && typeof progress.visits === 'object' &&
        !Array.isArray(progress.visits) ? progress.visits : {};
    progress.visits[visit] = true;
    return saveProgress(client, userId, mission.id, progress);
}

async function recordAnonymousCrimeSuccess(client, userId, subCategory) {
    const visit = CRIME_VISITS.get(String(subCategory));
    if (!visit) return null;

    const player = await client.query(
        'SELECT contact_exp FROM users WHERE user_id = $1',
        [userId]
    );
    if (player.rowCount !== 1 || anonymousRep(player.rows[0].contact_exp) !== 3) {
        return null;
    }

    const { mission, rule } = await loadCurrentAnonymousMission(
        client, userId, player.rows[0].contact_exp
    );
    const row = await lockProgress(client, userId, mission.id);
    if (row.status !== 'active') return row.progress_jsonb;

    const progress = normalizeProgress(row.progress_jsonb);
    progress.visits = progress.visits && typeof progress.visits === 'object' &&
        !Array.isArray(progress.visits) ? progress.visits : {};
    progress.visits[visit] = true;

    const required = integer(rule.requirements.successful_crimes, {
        field: 'Tutorial crime requirement', min: 1n, max: 1000000n
    });
    const current = integer(progress.successful_crimes ?? 0, {
        field: 'Tutorial crime progress', min: 0n, max: 1000000n
    });
    const next = current >= required ? required : current + 1n;
    progress.successful_crimes = Number(next);

    return saveProgress(client, userId, mission.id, progress);
}

async function recordAnonymousGymTraining(client, userId, statType, energySpent) {
    if (!['str', 'def', 'dex', 'spd'].includes(statType)) return null;
    const delta = integer(energySpent, {
        field: 'Tutorial gym Energy', min: 1n, max: 10000n
    });

    const player = await client.query(
        'SELECT contact_exp FROM users WHERE user_id = $1',
        [userId]
    );
    if (player.rowCount !== 1 || anonymousRep(player.rows[0].contact_exp) !== 4) {
        return null;
    }

    const { mission, rule } = await loadCurrentAnonymousMission(
        client, userId, player.rows[0].contact_exp
    );
    const row = await lockProgress(client, userId, mission.id);
    if (row.status !== 'active') return row.progress_jsonb;

    const progress = normalizeProgress(row.progress_jsonb);
    progress.visits = progress.visits && typeof progress.visits === 'object' &&
        !Array.isArray(progress.visits) ? progress.visits : {};
    progress.visits.gym = true;
    progress.energy_by_stat = progress.energy_by_stat &&
        typeof progress.energy_by_stat === 'object' &&
        !Array.isArray(progress.energy_by_stat) ? progress.energy_by_stat : {};

    const required = integer(rule.requirements.energy_by_stat[statType], {
        field: 'Tutorial Energy requirement', min: 1n, max: 1000000n
    });
    const current = integer(progress.energy_by_stat[statType] ?? 0, {
        field: 'Tutorial Energy progress', min: 0n, max: 1000000n
    });
    const next = current >= required
        ? required
        : (current + delta > required ? required : current + delta);
    progress.energy_by_stat[statType] = Number(next);

    return saveProgress(client, userId, mission.id, progress);
}

function assertAnonymousMissionComplete(rule, progressValue) {
    const progress = normalizeProgress(progressValue);
    const visits = progress.visits && typeof progress.visits === 'object'
        ? progress.visits
        : {};

    for (const visit of rule.requirements.visits || []) {
        if (visits[visit] !== true) {
            throw new ActionError(409, 'Anonymous mission objectives are not complete.');
        }
    }

    if (Object.prototype.hasOwnProperty.call(rule.requirements, 'successful_crimes')) {
        const required = integer(rule.requirements.successful_crimes, {
            field: 'Tutorial crime requirement', min: 1n, max: 1000000n
        });
        const done = integer(progress.successful_crimes ?? 0, {
            field: 'Tutorial crime progress', min: 0n, max: 1000000n
        });
        if (done < required) {
            throw new ActionError(409, 'Anonymous mission objectives are not complete.');
        }
    }

    if (rule.requirements.energy_by_stat) {
        const doneByStat = progress.energy_by_stat &&
            typeof progress.energy_by_stat === 'object'
            ? progress.energy_by_stat
            : {};
        for (const stat of ['str', 'def', 'dex', 'spd']) {
            const required = integer(rule.requirements.energy_by_stat[stat], {
                field: 'Tutorial Energy requirement', min: 1n, max: 1000000n
            });
            const done = integer(doneByStat[stat] ?? 0, {
                field: 'Tutorial Energy progress', min: 0n, max: 1000000n
            });
            if (done < required) {
                throw new ActionError(409, 'Anonymous mission objectives are not complete.');
            }
        }
    }
}

function rewardDeltas(rule) {
    const allowed = new Set(['dirty_cash', 'clean_cash', 'energy', 'nerve']);
    for (const key of Object.keys(rule.rewards)) {
        if (!allowed.has(key)) {
            throw new ActionError(503, 'Anonymous mission reward type is not supported.');
        }
    }
    const value = key => integer(rule.rewards[key] ?? 0, {
        field: 'Anonymous mission reward', min: 0n,
        max: 999999999999999999999999n
    });
    return {
        dirtyCash: value('dirty_cash'),
        cleanCash: value('clean_cash'),
        energy: value('energy'),
        nerve: value('nerve')
    };
}

module.exports = {
    anonymousRep,
    assertReconciledMission,
    loadCurrentAnonymousMission,
    lockProgress,
    recordAnonymousVisit,
    recordAnonymousCrimeSuccess,
    recordAnonymousGymTraining,
    assertAnonymousMissionComplete,
    rewardDeltas
};
