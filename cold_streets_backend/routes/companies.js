const express = require('express');
const router = express.Router();
// Route parameters are parsed after app-level middleware; enforce actor ownership here.
const { requireOwnedPlayerParam } = require('../middleware/playerIdentity');
router.param('user_id', requireOwnedPlayerParam);

const pool = require('../db');
const { ActionError, integer, dbInteger, actorId, sendActionError } = require('../utils/economyValidation');
const { requireIdempotencyKey, beginIdempotent, completeIdempotent } = require('../utils/idempotency');

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

// --- 2. INCORPORATE ---
// The recovered company type catalog exists, but blueprint_products is empty
// and the legacy products_json text belongs to a different/incomplete generation.
// Do not charge setup cost or create a partially configured company.
router.post('/incorporate', (_req, res) => {
    return res.status(503).json({
        error: 'Company incorporation is paused pending canonical product blueprint recovery.'
    });
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
    let client, transaction = false;
    try {
        const userId = actorId(req);
        const idempotencyKey = requireIdempotencyKey(req);
        const companyId = integer(req.body?.company_id, {
            field: 'Company ID', min: 1n, max: 9223372036854775807n
        }).toString();
        const pitch = typeof req.body?.pitch_message === 'string'
            ? req.body.pitch_message.trim()
            : '';
        if (pitch.length > 2000) {
            throw new ActionError(400, 'Application message is too long.');
        }

        client = await pool.connect();
        await client.query('BEGIN');
        transaction = true;

        const player = await client.query(
            'SELECT current_job_id FROM users WHERE user_id = $1 FOR UPDATE',
            [userId]
        );
        if (player.rowCount !== 1) throw new ActionError(404, 'Player not found.');
        const idem = await beginIdempotent(
            client, userId, 'company.apply', idempotencyKey,
            { companyId, pitch }
        );
        if (idem.replay) {
            await client.query('COMMIT');
            transaction = false;
            return res.status(idem.status).json(idem.response);
        }
        if (player.rows[0].current_job_id !== null) {
            throw new ActionError(409, 'Resign from your City Job before applying to a company.');
        }

        const employed = await client.query(
            `SELECT position_role
               FROM company_employees
              WHERE employee_id = $1 AND is_npc = false
              LIMIT 1`,
            [userId]
        );
        if (employed.rowCount) {
            throw new ActionError(409, 'You are already employed by a company.');
        }

        const company = await client.query(
            'SELECT company_id FROM player_companies WHERE company_id = $1 AND is_active = true',
            [companyId]
        );
        if (company.rowCount !== 1) throw new ActionError(404, 'Company is unavailable.');

        const pending = await client.query(
            `SELECT 1 FROM company_applicants
              WHERE company_id = $1 AND user_id = $2 AND status = 'Pending'
              LIMIT 1`,
            [companyId, userId]
        );
        if (pending.rowCount) {
            throw new ActionError(409, 'Your previous application is still pending.');
        }

        const inserted = await client.query(
            `INSERT INTO company_applicants (company_id, user_id, pitch_message)
             VALUES ($1, $2, $3)
             ON CONFLICT (company_id, user_id)
                 WHERE status = 'Pending'
             DO NOTHING
             RETURNING application_id`,
            [companyId, userId, pitch]
        );
        if (inserted.rowCount !== 1) {
            throw new ActionError(409, 'Your previous application is still pending.');
        }
        const response = {
            success: true,
            message: 'Application submitted to the Director.',
            application_id: inserted.rows[0].application_id
        };
        await completeIdempotent(client, idem, 200, response);
        await client.query('COMMIT');
        transaction = false;
        return res.json(response);
    } catch (err) {
        if (transaction) {
            try { await client.query('ROLLBACK'); }
            catch (rollback) { console.error('Company application rollback:', rollback); }
        }
        return sendActionError(res, err, 'Company application failed:');
    } finally {
        if (client) client.release();
    }
});

module.exports = router;
