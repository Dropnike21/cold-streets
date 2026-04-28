const express = require('express');
const router = express.Router();
const pool = require('../db');



/**
 * Calculates Employee Efficiency based on the Cold Streets GDD Formula.
 * Formula: efficiency = FLOOR(MIN(45, (45 / required) * stat) + MAX(0, (5 * LOG(stat / required, 2))))
 *
 * @param {number} playerStat - The player's actual stat value (e.g., 5000 Acumen)
 * @param {number} requiredStat - The role's recommended/required stat to hit 100%
 * @returns {number} Effectiveness percentage (e.g., 112)
 */
function calculateEmployeeEffectiveness(playerStat, requiredStat) {
    // Edge cases for roles with no stat requirements (e.g., Director)
    if (!requiredStat || requiredStat <= 0) return 100;

    // If they have 0 stats, they cannot contribute
    if (!playerStat || playerStat <= 0) return 0;

    // 1. Base Efficiency: Linear scaling up to a hard cap of 45%
    const baseEfficiency = Math.min(45, (45 / requiredStat) * playerStat);

    // 2. Mastery Bonus: Logarithmic scaling for stats exceeding the requirement
    const logBonus = Math.max(0, 5 * Math.log2(playerStat / requiredStat));

    // 3. Final Calculation
    return Math.floor(baseEfficiency + logBonus);
}

// --- 1. GET ALL COMPANY BLUEPRINTS ---
router.get('/blueprints', async (req, res) => {
    try {
        const result = await pool.query('SELECT * FROM company_types_master ORDER BY tier ASC, setup_cost ASC');
        res.json({ success: true, blueprints: result.rows });
    } catch (err) {
        console.error("Error fetching blueprints:", err);
        res.status(500).json({ error: "Server error fetching commercial registry." });
    }
});

// --- 2. INCORPORATE A NEW COMPANY ---
router.post('/incorporate', async (req, res) => {
    const { user_id, type_id, company_name } = req.body;
    const client = await pool.connect();

    try {
        await client.query('BEGIN');

        // Fetch User and Blueprint
        const userRes = await client.query('SELECT dirty_cash FROM users WHERE user_id = $1 FOR UPDATE', [user_id]);
        if (userRes.rows.length === 0) throw new Error("User not found.");

        const bpRes = await client.query('SELECT industry_type, setup_cost FROM company_types_master WHERE type_id = $1', [type_id]);
        if (bpRes.rows.length === 0) throw new Error("Invalid company blueprint.");

        if (!company_name || company_name.trim().length < 3) throw new Error("Invalid company name.");
        if (userRes.rows[0].dirty_cash < bpRes.rows[0].setup_cost) throw new Error("Insufficient funds.");

        // Deduct Cash & Create Company
        await client.query('UPDATE users SET dirty_cash = dirty_cash - $1 WHERE user_id = $2', [bpRes.rows[0].setup_cost, user_id]);

        const insertRes = await client.query(`
            INSERT INTO player_companies (owner_id, type_id, company_name)
            VALUES ($1, $2, $3) RETURNING company_id
        `, [user_id, type_id, company_name.trim()]);
        const newCompanyId = insertRes.rows[0].company_id;

        // Auto-hire the owner as the Director
        await client.query(`INSERT INTO company_employees (company_id, employee_id, is_npc, position_role, daily_salary) VALUES ($1, $2, false, 'Director', 0)`, [newCompanyId, user_id]);

        // NEW: Populate the initial inventory templates based on the blueprint
        await client.query(`
            INSERT INTO company_inventory (company_id, product_id, is_input, quantity, price_per_unit, daily_volume)
            SELECT $1, product_id, is_input, 0, 0, 0
            FROM blueprint_products WHERE type_id = $2
        `, [newCompanyId, type_id]);

        await client.query('COMMIT');
        res.json({ success: true, message: `${company_name.trim()} incorporated.` });

    } catch (err) {
        await client.query('ROLLBACK');
        res.status(400).json({ error: err.message });
    } finally {
        client.release();
    }
});

