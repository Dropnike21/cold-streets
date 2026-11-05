const express = require('express');
const router = express.Router();
const db = require('../db');

const { requireOwnedPlayerParam } = require('../middleware/playerIdentity');
const {
    ActionError,
    integer,
    dbInteger,
    exactJsonAmount,
    actorId,
    sendActionError
} = require('../utils/economyValidation');
const {
    requireIdempotencyKey,
    beginIdempotent,
    completeIdempotent
} = require('../utils/idempotency');

router.param('userId', requireOwnedPlayerParam);

const BANK_BLOCKERS = Object.freeze([
    'time_deposit_terms_not_master_data',
    'dirty_cash_to_clean_cash_conversion_conflict',
    'bank_trust_progression_unresolved',
    'bank_interest_perk_stacking_unresolved',
    'pending_check_issuer_integrations_pending',
    'pending_check_expiry_fallback_unresolved'
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

// pending_checks are a generic deferred-payout instrument issued by other
// authoritative systems. The client supplies only the check ID. The locked
// database row owns amount, currency, issuer identity and expiry.
//
// Fully contracted, unexpired checks can be redeemed exactly once. Legacy rows
// without issuer/source/currency metadata remain fail-closed. Expired checks
// are not auto-liquidated because expiry fallback semantics are unresolved.
router.post('/claim-check', async (req, res) => {
    let client;
    let transaction = false;
    try {
        const userId = actorId(req);
        const idempotencyKey = requireIdempotencyKey(req);
        const checkId = integer(
            req.body?.check_id,
            { field: 'Check ID', min: 1n, max: 9223372036854775807n }
        ).toString();

        client = await db.connect();
        await client.query('BEGIN');
        transaction = true;

        // Global economic lock order: actor -> idempotency -> action resource.
        const actor = await client.query(
            'SELECT dirty_cash, clean_cash FROM users WHERE user_id = $1 FOR UPDATE',
            [userId]
        );
        if (actor.rowCount !== 1) {
            throw new ActionError(404, 'Player not found.');
        }

        const idem = await beginIdempotent(
            client,
            userId,
            'bank.claim_deferred_payout',
            idempotencyKey,
            { checkId }
        );
        if (idem.replay) {
            await client.query('COMMIT');
            transaction = false;
            return res.status(idem.status).json(idem.response);
        }

        const checkRes = await client.query(
            `SELECT id, user_id, source, amount, expires_at, status,
                    issuer_type, source_ref, payout_currency, metadata_jsonb,
                    created_at, claimed_at,
                    (expires_at <= NOW()) AS timestamp_expired
               FROM pending_checks
              WHERE id = $1
              FOR UPDATE`,
            [checkId]
        );

        if (checkRes.rowCount !== 1) {
            throw new ActionError(404, 'Deferred payout not found.');
        }

        const check = checkRes.rows[0];
        if (String(check.user_id) !== userId) {
            throw new ActionError(403, 'Deferred payout does not belong to this player.');
        }
        if (check.status !== 'pending') {
            throw new ActionError(409, 'Deferred payout is no longer pending.');
        }
        if (!check.issuer_type || !check.source_ref || !check.payout_currency) {
            throw new ActionError(
                503,
                'Legacy deferred payout lacks the issuer contract required for settlement.'
            );
        }
        if (check.timestamp_expired === true) {
            throw new ActionError(
                409,
                'Deferred payout has expired; fallback settlement is not yet reconciled.'
            );
        }

        const amount = dbInteger(check.amount, {
            field: 'Deferred payout amount'
        });
        if (amount <= 0n) {
            throw new Error('Deferred payout amount must remain positive.');
        }

        const currencyColumn = check.payout_currency === 'dirty_cash'
            ? 'dirty_cash'
            : check.payout_currency === 'clean_cash'
                ? 'clean_cash'
                : null;
        if (!currencyColumn) {
            throw new ActionError(503, 'Deferred payout currency is unsupported.');
        }

        const credited = await client.query(
            `UPDATE users
                SET ${currencyColumn} = ${currencyColumn} + $1::numeric
              WHERE user_id = $2
              RETURNING dirty_cash, clean_cash`,
            [amount.toString(), userId]
        );
        if (credited.rowCount !== 1) {
            throw new Error('Deferred payout balance update failed.');
        }

        const claimed = await client.query(
            `UPDATE pending_checks
                SET status = 'claimed',
                    claimed_at = NOW()
              WHERE id = $1
                AND status = 'pending'
              RETURNING claimed_at`,
            [checkId]
        );
        if (claimed.rowCount !== 1) {
            throw new ActionError(409, 'Deferred payout changed before settlement.');
        }

        const response = {
            success: true,
            check_id: exactJsonAmount(BigInt(checkId)),
            issuer_type: check.issuer_type,
            source_ref: check.source_ref,
            source: check.source,
            payout_currency: check.payout_currency,
            amount: exactJsonAmount(amount),
            claimed_at: claimed.rows[0].claimed_at,
            dirty_cash: exactDbAmount(
                credited.rows[0].dirty_cash,
                'Dirty Cash'
            ),
            clean_cash: exactDbAmount(
                credited.rows[0].clean_cash,
                'Clean Cash'
            )
        };

        await completeIdempotent(client, idem, 200, response);
        await client.query('COMMIT');
        transaction = false;
        return res.json(response);
    } catch (error) {
        if (transaction) {
            try {
                await client.query('ROLLBACK');
            } catch (rollback) {
                console.error('Deferred payout claim rollback:', rollback);
            }
        }
        return sendActionError(res, error, 'Bank deferred payout claim failed:');
    } finally {
        if (client) client.release();
    }
});

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
                        issuer_type,
                        source_ref,
                        payout_currency,
                        claimed_at,
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
            issuer_type: row.issuer_type,
            source_ref: row.source_ref,
            payout_currency: row.payout_currency,
            amount_recorded: exactDbAmount(
                row.amount,
                'Recorded pending-check amount'
            ),
            created_at: row.created_at,
            expires_at: row.expires_at,
            status: row.status,
            claimed_at: row.claimed_at,
            timestamp_expired: row.timestamp_expired === true,
            claim_available:
                row.status === 'pending' &&
                row.timestamp_expired !== true &&
                !!row.issuer_type &&
                !!row.source_ref &&
                !!row.payout_currency,
            settlement_status:
                !row.issuer_type || !row.source_ref || !row.payout_currency
                    ? 'legacy_contract_incomplete'
                    : row.status === 'claimed'
                        ? 'claimed'
                        : row.timestamp_expired === true
                            ? 'expired_fallback_unresolved'
                            : 'claimable'
        }));

        return res.json({
            success: true,
            bank_status: 'deferred_payout_redemption_enabled',
            time_deposit_creation_available: false,
            time_deposit_claim_available: false,
            pending_check_claim_available: true,
            pending_check_role: 'external_deferred_payout',
            bank_trust_progression_status: 'unresolved',
            time_deposit_terms_status: 'historical_code_only',
            payout_currency_status: 'unresolved',
            dirty_to_clean_conversion_status: 'conflicts_with_gdd_laundering_model',
            pending_check_creation_status: 'server_contract_available_no_issuers_integrated',
            pending_check_expiry_status: 'fallback_unresolved',
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
