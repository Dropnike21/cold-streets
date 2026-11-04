const express = require('express');
const router = express.Router();
// Route parameters are parsed after app-level middleware; enforce actor ownership here.
const { requireOwnedPlayerParam } = require('../middleware/playerIdentity');
router.param('user_id', requireOwnedPlayerParam);

const pool = require('../db');
const { ActionError, integer, dbInteger, actorId, sendActionError } = require('../utils/economyValidation');

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

// --- 2. INCORPORATE: lock wallet; require a fully seeded blueprint.
router.post('/incorporate', async (req, res) => {
    let client, transaction = false;
    try {
        const actor = actorId(req);
        const typeId = integer(req.body?.type_id, { field: 'Company blueprint ID', min: 1n, max: 9223372036854775807n }).toString();
        const name = typeof req.body?.company_name === 'string' ? req.body.company_name.trim() : '';
        if (name.length < 3 || name.length > 80) throw new ActionError(400, 'Company name must contain 3–80 characters.');

        client = await pool.connect();
        await client.query('BEGIN');
        transaction = true;

        const user = await client.query(
            'SELECT dirty_cash, current_job_id FROM users WHERE user_id = $1 FOR UPDATE', [actor]
        );
        if (user.rowCount !== 1) throw new ActionError(404, 'Player not found.');
        if (user.rows[0].current_job_id !== null) {
            throw new ActionError(409, 'Resign from your City Job before incorporating.');
        }
        const employed = await client.query(
            "SELECT 1 FROM company_employees WHERE employee_id = $1 AND is_npc = false AND position_role <> 'Director' LIMIT 1",
            [actor]
        );
        if (employed.rowCount) throw new ActionError(409, 'You are employed at another company.');

        const blueprint = await client.query(
            'SELECT setup_cost FROM company_types_master WHERE type_id = $1', [typeId]
        );
        if (blueprint.rowCount !== 1) throw new ActionError(400, 'Invalid company blueprint.');
        const cost = dbInteger(blueprint.rows[0].setup_cost, { field: 'Company setup cost' });
        if (cost < 0n) throw new Error('Invalid company catalog price.');

        // This relationship data was NOT in the recovered 18-table dump.
        // Never charge setup fees for a company with zero known products.
        const products = await client.query(
            'SELECT 1 FROM blueprint_products WHERE type_id = $1 LIMIT 1', [typeId]
        );
        if (!products.rowCount) throw new ActionError(503, 'Company product blueprint is not yet restored.');

        if (dbInteger(user.rows[0].dirty_cash) < cost) {
            throw new ActionError(409, 'Insufficient Dirty Cash.');
        }
        const debit = await client.query(
            'UPDATE users SET dirty_cash = dirty_cash - $1::numeric WHERE user_id = $2 AND dirty_cash >= $1::numeric RETURNING user_id',
            [cost.toString(), actor]
        );
        if (debit.rowCount !== 1) throw new ActionError(409, 'Wallet changed before incorporation.');

        const company = await client.query(
            'INSERT INTO player_companies (owner_id, type_id, company_name) VALUES ($1, $2, $3) RETURNING company_id',
            [actor, typeId, name]
        );
        const companyId = company.rows[0].company_id;
        await client.query(
            "INSERT INTO company_employees (company_id, employee_id, is_npc, position_role, daily_salary) VALUES ($1, $2, false, 'Director', 0)",
            [companyId, actor]
        );
        await client.query(
            `INSERT INTO company_inventory (company_id, product_id, is_input, quantity, price_per_unit, daily_volume)
             SELECT $1, product_id, is_input, 0, 0, 0 FROM blueprint_products WHERE type_id = $2`,
            [companyId, typeId]
        );
        await client.query('COMMIT');
        transaction = false;
        return res.json({ success: true, message: name + ' incorporated.', company_id: companyId });
    } catch (err) {
        if (transaction) {
            try { await client.query('ROLLBACK'); } catch (rollback) { console.error('Incorporation rollback:', rollback); }
        }
        return sendActionError(res, err, 'Company incorporation failed:');
    } finally { if (client) client.release(); }
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
        res.status(500).json({ error: "Server error fetching your companies." });
    }
});

