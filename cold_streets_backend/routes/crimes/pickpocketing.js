const {
    ActionError,
    sendActionError
} = require('../../utils/economyValidation');

async function listTargets(client, res) {
    try {
        const crimes = await client.query(
            `SELECT id, category, sub_category, title, req_skill_level,
                    nerve_cost, mechanics_json
               FROM crimes_master
              WHERE sub_category = 'Pickpocketing'
              ORDER BY id ASC`
        );

        return res.json({
            execution_available: false,
            target_issuance_status: 'server_persistence_required',
            templates: crimes.rows
        });
    } catch (err) {
        return sendActionError(res, err, 'Pickpocket catalog fetch failed:');
    }
}

async function execute(_client, _user, _crime, _req, res) {
    return sendActionError(
        res,
        new ActionError(
            503,
            'Pickpocket execution is paused until target activity is server-issued, persisted, actor-bound, and replay-safe.'
        ),
        'Pickpocket execution blocked:'
    );
}

module.exports = { execute, listTargets };
