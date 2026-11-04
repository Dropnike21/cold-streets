const express = require('express');
const router = express.Router();
const db = require('../db');
const { requireOwnedPlayerParam } = require('../middleware/playerIdentity');
const { ActionError, integer, dbInteger, exactJsonAmount, actorId, sendActionError } = require('../utils/economyValidation');
router.param('userId', requireOwnedPlayerParam);

const INTEREST_BASIS_POINTS = [50n, 110n, 250n, 900n, 2200n];
const TERM_DAYS = [7, 14, 30, 90, 180];
const BANK_CAP = 2000000000n;

router.post('/deposit', async (req, res) => {
    let client, transaction = false;
    try {
        const userId = actorId(req);
        const amount = integer(req.body?.depositAmount, {
            field: 'Deposit amount', min: 1n, max: BANK_CAP
        });
        const durationIndex = req.body?.durationIndex;
        if (!Number.isInteger(durationIndex) ||
            durationIndex < 0 || durationIndex >= TERM_DAYS.length) {
            throw new ActionError(400, 'Invalid duration.');
        }

        client = await db.connect();
        await client.query('BEGIN');
        transaction = true;
        const account = await client.query(
            'SELECT dirty_cash, clean_cash, bank_trust_level FROM users WHERE user_id = $1 FOR UPDATE',
            [userId]
        );
        if (account.rowCount !== 1) throw new ActionError(404, 'Player not found.');
        const user = account.rows[0];
        if (!Number.isInteger(Number(user.bank_trust_level)) ||
            durationIndex > Number(user.bank_trust_level)) {
            throw new ActionError(403, 'Required bank trust level not reached.');
        }

        // Database also has a unique partial index for active deposits. This
        // check provides a clear API error while the unique index handles races.
        const active = await client.query(
            "SELECT 1 FROM time_deposits WHERE user_id = $1 AND status = 'active' LIMIT 1",
            [userId]
        );
        if (active.rowCount) throw new ActionError(409, 'Claim your active deposit before opening another.');

        const dirty = dbInteger(user.dirty_cash), clean = dbInteger(user.clean_cash);
        if (dirty + clean < amount) throw new ActionError(409, 'Insufficient funds.');
        const takeDirty = dirty < amount ? dirty : amount;
        const takeClean = amount - takeDirty;
        const interest = amount * INTEREST_BASIS_POINTS[durationIndex] / 10000n;
        const payout = amount + interest;

        const wallet = await client.query(
            `UPDATE users
               SET dirty_cash = dirty_cash - $1::numeric,
                   clean_cash = clean_cash - $2::numeric
             WHERE user_id = $3
               AND dirty_cash >= $1::numeric
               AND clean_cash >= $2::numeric
             RETURNING dirty_cash, clean_cash`,
            [takeDirty.toString(), takeClean.toString(), userId]
        );
        if (wallet.rowCount !== 1) throw new ActionError(409, 'Wallet changed before deposit.');

        await client.query(
            `INSERT INTO time_deposits
               (user_id, dirty_deposited, clean_deposited, total_payout,
                duration_index, unlocks_at, status)
             VALUES ($1, $2::numeric, $3::numeric, $4::numeric, $5,
                     NOW() + $6::integer * INTERVAL '1 day', 'active')`,
            [userId, takeDirty.toString(), takeClean.toString(),
             payout.toString(), durationIndex, TERM_DAYS[durationIndex]]
        );
        await client.query('COMMIT');
        transaction = false;
        return res.json({
            message: 'Deposit successful.',
            updatedCash: {
                dirty_cash: exactJsonAmount(dbInteger(wallet.rows[0].dirty_cash)),
                clean_cash: exactJsonAmount(dbInteger(wallet.rows[0].clean_cash))
            }
        });
    } catch (err) {
        if (transaction) {
            try { await client.query('ROLLBACK'); }
            catch (rollback) { console.error('Bank deposit rollback:', rollback); }
        }
        return sendActionError(res, err, 'Bank deposit failed:');
    } finally { if (client) client.release(); }
});

