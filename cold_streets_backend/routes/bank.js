const express = require('express');
const router = express.Router();
const db = require('../db');

// Existing game rates, represented as integer basis points to avoid JS float rounding.
const INTEREST_BASIS_POINTS = [50n, 110n, 250n, 900n, 2200n];
const TERM_DAYS = [7, 14, 30, 90, 180];
const BANK_CAP = 2000000000n;

class BankRequestError extends Error {
    constructor(status, message) {
        super(message);
        this.status = status;
    }
}

// Reject non-canonical IDs and amounts: no parseInt truncation, NaN, floats or negatives.
function positiveInteger(value) {
    if (typeof value === 'number') {
        if (!Number.isSafeInteger(value) || value <= 0) return null;
        return BigInt(value);
    }
    if (typeof value === 'string' && /^[1-9][0-9]*$/.test(value)) {
        return BigInt(value);
    }
    return null;
}

// node-postgres commonly returns NUMERIC as a string, sometimes with ".00".
function databaseMoney(value) {
    const text = String(value);
    if (!/^[0-9]+(?:\.0+)?$/.test(text)) {
        throw new Error('Unsupported non-integer money balance in database.');
    }
    return BigInt(text.split('.')[0]);
}

function clientMoney(value) {
    // Keep existing JSON numeric API for ordinary balances, but never silently
    // round balances that exceed the JS safe-integer boundary.
    return value <= BigInt(Number.MAX_SAFE_INTEGER) ? Number(value) : value.toString();
}

function requireUserId(value) {
    const id = positiveInteger(value);
    if (id === null || id > BigInt(Number.MAX_SAFE_INTEGER)) {
        throw new BankRequestError(400, 'Invalid user ID.');
    }
    return id.toString();
}

function sendError(res, err, label) {
    if (err instanceof BankRequestError) {
        return res.status(err.status).json({ error: err.message });
    }
    console.error(label, err);
    return res.status(500).json({ error: 'Internal server error.' });
}

// IMPORTANT: These routes still require verified authentication and account
// ownership middleware before deployment to an untrusted/public environment.
router.post('/deposit', async (req, res) => {
    let client;
    try {
        const { userId, depositAmount, durationIndex } = req.body || {};
        const id = requireUserId(userId);
        const amount = positiveInteger(depositAmount);
        if (amount === null || amount > BANK_CAP) {
            throw new BankRequestError(400, 'Invalid deposit amount.');
        }
        if (!Number.isInteger(durationIndex) || durationIndex < 0 || durationIndex >= TERM_DAYS.length) {
            throw new BankRequestError(400, 'Invalid duration.');
        }

        client = await db.connect();
        await client.query('BEGIN');

        // The user lock serializes this user's deposits, withdrawals and claims
        // that consistently use the same lock order.
        const account = await client.query(
            'SELECT dirty_cash, clean_cash, bank_trust_level FROM users WHERE user_id = $1 FOR UPDATE',
            [id]
        );
        if (account.rowCount === 0) throw new BankRequestError(404, 'User not found.');
        const user = account.rows[0];

        if (durationIndex > Number(user.bank_trust_level)) {
            throw new BankRequestError(403, 'You do not have the required trust level for this duration.');
        }

        // The client prevents multiple active deposits. Enforce it on the server too.
        const existing = await client.query(
            "SELECT 1 FROM time_deposits WHERE user_id = $1 AND status = 'active' LIMIT 1",
            [id]
        );
        if (existing.rowCount > 0) {
            throw new BankRequestError(409, 'You already have an active time deposit.');
        }

        const dirtyCash = databaseMoney(user.dirty_cash);
        const cleanCash = databaseMoney(user.clean_cash);
        if (amount > dirtyCash + cleanCash) {
            throw new BankRequestError(400, 'Insufficient funds.');
        }

        const dirtyToTake = amount < dirtyCash ? amount : dirtyCash;
        const cleanToTake = amount - dirtyToTake;
        const interestEarned = (amount * INTEREST_BASIS_POINTS[durationIndex]) / 10000n;
        const payout = amount + interestEarned;

        const wallet = await client.query(
            `UPDATE users
             SET dirty_cash = dirty_cash - $1::numeric,
                 clean_cash = clean_cash - $2::numeric
             WHERE user_id = $3 AND dirty_cash >= $1::numeric AND clean_cash >= $2::numeric
             RETURNING dirty_cash, clean_cash`,
            [dirtyToTake.toString(), cleanToTake.toString(), id]
        );
        if (wallet.rowCount !== 1) {
            throw new BankRequestError(409, 'Funds changed; retry the deposit.');
        }

        await client.query(
            `INSERT INTO time_deposits
               (user_id, dirty_deposited, clean_deposited, total_payout, duration_index, unlocks_at, status)
             VALUES ($1, $2, $3, $4, $5, NOW() + $6::integer * INTERVAL '1 day', 'active')`,
            [id, dirtyToTake.toString(), cleanToTake.toString(), payout.toString(),
                durationIndex, TERM_DAYS[durationIndex]]
        );

        await client.query('COMMIT');
        return res.status(200).json({
            message: 'Deposit successful',
            updatedCash: {
                dirty_cash: clientMoney(databaseMoney(wallet.rows[0].dirty_cash)),
                clean_cash: clientMoney(databaseMoney(wallet.rows[0].clean_cash))
            }
        });
    } catch (err) {
        if (client) {
            try { await client.query('ROLLBACK'); } catch (rollbackError) {
                console.error('Bank deposit rollback failed:', rollbackError);
            }
        }
        return sendError(res, err, 'Bank deposit error:');
    } finally {
        if (client) client.release();
    }
});

