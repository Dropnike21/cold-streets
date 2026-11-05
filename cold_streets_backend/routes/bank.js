const express = require('express');
const router = express.Router();
const db = require('../db');

const { requireOwnedPlayerParam } = require('../middleware/playerIdentity');
const {
    ActionError,
    dbInteger,
    exactJsonAmount,
    actorId,
    sendActionError
} = require('../utils/economyValidation');

router.param('userId', requireOwnedPlayerParam);

const BANK_BLOCKERS = Object.freeze([
    'time_deposit_terms_not_master_data',
    'dirty_cash_to_clean_cash_conversion_conflict',
    'bank_trust_progression_unresolved',
    'bank_interest_perk_stacking_unresolved',
    'pending_check_issuer_contract_unresolved',
    'pending_check_expiry_settlement_unrecovered'
]);

function exactDbAmount(value, field) {
    return exactJsonAmount(dbInteger(value, { field }));
}

function pausedBankMutation(req, res, action) {
    try {
        actorId(req);
        throw new ActionError(
            503,
            'Bank ' + action + ' is paused until deposit, conversion, and settlement semantics are reconciled.'
        );
    } catch (error) {
        return sendActionError(res, error, 'Bank ' + action + ' failed:');
    }
}

// Time-deposit creation is intentionally paused.
//
// Historical implementation facts are preserved in docs, but they are not
// treated as canonical gameplay rules:
// - 7/14/30/90/180 day terms;
// - 0.5/1.1/2.5/9/22 percent rates;
// - 2B cap;
// - bank-trust duration gating;
// - Dirty Cash drained before Clean Cash;
// - all matured principal + interest paid to Clean Cash.
//
// The last two points make the Bank a laundering path, which conflicts with
// the GDD assigning laundering to player businesses/fronts.
router.post('/deposit', (req, res) =>
    pausedBankMutation(req, res, 'time-deposit creation')
);

// Existing/recovered deposit records are not settled automatically while the
// payout denomination and legacy Dirty->Clean conversion remain disputed.
// This avoids minting or laundering value from a rule that exists only in code.
router.post('/claim-deposit', (req, res) =>
    pausedBankMutation(req, res, 'time-deposit settlement')
);

// pending_checks are treated as a generic deferred-payout instrument issued
// by other authoritative systems (for example future Casino lottery/jackpot,
// auction/trade settlement, or reward flows), not as Bank-created money.
// No issuer contract currently defines currency, unique source reference,
// expiry, or fallback settlement, so claims remain paused.
router.post('/claim-check', (req, res) =>
    pausedBankMutation(req, res, 'pending-check settlement')
);

// Read-only bank state. This exposes recovered financial rows without implying
// that their terms are currently executable.
router.get('/status/:userId', async (req, res) => {
    try {
        const userId = actorId(req);

        const [accountRes, depositRes, checksRes] = await Promise.all([
            db.query(
                'SELECT bank_trust_level, dirty_cash, clean_cash FROM users WHERE user_id = $1',
                [userId]
            ),
            db.query(
                `SELECT deposit_id,
                        dirty_deposited,
                        clean_deposited,
                        total_payout,
                        duration_index,
                        created_at,
                        unlocks_at,
                        status,
                        (unlocks_at <= NOW()) AS timestamp_matured
                   FROM time_deposits
                  WHERE user_id = $1
                  ORDER BY created_at DESC, deposit_id DESC`,
                [userId]
            ),
            db.query(
                `SELECT id,
                        source,
                        amount,
                        created_at,
                        expires_at,
                        status,
                        (expires_at <= NOW()) AS timestamp_expired
                   FROM pending_checks
                  WHERE user_id = $1
                  ORDER BY created_at DESC, id DESC`,
                [userId]
            )
        ]);

        if (accountRes.rowCount !== 1) {
            throw new ActionError(404, 'Player not found.');
        }

        const account = accountRes.rows[0];

        const deposits = depositRes.rows.map(row => ({
            deposit_id: row.deposit_id,
            dirty_deposited: exactDbAmount(
                row.dirty_deposited,
                'Recorded Dirty Cash deposit'
            ),
            clean_deposited: exactDbAmount(
                row.clean_deposited,
                'Recorded Clean Cash deposit'
            ),
            total_payout_recorded: exactDbAmount(
                row.total_payout,
                'Recorded time-deposit payout'
            ),
            duration_index_recorded: row.duration_index,
            created_at: row.created_at,
            unlocks_at: row.unlocks_at,
            status: row.status,
            timestamp_matured: row.timestamp_matured === true,
            settlement_available: false,
            settlement_status: 'paused_semantics_unresolved'
        }));

        const checks = checksRes.rows.map(row => ({
            id: row.id,
            source: row.source,
            amount_recorded: exactDbAmount(
                row.amount,
                'Recorded pending-check amount'
            ),
            created_at: row.created_at,
            expires_at: row.expires_at,
            status: row.status,
            timestamp_expired: row.timestamp_expired === true,
            claim_available: false,
            settlement_status: 'paused_issuer_contract_unresolved'
        }));

        return res.json({
            success: true,
            bank_status: 'read_only_reconciliation',
            time_deposit_creation_available: false,
            time_deposit_claim_available: false,
            pending_check_claim_available: false,
            pending_check_role: 'external_deferred_payout',
            bank_trust_progression_status: 'unresolved',
            time_deposit_terms_status: 'historical_code_only',
            payout_currency_status: 'unresolved',
            dirty_to_clean_conversion_status: 'conflicts_with_gdd_laundering_model',
            pending_check_creation_status: 'external_issuer_contract_unimplemented',
            pending_check_expiry_status: 'auto_liquidation_unrecovered',
            blockers: BANK_BLOCKERS,
            account: {
                bank_trust_level_recorded: exactDbAmount(
                    account.bank_trust_level,
                    'Bank trust level'
                ),
                dirty_cash: exactDbAmount(account.dirty_cash, 'Dirty Cash'),
                clean_cash: exactDbAmount(account.clean_cash, 'Clean Cash')
            },
            recorded_time_deposits: deposits,
            recorded_pending_checks: checks
        });
    } catch (error) {
        return sendActionError(res, error, 'Bank status failed:');
    }
});

module.exports = router;
