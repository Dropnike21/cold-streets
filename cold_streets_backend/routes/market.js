const express = require('express');
const pool = require('../db');
const router = express.Router();

// 1. GET ALL ITEMS FOR THE MARKET UI
router.get('/list', async (req, res) => {
    try {
        // Reverted to base_value, but keeping the live circulation stat!
        const query = `
            SELECT
                im.*,
                (COALESCE(SUM(ui.quantity), 0) + im.stock) AS circulation
            FROM items_master im
            LEFT JOIN user_inventory ui ON im.item_id = ui.item_id
            GROUP BY im.item_id
            ORDER BY im.base_value ASC
        `;
        const items = await pool.query(query);
        res.json(items.rows);
    } catch (err) {
        console.error("Market Fetch Error:", err.message);
        res.status(500).json({ error: "Failed to load the Black Market." });
    }
});

// 2. BULK BUY ITEMS (Shopping Cart)
router.post('/buy-bulk', async (req, res) => {
    try {
        const { user_id, cart } = req.body;
        if (!cart || cart.length === 0) return res.status(400).json({ error: "Cart is empty." });

        await pool.query('BEGIN');

        const userCheck = await pool.query("SELECT dirty_cash FROM users WHERE user_id = $1", [user_id]);
        if (userCheck.rows.length === 0) throw new Error("Ghost account.");
        const dirtyCash = userCheck.rows[0].dirty_cash;

        let totalCost = 0;
        let totalItemsInCart = 0;

        // Count how many items they are trying to buy right now
        for (let cartItem of cart) {
            totalItemsInCart += cartItem.quantity;
        }

        // --- [TODO: MVP TESTING ONLY - UNCOMMENT FOR PRODUCTION] ---
        // This checks a 'user_purchases' table to see what they bought today
        // const dailyLimitCheck = await pool.query("SELECT COALESCE(SUM(quantity), 0) as daily_bought FROM user_purchases WHERE user_id = $1 AND purchase_date = CURRENT_DATE", [user_id]);
        // const alreadyBoughtToday = parseInt(dailyLimitCheck.rows[0].daily_bought);
        // if (alreadyBoughtToday + totalItemsInCart > 100) {
        //     throw new Error(`Daily purchase limit exceeded. You can only buy ${100 - alreadyBoughtToday} more items today.`);
        // }
        // -----------------------------------------------------------

        for (let cartItem of cart) {
            const itemCheck = await pool.query("SELECT * FROM items_master WHERE item_id = $1", [cartItem.item_id]);
            if (itemCheck.rows.length === 0) throw new Error(`Item missing from database.`);
            const item = itemCheck.rows[0];

            if (item.stock < cartItem.quantity) throw new Error(`Not enough stock for ${item.name}.`);

            // Reverted back to static base_value
            totalCost += (item.base_value * cartItem.quantity);

            await pool.query("UPDATE items_master SET stock = stock - $1 WHERE item_id = $2", [cartItem.quantity, item.item_id]);

            const invCheck = await pool.query("SELECT * FROM user_inventory WHERE user_id = $1 AND item_id = $2", [user_id, item.item_id]);
            if (invCheck.rows.length > 0) {
                await pool.query("UPDATE user_inventory SET quantity = quantity + $1 WHERE user_id = $2 AND item_id = $3", [cartItem.quantity, user_id, item.item_id]);
            } else {
                await pool.query("INSERT INTO user_inventory (user_id, item_id, quantity) VALUES ($1, $2, $3)", [user_id, item.item_id, cartItem.quantity]);
            }

            // --- [TODO: MVP TESTING ONLY - UNCOMMENT FOR PRODUCTION] ---
            // Log the purchase to track daily limits
            // await pool.query("INSERT INTO user_purchases (user_id, item_id, quantity, purchase_date) VALUES ($1, $2, $3, CURRENT_DATE)", [user_id, item.item_id, cartItem.quantity]);
            // -----------------------------------------------------------
        }

        if (dirtyCash < totalCost) throw new Error("Not enough Dirty Cash for this transaction.");

        const updatedUser = await pool.query(
            "UPDATE users SET dirty_cash = dirty_cash - $1 WHERE user_id = $2 RETURNING dirty_cash, energy, nerve, max_nerve, hp",
            [totalCost, user_id]
        );

        await pool.query('COMMIT');

        res.json({ status: "success", message: `Bulk purchase successful! Spent $${totalCost}.`, user: updatedUser.rows[0] });

    } catch (err) {
        await pool.query('ROLLBACK');
        console.error("Bulk Buy Error:", err.message);
        res.status(400).json({ error: err.message || "Transaction failed." });
    }
});

module.exports = router;