// --- 3. GET PLAYER'S OWNED COMPANIES ---
router.get('/my-companies/:user_id', async (req, res) => {
    try {
        const { user_id } = req.params;
        const result = await pool.query(`
            SELECT pc.company_id, pc.company_name, pc.star_rating, pc.bank_clean, pc.bank_dirty, pc.is_active,
                   ctm.industry_type, ctm.tier
            FROM player_companies pc
            JOIN company_types_master ctm ON pc.type_id = ctm.type_id
            WHERE pc.owner_id = $1
            ORDER BY pc.created_at DESC
        `, [user_id]);

        res.json({ success: true, companies: result.rows });
    } catch (err) {
        console.error("Error fetching player companies:", err);
        res.status(500).json({ error: "Server error fetching your companies." });
    }
});


// --- 4. GET COMPANY DASHBOARD DETAILS (UPDATED WITH RUNWAY MATH) ---
router.get('/:company_id/dashboard/:user_id', async (req, res) => {
    try {
        const { company_id, user_id } = req.params;

        const employeeCheck = await pool.query('SELECT position_role FROM company_employees WHERE company_id = $1 AND employee_id = $2', [company_id, user_id]);
        if (employeeCheck.rows.length === 0) return res.status(403).json({ error: "Access Denied." });
        const userRole = employeeCheck.rows[0].position_role;

        const companyRes = await pool.query(`
            SELECT pc.*,
                   EXTRACT(DAY FROM (NOW() - pc.created_at)) AS age_days,
                   ctm.industry_type, ctm.tier, ctm.daily_upkeep, ctm.base_warehouse_max,
                   CAST(FLOOR(ctm.max_employees * (1 + 0.25 * COALESCE(pc.size_upgrade_level, 0))) AS INT) AS max_employees
            FROM player_companies pc
            JOIN company_types_master ctm ON pc.type_id = ctm.type_id
            WHERE pc.company_id = $1
        `, [company_id]);

        if (companyRes.rows.length === 0) return res.status(404).json({ error: "Company not found." });
        const company = companyRes.rows[0];

        // 1. Calculate Total Daily Salaries
        const salaryRes = await pool.query("SELECT SUM(daily_salary) as total_salaries FROM company_employees WHERE company_id = $1", [company_id]);
        const totalSalaries = parseInt(salaryRes.rows[0].total_salaries) || 0;
        const dailyUpkeep = parseInt(company.daily_upkeep) || 0;
        const totalDailyCosts = totalSalaries + dailyUpkeep;

        // 2. Calculate Runway (GDD SEC 4.B: Total Funds / Daily Costs)
        const totalFunds = parseInt(company.bank_dirty) + parseInt(company.bank_clean);
        const runwayDays = totalDailyCosts > 0 ? (totalFunds / totalDailyCosts).toFixed(1) : 99.9;

        const [rosterRes, logsRes, positionsRes, inventoryRes, shipmentsRes, applicantsRes, specialsRes] = await Promise.all([
            // ... (keep your existing Promise.all queries here) ...
        ]);

        res.json({
            success: true,
            user_role: userRole,
            company: company,
            runway_days: runwayDays, // NEW
            total_daily_costs: totalDailyCosts, // NEW
            roster: rosterRes.rows,
            logs: logsRes.rows,
            positions: positionsRes.rows,
            inventory: inventoryRes.rows,
            shipments: shipmentsRes.rows,
            applicants: applicantsRes.rows,
            specials: specialsRes.rows
        });
    } catch (err) { res.status(500).json({ error: "Server error." }); }
});