router.post('/claim-check', async (req, res) => {
    let client;
    try {
        const { userId, checkId } = req.body || {};
        const id = requireUserId(userId);
        const parsedCheckId = positiveInteger(checkId);
        if (parsedCheckId === null || parsedCheckId > BigInt(Number.MAX_SAFE_INTEGER)) {
            throw new BankRequestError(400, 'Invalid check ID.');
        }

        client = await db.connect();
        await client.query('BEGIN');

        const account = await client.query(
            'SELECT user_id FROM users WHERE user_id = $1 FOR UPDATE',
            [id]
        );
        if (account.rowCount === 0) throw new BankRequestError(404, 'User not found.');

        const checkResult = await client.query(
            'SELECT amount, expires_at, status FROM pending_checks WHERE id = $1 AND user_id = $2 FOR UPDATE',
            [parsedCheckId.toString(), id]
        );
        if (checkResult.rowCount === 0) throw new BankRequestError(404, 'Check not found.');

        const check = checkResult.rows[0];
        if (check.status !== 'pending') throw new BankRequestError(400, 'Check already processed.');
        if (new Date(check.expires_at).getTime() <= Date.now()) {
            throw new BankRequestError(400, 'This check has expired and is awaiting auto-liquidation.');
        }

        const amount = databaseMoney(check.amount);
        if (amount <= 0n) throw new Error('Pending check contains an invalid payout.');

        // Atomic conditional state transition blocks duplicate claims.
        const claim = await client.query(
            `UPDATE pending_checks SET status = 'claimed'
             WHERE id = $1 AND user_id = $2 AND status = 'pending' AND expires_at > NOW()
             RETURNING id`,
            [parsedCheckId.toString(), id]
        );
        if (claim.rowCount !== 1) throw new BankRequestError(409, 'Check could not be claimed.');

        const wallet = await client.query(
            'UPDATE users SET clean_cash = clean_cash + $1::numeric WHERE user_id = $2 RETURNING clean_cash',
            [amount.toString(), id]
        );
        if (wallet.rowCount !== 1) throw new Error('Account not found during check claim.');

        await client.query('COMMIT');
        return res.status(200).json({
            message: 'Check claimed successfully',
            updatedCash: { clean_cash: clientMoney(databaseMoney(wallet.rows[0].clean_cash)) }
        });
    } catch (err) {
        if (client) {
            try { await client.query('ROLLBACK'); } catch (rollbackError) {
                console.error('Bank check rollback failed:', rollbackError);
            }
        }
        return sendError(res, err, 'Bank claim error:');
    } finally {
        if (client) client.release();
    }
});

router.get('/status/:userId', async (req, res) => {
    try {
        const id = requireUserId(req.params.userId);
        const depositResult = await db.query(
            "SELECT dirty_deposited, clean_deposited, duration_index, unlocks_at FROM time_deposits WHERE user_id = $1 AND status = 'active' LIMIT 1",
            [id]
        );
        const checksResult = await db.query(
            "SELECT id, source, amount, expires_at FROM pending_checks WHERE user_id = $1 AND status = 'pending'",
            [id]
        );
        return res.status(200).json({
            active_time_deposit: depositResult.rows[0] || null,
            pending_checks: checksResult.rows
        });
    } catch (err) {
        return sendError(res, err, 'Bank fetch error:');
    }
});

module.exports = router;
