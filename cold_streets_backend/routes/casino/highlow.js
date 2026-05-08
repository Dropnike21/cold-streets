const express = require('express');
const router = express.Router();
const db = require('../../db');

const TOKEN_COST = 1;
const SUITS = ['HEARTS', 'DIAMONDS', 'CLUBS', 'SPADES'];
const getRandomCard = () => ({
    value: Math.floor(Math.random() * 13) + 2, // 2 through 14 (Ace)
    suit: SUITS[Math.floor(Math.random() * SUITS.length)]
});

// --- 1. GET ACTIVE SESSION (When player opens the game) ---
router.get('/session/:userId', async (req, res) => {
    try {
        const session = await db.query("SELECT * FROM hilo_sessions WHERE user_id = $1", [req.params.userId]);
        if (session.rows.length > 0) return res.status(200).json({ active: true, session: session.rows[0] });
        res.status(200).json({ active: false });
    } catch (error) { res.status(500).json({ error: "Server error." }); }
});

// --- 2. START A NEW GAME ---
router.post('/start', async (req, res) => {
    try {
        const userId = Number(req.body.userId);
        const betAmount = Number(req.body.betAmount);

        if (betAmount <= 0) return res.status(400).json({ error: "Invalid bet." });

        await db.query('BEGIN');
        const userRes = await db.query("SELECT dirty_cash, clean_cash, casino_tokens FROM users WHERE user_id = $1", [userId]);
        const user = userRes.rows[0];

        if (user.casino_tokens < TOKEN_COST) throw new Error("Out of Tokens!");
        if ((Number(user.dirty_cash) + Number(user.clean_cash)) < betAmount) throw new Error("Insufficient Cash.");

        // Deduct 1 Token & Cash
        let dirtyToDeduct = Math.min(Number(user.dirty_cash), betAmount);
        let cleanToDeduct = betAmount - dirtyToDeduct;
        await db.query("UPDATE users SET casino_tokens = casino_tokens - $1, dirty_cash = dirty_cash - $2, clean_cash = clean_cash - $3 WHERE user_id = $4", [TOKEN_COST, dirtyToDeduct, cleanToDeduct, userId]);

        // Deal first card and create session
        const card = getRandomCard();
        await db.query(
            "INSERT INTO hilo_sessions (user_id, bet_amount, current_card_value, current_card_suit) VALUES ($1, $2, $3, $4)",
            [userId, betAmount, card.value, card.suit]
        );

        await db.query('COMMIT');

        const finalUser = await db.query("SELECT dirty_cash, clean_cash, casino_tokens FROM users WHERE user_id = $1", [userId]);
        res.status(200).json({ card: card, updatedBalances: finalUser.rows[0] });

    } catch (error) {
        await db.query('ROLLBACK');
        res.status(400).json({ error: error.message });
    }
});

// --- 3. GUESS HIGH, LOW, OR SAME ---
router.post('/guess', async (req, res) => {
    try {
        const { userId, guess } = req.body; // guess = 'HIGH', 'LOW', or 'SAME'

        await db.query('BEGIN');
        const sessionRes = await db.query("SELECT * FROM hilo_sessions WHERE user_id = $1", [userId]);
        if (sessionRes.rows.length === 0) throw new Error("No active game found.");
        const session = sessionRes.rows[0];

        const nextCard = getRandomCard();
        let isWin = false;
        let multiplierBoost = 0;

        // 🚨 NEW LOGIC: High, Low, and Draw
        if (guess === 'HIGH' && nextCard.value > session.current_card_value) {
            isWin = true;
            multiplierBoost = 0.30;
        } else if (guess === 'LOW' && nextCard.value < session.current_card_value) {
            isWin = true;
            multiplierBoost = 0.30;
        } else if (guess === 'SAME' && nextCard.value === session.current_card_value) {
            isWin = true;
            multiplierBoost = 5.00; // MASSIVE boost for guessing a tie!
        }

        if (isWin) {
            const newMultiplier = Number(session.current_multiplier) + multiplierBoost;
            const newStreak = session.current_streak + 1;

            await db.query(
                "UPDATE hilo_sessions SET current_multiplier = $1, current_streak = $2, current_card_value = $3, current_card_suit = $4 WHERE user_id = $5",
                [newMultiplier, newStreak, nextCard.value, nextCard.suit, userId]
            );
            await db.query('COMMIT');
            res.status(200).json({ status: 'WIN', nextCard, newMultiplier, newStreak });
        } else {
            // LOSS: Delete session, feed 10% to Jackpot
            const betAmount = Number(session.bet_amount);
            const jackpotFeed = Math.floor(betAmount * 0.10);

            await db.query("DELETE FROM hilo_sessions WHERE user_id = $1", [userId]);
            await db.query("UPDATE casino_jackpots SET current_value = current_value + $1 WHERE game_id = 'slots_progressive'", [jackpotFeed]);
            await db.query("INSERT INTO casino_audit (user_id, game_name, bet_amount, payout) VALUES ($1, $2, $3, $4)", [userId, 'HighLow', betAmount, 0]);

            await db.query('COMMIT');
            res.status(200).json({ status: 'LOSS', nextCard });
        }
    } catch (error) {
        await db.query('ROLLBACK');
        res.status(400).json({ error: error.message });
    }
});

// --- 4. CASH OUT ---
router.post('/cashout', async (req, res) => {
    try {
        const { userId } = req.body;

        await db.query('BEGIN');
        const sessionRes = await db.query("SELECT * FROM hilo_sessions WHERE user_id = $1", [userId]);
        if (sessionRes.rows.length === 0) throw new Error("No active game found.");
        const session = sessionRes.rows[0];

        const payoutAmount = Math.floor(Number(session.bet_amount) * Number(session.current_multiplier));

        // Award Clean Cash and delete session
        await db.query("UPDATE users SET clean_cash = clean_cash + $1 WHERE user_id = $2", [payoutAmount, userId]);
        await db.query("DELETE FROM hilo_sessions WHERE user_id = $1", [userId]);
        await db.query("INSERT INTO casino_audit (user_id, game_name, bet_amount, payout) VALUES ($1, $2, $3, $4)", [userId, 'HighLow', session.bet_amount, payoutAmount]);

        await db.query('COMMIT');

        const finalUser = await db.query("SELECT dirty_cash, clean_cash, casino_tokens FROM users WHERE user_id = $1", [userId]);
        res.status(200).json({ payout: payoutAmount, updatedBalances: finalUser.rows[0] });

    } catch (error) {
        await db.query('ROLLBACK');
        res.status(400).json({ error: error.message });
    }
});

module.exports = router;