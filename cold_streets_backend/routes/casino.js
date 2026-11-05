const express = require('express');
const router = express.Router();
const pool = require('../db');
const {
    actorId,
    exactJsonAmount,
    sendActionError
} = require('../utils/economyValidation');
const {
    BASE_DAILY_TOKEN_SPEND_CAP,
    VIP_DAILY_TOKEN_BONUS,
    MAX_DAILY_TOKEN_SPEND_CAP,
    RECONCILED_TOKEN_ENGINES,
    getCasinoTokenStatus
} = require('../utils/casinoTokenLedger');

// Read-only Category 1 token accounting. The source establishes Casino Tokens
// and a 100-token base daily SPEND cap; VIP Status adds +50 (150 total).
// No Casino game mutation is opened by this endpoint.
router.get('/status', async (req, res) => {
    try {
        const userId = actorId(req);
        const status = await getCasinoTokenStatus(pool, userId);

        return res.json({
            success: true,
            casino_status: 'token_accounting_ready_games_paused',
            category_1_currency: 'casino_tokens',
            token_balance: exactJsonAmount(status.balance),
            vip_status_active: status.vipActive,
            base_daily_token_spend_cap: exactJsonAmount(BASE_DAILY_TOKEN_SPEND_CAP),
            vip_daily_token_bonus: exactJsonAmount(
                status.vipActive ? VIP_DAILY_TOKEN_BONUS : 0n
            ),
            effective_daily_token_spend_cap: exactJsonAmount(status.dailyCap),
            maximum_supported_daily_token_spend_cap:
                exactJsonAmount(MAX_DAILY_TOKEN_SPEND_CAP),
            spent_today: exactJsonAmount(status.spentToday),
            remaining_daily_spend: exactJsonAmount(status.remainingToday),
            day_key: status.dayKey,
            reset_boundary: 'database_calendar_day',
            preserved_token_engines: Array.from(RECONCILED_TOKEN_ENGINES),
            token_issuance_available: false,
            token_gameplay_available: false,
            category_2_clean_cash_gameplay_available: false,
            paytable_status: 'unresolved',
            blockers: [
                'Casino Token issuance and replenishment semantics are not source-reconciled.',
                'Perya gross-versus-profit multiplier semantics are unresolved.',
                'Slots paytable and progressive-jackpot settlement are unresolved.',
                'High-Low exact multiplier and cashout rules are unresolved.',
                'Legacy Casino audit rows do not establish authoritative Token spend history.'
            ]
        });
    } catch (err) {
        return sendActionError(res, err, 'Casino token status failed:');
    }
});

// Casino settlement remains intentionally fail-closed.
//
// The recovered Casino V1.0 establishes that Perya, Syndicate Slots and
// High-Low are Category 1 Token Games whose currency is Casino Tokens and whose
// base daily token spend is capped at 100, with VIP Status increasing that
// cap by 50 to 150. The preserved child engines instead
// contain an unsupported hybrid of token and cash settlement. Keep those
// engines unavailable until denomination/paytable/issuance rules are canonical.
router.use((_req, res) => {
    return res.status(503).json({
        error: 'Casino games are paused. Only read-only token status is currently available.'
    });
});

module.exports = router;
