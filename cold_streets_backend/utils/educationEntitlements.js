async function hasEducationUnlock(client, userId, unlockKey) {
    if (typeof unlockKey !== 'string' || !/^[a-z0-9_]{1,80}$/.test(unlockKey)) {
        throw new Error('Invalid education unlock key.');
    }
    const result = await client.query(
        `SELECT 1
           FROM user_completed_courses ucc
           JOIN education_courses_master ec ON ec.course_id = ucc.course_id
          WHERE ucc.user_id = $1
            AND COALESCE(ec.rewards_jsonb->'unlocks', '[]'::jsonb) ? $2
          LIMIT 1`,
        [userId, unlockKey]
    );
    return result.rowCount === 1;
}

async function listEducationEntitlements(client, userId) {
    const result = await client.query(
        `SELECT ucc.course_id,
                ec.title,
                COALESCE(ec.rewards_jsonb->'perks', '[]'::jsonb) AS perks,
                COALESCE(ec.rewards_jsonb->'unlocks', '[]'::jsonb) AS unlocks
           FROM user_completed_courses ucc
           JOIN education_courses_master ec ON ec.course_id = ucc.course_id
          WHERE ucc.user_id = $1
            AND (
              jsonb_array_length(COALESCE(ec.rewards_jsonb->'perks', '[]'::jsonb)) > 0
              OR jsonb_array_length(COALESCE(ec.rewards_jsonb->'unlocks', '[]'::jsonb)) > 0
            )
          ORDER BY ucc.completed_at ASC, ucc.course_id ASC`,
        [userId]
    );
    return result.rows;
}

module.exports = { hasEducationUnlock, listEducationEntitlements };