// Explicit maturity settlement. The recovery specification confirms there was
// no trustworthy maturation worker. A state-changing POST avoids side effects
// in GET /status and makes repeated claims fail closed.
router.post('/claim-deposit', async (req, res) => {
    let client, transaction = false;
    try {
        const userId = actorId(req);
        client = await db.connect();
        await client.query('BEGIN');
        transaction = true;
        const player = await client.query(
            'SELECT user_id FROM users WHERE user_id = $1 FOR UPDATE', [userId]
        );
        if (player.rowCount !== 1) throw new ActionError(404, 'Player not found.');

        const result = await client.query(
            `SELECT deposit_id, total_payout, unlocks_at
               FROM time_deposits
              WHERE user_id = $1 AND status = 'active'
              FOR UPDATE`,
            [userId]
        );
        if (result.rowCount !== 1) throw new ActionError(409, 'No active deposit to claim.');
        const deposit = result.rows[0];

        const claimed = await client.query(
            `UPDATE time_deposits SET status = 'claimed'
              WHERE deposit_id = $1 AND user_id = $2
                AND status = 'active' AND unlocks_at <= NOW()
              RETURNING total_payout`,
            [deposit.deposit_id, userId]
        );
        if (claimed.rowCount !== 1) {
            throw new ActionError(409, 'Deposit has not matured yet.');
        }
        const payout = dbInteger(claimed.rows[0].total_payout, { field: 'Deposit payout' });
        if (payout <= 0n) throw new Error('Invalid matured deposit payout.');

        const wallet = await client.query(
            'UPDATE users SET clean_cash = clean_cash + $1::numeric WHERE user_id = $2 RETURNING clean_cash',
            [payout.toString(), userId]
        );
        if (wallet.rowCount !== 1) throw new Error('Player disappeared during deposit claim.');
        await client.query('COMMIT');
        transaction = false;
        return res.json({
            message: 'Matured deposit claimed.',
            payout: exactJsonAmount(payout),
            updatedCash: { clean_cash: exactJsonAmount(dbInteger(wallet.rows[0].clean_cash)) }
        });
    } catch (err) {
        if (transaction) {
            try { await client.query('ROLLBACK'); }
            catch (rollback) { console.error('Deposit claim rollback:', rollback); }
        }
        return sendActionError(res, err, 'Deposit claim failed:');
    } finally { if (client) client.release(); }
});

router.post('/claim-check', async (req, res) => {
    let client, transaction = false;
    try {
        const userId = actorId(req);
        const checkId = integer(req.body?.checkId, {
            field: 'Check ID', min: 1n, max: 9223372036854775807n
        }).toString();
        client = await db.connect();
        await client.query('BEGIN');
        transaction = true;

        const account = await client.query(
            'SELECT user_id FROM users WHERE user_id = $1 FOR UPDATE', [userId]
        );
        if (account.rowCount !== 1) throw new ActionError(404, 'Player not found.');
        const check = await client.query(
            'SELECT amount, expires_at, status FROM pending_checks WHERE id = $1 AND user_id = $2 FOR UPDATE',
            [checkId, userId]
        );
        if (check.rowCount !== 1) throw new ActionError(404, 'Check not found.');
        if (check.rows[0].status !== 'pending') throw new ActionError(409, 'Check already processed.');

        const claimed = await client.query(
            `UPDATE pending_checks SET status = 'claimed'
              WHERE id = $1 AND user_id = $2 AND status = 'pending'
                AND expires_at > NOW()
              RETURNING amount`,
            [checkId, userId]
        );
        if (claimed.rowCount !== 1) throw new ActionError(409, 'Check is expired or already processed.');
        const amount = dbInteger(claimed.rows[0].amount, { field: 'Check payout' });
        if (amount <= 0n) throw new Error('Invalid check payout.');

        const wallet = await client.query(
            'UPDATE users SET clean_cash = clean_cash + $1::numeric WHERE user_id = $2 RETURNING clean_cash',
            [amount.toString(), userId]
        );
        if (wallet.rowCount !== 1) throw new Error('Player disappeared during check claim.');
        await client.query('COMMIT');
        transaction = false;
        return res.json({
            message: 'Check claimed successfully.',
            updatedCash: { clean_cash: exactJsonAmount(dbInteger(wallet.rows[0].clean_cash)) }
        });
    } catch (err) {
        if (transaction) {
            try { await client.query('ROLLBACK'); }
            catch (rollback) { console.error('Check claim rollback:', rollback); }
        }
        return sendActionError(res, err, 'Bank check claim failed:');
    } finally { if (client) client.release(); }
});

router.get('/status/:userId', async (req, res) => {
    try {
        const userId = actorId(req);
        const [deposit, checks] = await Promise.all([
            db.query(
                `SELECT deposit_id, dirty_deposited, clean_deposited,
                        total_payout, duration_index, unlocks_at,
                        (unlocks_at <= NOW()) AS matured
                   FROM time_deposits
                  WHERE user_id = $1 AND status = 'active' LIMIT 1`,
                [userId]
            ),
            db.query(
                "SELECT id, source, amount, expires_at FROM pending_checks WHERE user_id = $1 AND status = 'pending'",
                [userId]
            )
        ]);
        return res.json({
            active_time_deposit: deposit.rows[0] || null,
            pending_checks: checks.rows
        });
    } catch (err) {
        return sendActionError(res, err, 'Bank status failed:');
    }
});

module.exports = router;
