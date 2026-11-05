const { ActionError, dbInteger } = require('./economyValidation');

const STAT_COLUMNS = Object.freeze({
    acu: 'stat_acu',
    ops: 'stat_ops',
    pre: 'stat_pre',
    res: 'stat_res'
});

function statValue(player, statKey) {
    const column = STAT_COLUMNS[statKey];
    if (!column) {
        throw new ActionError(503, 'Company position contains an unsupported Working Stat key.');
    }
    return dbInteger(player[column], { field: 'Player ' + statKey.toUpperCase() });
}

function requirementValue(position, field, label) {
    return dbInteger(position[field], { field: label });
}

function assertPositionEligibility(player, position) {
    const primaryReq = requirementValue(
        position,
        'req_amount_primary',
        'Primary position requirement'
    );
    const secondaryReq = requirementValue(
        position,
        'req_amount_secondary',
        'Secondary position requirement'
    );

    const primaryValue = statValue(player, position.req_stat_primary);
    const secondaryValue = statValue(player, position.req_stat_secondary);

    if (primaryValue < primaryReq || secondaryValue < secondaryReq) {
        throw new ActionError(
            409,
            'Player does not meet the source-backed Working Stat requirements for this position.'
        );
    }

    return {
        primary: {
            stat: position.req_stat_primary,
            required: primaryReq,
            actual: primaryValue
        },
        secondary: {
            stat: position.req_stat_secondary,
            required: secondaryReq,
            actual: secondaryValue
        }
    };
}

module.exports = {
    STAT_COLUMNS,
    assertPositionEligibility
};
