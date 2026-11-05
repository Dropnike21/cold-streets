const { ActionError } = require('./economyValidation');

// Historical helper intentionally fail-closed.
//
// Legacy Casino child engines previously used this function to debit a hybrid
// of Casino Tokens plus Dirty/Clean Cash. That denomination model is not
// source-reconciled. New Casino settlement code must use the canonical token
// ledger helpers once exact game rules are established.
async function chargeWager() {
    throw new ActionError(
        503,
        'Legacy Casino wager settlement is retired pending source-reconciled denomination and paytable rules.'
    );
}

module.exports = { chargeWager };
