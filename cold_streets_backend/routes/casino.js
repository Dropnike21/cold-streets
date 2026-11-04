const express = require('express');
const router = express.Router();

// Casino settlement is intentionally fail-closed.
//
// The recovered Casino V1.0 establishes that Perya, Syndicate Slots and
// High-Low are Category 1 "Token Games" whose currency is Casino Tokens and
// whose daily token spend is capped at 100. The current child engines instead
// combine one token with an arbitrary Dirty/Clean Cash wager and pay Clean
// Cash. The source does not define that hybrid denomination, token issuance or
// reset semantics, exact High-Low multipliers, Slots paytable/reset value, or
// whether Perya's 1x/2x/3x wording means gross payout or profit.
//
// Keep the historical engines in the repository for reconciliation, but do
// not expose any read or mutation endpoint as a live economy until the
// denomination/paytable contract is canonical.
router.use((_req, res) => {
    return res.status(503).json({
        error: 'Casino games are paused pending canonical token denomination, daily-cap, and paytable rules.'
    });
});

module.exports = router;
