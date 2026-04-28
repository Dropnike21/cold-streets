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
app.use('/auth', require('./routes/auth'));
app.use('/crimes', require('./routes/crimes'));
app.use('/market', require('./routes/market'));
app.use('/inventory', require('./routes/inventory'));
app.use('/syndicate', require('./routes/syndicate'));
app.use('/gym', require('./routes/gym'));
app.use('/achievements', require('./routes/achievements'));
app.use('/events', require('./routes/events'));
app.use('/credit-broker', require('./routes/credit_broker'));
app.use('/jobs', require('./routes/jobs'));
app.use('/cityhall', require('./routes/cityhall'));
app.use('/companies', require('./routes/companies'));


// --- THE VITAL TICK & WARDEN (Cron Job) ---
// Runs checks for bankruptcy and processes sales
setInterval(async () => {
    try {
        console.log("🏢 CORPORATE TICK: Checking Runway and Processing Sales...");

        // 1. Bankruptcy Check (GDD SEC 4.B)
        // If (Bank Funds / Daily Costs) < 1.0, and it's the payout time, deactivate the company.
        // For now, we flag companies with 0 funds.
        await pool.query(`
            UPDATE player_companies
            SET is_active = false
            WHERE (bank_dirty + bank_clean) <= 0 AND is_active = true
        `);

        // 2. Sales & Laundering Simulation
        // For every active company, simulate 5-10 system customers buying 1 unit of their output.
        // This converts potential value into direct Clean Cash.
        const companies = await pool.query("SELECT company_id, product_price FROM player_companies WHERE is_active = true");

        for (let comp of companies.rows) {
            const customers = Math.floor(Math.random() * 5) + 1; // 1-5 sales per tick for testing
            const price = parseInt(comp.product_price) || 100;
            const revenue = Math.floor((customers * price) * 0.90); // 10% "Legitimacy Tax"

            // Move revenue directly to CLEAN bank
            await pool.query(`
                UPDATE player_companies
                SET bank_clean = bank_clean + $1
                WHERE company_id = $2
            `, [revenue, comp.company_id]);
        }
    } catch (err) { console.error("🔴 CORPORATE TICK ERROR:", err.message); }
}, 60 * 1000 * 60); // Set to 1 hour for testing, later 24 hours.
// Runs every 1 minute for testing (Change to 5 minutes for production: 5 * 60 * 1000)
setInterval(async () => {
    try {
        console.log("⏱️ THE VITAL TICK: Regenerating player stats and checking Wardens...");

        // 1. The Warden: Clear expired cooldowns (Hospital/Jail)
        await pool.query("DELETE FROM user_cooldowns WHERE expires_at <= NOW()");

        // 2. The Vital Tick: Restore 10 Energy, 2 Nerve, and 10 HP globally (up to caps)
        await pool.query(`
            UPDATE users
            SET
                energy = LEAST(energy + 5, 100),
                nerve = LEAST(nerve + 2, max_nerve),
                hp = LEAST(hp + 10, 100)
        `);
    } catch (err) {
        console.error("🔴 CRITICAL WARDEN ERROR:", err.message);
    }
}, 30 * 1000); // 1 minute interval


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