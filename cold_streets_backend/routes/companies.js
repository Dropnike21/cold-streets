const express = require('express');
const router = express.Router();
const pool = require('../db');

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

        // 1. Fetch User and Blueprint
        const userRes = await client.query('SELECT dirty_cash FROM users WHERE user_id = $1 FOR UPDATE', [user_id]);
        if (userRes.rows.length === 0) throw new Error("User not found.");
        const user = userRes.rows[0];

        const bpRes = await client.query('SELECT industry_type, setup_cost FROM company_types_master WHERE type_id = $1', [type_id]);
        if (bpRes.rows.length === 0) throw new Error("Invalid company blueprint.");
        const blueprint = bpRes.rows[0];

        // 2. Enforce Name Rules
        if (!company_name || company_name.trim().length < 3 || company_name.trim().length > 30) {
            throw new Error("Company name must be between 3 and 30 characters.");
        }

        // 3. Check Funds
        if (user.dirty_cash < blueprint.setup_cost) {
            throw new Error(`Insufficient funds. You need $${blueprint.setup_cost.toLocaleString()} Dirty Cash to open a ${blueprint.industry_type}.`);
        }

        // 4. Deduct Cash & Create Company
        await client.query('UPDATE users SET dirty_cash = dirty_cash - $1 WHERE user_id = $2', [blueprint.setup_cost, user_id]);

        const insertRes = await client.query(`
            INSERT INTO player_companies (owner_id, type_id, company_name)
            VALUES ($1, $2, $3) RETURNING company_id
        `, [user_id, type_id, company_name.trim()]);

        const newCompanyId = insertRes.rows[0].company_id;

        // 5. Auto-hire the owner as the Director
        await client.query(`
            INSERT INTO company_employees (company_id, employee_id, is_npc, position_role, daily_salary)
            VALUES ($1, $2, false, 'Director', 0)
        `, [newCompanyId, user_id]);

        await client.query('COMMIT');
        res.json({ success: true, message: `Congratulations. ${company_name.trim()} is now a registered enterprise. Access your dashboard from your Hub.` });

    } catch (err) {
        await client.query('ROLLBACK');
        console.error(err);
        res.status(400).json({ error: err.message || "Server error processing incorporation." });
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
// --- 4. GET COMPANY DASHBOARD DETAILS ---
router.get('/:company_id/dashboard/:user_id', async (req, res) => {
    try {
        const { company_id, user_id } = req.params;

        // 1. Verify the user actually works here (Security Check)
        const employeeCheck = await pool.query('SELECT position_role FROM company_employees WHERE company_id = $1 AND employee_id = $2', [company_id, user_id]);
        if (employeeCheck.rows.length === 0) {
            return res.status(403).json({ error: "Access Denied. You do not work for this enterprise." });
        }
        const userRole = employeeCheck.rows[0].position_role;

        // 2. Fetch Core Company & Blueprint Data
        const companyRes = await pool.query(`
            SELECT pc.*, ctm.industry_type, ctm.tier, ctm.daily_upkeep, ctm.base_warehouse_max, ctm.max_employees
            FROM player_companies pc
            JOIN company_types_master ctm ON pc.type_id = ctm.type_id
            WHERE pc.company_id = $1
        `, [company_id]);

        if (companyRes.rows.length === 0) return res.status(404).json({ error: "Company not found." });
        const company = companyRes.rows[0];

        // 3. Fetch Roster (Join with users table to get real usernames)
        const rosterRes = await pool.query(`
            SELECT ce.position_id, ce.position_role, ce.daily_salary, ce.effectiveness_score, ce.days_employed,
                   u.username, u.level
            FROM company_employees ce
            LEFT JOIN users u ON ce.employee_id = u.user_id AND ce.is_npc = false
            WHERE ce.company_id = $1
            ORDER BY ce.position_id ASC
        `, [company_id]);

        res.json({
            success: true,
            user_role: userRole,
            company: company,
            roster: rosterRes.rows
        });

    } catch (err) {
        console.error("Error fetching company dashboard:", err);
        res.status(500).json({ error: "Server error fetching enterprise data." });
    }
});


module.exports = router;