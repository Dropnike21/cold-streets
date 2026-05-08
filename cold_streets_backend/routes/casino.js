const express = require('express');
const router = express.Router();

// --- MODULAR CASINO GAMES ---

// 1. Perya Color Game
// Every route inside perya.js will now automatically start with /casino/perya
router.use('/perya', require('./casino/perya'));
router.use('/slots', require('./casino/slots'));
router.use('/highlow', require('./casino/highlow'));


module.exports = router;