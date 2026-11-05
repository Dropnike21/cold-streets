const express = require('express');
const router = express.Router();

// Historical Casino engine intentionally disabled.
//
// The preserved implementation mixed Casino Tokens with Dirty/Clean Cash and
// embedded paytable/jackpot semantics that are not reconciled with the current
// Casino source. The canonical /casino router exposes read-only status only.
//
// Keeping this module fail-closed prevents an accidental future mount from
// reactivating legacy settlement code.
router.use((_req, res) => {
    return res.status(503).json({
        error: 'Legacy Casino engine is retired pending source-reconciled settlement rules.'
    });
});

module.exports = router;
