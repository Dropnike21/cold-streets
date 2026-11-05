const pool = require('../db');
const logger = require('./logger');

async function checkPlayerState(req, res, next) {
    // Read the identity established by verified Supabase Auth middleware.
    // The old code trusted a user ID supplied by the client and skipped the
    // gatekeeper entirely for GET endpoints whose route params were not yet parsed.
    const userId = req.player?.userId;
    if (!userId) return res.status(401).json({ error: 'Authentication required.' });

    try {
        const { rows } = await pool.query(`
            SELECT jail_expires_at, hospital_expires_at
            FROM users
            WHERE user_id = $1
        `, [userId]);

        if (rows.length === 0) return next();

        const user = rows[0];
        const now = new Date();

if (req.originalUrl.includes('/character/level') || req.originalUrl.includes('/character/hold')) {
        return next();
    }
        // 1. JAIL CHECK (Takes priority)
        if (user.jail_expires_at && new Date(user.jail_expires_at) > now) {
            return res.status(403).json({
                error: "You are currently incarcerated. You can only access the Yard, Records, and your Inventory.",
                state: "jailed",
                expires_at: user.jail_expires_at
            });
        }

        // 2. HOSPITAL CHECK
        if (user.hospital_expires_at && new Date(user.hospital_expires_at) > now) {
            return res.status(403).json({
                error: "You are recovering in the hospital. You can only access your Inventory.",
                state: "hospitalized",
                expires_at: user.hospital_expires_at
            });
        }

        // 3. Player is free, allow the request to proceed
        next();
    } catch (err) {
        logger.error('state_gatekeeper_failed', {
            request_id: req.requestId,
            ...logger.errorFields(err)
        });
        res.status(500).json({ error: "Server error verifying player state." });
    }
}

module.exports = checkPlayerState;