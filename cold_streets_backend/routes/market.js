const express = require('express');
const pool = require('../db');
const router = express.Router();

// --- 1. GET ALL ITEMS FOR THE MARKET UI ---
router.get('/list', async (req, res) => {
    try {
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

// --- 2. BULK BUY ITEMS (Shopping Cart) ---
router.post('/buy-bulk', async (req, res) => {
    // V1.1 FIX: Must use a dedicated client for Transactions, NOT the global pool!
    const client = await pool.connect();

    try {
        const { user_id, cart } = req.body;
        if (!cart || cart.length === 0) return res.status(400).json({ error: "Cart is empty." });

        await client.query('BEGIN');

        // V1.1 FIX: FOR UPDATE lock on the user to prevent rapid-fire macro exploits
        const userCheck = await client.query("SELECT dirty_cash FROM users WHERE user_id = $1 FOR UPDATE", [user_id]);
        if (userCheck.rows.length === 0) throw new Error("Ghost account.");
        const dirtyCash = userCheck.rows[0].dirty_cash;

        let totalCost = 0;
        let totalItemsInCart = 0;

        // V1.1 FIX: Sort cart by item_id to absolutely prevent PostgreSQL Deadlocks
        cart.sort((a, b) => a.item_id - b.item_id);

        // Pre-flight check & totals loop
        for (let cartItem of cart) {
            // V1.1 FIX: Prevent Negative Quantity Exploit
            if (cartItem.quantity < 1) throw new Error("Invalid quantity detected.");
            totalItemsInCart += cartItem.quantity;
        }

        // --- [TODO: MVP TESTING ONLY - UNCOMMENT FOR PRODUCTION] ---
        // const dailyLimitCheck = await client.query("SELECT COALESCE(SUM(quantity), 0) as daily_bought FROM user_purchases WHERE user_id = $1 AND purchase_date = CURRENT_DATE", [user_id]);
        // const alreadyBoughtToday = parseInt(dailyLimitCheck.rows[0].daily_bought);
        // if (alreadyBoughtToday + totalItemsInCart > 100) {
        //     throw new Error(`Daily purchase limit exceeded. You can only buy ${100 - alreadyBoughtToday} more items today.`);
        // }
        // -----------------------------------------------------------

        for (let cartItem of cart) {
            // V1.1 FIX: FOR UPDATE lock on the item to prevent negative stock
            const itemCheck = await client.query("SELECT * FROM items_master WHERE item_id = $1 FOR UPDATE", [cartItem.item_id]);
            if (itemCheck.rows.length === 0) throw new Error(`Item missing from database.`);
            const item = itemCheck.rows[0];

            if (item.stock < cartItem.quantity) throw new Error(`Not enough stock for ${item.name}.`);

            totalCost += (item.base_value * cartItem.quantity);

            // Deduct from Market Stock
            await client.query("UPDATE items_master SET stock = stock - $1 WHERE item_id = $2", [cartItem.quantity, item.item_id]);

            // Add to User Inventory
            const invCheck = await client.query("SELECT * FROM user_inventory WHERE user_id = $1 AND item_id = $2", [user_id, item.item_id]);
            if (invCheck.rows.length > 0) {
                await client.query("UPDATE user_inventory SET quantity = quantity + $1 WHERE user_id = $2 AND item_id = $3", [cartItem.quantity, user_id, item.item_id]);
            } else {
                await client.query("INSERT INTO user_inventory (user_id, item_id, quantity) VALUES ($1, $2, $3)", [user_id, item.item_id, cartItem.quantity]);
            }

            // --- [TODO: MVP TESTING ONLY - UNCOMMENT FOR PRODUCTION] ---
            // await client.query("INSERT INTO user_purchases (user_id, item_id, quantity, purchase_date) VALUES ($1, $2, $3, CURRENT_DATE)", [user_id, item.item_id, cartItem.quantity]);
            // -----------------------------------------------------------
        }

        if (dirtyCash < totalCost) throw new Error("Not enough Dirty Cash for this transaction.");

        // Deduct Cash
        const updatedUser = await client.query(
            "UPDATE users SET dirty_cash = dirty_cash - $1 WHERE user_id = $2 RETURNING dirty_cash, energy, nerve, max_nerve, hp",
            [totalCost, user_id]
        );

        await client.query('COMMIT');

        res.json({ status: "success", message: `Bulk purchase successful! Spent $${totalCost}.`, user: updatedUser.rows[0] });

    } catch (err) {
        await client.query('ROLLBACK');
        console.error("Bulk Buy Error:", err.message);
        res.status(400).json({ error: err.message || "Transaction failed." });
    } finally {
        // ALWAYS release the client back to the pool
        client.release();
    }
});

module.exports = router;