// --- 5. VAULT MANAGEMENT (DEPOSIT / WITHDRAW) ---
router.post('/funds', async (req, res) => {
    const { company_id, user_id, amount, action_type, currency_type } = req.body;
    // action_type: 'deposit' or 'withdraw' | currency_type: 'clean' or 'dirty'
    const client = await pool.connect();

    try {
        await client.query('BEGIN');

        // Ensure Director
        const roleRes = await client.query("SELECT position_role FROM company_employees WHERE company_id=$1 AND employee_id=$2", [company_id, user_id]);
        if (roleRes.rows.length === 0 || roleRes.rows[0].position_role !== 'Director') throw new Error("Only the Director can manage funds.");

        const amt = parseInt(amount);
        if (isNaN(amt) || amt <= 0) throw new Error("Invalid amount.");

        const userCol = currency_type === 'clean' ? 'clean_cash' : 'dirty_cash';
        const corpCol = currency_type === 'clean' ? 'bank_clean' : 'bank_dirty';

        if (action_type === 'deposit') {
            const uCheck = await client.query(`SELECT ${userCol} FROM users WHERE user_id=$1`, [user_id]);
            if (uCheck.rows[0][userCol] < amt) throw new Error("Insufficient personal funds.");

            await client.query(`UPDATE users SET ${userCol} = ${userCol} - $1 WHERE user_id=$2`, [amt, user_id]);
            await client.query(`UPDATE player_companies SET ${corpCol} = ${corpCol} + $1 WHERE company_id=$2`, [amt, company_id]);

            // Log Event
            await client.query(`INSERT INTO company_logs (company_id, log_type, log_text) VALUES ($1, 'FUNDS', $2)`,
                [company_id, `Director deposited $${amt.toLocaleString()} ${currency_type} cash.`]);

        } else if (action_type === 'withdraw') {
            const cCheck = await client.query(`SELECT ${corpCol} FROM player_companies WHERE company_id=$1`, [company_id]);
            if (cCheck.rows[0][corpCol] < amt) throw new Error("Insufficient corporate funds.");

            await client.query(`UPDATE player_companies SET ${corpCol} = ${corpCol} - $1 WHERE company_id=$2`, [amt, company_id]);
            await client.query(`UPDATE users SET ${userCol} = ${userCol} + $1 WHERE user_id=$2`, [amt, user_id]);

            await client.query(`INSERT INTO company_logs (company_id, log_type, log_text) VALUES ($1, 'FUNDS', $2)`,
                [company_id, `Director withdrew $${amt.toLocaleString()} ${currency_type} cash.`]);
        }

        await client.query('COMMIT');
        res.json({ success: true, message: `Vault transfer successful.` });
    } catch (err) {
        await client.query('ROLLBACK');
        res.status(400).json({ error: err.message || "Transfer failed." });
    } finally {
        client.release();
    }
});

// --- 6. EDIT COMPANY PROFILE ---
router.post('/update-profile', async (req, res) => {
    const { company_id, user_id, company_name, logo_url } = req.body;
    try {
        const roleRes = await pool.query("SELECT position_role FROM company_employees WHERE company_id=$1 AND employee_id=$2", [company_id, user_id]);
        if (roleRes.rows.length === 0 || roleRes.rows[0].position_role !== 'Director') return res.status(403).json({ error: "Only the Director can do this." });

        if (!company_name || company_name.trim().length < 3) return res.status(400).json({ error: "Invalid company name." });

        await pool.query(`UPDATE player_companies SET company_name = $1, logo_url = $2 WHERE company_id = $3`, [company_name.trim(), logo_url, company_id]);
        await pool.query(`INSERT INTO company_logs (company_id, log_type, log_text) VALUES ($1, 'MAIN', 'Company profile updated.')`, [company_id]);

        res.json({ success: true, message: "Profile updated successfully." });
    } catch (err) {
        res.status(500).json({ error: "Server error updating profile." });
    }
});

