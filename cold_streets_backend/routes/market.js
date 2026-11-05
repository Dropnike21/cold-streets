const express = require('express');
const pool = require('../db');
const router = express.Router();
const { ActionError, integer, dbInteger, exactJsonAmount, actorId, sendActionError } = require('../utils/economyValidation');
const { requireIdempotencyKey, beginIdempotent, completeIdempotent } = require('../utils/idempotency');
const { refreshUniqueItemDiscoveryAchievements } = require('../utils/achievement_engine');
const {
    BASE_CITY_MARKET_DAILY_ITEM_LIMIT,
    SUBSCRIBER_CITY_MARKET_BONUS_PERCENT,
    SUBSCRIBER_CITY_MARKET_DAILY_ITEM_LIMIT,
    getPremiumStatus
} = require('../utils/premiumEntitlements');

const MAX_CITY_MARKET_DAILY_ITEM_LIMIT =
    SUBSCRIBER_CITY_MARKET_DAILY_ITEM_LIMIT;

// --- HELPER: Fix pgAdmin's stripped JSON strings ---
// This handles ANY key name and ANY string value dynamically
function fixMalformedEffects(str) {
    // If it's empty, null, or already an object, return an empty object
    if (!str || str === '{}' || typeof str !== 'string') return {};

    try {
        // Step 1: Find any text right before a colon and wrap it in quotes.
        // This catches ranged_damage, accuracy, heal_amount, anything.
        let fixedStr = str.replace(/([{,]\s*)([a-zA-Z0-9_]+)\s*:/g, '$1"$2":');

        // Step 2: Look at the values after the colons.
        fixedStr = fixedStr.replace(/:\s*([^,}\s]+)/g, (match, val) => {
            // If the value is a number (45) or a boolean (true/false), leave it alone.
            if (!isNaN(val) || val === 'true' || val === 'false') return `: ${val}`;

            // Otherwise, it's a string (like 7.62_short), so wrap it in quotes.
            return `: "${val}"`;
        });

        // Parse it into a perfect JavaScript object
        return JSON.parse(fixedStr);
    } catch (e) {
        console.error("Regex fix failed on string:", str);
        return {}; // Failsafe: return empty stats if something goes horribly wrong
    }
}

// --- CITY NPC MARKET DAILY USAGE ---
// The recovered source defines a 100-item base daily cap for city NPC markets.
// User-defined Subscriber semantics add +20%, producing a 120-item effective
// cap while the subscription period is active. CURRENT_DATE remains the
// deterministic database calendar-day boundary.
router.get('/status', async (req, res) => {
    try {
        const userId = actorId(req);
        const [usage, premium] = await Promise.all([
            pool.query(
            `SELECT CURRENT_DATE::text AS day_key,
                    COALESCE(SUM(quantity), 0)::bigint AS purchased_today
               FROM user_purchases
              WHERE user_id = $1
                AND purchase_source = 'city_market'
                AND purchase_date >= CURRENT_DATE
                AND purchase_date < CURRENT_DATE + INTERVAL '1 day'`,
            [userId]
            ),
            getPremiumStatus(pool, userId)
        ]);
        const dailyLimit = premium.effectiveBenefits.cityMarketDailyItemLimit;
        const purchased = dbInteger(
            usage.rows[0].purchased_today,
            { field: 'City market daily purchases' }
        );
        if (purchased < 0n || purchased > dailyLimit) {
            throw new Error('City market daily purchase ledger is outside the source limit.');
        }
        return res.json({
            success: true,
            day_key: usage.rows[0].day_key,
            reset_boundary: 'database_calendar_day',
            base_daily_item_limit:
                exactJsonAmount(BASE_CITY_MARKET_DAILY_ITEM_LIMIT),
            subscriber_bonus_percent:
                exactJsonAmount(SUBSCRIBER_CITY_MARKET_BONUS_PERCENT),
            subscriber_active: premium.subscriberActive,
            daily_item_limit: exactJsonAmount(dailyLimit),
            purchased_today: exactJsonAmount(purchased),
            remaining_today: exactJsonAmount(dailyLimit - purchased),
            player_bazaar_limit_status: 'unlimited_by_source'
        });
    } catch (err) {
        return sendActionError(res, err, 'Market status failed:');
    }
});

