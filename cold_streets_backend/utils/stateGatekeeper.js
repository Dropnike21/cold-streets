const pool = require('../db'); // Adjust path to your db.js if necessary

async function checkPlayerState(req, res, next) {
    // FIX: Added optional chaining (?.) so it doesn't crash if req.body is undefined
    const userId = req.body?.user_id || req.params?.user_id || req.query?.user_id;

    // If no user ID is provided, let the specific route handle the missing param error
    if (!userId) return next();

    try {
        const { rows } = await pool.query(`
            SELECT jail_expires_at, hospital_expires_at
            FROM users
            WHERE user_id = $1
        `, [userId]);

        if (rows.length === 0) return next();

        const user = rows[0];
        const now = new Date();

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
        console.error("Gatekeeper Error:", err.message);
        res.status(500).json({ error: "Server error verifying player state." });
    }
}

module.exports = checkPlayerState;