// --- 7. MANAGE EMPLOYEES (UPDATE, FIRE, TRAIN) ---
router.post('/manage-employee', async (req, res) => {
    const { company_id, user_id, target_username, action_type, new_position, new_salary } = req.body;
    const client = await pool.connect();

    try {
        await client.query('BEGIN');

        // Verify Director
        const roleRes = await client.query("SELECT position_role FROM company_employees WHERE company_id=$1 AND employee_id=$2", [company_id, user_id]);
        if (roleRes.rows.length === 0 || roleRes.rows[0].position_role !== 'Director') throw new Error("Only the Director can manage personnel.");

        // Find Target Employee
        const targetRes = await client.query("SELECT user_id FROM users WHERE username = $1", [target_username]);
        if (targetRes.rows.length === 0) throw new Error("Employee not found.");
        const targetId = targetRes.rows[0].user_id;

        if (targetId === user_id) throw new Error("You cannot perform this action on yourself.");

        if (action_type === 'update') {
            await client.query(`UPDATE company_employees SET position_role = $1, daily_salary = $2 WHERE company_id = $3 AND employee_id = $4`,
                [new_position, new_salary, company_id, targetId]);
            await client.query(`INSERT INTO company_logs (company_id, log_type, log_text) VALUES ($1, 'STAFF', $2)`,
                [company_id, `Updated ${target_username}'s contract: ${new_position} at $${new_salary.toLocaleString()}/day.`]);

        } else if (action_type === 'fire') {
            await client.query(`DELETE FROM company_employees WHERE company_id = $1 AND employee_id = $2`, [company_id, targetId]);
            await client.query(`INSERT INTO company_logs (company_id, log_type, log_text) VALUES ($1, 'STAFF', $2)`,
                [company_id, `Terminated employee: ${target_username}.`]);

        } else if (action_type === 'train') {
            // Mock training logic: Cost 1 train, +1% effectiveness
            await client.query(`UPDATE company_employees SET effectiveness_score = LEAST(effectiveness_score + 1, 100) WHERE company_id = $1 AND employee_id = $2`, [company_id, targetId]);
            await client.query(`INSERT INTO company_logs (company_id, log_type, log_text) VALUES ($1, 'TRAINING', $2)`,
                [company_id, `Trained ${target_username}. Effectiveness increased.`]);
        }

        await client.query('COMMIT');
        res.json({ success: true, message: `Successfully executed ${action_type} on ${target_username}.` });
    } catch (err) {
        await client.query('ROLLBACK');
        res.status(400).json({ error: err.message || "Failed to manage employee." });
    } finally {
        client.release();
    }
});

// --- 6. EDIT COMPANY PROFILE ---
router.post('/update-profile', async (req, res) => {
    const { company_id, user_id, company_name, logo_url } = req.body;
    try {
        const roleRes = await pool.query("SELECT position_role FROM company_employees WHERE company_id=$1 AND employee_id=$2", [company_id, user_id]);
        if (roleRes.rows.length === 0 || roleRes.rows[0].position_role !== 'Director') return res.status(403).json({ error: "Only the Director can do this." });

        if (!company_name || company_name.trim().length < 3) return res.status(400).json({ error: "Invalid company name." });

        await pool.query(`UPDATE player_companies SET company_name = $1, logo_url = $2 WHERE company_id = $3`, [company_name.trim(), logo_url, company_id]);
        await pool.query(`INSERT INTO company_logs (company_id, log_type, log_text) VALUES ($1, 'MAIN', 'Company profile updated.')`, [company_id]);

        res.json({ success: true, message: "Profile updated successfully." });
    } catch (err) {
        res.status(500).json({ error: "Server error updating profile." });
    }
});