// --- 1. GET ALL ITEMS FOR THE MARKET UI ---
router.get('/list', async (req, res) => {
    try {
        // V1.5 FIX: Safer Subquery to avoid GROUP BY crashes, and added the 'city_market' filter!
        const query = `
            SELECT
                im.*,
                (COALESCE(ui_sum.total_qty, 0) + im.stock) AS circulation
            FROM items_master im
            LEFT JOIN (
                SELECT item_id, SUM(quantity) as total_qty
                FROM user_inventory
                GROUP BY item_id
            ) ui_sum ON im.item_id = ui_sum.item_id
            WHERE im.source = 'city_market'
            ORDER BY im.base_value ASC
        `;
        const items = await pool.query(query);

        // Map over the results and clean the effects column on the fly
        const cleanedItems = items.rows.map(item => {
            item.effects = fixMalformedEffects(item.effects);
            return item;
        });

        res.json(cleanedItems);
    } catch (err) {
        // This will print the EXACT reason to your Node terminal if it fails again
        console.error("Market Fetch Error:", err.message);
        res.status(500).json({ error: "Failed to load the Market." });
    }
});

// --- 2. BULK BUY ITEMS ---
// One transaction and one database client cover money, stock, inventory
// and audit rows. The server alone determines item eligibility and prices.
router.post('/buy-bulk', async (req, res) => {
    let userId, entries;
    try {
        userId = actorId(req);
        const idempotencyKey = requireIdempotencyKey(req);
        const cart = req.body?.cart;
        if (!Array.isArray(cart) ||
            cart.length < 1 ||
            BigInt(cart.length) > MAX_CITY_MARKET_DAILY_ITEM_LIMIT) {
            throw new ActionError(
                400,
                'Cart line count exceeds the maximum supported daily market allowance.'
            );
        }
        const seen = new Set();
        let totalQty = 0n;
        entries = cart.map(raw => {
            if (!raw || typeof raw !== 'object' || Array.isArray(raw)) {
                throw new ActionError(400, 'Invalid cart line.');
            }
            const itemId = integer(raw.item_id, { field: 'Item ID', min: 1n, max: 9223372036854775807n }).toString();
            const qty = integer(raw.quantity, {
                field: 'Quantity',
                min: 1n,
                max: MAX_CITY_MARKET_DAILY_ITEM_LIMIT
            });
            if (seen.has(itemId)) throw new ActionError(400, 'Duplicate items in cart.');
            seen.add(itemId);
            totalQty += qty;
            if (totalQty > MAX_CITY_MARKET_DAILY_ITEM_LIMIT) {
                throw new ActionError(
                    400,
                    'A city-market cart exceeds the maximum supported daily allowance.'
                );
            }
            return { itemId, qty };
        }).sort((a, b) => a.itemId.length - b.itemId.length || a.itemId.localeCompare(b.itemId));
    } catch (error) {
        return sendActionError(res, error, 'Invalid market cart:');
    }

    let client, active = false;
    try {
        client = await pool.connect();
        await client.query('BEGIN');
        active = true;

        const wallet = await client.query(
            'SELECT dirty_cash FROM users WHERE user_id = $1 FOR UPDATE', [userId]
        );
        if (wallet.rowCount !== 1) throw new ActionError(404, 'Player not found.');
        const balance = dbInteger(wallet.rows[0].dirty_cash);
        const premium = await getPremiumStatus(client, userId);
        const dailyLimit = premium.effectiveBenefits.cityMarketDailyItemLimit;

        // The player wallet lock serializes all city-market buys for this user,
        // so the daily audit sum cannot be raced by a concurrent cart.
        const dailyUsage = await client.query(
            `SELECT COALESCE(SUM(quantity), 0)::bigint AS purchased_today
               FROM user_purchases
              WHERE user_id = $1
                AND purchase_source = 'city_market'
                AND purchase_date >= CURRENT_DATE
                AND purchase_date < CURRENT_DATE + INTERVAL '1 day'`,
            [userId]
        );
        const purchasedToday = dbInteger(
            dailyUsage.rows[0].purchased_today,
            { field: 'City market daily purchases' }
        );
        if (purchasedToday < 0n ||
            purchasedToday > dailyLimit) {
            throw new Error(
                'City market daily purchase ledger is outside the source limit.'
            );
        }
        if (purchasedToday + totalQty > dailyLimit) {
            throw new ActionError(
                409,
                'City NPC market daily limit exceeded. ' +
                    (dailyLimit - purchasedToday).toString() +
                    ' item(s) remain today.'
            );
        }

        const idem = await beginIdempotent(
            client, userId, 'market.buy_bulk', idempotencyKey,
            { cart: entries.map(line => ({ itemId: line.itemId, quantity: line.qty.toString() })) }
        );
        if (idem.replay) {
            await client.query('COMMIT');
            active = false;
            return res.status(idem.status).json(idem.response);
        }
        let totalCost = 0n;
        const selected = [];

        // Lock item rows in deterministic order after locking the player.
        for (const line of entries) {
            const result = await client.query(
                'SELECT item_id, name, source, base_value, stock FROM items_master WHERE item_id = $1 FOR UPDATE',
                [line.itemId]
            );
            if (result.rowCount !== 1 || result.rows[0].source !== 'city_market') {
                throw new ActionError(400, 'This item is not sold at the city market.');
            }
            const item = result.rows[0];
            const price = dbInteger(item.base_value, { field: 'Item price' });
            const stock = dbInteger(item.stock, { field: 'Item stock' });
            if (price < 0n) throw new Error('Catalog has a negative item price.');
            if (stock < line.qty) throw new ActionError(409, 'Market stock is insufficient for ' + item.name + '.');
            const lineCost = price * line.qty;
            totalCost += lineCost;
            if (totalCost > 999999999999999999999999n) throw new ActionError(400, 'Cart exceeds maximum transaction value.');
            selected.push(line);
        }
        if (balance < totalCost) throw new ActionError(409, 'Not enough Dirty Cash.');

        const debit = await client.query(
            'UPDATE users SET dirty_cash = dirty_cash - $1::numeric WHERE user_id = $2 AND dirty_cash >= $1::numeric RETURNING dirty_cash, energy, nerve, max_nerve, hp',
            [totalCost.toString(), userId]
        );
        if (debit.rowCount !== 1) throw new ActionError(409, 'Balance changed before purchase.');

        for (const line of selected) {
            const stockUpdate = await client.query(
                'UPDATE items_master SET stock = stock - $1::bigint WHERE item_id = $2 AND stock >= $1::bigint RETURNING item_id',
                [line.qty.toString(), line.itemId]
            );
            if (stockUpdate.rowCount !== 1) throw new ActionError(409, 'Market stock changed before purchase.');
            await client.query(
                `INSERT INTO user_inventory (user_id, item_id, quantity)
                 VALUES ($1, $2, $3::bigint)
                 ON CONFLICT (user_id, item_id) DO UPDATE
                   SET quantity = user_inventory.quantity + EXCLUDED.quantity`,
                [userId, line.itemId, line.qty.toString()]
            );
            await client.query(
                'INSERT INTO user_purchases (user_id, item_id, quantity, purchase_source) VALUES ($1, $2, $3::bigint, \'city_market\')',
                [userId, line.itemId, line.qty.toString()]
            );
        }

        const uniqueItemsFound = await refreshUniqueItemDiscoveryAchievements(
            client,
            userId
        );

        const response = {
            status: 'success',
            message: 'Bulk purchase successful. Spent ' +
                totalCost.toString() + '.',
            total_cost: exactJsonAmount(totalCost),
            base_daily_item_limit:
                exactJsonAmount(BASE_CITY_MARKET_DAILY_ITEM_LIMIT),
            subscriber_bonus_percent:
                exactJsonAmount(SUBSCRIBER_CITY_MARKET_BONUS_PERCENT),
            subscriber_active: premium.subscriberActive,
            daily_item_limit: exactJsonAmount(dailyLimit),
            purchased_today: exactJsonAmount(purchasedToday + totalQty),
            remaining_today: exactJsonAmount(
                dailyLimit - purchasedToday - totalQty
            ),
            reset_boundary: 'database_calendar_day',
            unique_items_found: exactJsonAmount(
                dbInteger(uniqueItemsFound, { field: 'Unique item discoveries' })
            ),
            user: debit.rows[0]
        };
        await completeIdempotent(client, idem, 200, response);
        await client.query('COMMIT');
        active = false;
        return res.status(200).json(response);
    } catch (error) {
        if (active) {
            try {
                await client.query('ROLLBACK');
            } catch (rollbackError) {
                console.error('Market rollback failed:', rollbackError);
            }
        }
        return sendActionError(res, error, 'Market purchase failed:');
    } finally {
        if (client) client.release();
    }
});

module.exports = router;
