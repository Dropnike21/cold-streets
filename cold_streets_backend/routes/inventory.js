const express = require('express');
const pool = require('../db');
const router = express.Router();

// --- 1. GET PLAYER INVENTORY ---
router.get('/:user_id', async (req, res) => {
    try {
        const { user_id } = req.params;

        // V1.1 Fix: Added GREATEST(..., 1) to strictly enforce the $1 Floor Economy
        const query = `
            SELECT
                ui.inventory_id, ui.quantity, im.*,
                (SELECT COALESCE(SUM(quantity), 0) FROM user_inventory WHERE item_id = im.item_id) + im.stock AS circulation,
                GREATEST(ROUND(im.base_value * (1 + ((im.baseline_stock - im.stock)::numeric / im.baseline_stock) * 0.5)), 1) AS current_value
            FROM user_inventory ui
            JOIN items_master im ON ui.item_id = im.item_id
            WHERE ui.user_id = $1 AND ui.quantity > 0
            ORDER BY im.category ASC, im.name ASC
        `;

        const inventory = await pool.query(query, [user_id]);
        res.json(inventory.rows);
    } catch (err) {
        console.error("Inventory Fetch Error:", err.message);
        res.status(500).json({ error: "Failed to load stash." });
    }
});

// --- 2. USE A CONSUMABLE ITEM ---
// --- 2. USE A CONSUMABLE ITEM (V1.2 JSONB ENGINE) ---
router.post('/use', async (req, res) => {
    const client = await pool.connect();
    try {
        const { user_id, item_id } = req.body;

        await client.query('BEGIN');

        // A. Verify item exists in inventory
        const invCheck = await client.query("SELECT quantity FROM user_inventory WHERE user_id = $1 AND item_id = $2 FOR UPDATE", [user_id, item_id]);
        if (invCheck.rows.length === 0 || invCheck.rows[0].quantity <= 0) {
            throw new Error("You do not have this item.");
        }

        // B. Get Item Stats & Player Data
        const itemCheck = await client.query("SELECT * FROM items_master WHERE item_id = $1", [item_id]);
        const item = itemCheck.rows[0];

        const userCheck = await client.query("SELECT level, hp, energy, nerve, max_nerve FROM users WHERE user_id = $1 FOR UPDATE", [user_id]);
        const user = userCheck.rows[0];

        if (item.category !== 'CONSUMABLES') {
            throw new Error("This item cannot be consumed.");
        }

        // C. Check Cooldown Overlaps
        if (item.cooldown_type && item.cooldown_type !== 'none') {
            const cdCheck = await client.query("SELECT * FROM user_cooldowns WHERE user_id = $1 AND type = $2 AND expires_at > NOW()", [user_id, item.cooldown_type]);
            if (cdCheck.rows.length > 0) {
                throw new Error(`You are already under the effect of a ${item.cooldown_type} cooldown.`);
            }
        }

        // D. UNIVERSAL JSON EFFECT PARSER
        const dynamicMaxHp = 100 + (user.level * 25);
        const MAX_ENERGY = 100;

        // Parse the JSON object from the database (fallback to empty if null)
        const effects = item.effects || {};

        // Calculate new stats, applying limits (Math.max prevents dropping below 1 HP or 0 Energy/Nerve)
        let newHp = user.hp;
        let newEnergy = user.energy;
        let newNerve = user.nerve;

        if (effects.hp) {
            newHp = Math.min(Math.max(newHp + effects.hp, 1), dynamicMaxHp);
        }
        if (effects.energy) {
            newEnergy = Math.min(Math.max(newEnergy + effects.energy, 0), MAX_ENERGY);
        }
        if (effects.nerve) {
            newNerve = Math.min(Math.max(newNerve + effects.nerve, 0), user.max_nerve);
        }

        // Single, clean update query handling all modifications at once
        const updateQuery = "UPDATE users SET hp = $1, energy = $2, nerve = $3 WHERE user_id = $4 RETURNING dirty_cash, energy, nerve, max_nerve, hp";
        const updatedUser = await client.query(updateQuery, [newHp, newEnergy, newNerve, user_id]);

        // E. Apply Dynamic DB Cooldown
        if (item.cooldown_type && item.cooldown_type !== 'none') {
            const cdSeconds = item.cooldown_seconds || 60;
            await client.query("INSERT INTO user_cooldowns (user_id, type, expires_at, reason) VALUES ($1, $2, NOW() + INTERVAL '1 second' * $3, 'Consumable sickness.')", [user_id, item.cooldown_type, cdSeconds]);
        }

        // F. Deduct Item & Cleanup
        await client.query("UPDATE user_inventory SET quantity = quantity - 1 WHERE user_id = $1 AND item_id = $2", [user_id, item_id]);
        await client.query("DELETE FROM user_inventory WHERE user_id = $1 AND quantity <= 0", [user_id]);

        await client.query('COMMIT');

        res.json({
            status: "success",
            message: `Used ${item.name}.`,
            user: updatedUser.rows[0]
        });

    } catch (err) {
        await client.query('ROLLBACK');
        console.error("Item Use Error:", err.message);
        res.status(400).json({ error: err.message || "Failed to use item." });
    } finally {
        client.release();
    }
});

// --- 3. EQUIP WEAPON / ARMOR (NEW) ---
router.post('/equip', async (req, res) => {
    const client = await pool.connect();
    try {
        const { user_id, item_id, slot } = req.body;
        // Valid slots mapping based on your V1.1 Tech Master Database
        const validSlots = ['primary_weapon_id', 'secondary_weapon_id', 'melee_weapon_id', 'armor_id'];

        if (!validSlots.includes(slot)) {
            return res.status(400).json({ error: "Invalid equipment slot." });
        }

        await client.query('BEGIN');

        // A. Verify ownership
        const invCheck = await client.query("SELECT quantity FROM user_inventory WHERE user_id = $1 AND item_id = $2", [user_id, item_id]);
        if (invCheck.rows.length === 0 || invCheck.rows[0].quantity <= 0) {
            throw new Error("You do not own this item.");
        }

        // B. Verify item matches the slot type
        const itemCheck = await client.query("SELECT name, category FROM items_master WHERE item_id = $1", [item_id]);
        const item = itemCheck.rows[0];

        // Sanity checks to prevent putting armor in a gun slot
        if (slot === 'armor_id' && item.category !== 'ARMOR') throw new Error("This is not armor.");
        if (slot === 'primary_weapon_id' && item.category !== 'PRIMARY') throw new Error("This is not a primary weapon.");
        if (slot === 'secondary_weapon_id' && item.category !== 'SECONDARY') throw new Error("This is not a secondary weapon.");
        if (slot === 'melee_weapon_id' && item.category !== 'MELEE') throw new Error("This is not a melee weapon.");

        // C. Equip the item
        await client.query(`UPDATE user_equipment SET ${slot} = $1 WHERE user_id = $2`, [item_id, user_id]);

        await client.query('COMMIT');

        res.json({ status: "success", message: `Equipped ${item.name}.` });

    } catch (err) {
        await client.query('ROLLBACK');
        console.error("Equip Error:", err.message);
        res.status(400).json({ error: err.message || "Failed to equip item." });
    } finally {
        client.release();
    }
});

module.exports = router;