// --- 7. MANAGE EMPLOYEES (UPDATE, FIRE, TRAIN) ---
router.post('/manage-employee', async (req, res) => {
    const { company_id, user_id, employee_id, is_npc, target_username, action_type, new_position, new_salary } = req.body;
    const client = await pool.connect();

    try {
        await client.query('BEGIN');

        // Verify Director
        const roleRes = await client.query("SELECT position_role FROM company_employees WHERE company_id=$1 AND employee_id=$2", [company_id, user_id]);
        if (roleRes.rows.length === 0 || roleRes.rows[0].position_role !== 'Director') throw new Error("Only the Director can manage personnel.");
        if (employee_id === user_id) throw new Error("You cannot perform this action on yourself.");

        if (action_type === 'update') {
            // NPCs cannot be paid a salary.
            const finalSalary = is_npc ? 0 : (parseInt(new_salary) || 0);

            await client.query(`UPDATE company_employees SET position_role = $1, daily_salary = $2 WHERE company_id = $3 AND employee_id = $4 AND is_npc = $5`,
                [new_position, finalSalary, company_id, employee_id, is_npc]);
            await client.query(`INSERT INTO company_logs (company_id, log_type, log_text) VALUES ($1, 'STAFF', $2)`,
                [company_id, `Updated ${target_username}'s contract: ${new_position} at $${finalSalary.toLocaleString()}/day.`]);

        } else if (action_type === 'fire') {
            await client.query(`DELETE FROM company_employees WHERE company_id = $1 AND employee_id = $2 AND is_npc = $3`, [company_id, employee_id, is_npc]);

            // If they are an NPC, reset their crew assignment status
            if (is_npc) {
                await client.query(`UPDATE user_crew SET assignment = 'Idle' WHERE crew_id = $1`, [employee_id]);
            }

            await client.query(`INSERT INTO company_logs (company_id, log_type, log_text) VALUES ($1, 'STAFF', $2)`,
                [company_id, `Terminated employee: ${target_username}.`]);

        } else if (action_type === 'train') {
            await client.query(`UPDATE company_employees SET effectiveness_score = LEAST(effectiveness_score + 1, 100) WHERE company_id = $1 AND employee_id = $2 AND is_npc = $3`, [company_id, employee_id, is_npc]);
            await client.query(`INSERT INTO company_logs (company_id, log_type, log_text) VALUES ($1, 'TRAINING', $2)`,
                [company_id, `Trained ${target_username}. Effectiveness increased.`]);
        }

        await client.query('COMMIT');
        res.json({ success: true, message: `Successfully executed ${action_type} on ${target_username}.` });
    } catch (err) {
        await client.query('ROLLBACK');
        res.status(400).json({ error: err.message || "Failed to manage employee." });
    } finally {
        client.release();
    }
});

// --- 8. TRANSFER DIRECTORSHIP ---
router.post('/change-director', async (req, res) => {
    const { company_id, user_id, new_director_username } = req.body;
    const client = await pool.connect();

    try {
        await client.query('BEGIN');

        // Verify Current Director
        const roleRes = await client.query("SELECT position_role FROM company_employees WHERE company_id=$1 AND employee_id=$2", [company_id, user_id]);
        if (roleRes.rows.length === 0 || roleRes.rows[0].position_role !== 'Director') throw new Error("Only the Director can transfer ownership.");

        // Find Target User
        const targetRes = await client.query("SELECT user_id FROM users WHERE username = $1", [new_director_username]);
        if (targetRes.rows.length === 0) throw new Error("User not found.");
        const targetId = targetRes.rows[0].user_id;

        // Verify Target is Unassigned Employee
        const empCheck = await client.query("SELECT position_role FROM company_employees WHERE company_id=$1 AND employee_id=$2 AND is_npc=false", [company_id, targetId]);
        if (empCheck.rows.length === 0) throw new Error("The target user must be an employee of this company first.");
        if (empCheck.rows[0].position_role !== 'Unassigned') throw new Error("The target employee must hold the 'Unassigned' role to accept Directorship.");

        // Swap Roles & Owner ID
        await client.query("UPDATE company_employees SET position_role = 'Unassigned', daily_salary = 0 WHERE company_id=$1 AND employee_id=$2", [company_id, user_id]);
        await client.query("UPDATE company_employees SET position_role = 'Director', daily_salary = 0 WHERE company_id=$1 AND employee_id=$2", [company_id, targetId]);
        await client.query("UPDATE player_companies SET owner_id = $1 WHERE company_id = $2", [targetId, company_id]);

        await client.query(`INSERT INTO company_logs (company_id, log_type, log_text) VALUES ($1, 'MAIN', $2)`,
            [company_id, `Directorship officially transferred to ${new_director_username}.`]);

        await client.query('COMMIT');
        res.json({ success: true, message: `You have transferred the company to ${new_director_username}.` });
    } catch (err) {
        await client.query('ROLLBACK');
        res.status(400).json({ error: err.message || "Failed to transfer directorship." });
    } finally {
        client.release();
    }
});

