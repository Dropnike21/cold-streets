const express = require('express');
const router = express.Router();
const db = require('../db'); 

// --- HELPER: Safely parse Postgres numeric strings ---
const formatProp = (row) => ({
    ...row,
    cost: Number(row.cost || 0),
    upkeep_val: Number(row.upkeep_val || 0),
    hp_bonus: Number(row.hp_bonus || 0),
    gym_bonus: Number(row.gym_bonus || 0),
    vault_capacity: Number(row.vault_capacity || 0),
    asking_price: row.asking_price ? Number(row.asking_price) : 0
});

// 1. FETCH CATALOG
router.get('/catalog', async (req, res) => {
    try {
        const result = await db.query("SELECT * FROM properties_master ORDER BY id ASC");
        const catalog = result.rows.map(formatProp);
        res.status(200).json({ catalog });
    } catch (error) {
        res.status(500).json({ error: "Failed to load real estate catalog." });
    }
});

// 2. FETCH PORTFOLIO & AUTO-ASSIGN TRAILER
router.get('/portfolio/:userId', async (req, res) => {
    try {
        const { userId } = req.params;

        let result = await db.query(
            "SELECT op.id AS instance_id, op.property_type_id, op.status, op.upgrades, pm.name, pm.tier, pm.cost, pm.upkeep_type, pm.upkeep_val, pm.hp_bonus, pm.gym_bonus " +
            "FROM owned_properties op " +
            "JOIN properties_master pm ON op.property_type_id = pm.id " +
            "WHERE op.user_id = $1 ORDER BY op.id ASC",
            [userId]
        );

        // MIGRATION: If user has 0 properties (Older Account), give them a Free Trailer
        if (result.rows.length === 0) {
            await db.query(
                "INSERT INTO owned_properties (user_id, property_type_id, status) VALUES ($1, 1, 'active_residence')",
                [userId]
            );
            result = await db.query(
                "SELECT op.id AS instance_id, op.property_type_id, op.status, op.upgrades, pm.name, pm.tier, pm.cost, pm.upkeep_type, pm.upkeep_val, pm.hp_bonus, pm.gym_bonus " +
                "FROM owned_properties op JOIN properties_master pm ON op.property_type_id = pm.id WHERE op.user_id = $1",
                [userId]
            );
        }

        const portfolio = result.rows.map(formatProp);
        res.status(200).json({ portfolio });
    } catch (error) {
        console.error("Portfolio Fetch Error:", error);
        res.status(500).json({ error: "Internal server error." });
    }
});

// 3. BUY FROM AGENCY (Now supports Move-In Logic)
router.post('/buy-agency', async (req, res) => {
    const { userId, propertyTypeId, autoMoveIn } = req.body;

    try {
        await db.query('BEGIN');

        const catalogCheck = await db.query("SELECT cost FROM properties_master WHERE id = $1", [propertyTypeId]);
        if (catalogCheck.rows.length === 0) throw new Error("Invalid property ID.");
        const cost = Number(catalogCheck.rows[0].cost);

        const userResult = await db.query("SELECT clean_cash FROM users WHERE user_id = $1", [userId]);
        if (Number(userResult.rows[0].clean_cash) < cost) {
            await db.query('ROLLBACK');
            return res.status(400).json({ error: "Insufficient clean cash." });
        }

        await db.query("UPDATE users SET clean_cash = clean_cash - $1 WHERE user_id = $2", [cost, userId]);

        let finalStatus = 'idle';

        // Evict from old residence ONLY if they chose to move in
        if (autoMoveIn) {
            await db.query("UPDATE owned_properties SET status = 'idle' WHERE user_id = $1 AND status = 'active_residence'", [userId]);
            finalStatus = 'active_residence';
        }

        const newProp = await db.query(
            "INSERT INTO owned_properties (user_id, property_type_id, status) VALUES ($1, $2, $3) RETURNING id",
            [userId, propertyTypeId, finalStatus]
        );
        const instanceId = newProp.rows[0].id;

        // AUDIT LOG
        await db.query(
            "INSERT INTO property_transactions (instance_id, seller_id, buyer_id, transaction_type, amount) VALUES ($1, 0, $2, 'AGENCY_BUY', $3)",
            [instanceId, userId, cost]
        );

        await db.query('COMMIT');
        res.status(200).json({ message: "Property purchased successfully.", newInstanceId: instanceId, status: finalStatus });
    } catch (error) {
        await db.query('ROLLBACK');
        console.error("Agency Buy Error:", error);
        res.status(500).json({ error: "Transaction failed." });
    }
});

// 4. UPGRADE ENDPOINT
router.post('/upgrade', async (req, res) => {
    const { userId, instanceId, upgradeId, cost } = req.body;

    try {
        await db.query('BEGIN');

        const userResult = await db.query("SELECT clean_cash FROM users WHERE user_id = $1", [userId]);
        if (Number(userResult.rows[0].clean_cash) < cost) {
            await db.query('ROLLBACK');
            return res.status(400).json({ error: "Insufficient clean cash." });
        }

        const propResult = await db.query("SELECT upgrades FROM owned_properties WHERE id = $1 AND user_id = $2", [instanceId, userId]);
        if (propResult.rows.length === 0) throw new Error("Property not found");

        await db.query("UPDATE users SET clean_cash = clean_cash - $1 WHERE user_id = $2", [cost, userId]);

        const upgradePayload = JSON.stringify({ [upgradeId]: true });
        await db.query("UPDATE owned_properties SET upgrades = upgrades || $1::jsonb WHERE id = $2", [upgradePayload, instanceId]);

        await db.query('COMMIT');
        res.status(200).json({ message: "Upgrade installed successfully." });
    } catch (error) {
        await db.query('ROLLBACK');
        res.status(500).json({ error: "Upgrade transaction failed." });
    }
});

// 5. FETCH PLAYER MARKET
router.get('/market', async (req, res) => {
    try {
        const result = await db.query(`
            SELECT pmkt.id as listing_id, pmkt.listing_type, pmkt.asking_price,
                   u.username as owner_name,
                   pmast.name as prop_name, pmast.tier,
                   op.upgrades
            FROM property_market pmkt
            JOIN users u ON pmkt.seller_id = u.user_id
            JOIN owned_properties op ON pmkt.instance_id = op.id
            JOIN properties_master pmast ON op.property_type_id = pmast.id
            ORDER BY pmkt.created_at DESC
        `);
        const listings = result.rows.map(formatProp);
        res.status(200).json({ listings });
    } catch (error) {
        res.status(500).json({ error: "Failed to load player market." });
    }
});

// 6. MOVE-IN ENDPOINT
router.post('/move-in', async (req, res) => {
    const { userId, instanceId } = req.body;
    try {
        await db.query('BEGIN');
        const check = await db.query("SELECT id FROM owned_properties WHERE id = $1 AND user_id = $2", [instanceId, userId]);
        if (check.rows.length === 0) throw new Error("Unauthorized");

        await db.query("UPDATE owned_properties SET status = 'idle' WHERE user_id = $1 AND status = 'active_residence'", [userId]);
        await db.query("UPDATE owned_properties SET status = 'active_residence' WHERE id = $1", [instanceId]);
        await db.query('COMMIT');
        res.status(200).json({ message: "Moved into new residence." });
    } catch (error) {
        await db.query('ROLLBACK');
        res.status(500).json({ error: "Failed to move in." });
    }
});

module.exports = router;