// --- 4. GET COMPANY DASHBOARD DETAILS ---
router.get('/:company_id/dashboard/:user_id', async (req, res) => {
    try {
        const { company_id, user_id } = req.params;

        const employeeCheck = await pool.query('SELECT position_role FROM company_employees WHERE company_id = $1 AND employee_id = $2 AND is_npc = false', [company_id, user_id]);
        if (employeeCheck.rows.length === 0) return res.status(403).json({ error: "Access Denied." });
        const userRole = employeeCheck.rows[0].position_role;

        const companyRes = await pool.query(`
            SELECT pc.*,
                   u.username AS owner_name,
                   EXTRACT(DAY FROM (NOW() - pc.created_at)) AS age_days,
                   ctm.industry_type, ctm.tier, ctm.daily_upkeep, ctm.base_warehouse_max,
                   CAST(FLOOR(ctm.max_employees * (1 + 0.25 * COALESCE(pc.size_upgrade_level, 0))) AS INT) AS max_employees
            FROM player_companies pc
            JOIN company_types_master ctm ON pc.type_id = ctm.type_id
            LEFT JOIN users u ON pc.owner_id = u.user_id
            WHERE pc.company_id = $1
        `, [company_id]);

        if (companyRes.rows.length === 0) return res.status(404).json({ error: "Company not found." });
        const company = companyRes.rows[0];

        const salaryRes = await pool.query("SELECT SUM(daily_salary) as total_salaries FROM company_employees WHERE company_id = $1", [company_id]);
        const totalSalaries = parseInt(salaryRes.rows[0].total_salaries) || 0;
        const dailyUpkeep = parseInt(company.daily_upkeep) || 0;
        const totalDailyCosts = totalSalaries + dailyUpkeep;

        const totalFunds = parseInt(company.bank_dirty) + parseInt(company.bank_clean);
        const runwayDays = totalDailyCosts > 0 ? (totalFunds / totalDailyCosts).toFixed(1) : 99.9;

        const [rosterRes, logsRes, positionsRes, inventoryRes, shipmentsRes, applicantsRes, specialsRes] = await Promise.all([
            pool.query(`
                SELECT ce.*, u.username, u.level, u.stat_acu, u.stat_ops, u.stat_pre, u.stat_res
                FROM company_employees ce
                LEFT JOIN users u ON ce.employee_id = u.user_id AND ce.is_npc = false
                WHERE ce.company_id = $1
            `, [company_id]),
            pool.query(`SELECT * FROM company_logs WHERE company_id = $1 ORDER BY created_at DESC LIMIT 50`, [company_id]),
            pool.query(`
                SELECT position_id, type_id, role_name AS name, req_stat_primary, req_stat_secondary, stat_gain_desc, description
                FROM company_positions_master WHERE type_id = $1
            `, [company.type_id]),
            pool.query(`
                SELECT ci.*, ci.product_id AS item_id, p.product_name AS item_name
                FROM company_inventory ci
                JOIN company_products_master p ON ci.product_id = p.product_id
                WHERE ci.company_id = $1
            `, [company_id]),
            pool.query(`
                SELECT cs.*, p.product_name AS item_name
                FROM company_shipments cs
                JOIN company_products_master p ON cs.product_id = p.product_id
                WHERE cs.company_id = $1 AND cs.arrival_date > NOW()
            `, [company_id]),
            pool.query(`
                SELECT ca.*, u.username, u.level, u.stat_acu, u.stat_ops, u.stat_pre, u.stat_res
                FROM company_applicants ca
                JOIN users u ON ca.user_id = u.user_id
                WHERE ca.company_id = $1 AND ca.status = 'Pending'
            `, [company_id]),
            pool.query(`
                SELECT special_id, type_id, star_requirement AS star, special_name AS name, effect_description AS effect, jp_cost AS cost, is_passive
                FROM company_specials_master WHERE type_id = $1 ORDER BY star_requirement ASC
            `, [company.type_id])
        ]);

        res.json({
            success: true, user_role: userRole, company: company, runway_days: runwayDays, total_daily_costs: totalDailyCosts,
            roster: rosterRes.rows, logs: logsRes.rows, positions: positionsRes.rows, inventory: inventoryRes.rows,
            shipments: shipmentsRes.rows, applicants: applicantsRes.rows, specials: specialsRes.rows
        });
    } catch (err) { res.status(500).json({ error: "Server error." }); }
});