// --- 9. SELL / LIQUIDATE COMPANY ---
router.post('/sell-company', async (req, res) => {
    const { company_id, user_id } = req.body;
    const client = await pool.connect();

    try {
        await client.query('BEGIN');

        // Verify Director
        const roleRes = await client.query("SELECT position_role FROM company_employees WHERE company_id=$1 AND employee_id=$2", [company_id, user_id]);
        if (roleRes.rows.length === 0 || roleRes.rows[0].position_role !== 'Director') throw new Error("Only the Director can liquidate the company.");

        // Calculate Liquidation Value (75% Setup + Vaults)
        const compRes = await client.query(`
            SELECT pc.bank_dirty, pc.bank_clean, ctm.setup_cost
            FROM player_companies pc JOIN company_types_master ctm ON pc.type_id = ctm.type_id
            WHERE pc.company_id=$1
        `, [company_id]);
        const comp = compRes.rows[0];

        const liquidationValue = Math.floor(comp.setup_cost * 0.75) + parseInt(comp.bank_dirty);

        // Payout to User, Set NPCs back to Idle, & Destroy Company
        await client.query("UPDATE users SET dirty_cash = dirty_cash + $1, clean_cash = clean_cash + $2 WHERE user_id=$3", [liquidationValue, parseInt(comp.bank_clean), user_id]);

        const npcRes = await client.query("SELECT employee_id FROM company_employees WHERE company_id=$1 AND is_npc = true", [company_id]);
        for (let row of npcRes.rows) {
            await client.query(`UPDATE user_crew SET assignment = 'Idle' WHERE crew_id = $1`, [row.employee_id]);
        }

        await client.query("DELETE FROM player_companies WHERE company_id = $1", [company_id]);

        await client.query('COMMIT');
        res.json({ success: true, message: `Company liquidated. $${liquidationValue.toLocaleString()} Dirty Cash returned to you.` });
    } catch (err) {
        await client.query('ROLLBACK');
        res.status(400).json({ error: err.message || "Failed to liquidate company." });
    } finally {
        client.release();
    }
});

// --- 10. UPDATE PRICING ---
router.post('/update-pricing', async (req, res) => {
    const { company_id, user_id, item_id, product_price } = req.body;
    try {
        const roleRes = await pool.query("SELECT position_role FROM company_employees WHERE company_id=$1 AND employee_id=$2", [company_id, user_id]);
        if (roleRes.rows.length === 0 || roleRes.rows[0].position_role !== 'Director') return res.status(403).json({ error: "Unauthorized." });

        const price = parseInt(product_price) || 0;
        await pool.query("UPDATE company_inventory SET price_per_unit = $1 WHERE company_id = $2 AND item_id = $3", [price, company_id, item_id]);

        await pool.query(`INSERT INTO company_logs (company_id, log_type, log_text) VALUES ($1, 'MAIN', 'Director updated product pricing to $${price.toLocaleString()}.')`, [company_id]);

        res.json({ success: true, message: "Pricing updated." });
    } catch (err) {
        res.status(500).json({ error: "Failed to update pricing." });
    }
});

// --- 11. ORDER STOCK (UPDATED WITH 20% SYSTEM MARKUP) ---
router.post('/order-stock', async (req, res) => {
    const { company_id, user_id, item_id, order_quantity } = req.body;
    const client = await pool.connect();
    try {
        await client.query('BEGIN');

        // 1. Get base value and calculate 20% System Markup
        const prodRes = await client.query("SELECT base_cost FROM company_products_master WHERE product_id = $1", [item_id]);
        const baseCost = parseInt(prodRes.rows[0].base_cost);
        const systemPrice = Math.floor(baseCost * 1.20); // 20% extra for system orders
        const totalCost = systemPrice * parseInt(order_quantity);

        const compRes = await client.query("SELECT bank_dirty FROM player_companies WHERE company_id=$1 FOR UPDATE", [company_id]);
        if (compRes.rows[0].bank_dirty < totalCost) throw new Error("Insufficient corporate Dirty Cash.");

        await client.query("UPDATE player_companies SET bank_dirty = bank_dirty - $1 WHERE company_id = $2", [totalCost, company_id]);

        await client.query(`
            INSERT INTO company_shipments (company_id, product_id, quantity, total_cost, arrival_date)
            VALUES ($1, $2, $3, $4, NOW() + INTERVAL '1 day')
        `, [company_id, item_id, order_quantity, totalCost]);

        await client.query('COMMIT');
        res.json({ success: true, message: `System Order: $${systemPrice.toLocaleString()}/unit (incl. 20% markup).` });
    } catch (err) {
        await client.query('ROLLBACK');
        res.status(400).json({ error: err.message });
    } finally { client.release(); }
});

