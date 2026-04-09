const express = require('express');
const pool = require('../db');
const router = express.Router();

// 1. GET PLAYER INVENTORY
router.get('/:user_id', async (req, res) => {
    try {
        const { user_id } = req.params;

        // This query perfectly calculates the dynamic Street Value and Circulation
        const query = `
            SELECT
                ui.inventory_id, ui.quantity, im.*,
                (SELECT COALESCE(SUM(quantity), 0) FROM user_inventory WHERE item_id = im.item_id) + im.stock AS circulation,
                ROUND(im.base_value * (1 + ((im.baseline_stock - im.stock)::numeric / im.baseline_stock) * 0.5)) AS current_value
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

// 2. USE A CONSUMABLE ITEM
router.post('/use', async (req, res) => {
    try {
        const { user_id, item_id } = req.body;

        await pool.query('BEGIN');

        // A. Verify item exists in inventory
        const invCheck = await pool.query("SELECT quantity FROM user_inventory WHERE user_id = $1 AND item_id = $2", [user_id, item_id]);
        if (invCheck.rows.length === 0 || invCheck.rows[0].quantity <= 0) {
            throw new Error("You do not have this item.");
        }

        // B. Get item stats
        const itemCheck = await pool.query("SELECT * FROM items_master WHERE item_id = $1", [item_id]);
        const item = itemCheck.rows[0];

        if (item.category !== 'CONSUMABLES') {
            throw new Error("This item cannot be consumed.");
        }

        // C. Check Cooldown Overlaps (e.g., Can't use 2 Medical items back to back)
        if (item.cooldown_type && item.cooldown_type !== 'none') {
            const cdCheck = await pool.query("SELECT * FROM user_cooldowns WHERE user_id = $1 AND type = $2 AND expires_at > NOW()", [user_id, item.cooldown_type]);
            if (cdCheck.rows.length > 0) {
                throw new Error(`You are already under the effect of a ${item.cooldown_type} cooldown.`);
            }
        }

        // D. Apply Item Effects (HP, Energy, or Nerve)
        let updateQuery = "";
        if (item.stat_modifier === 'MEDICAL') {
            updateQuery = "UPDATE users SET hp = LEAST(hp + $1, 100) WHERE user_id = $2 RETURNING dirty_cash, energy, nerve, max_nerve, hp";
        } else if (item.stat_modifier === 'BOOSTS' && item.name.includes('Energy')) {
            updateQuery = "UPDATE users SET energy = LEAST(energy + $1, 100) WHERE user_id = $2 RETURNING dirty_cash, energy, nerve, max_nerve, hp";
        } else if (item.stat_modifier === 'BOOSTS') {
            updateQuery = "UPDATE users SET nerve = LEAST(nerve + $1, max_nerve) WHERE user_id = $2 RETURNING dirty_cash, energy, nerve, max_nerve, hp";
        }

        const updatedUser = await pool.query(updateQuery, [parseInt(item.description.replace(/[^0-9]/g, '')) || 50, user_id]); // Quick regex to pull number from description for MVP

        // E. Apply Cooldown (If applicable)
        // Hardcoding 60 seconds (1 minute) for testing. Later change to item.cooldown_seconds
        if (item.cooldown_type && item.cooldown_type !== 'none') {
            await pool.query("INSERT INTO user_cooldowns (user_id, type, expires_at) VALUES ($1, $2, NOW() + INTERVAL '1 minute')", [user_id, item.cooldown_type]);
        }

        // F. Deduct Item
        await pool.query("UPDATE user_inventory SET quantity = quantity - 1 WHERE user_id = $1 AND item_id = $2", [user_id, item_id]);

        // Clean up empty rows
        await pool.query("DELETE FROM user_inventory WHERE quantity <= 0");

        await pool.query('COMMIT');

        res.json({
            status: "success",
            message: `Used ${item.name}.`,
            user: updatedUser.rows[0]
        });

    } catch (err) {
        await pool.query('ROLLBACK');
        console.error("Item Use Error:", err.message);
        res.status(400).json({ error: err.message || "Failed to use item." });
    }
});

module.exports = router;