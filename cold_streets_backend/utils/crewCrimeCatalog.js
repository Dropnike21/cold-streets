const { ActionError } = require('./economyValidation');

const ELIGIBILITY_SQL = `
    c.mechanics_json->>'allow_npc' = 'true'
    AND c.mechanics_json->>'automation_CD' ~ '^[0-9]+$'
    AND (c.mechanics_json->>'automation_CD')::bigint > 0
    AND c.rewards_json->>'min_cash' ~ '^[0-9]+$'
    AND c.rewards_json->>'max_cash' ~ '^[0-9]+$'
    AND (c.rewards_json->>'max_cash')::bigint >=
        (c.rewards_json->>'min_cash')::bigint
    AND (
        (c.rewards_json->>'max_cash')::bigint +
        (c.rewards_json->>'min_cash')::bigint
    ) > 0
    AND (
        (
            (c.rewards_json->>'max_cash')::bigint +
            (c.rewards_json->>'min_cash')::bigint
        ) % 2
    ) = 0
    AND c.penalties_json->>'npc_casualty_risk'
        ~ '^0([.][0-9]+)?$|^1([.]0+)?$'
    AND (c.penalties_json->>'npc_casualty_risk')::numeric
        BETWEEN 0::numeric AND 1::numeric
    AND c.requirements_json->>'time_of_day' = 'Any'
    AND NOT EXISTS (
        SELECT 1
          FROM jsonb_object_keys(COALESCE(c.requirements_json, '{}'::jsonb))
               AS keys(key)
         WHERE keys.key NOT IN ('tool_req', 'time_of_day')
    )
    AND (
        c.requirements_json->>'tool_req' = 'NONE'
        OR (
            c.requirements_json->>'tool_req' ~ '^[0-9]+$'
            AND EXISTS (
                SELECT 1
                  FROM items_master valid_tool
                 WHERE valid_tool.item_id =
                    (c.requirements_json->>'tool_req')::bigint
            )
        )
    )
`;

const SELECT_RULE_SQL = `
    SELECT c.id,
           c.category,
           c.sub_category,
           c.title,
           (c.mechanics_json->>'automation_CD')::bigint AS automation_seconds,
           (c.rewards_json->>'min_cash')::bigint AS min_cash,
           (c.rewards_json->>'max_cash')::bigint AS max_cash,
           (
             (c.rewards_json->>'min_cash')::bigint +
             (c.rewards_json->>'max_cash')::bigint
           ) / 2 AS average_cash,
           ROUND(
             (c.penalties_json->>'npc_casualty_risk')::numeric * 1000000
           )::integer AS casualty_ppm,
           CASE
             WHEN c.requirements_json->>'tool_req' ~ '^[0-9]+$'
             THEN (c.requirements_json->>'tool_req')::bigint
             ELSE NULL
           END AS tool_item_id,
           COALESCE(tool.name, 'NONE') AS tool_name
      FROM crimes_master c
      LEFT JOIN items_master tool
        ON tool.item_id = CASE
             WHEN c.requirements_json->>'tool_req' ~ '^[0-9]+$'
             THEN (c.requirements_json->>'tool_req')::bigint
             ELSE NULL
           END
`;

function normalizeRule(row) {
    const casualtyPpm = Number(row.casualty_ppm);
    if (!Number.isSafeInteger(casualtyPpm) ||
        casualtyPpm < 0 || casualtyPpm > 1000000) {
        throw new Error('Invalid NPC casualty probability in crime catalog.');
    }
    return {
        crimeId: String(row.id),
        category: row.category,
        subCategory: row.sub_category,
        title: row.title,
        automationSeconds: String(row.automation_seconds),
        minCash: String(row.min_cash),
        maxCash: String(row.max_cash),
        averageCash: String(row.average_cash),
        casualtyPpm,
        toolItemId: row.tool_item_id == null ? null : String(row.tool_item_id),
        toolName: row.tool_name
    };
}

async function getCrewCrimeRule(client, { crimeId = null } = {}) {
    if (crimeId === null) {
        throw new Error('Canonical crime ID is required.');
    }

    const result = await client.query(
        SELECT_RULE_SQL + ' WHERE c.id = $1::bigint' +
        ' AND ' + ELIGIBILITY_SQL + ' LIMIT 1',
        [crimeId]
    );
    if (result.rowCount !== 1) {
        throw new ActionError(
            409,
            'This crime is not eligible for crew automation under the recovered catalog.'
        );
    }
    return normalizeRule(result.rows[0]);
}

async function listCrewCrimeRules(client) {
    const result = await client.query(
        SELECT_RULE_SQL +
        ' WHERE ' + ELIGIBILITY_SQL +
        ' ORDER BY c.category ASC, c.sub_category ASC, c.req_skill_level ASC, c.id ASC'
    );
    return result.rows.map(normalizeRule);
}

async function ownsRequiredTool(client, userId, rule, { lock = false } = {}) {
    if (!rule.toolItemId) return true;
    const suffix = lock ? ' FOR UPDATE' : '';
    const result = await client.query(
        `SELECT quantity
           FROM user_inventory
          WHERE user_id = $1 AND item_id = $2::bigint
            AND quantity > 0` + suffix,
        [userId, rule.toolItemId]
    );
    return result.rowCount === 1;
}

module.exports = {
    getCrewCrimeRule,
    listCrewCrimeRules,
    ownsRequiredTool
};