// --- 12. UPDATE ADVERTISING ---
router.post('/update-advertising', async (req, res) => {
    const { company_id, user_id, ad_budget } = req.body;
    try {
        const roleRes = await pool.query("SELECT position_role FROM company_employees WHERE company_id=$1 AND employee_id=$2", [company_id, user_id]);
        if (roleRes.rows.length === 0 || roleRes.rows[0].position_role !== 'Director') return res.status(403).json({ error: "Unauthorized." });

        const budget = parseInt(ad_budget) || 0;
        await pool.query("UPDATE player_companies SET advertising_budget = $1 WHERE company_id = $2", [budget, company_id]);
        await pool.query(`INSERT INTO company_logs (company_id, log_type, log_text) VALUES ($1, 'FUNDS', 'Daily advertising budget set to $${budget.toLocaleString()}.')`, [company_id]);

        res.json({ success: true, message: "Advertising budget updated." });
    } catch (err) {
        res.status(500).json({ error: "Failed to update budget." });
    }
});
// --- 13. BUY UPGRADE ---
router.post('/buy-upgrade', async (req, res) => {
    const { company_id, user_id, upgrade_type, cost } = req.body;
    const client = await pool.connect();
    try {
        await client.query('BEGIN');
        const roleRes = await client.query("SELECT position_role FROM company_employees WHERE company_id=$1 AND employee_id=$2", [company_id, user_id]);
        if (roleRes.rows.length === 0 || roleRes.rows[0].position_role !== 'Director') throw new Error("Unauthorized.");

        const compRes = await client.query("SELECT bank_dirty FROM player_companies WHERE company_id=$1", [company_id]);
        if (compRes.rows[0].bank_dirty < cost) throw new Error("Insufficient corporate Dirty Cash.");

        // Deduct cost and apply upgrade
        await client.query("UPDATE player_companies SET bank_dirty = bank_dirty - $1 WHERE company_id = $2", [cost, company_id]);

        if (upgrade_type === 'size') {
            await client.query("UPDATE player_companies SET size_upgrade_level = size_upgrade_level + 1 WHERE company_id = $1", [company_id]);
        } else if (upgrade_type === 'staff') {
            await client.query("UPDATE player_companies SET staff_room_level = staff_room_level + 1 WHERE company_id = $1", [company_id]);
        } else if (upgrade_type === 'warehouse') {
            await client.query("UPDATE player_companies SET warehouse_level = warehouse_level + 1 WHERE company_id = $1", [company_id]);
        }

        await client.query(`INSERT INTO company_logs (company_id, log_type, log_text) VALUES ($1, 'MAIN', 'Purchased company upgrade: ${upgrade_type.toUpperCase()}.')`, [company_id]);

        await client.query('COMMIT');
        res.json({ success: true, message: "Upgrade purchased successfully." });
    } catch (err) {
        await client.query('ROLLBACK');
        res.status(400).json({ error: err.message });
    } finally {
        client.release();
    }
});

// --- 14. FETCH PLAYER'S NPC CREW FOR ASSIGNMENT ---
router.get('/:company_id/available-crew/:user_id', async (req, res) => {
    try {
        const { company_id, user_id } = req.params;
        const crewRes = await pool.query(`
            SELECT crew_id, npc_name, tier, assignment, cur_acu, cur_ops, cur_pre, cur_res
            FROM user_crew
            WHERE user_id = $1
            ORDER BY tier DESC
        `, [user_id]);
        res.json({ success: true, crew: crewRes.rows });
    } catch (err) {
        res.status(500).json({ error: "Failed to fetch crew." });
    }
});

