const express = require('express');
const cors = require('cors');
const pool = require('./db');

require('dotenv').config();

const app = express();

app.use(cors());
app.use(express.json());

// Check Database Connection
pool.connect()
  .then(() => console.log("🟢 SYSTEM ONLINE: Connected to Cold Streets Database."))
  .catch(err => console.error("🔴 CRITICAL ERROR: Database connection failed.", err.message));

// --- MODULAR ROUTERS ---
const checkPlayerState = require('./utils/stateGatekeeper');

// 🟢 WHITELISTED ROUTES (Can be accessed anywhere)
app.use('/auth', require('./routes/auth'));
app.use('/inventory', require('./routes/inventory')); // Allows using medical/lawyer items
app.use('/info-broker', require('./routes/infoBroker'));
app.use('/cityhall', require('./routes/cityhall'));
app.use('/events', require('./routes/events'));
app.use('/jail', require('./routes/jail'));
app.use('/hospital', require('./routes/hospital'));
app.use('/university', require('./routes/university'));
app.use('/bank', require('./routes/bank'));

// 🛑 THE STATE GATEKEEPER
// Any route placed below this line will be BLOCKED if the player is in Jail or Hospital.
app.use(checkPlayerState);

// 🔴 RESTRICTED ROUTES (Must be free to access)
app.use('/crimes', require('./routes/crimes'));
app.use('/market', require('./routes/market'));
app.use('/syndicate', require('./routes/syndicate'));
app.use('/gym', require('./routes/gym')); // The normal gym
app.use('/jobs', require('./routes/jobs'));
app.use('/companies', require('./routes/companies'));
app.use('/company-management', require('./routes/company_management'));
app.use('/credit-broker', require('./routes/credit_broker'));
app.use('/real-estate', require('./routes/realEstate'));
app.use('/casino', require('./routes/casino')); // This loads the hub!



// Runs every 30 seconds for testing (Change to 5 minutes for production: 5 * 60 * 1000)[cite: 7]
setInterval(async () => {
    try {
        console.log("⏱️ THE VITAL TICK: Regenerating player stats and checking Wardens...");

        // 1. Clear legacy cooldowns (You can eventually phase this table out for core states)
        await pool.query("DELETE FROM user_cooldowns WHERE expires_at <= NOW()");

        // 2. Clear expired Jail/Hospital timers directly in the users table
        await pool.query(`
            UPDATE users
            SET jail_expires_at = NULL, jail_initial_seconds = 0
            WHERE jail_expires_at <= NOW();

            UPDATE users
            SET hospital_expires_at = NULL
            WHERE hospital_expires_at <= NOW();
        `);

        // 3. The Vital Tick: Restore Stats & Calculate Heat Decay
        await pool.query(`
            UPDATE users
            SET
                energy = LEAST(energy + 5, 100),
                nerve = LEAST(nerve + 2, max_nerve),
                hp = LEAST(hp + 10, 100),
                heat = GREATEST(0, heat - CASE
                    WHEN jail_expires_at > NOW() THEN 2.00
                    WHEN last_active_at < NOW() - INTERVAL '5 minutes' THEN 2.00
                    ELSE 1.00
                END)
        `);
    } catch (err) {
        console.error("🔴 CRITICAL WARDEN ERROR:", err.message);
    }
}, 30 * 1000);

// --- THE CARTEL ECONOMY ENGINE (AUTOMATED RESTOCK) ---
// Currently set to 1 minute (60 * 1000) for testing.
// Later, change to (4 * 60 * 60 * 1000) for 4 hours.
setInterval(async () => {
    try {
        const pool = require('./db');

        // 1. Find all items that are running low on the streets
        // We now pull the current stock so we can log it!
        const lowStock = await pool.query("SELECT item_id, name, stock FROM items_master WHERE stock < 100");

        if (lowStock.rows.length > 0) {
            // 2. Shuffle the list to simulate random cartel shipments
            const shuffled = lowStock.rows.sort(() => 0.5 - Math.random());

            // 3. Pick 1 or 2 items randomly to restock
            const numToRestock = Math.min(Math.floor(Math.random() * 2) + 1, shuffled.length);
            const selectedItems = shuffled.slice(0, numToRestock);

            for (let item of selectedItems) {
                // 4. Generate a random shipment size between 2,000 and 5,000 units
                const shipmentSize = Math.floor(Math.random() * (5000 - 2000 + 1)) + 2000;

                // 5. ADD the shipment to the current stock instead of overwriting it!
                await pool.query("UPDATE items_master SET stock = stock + $1 WHERE item_id = $2", [shipmentSize, item.item_id]);

                console.log(`[ECONOMY] 📦 CRATE ARRIVED: Added ${shipmentSize} units of ${item.name}. (Was: ${item.stock} | Now: ${item.stock + shipmentSize})`);
            }
        } else {
            console.log(`[ECONOMY] 📊 Market stable. No shortages detected.`);
        }
    } catch (e) {
        console.error("[ECONOMY ENGINE ERROR]:", e.message);
    }
}, 60 * 1000); // <-- 60,000 ms = 1 minute


// Start Server
const PORT = process.env.PORT || 3000;
app.listen(PORT, () => {
    console.log(`🔌 Node API running on http://localhost:${PORT}`);
});