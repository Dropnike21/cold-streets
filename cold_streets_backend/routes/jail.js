const express = require('express');
const pool = require('../db');
const router = express.Router();
const { sendActionError } = require('../utils/economyValidation');

// ==========================================
// 1. GET INMATE LIST
// ==========================================
router.get('/inmates', async (_req, res) => {
    try {
        const inmates = await pool.query(
            `SELECT user_id, username, level, jail_expires_at,
                    jail_initial_seconds, state_reason AS reason
               FROM users
              WHERE jail_expires_at > NOW()
              ORDER BY jail_expires_at ASC`
        );
        return res.json({ success: true, inmates: inmates.rows });
    } catch (err) {
        return sendActionError(res, err, 'Jail inmate list failed:');
    }
});

// ==========================================
// 2. PAY BAIL
// ==========================================
router.post('/bail', (_req, res) => {
    // The recovered design defines initial-sentence pricing semantics and the
    // +25 Influence reward for bailing another player, but it never defines
    // the Clean Cash rate. The former $100/minute value was code-only.
    return res.status(503).json({
        error: 'Bail settlement is paused pending a canonical Clean Cash rate.'
    });
});

// ==========================================
// 3. BREAKOUT / SELF-ESCAPE
// ==========================================
router.post('/breakout', (_req, res) => {
    // The recovered design defines outside-in vs inside-out behavior and the
    // +20 Heat / +1 hour failure penalty, but it does not define Nerve cost or
    // success probability. The former 5 Nerve / 40% values were placeholders.
    //
    // The source-backed Juris Doctor entitlement remains the recovered access
    // rule for an eventual outside-in Bust Out; this route stays closed until
    // the missing balance values are selected canonically.
    return res.status(503).json({
        error: 'Jail breakout is paused pending canonical Nerve cost and success probability.'
    });
});

// ==========================================
// 4. PRISON YARD
// ==========================================
router.post('/gym/train', (_req, res) => {
    // The source requires gains to be split evenly across STR/DEF/DEX/SPD and
    // to use a drastically reduced multiplier, but it never specifies that
    // multiplier or an EXP award. The former formula and +5 EXP/Energy were
    // code-only balance assumptions.
    return res.status(503).json({
        error: 'Prison-yard training is paused pending a canonical gain multiplier.'
    });
});

module.exports = router;