// --- 15. ASSIGN NPC TO COMPANY ---
router.post('/assign-crew', async (req, res) => {
    const { company_id, user_id, crew_id } = req.body;
    const client = await pool.connect();
    try {
        await client.query('BEGIN');
        const compRes = await client.query("SELECT max_employees FROM player_companies c JOIN company_types_master t ON c.type_id = t.type_id WHERE company_id=$1", [company_id]);
        const currentEmps = await client.query("SELECT count(*) as total FROM company_employees WHERE company_id=$1", [company_id]);
        if (parseInt(currentEmps.rows[0].total) >= compRes.rows[0].max_employees) throw new Error("Company is at maximum capacity.");

        // Clear any old assignments and set to Company
        await client.query(`UPDATE user_crew SET assignment = $1 WHERE crew_id = $2 AND user_id = $3`, [`Company: ${company_id}`, crew_id, user_id]);

        // Insert into company (NPCs don't get a salary)
        await client.query(`
            INSERT INTO company_employees (company_id, employee_id, is_npc, position_role, daily_salary, effectiveness_score)
            VALUES ($1, $2, true, 'Unassigned', 0, 100)
        `, [company_id, crew_id]);

        await client.query(`INSERT INTO company_logs (company_id, log_type, log_text) VALUES ($1, 'STAFF', 'Assigned an NPC recruit to the company.')`, [company_id]);

        await client.query('COMMIT');
        res.json({ success: true, message: "NPC Assigned." });
    } catch (err) {
        await client.query('ROLLBACK');
        res.status(400).json({ error: err.message });
    } finally {
        client.release();
    }
});

// --- 16. RECALL NPC FROM COMPANY ---
router.post('/recall-crew', async (req, res) => {
    const { company_id, crew_id } = req.body;
    const client = await pool.connect();
    try {
        await client.query('BEGIN');
        await client.query(`DELETE FROM company_employees WHERE company_id = $1 AND employee_id = $2 AND is_npc = true`, [company_id, crew_id]);
        await client.query(`UPDATE user_crew SET assignment = 'Idle' WHERE crew_id = $1`, [crew_id]);
        await client.query(`INSERT INTO company_logs (company_id, log_type, log_text) VALUES ($1, 'STAFF', 'Recalled an NPC recruit from the company.')`, [company_id]);

        await client.query('COMMIT');
        res.json({ success: true, message: "NPC Recalled." });
    } catch (err) {
        await client.query('ROLLBACK');
        res.status(400).json({ error: err.message });
    } finally {
        client.release();
    }
});

// --- 15. MANAGE APPLICANT ---
router.post('/manage-applicant', async (req, res) => {
    const { company_id, user_id, application_id, target_user_id, action } = req.body;
    // action = 'accept' or 'reject'
    const client = await pool.connect();
    try {
        await client.query('BEGIN');
        const roleRes = await client.query("SELECT position_role FROM company_employees WHERE company_id=$1 AND employee_id=$2", [company_id, user_id]);
        if (roleRes.rows.length === 0 || roleRes.rows[0].position_role !== 'Director') throw new Error("Unauthorized.");

        if (action === 'accept') {
            const compRes = await client.query("SELECT max_employees FROM player_companies c JOIN company_types_master t ON c.type_id = t.type_id WHERE company_id=$1", [company_id]);
            const currentEmps = await client.query("SELECT count(*) as total FROM company_employees WHERE company_id=$1", [company_id]);
            if (parseInt(currentEmps.rows[0].total) >= compRes.rows[0].max_employees) throw new Error("Company is at maximum capacity.");

            // Insert as unassigned, minimum wage
            await client.query(`INSERT INTO company_employees (company_id, employee_id, is_npc, position_role, daily_salary) VALUES ($1, $2, false, 'Unassigned', 0)`, [company_id, target_user_id]);
            await client.query(`UPDATE company_applicants SET status = 'Accepted' WHERE application_id = $1`, [application_id]);
            await client.query(`INSERT INTO company_logs (company_id, log_type, log_text) VALUES ($1, 'STAFF', 'Accepted a new player application.')`, [company_id]);
        } else {
            await client.query(`UPDATE company_applicants SET status = 'Rejected' WHERE application_id = $1`, [application_id]);
        }

        await client.query('COMMIT');
        res.json({ success: true, message: `Applicant ${action}ed.` });
    } catch (err) {
        await client.query('ROLLBACK');
        res.status(400).json({ error: err.message });
    } finally {
        client.release();
    }
});



module.exports = router;