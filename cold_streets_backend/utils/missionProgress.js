// Server-authoritative Kevin contract progress.
// Only gameplay routes call this helper, inside the SAME transaction as the
// successful action. Client-provided progress is never accepted.
const { ActionError, integer } = require('./economyValidation');

async function incrementKevinProgress(client, userId, field, amount = 1) {
    if (!['crimes', 'gym'].includes(field)) throw new Error('Unknown contract progress field.');
    const delta = integer(amount, { field: 'Progress increment', min: 1n, max: 1000000n });
    const result = await client.query(
        `UPDATE users
         SET active_contract = jsonb_set(
             active_contract,
             ARRAY['progress', $2::text],
             to_jsonb(
               LEAST(
                 COALESCE((active_contract #>> ARRAY['progress', $2::text])::bigint, 0) + $3::bigint,
                 COALESCE((active_contract #>> ARRAY['reqs', $2::text])::bigint, 0)
               )
             ),
             true
         )
         WHERE user_id = $1
           AND active_contract IS NOT NULL
           AND active_contract->>'fixer' = 'kevin'
           AND COALESCE((active_contract #>> ARRAY['reqs', $2::text])::bigint, 0) > 0
         RETURNING active_contract`,
        [userId, field, delta.toString()]
    );
    return result.rows[0]?.active_contract || null;
}

function assertKevinContractComplete(contract) {
    if (!contract || contract.fixer !== 'kevin') {
        throw new ActionError(409, 'No active Kevin contract.');
    }
    const reqs = contract.reqs || {};
    const progress = contract.progress || {};
    for (const key of ['crimes', 'gym']) {
        const required = integer(reqs[key] ?? 0, { field: 'Contract requirement', min: 0n, max: 1000000n });
        const done = integer(progress[key] ?? 0, { field: 'Contract progress', min: 0n, max: 1000000n });
        if (done < required) throw new ActionError(409, 'Contract objectives are not complete.');
    }
}

module.exports = { incrementKevinProgress, assertKevinContractComplete };