// --- 5. GET DIRECTORY & APPLY ---
router.get('/directory/types', async (req, res) => {
    try {
        const result = await pool.query(`
            SELECT ctm.type_id, ctm.industry_type, ctm.tier,
                   (SELECT COUNT(*) FROM player_companies pc WHERE pc.type_id = ctm.type_id AND pc.is_active = true) as active_count
            FROM company_types_master ctm ORDER BY ctm.tier ASC, ctm.industry_type ASC
        `);
        res.json({ success: true, types: result.rows });
    } catch (err) { res.status(500).json({ error: "Failed to load corporate directory." }); }
});

router.get('/directory/details/:type_id', async (req, res) => {
    try {
        const { type_id } = req.params;
        const posRes = await pool.query(`SELECT role_name, req_stat_primary, req_stat_secondary, stat_gain_desc, description FROM company_positions_master WHERE type_id = $1 AND role_name != 'Director' ORDER BY position_id ASC`, [type_id]);
        const compRes = await pool.query(`SELECT pc.company_id, pc.company_name, pc.star_rating, pc.daily_income, u.username as owner_name FROM player_companies pc JOIN users u ON pc.owner_id = u.user_id WHERE pc.type_id = $1 AND pc.is_active = true ORDER BY pc.star_rating DESC, pc.daily_income DESC`, [type_id]);
        res.json({ success: true, positions: posRes.rows, companies: compRes.rows });
    } catch (err) { res.status(500).json({ error: "Failed to load industry details." }); }
});

// --- 6. SUBMIT JOB APPLICATION ---
router.post('/apply', async (req, res) => {
    const { company_id, user_id, pitch_message } = req.body;
    try {
        // 1. GATEKEEPER: Ensure they don't have a City Job
        const userCheck = await pool.query('SELECT current_job_id FROM users WHERE user_id = $1', [user_id]);
        if (userCheck.rows[0].current_job_id !== null) {
            return res.status(400).json({ error: "You must resign from your City Job before applying to the private sector." });
        }

        // 2. GATEKEEPER: Ensure they don't work anywhere else (and aren't a Director)
        const empCheck = await pool.query('SELECT position_role FROM company_employees WHERE employee_id = $1 AND is_npc = false', [user_id]);
        if (empCheck.rows.length > 0) {
            const role = empCheck.rows[0].position_role;
            if (role === 'Director') {
                return res.status(400).json({ error: "Directors cannot be employees. You must liquidate your assets or transfer ownership first." });
            } else {
                return res.status(400).json({ error: "You are already employed at another company. Resign before applying here." });
            }
        }

        // 3. Prevent spamming pending applications to the SAME company
        const appCheck = await pool.query("SELECT * FROM company_applicants WHERE company_id = $1 AND user_id = $2 AND status = 'Pending'", [company_id, user_id]);
        if (appCheck.rows.length > 0) return res.status(400).json({ error: "Your previous application is still pending review." });

        await pool.query(`INSERT INTO company_applicants (company_id, user_id, pitch_message) VALUES ($1, $2, $3)`, [company_id, user_id, pitch_message]);
        res.json({ success: true, message: "Application submitted to the Director." });
    } catch (err) {
        res.status(500).json({ error: "Failed to submit application." });
    }
});

module.exports = router;