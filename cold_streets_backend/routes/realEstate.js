const express = require('express');
const router = express.Router();
// Reject URLs referencing any player other than the verified session owner.
const { requireOwnedPlayerParam } = require('../middleware/playerIdentity');
router.param('userId', requireOwnedPlayerParam);

const db = require('../db');
const { ActionError, integer, dbInteger, actorId, sendActionError } = require('../utils/economyValidation');

// Legacy catalog stores upgrades as restricted object-like TEXT, not JSON.
// Extract only a whitelisted upgrade key's server-defined integer cost.
// No eval, Function, broad pseudo-JSON rewriting, or client price is allowed.
function upgradeCost(source, upgradeId) {
    if (typeof source !== 'string' || !/^[a-z][a-z0-9_]{0,63}$/.test(upgradeId)) {
        throw new ActionError(400, 'Unknown property upgrade.');
    }
    const entries = [...source.matchAll(/([a-z][a-z0-9_]*)\s*:\s*\{([^{}]*)\}/g)];
    const found = entries.filter(match => match[1] === upgradeId);
    if (found.length !== 1) throw new ActionError(400, 'Upgrade is not available for this property.');
    const costField = found[0][2].match(/(?:^|,)\s*cost\s*:\s*([0-9]+)\s*(?:,|$)/);
    if (!costField) throw new ActionError(503, 'Upgrade catalog price is unavailable.');
    return integer(costField[1], { field: 'Catalog upgrade cost', min: 1n });
}
 

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

        // Do not grant free property on a GET request. Signup creates the
        // starter property transactionally. Older accounts require a separate
        // idempotent and verified migration, never an unbounded read-trigger.

        const portfolio = result.rows.map(formatProp);
        res.status(200).json({ portfolio });
    } catch (error) {
        console.error("Portfolio Fetch Error:", error);
        res.status(500).json({ error: "Internal server error." });
    }
});

// 3. AGENCY PURCHASE: catalog price and user wallet are authoritative.
router.post('/buy-agency', async (req, res) => {
    let client, transaction = false;
    try {
        const userId = actorId(req);
        const propertyTypeId = integer(req.body?.propertyTypeId, { field: 'Property ID', min: 1n, max: 9223372036854775807n }).toString();
        if (typeof req.body?.autoMoveIn !== 'boolean') {
            throw new ActionError(400, 'autoMoveIn must be a boolean.');
        }

        client = await db.connect();
        await client.query('BEGIN');
        transaction = true;
        const user = await client.query(
            'SELECT clean_cash FROM users WHERE user_id = $1 FOR UPDATE', [userId]
        );
        if (user.rowCount !== 1) throw new ActionError(404, 'Player not found.');

        const item = await client.query('SELECT cost FROM properties_master WHERE id = $1', [propertyTypeId]);
        if (item.rowCount !== 1) throw new ActionError(400, 'Property not listed by agency.');
        const cost = dbInteger(item.rows[0].cost, { field: 'Property catalog price' });
        // Zero-cost starter home is granted exactly once through profile creation.
        if (cost <= 0n) throw new ActionError(400, 'Starter properties cannot be purchased again.');
        if (dbInteger(user.rows[0].clean_cash) < cost) {
            throw new ActionError(409, 'Insufficient clean cash.');
        }

        const debit = await client.query(
            'UPDATE users SET clean_cash = clean_cash - $1::numeric WHERE user_id = $2 AND clean_cash >= $1::numeric RETURNING clean_cash',
            [cost.toString(), userId]
        );
        if (debit.rowCount !== 1) throw new ActionError(409, 'Balance changed before purchase.');

        if (req.body.autoMoveIn) {
            await client.query(
                "UPDATE owned_properties SET status = 'idle' WHERE user_id = $1 AND status = 'active_residence'",
                [userId]
            );
        }
        const finalStatus = req.body.autoMoveIn ? 'active_residence' : 'idle';
        const property = await client.query(
            'INSERT INTO owned_properties (user_id, property_type_id, status) VALUES ($1, $2, $3) RETURNING id',
            [userId, propertyTypeId, finalStatus]
        );
        const instanceId = property.rows[0].id;
        await client.query(
            "INSERT INTO property_transactions (instance_id, seller_id, buyer_id, transaction_type, amount) VALUES ($1, 0, $2, 'AGENCY_BUY', $3::numeric)",
            [instanceId, userId, cost.toString()]
        );
        await client.query('COMMIT');
        transaction = false;
        return res.json({ message: 'Property purchased successfully.', newInstanceId: instanceId, status: finalStatus });
    } catch (error) {
        if (transaction) {
            try { await client.query('ROLLBACK'); } catch (rollback) { console.error('Agency rollback failed:', rollback); }
        }
        return sendActionError(res, error, 'Agency purchase failed:');
    } finally {
        if (client) client.release();
    }
});

