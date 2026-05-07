// bankRoutes.js (or similar)
const express = require('express');
const router = express.Router();

// The exact same rates we used in the app to ensure server/client match
const baseRates = [0.005, 0.011, 0.025, 0.09, 0.22];
const bankCap = 2000000000; // 2 Billion

router.post('/deposit', async (req, res) => {
    const { userId, depositAmount, durationIndex } = req.body;

    // 1. Basic Validation
    if (depositAmount <= 0 || depositAmount > bankCap) {
        return res.status(400).json({ error: "Invalid deposit amount." });
    }
    if (durationIndex < 0 || durationIndex > 4) {
        return res.status(400).json({ error: "Invalid duration." });
    }

    try {
        // --- START DATABASE TRANSACTION ---
        // (Pseudocode: Replace db.query with your actual DB syntax)

        // 2. Fetch User Data
        const user = await db.query("SELECT dirty_cash, clean_cash, bank_trust_level FROM users WHERE id = ?", [userId]);

        if (!user) return res.status(404).json({ error: "User not found." });

        // Check sequential unlock (Trust Level)
        if (durationIndex > user.bank_trust_level) {
            return res.status(403).json({ error: "You do not have the required trust level for this duration." });
        }

        const totalCash = user.dirty_cash + user.clean_cash;
        if (depositAmount > totalCash) {
            return res.status(400).json({ error: "Insufficient funds." });
        }

        // 3. Priority Drain Math
        const dirtyToTake = Math.min(depositAmount, user.dirty_cash);
        const cleanToTake = depositAmount - dirtyToTake;

        // 4. Calculate Payout & Unlock Time
        const interestRate = baseRates[durationIndex];
        // NOTE: Add your perkBonus logic here if applicable
        const interestEarned = Math.floor(depositAmount * interestRate);
        const totalPayout = depositAmount + interestEarned;

        // Calculate when the money unlocks based on the index
        let daysToLock = 0;
        if (durationIndex === 0) daysToLock = 7;
        else if (durationIndex === 1) daysToLock = 14;
        else if (durationIndex === 2) daysToLock = 30;
        else if (durationIndex === 3) daysToLock = 90;
        else if (durationIndex === 4) daysToLock = 180;

        const unlockDate = new Date();
        unlockDate.setDate(unlockDate.getDate() + daysToLock);

        // 5. Update Database (Deduct Cash & Create Record)
        await db.query(
            "UPDATE users SET dirty_cash = dirty_cash - ?, clean_cash = clean_cash - ? WHERE id = ?",
            [dirtyToTake, cleanToTake, userId]
        );

        await db.query(
            "INSERT INTO time_deposits (user_id, dirty_deposited, clean_deposited, total_payout, duration_index, unlocks_at) VALUES (?, ?, ?, ?, ?, ?)",
            [userId, dirtyToTake, cleanToTake, totalPayout, durationIndex, unlockDate]
        );

        // --- COMMIT DATABASE TRANSACTION ---

        // 6. Return success and the updated balances to the app
        res.status(200).json({
            message: "Deposit successful",
            updatedCash: {
                dirty_cash: user.dirty_cash - dirtyToTake,
                clean_cash: user.clean_cash - cleanToTake
            }
        });

    } catch (error) {
        console.error("Bank Error:", error);
        res.status(500).json({ error: "Internal server error." });
    }
});
// bankRoutes.js

router.post('/claim-check', async (req, res) => {
    const { userId, checkId } = req.body;

    try {
        // --- START TRANSACTION ---

        // 1. Find the specific check
        const check = await db.query(
            "SELECT amount, expires_at, status FROM pending_checks WHERE id = ? AND user_id = ?",
            [checkId, userId]
        );

        if (!check) return res.status(404).json({ error: "Check not found." });
        if (check.status !== 'pending') return res.status(400).json({ error: "Check already processed." });

        // 2. Check if it's expired (The 24hr rule)
        const now = new Date();
        if (new Date(check.expires_at) < now) {
            return res.status(400).json({ error: "This check has expired and is awaiting auto-liquidation." });
        }

        // 3. Mark check as claimed and add money to Clean Cash
        await db.query("UPDATE pending_checks SET status = 'claimed' WHERE id = ?", [checkId]);

        await db.query(
            "UPDATE users SET clean_cash = clean_cash + ? WHERE id = ?",
            [check.amount, userId]
        );

        // --- COMMIT TRANSACTION ---

        // 4. Fetch the fresh wallet balance to send back to the app
        const user = await db.query("SELECT clean_cash FROM users WHERE id = ?", [userId]);

        res.status(200).json({
            message: "Check claimed successfully",
            updatedCash: {
                clean_cash: user.clean_cash
            }
        });

    } catch (error) {
        console.error("Claim Error:", error);
        res.status(500).json({ error: "Internal server error." });
    }
});

module.exports = router;