// 4. PROPERTY UPGRADE: never trust req.body.cost.
router.post('/upgrade', async (req, res) => {
    let client, transaction = false;
    try {
        const userId = actorId(req);
        const instanceId = integer(req.body?.instanceId, { field: 'Property instance ID', min: 1n, max: 9223372036854775807n }).toString();
        const upgradeId = req.body?.upgradeId;

        client = await db.connect();
        await client.query('BEGIN');
        transaction = true;
        const user = await client.query('SELECT clean_cash FROM users WHERE user_id = $1 FOR UPDATE', [userId]);
        if (user.rowCount !== 1) throw new ActionError(404, 'Player not found.');

        const property = await client.query(
            `SELECT op.upgrades, pm.available_upgrades_json
             FROM owned_properties op
             JOIN properties_master pm ON op.property_type_id = pm.id
             WHERE op.id = $1 AND op.user_id = $2 FOR UPDATE OF op`,
            [instanceId, userId]
        );
        if (property.rowCount !== 1) throw new ActionError(404, 'Property not owned by player.');

        const installed = property.rows[0].upgrades || {};
        if (Object.prototype.hasOwnProperty.call(installed, upgradeId) && installed[upgradeId]) {
            throw new ActionError(409, 'Upgrade already installed.');
        }
        const cost = upgradeCost(property.rows[0].available_upgrades_json, upgradeId);
        if (dbInteger(user.rows[0].clean_cash) < cost) {
            throw new ActionError(409, 'Insufficient clean cash.');
        }
        const debit = await client.query(
            'UPDATE users SET clean_cash = clean_cash - $1::numeric WHERE user_id = $2 AND clean_cash >= $1::numeric RETURNING user_id',
            [cost.toString(), userId]
        );
        if (debit.rowCount !== 1) throw new ActionError(409, 'Balance changed before upgrade.');
        await client.query(
            'UPDATE owned_properties SET upgrades = upgrades || jsonb_build_object($1::text, true) WHERE id = $2 AND user_id = $3',
            [upgradeId, instanceId, userId]
        );
        await client.query('COMMIT');
        transaction = false;
        return res.json({ message: 'Upgrade installed successfully.', charged: cost.toString() });
    } catch (error) {
        if (transaction) {
            try { await client.query('ROLLBACK'); } catch (rollback) { console.error('Upgrade rollback failed:', rollback); }
        }
        return sendActionError(res, error, 'Property upgrade failed:');
    } finally {
        if (client) client.release();
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

// 6. MOVE IN: lock the account and verify instance ownership.
router.post('/move-in', async (req, res) => {
    let client, transaction = false;
    try {
        const userId = actorId(req);
        const instanceId = integer(req.body?.instanceId, { field: 'Property instance ID', min: 1n, max: 9223372036854775807n }).toString();
        client = await db.connect();
        await client.query('BEGIN');
        transaction = true;
        const user = await client.query('SELECT user_id FROM users WHERE user_id = $1 FOR UPDATE', [userId]);
        if (user.rowCount !== 1) throw new ActionError(404, 'Player not found.');
        const property = await client.query(
            'SELECT id FROM owned_properties WHERE id = $1 AND user_id = $2 FOR UPDATE',
            [instanceId, userId]
        );
        if (property.rowCount !== 1) throw new ActionError(404, 'Property not owned by player.');
        await client.query(
            "UPDATE owned_properties SET status = 'idle' WHERE user_id = $1 AND status = 'active_residence'",
            [userId]
        );
        const moved = await client.query(
            "UPDATE owned_properties SET status = 'active_residence' WHERE id = $1 AND user_id = $2 RETURNING id",
            [instanceId, userId]
        );
        if (moved.rowCount !== 1) throw new Error('Property could not be activated.');
        await client.query('COMMIT');
        transaction = false;
        return res.json({ message: 'Moved into new residence.' });
    } catch (error) {
        if (transaction) {
            try { await client.query('ROLLBACK'); } catch (rollback) { console.error('Move-in rollback failed:', rollback); }
        }
        return sendActionError(res, error, 'Property move-in failed:');
    } finally {
        if (client) client.release();
    }
});

module.exports = router;
