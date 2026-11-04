const express = require('express');
const router = express.Router();
// Route parameters are parsed after app-level middleware; enforce actor ownership here.
const { requireOwnedPlayerParam } = require('../middleware/playerIdentity');
router.param('user_id', requireOwnedPlayerParam);

const pool = require('../db');
const { ActionError, integer, dbInteger, actorId, sendActionError } = require('../utils/economyValidation');
const { requireIdempotencyKey, beginIdempotent, completeIdempotent } = require('../utils/idempotency');

// Central actor/company ownership check. The original route checks allowed
// some company_id operations with no director authorization at all.
const pausedManagementActions = new Set([
    '/manage-employee', '/change-director', '/sell-company',
    '/buy-upgrade', '/manage-applicant'
]);
router.use(async (req, res, next) => {
    if (req.method !== 'POST') return next();
    try {
        const actor = actorId(req);
        const companyId = integer(req.body?.company_id, {
            field: 'Company ID', min: 1n, max: 9223372036854775807n
        }).toString();
        const allowed = await pool.query(
            `SELECT 1 FROM player_companies pc
             JOIN company_employees ce ON ce.company_id = pc.company_id
             WHERE pc.company_id = $1 AND pc.owner_id = $2
               AND ce.employee_id = $2 AND ce.is_npc = false
               AND ce.position_role = 'Director'`,
            [companyId, actor]
        );
        if (allowed.rowCount !== 1) {
            throw new ActionError(403, 'Only the current company owner/director may manage it.');
        }
        req.managedCompanyId = companyId;
        if (pausedManagementActions.has(req.path)) {
            throw new ActionError(503, 'This management action is paused pending a server-authoritative rules audit.');
        }
        return next();
    } catch (err) {
        return sendActionError(res, err, 'Company authorization:');
    }
});


// --- 1. VAULT MANAGEMENT: exact money, owner row lock, atomic transfer.
router.post('/funds', async (req, res) => {
    let client, transaction = false;
    try {
        const actor = actorId(req);
        const idempotencyKey = requireIdempotencyKey(req);
        const companyId = req.managedCompanyId;
        const { action_type: action, currency_type: currency } = req.body || {};
        if (!['deposit', 'withdraw'].includes(action) || !['clean', 'dirty'].includes(currency)) {
            throw new ActionError(400, 'Invalid company transfer action or currency.');
        }
        const amount = integer(req.body?.amount, { field: 'Transfer amount', min: 1n });
        const userColumn = currency === 'clean' ? 'clean_cash' : 'dirty_cash';
        const companyColumn = currency === 'clean' ? 'bank_clean' : 'bank_dirty';

        client = await pool.connect();
        await client.query('BEGIN');
        transaction = true;
        // Always lock actor BEFORE company; consistent with incorporation.
        const user = await client.query(
            'SELECT clean_cash, dirty_cash FROM users WHERE user_id = $1 FOR UPDATE', [actor]
        );
        if (user.rowCount !== 1) throw new ActionError(404, 'Player not found.');
        const idem = await beginIdempotent(
            client, actor, 'company.vault_transfer', idempotencyKey,
            { companyId, action, currency, amount: amount.toString() }
        );
        if (idem.replay) {
            await client.query('COMMIT');
            transaction = false;
            return res.status(idem.status).json(idem.response);
        }
        const company = await client.query(
            'SELECT owner_id, bank_clean, bank_dirty FROM player_companies WHERE company_id = $1 FOR UPDATE',
            [companyId]
        );
        if (company.rowCount !== 1 || String(company.rows[0].owner_id) !== actor) {
            throw new ActionError(403, 'Company ownership changed.');
        }
        const sourceBalance = action === 'deposit'
            ? dbInteger(user.rows[0][userColumn])
            : dbInteger(company.rows[0][companyColumn]);
        if (sourceBalance < amount) throw new ActionError(409, 'Insufficient funds.');

        if (action === 'deposit') {
            const debit = await client.query(
                'UPDATE users SET ' + userColumn + ' = ' + userColumn +
                ' - $1::numeric WHERE user_id = $2 AND ' + userColumn + ' >= $1::numeric RETURNING user_id',
                [amount.toString(), actor]
            );
            if (debit.rowCount !== 1) throw new ActionError(409, 'Player wallet changed.');
            await client.query(
                'UPDATE player_companies SET ' + companyColumn + ' = ' + companyColumn +
                ' + $1::numeric WHERE company_id = $2',
                [amount.toString(), companyId]
            );
        } else {
            const debit = await client.query(
                'UPDATE player_companies SET ' + companyColumn + ' = ' + companyColumn +
                ' - $1::numeric WHERE company_id = $2 AND ' + companyColumn +
                ' >= $1::numeric RETURNING company_id',
                [amount.toString(), companyId]
            );
            if (debit.rowCount !== 1) throw new ActionError(409, 'Company vault changed.');
            await client.query(
                'UPDATE users SET ' + userColumn + ' = ' + userColumn +
                ' + $1::numeric WHERE user_id = $2',
                [amount.toString(), actor]
            );
        }
        await client.query(
            "INSERT INTO company_logs (company_id, log_type, log_text) VALUES ($1, 'FUNDS', $2)",
            [companyId, 'Director ' + (action === 'deposit' ? 'deposited ' : 'withdrew ') +
                amount.toString() + ' ' + currency + ' cash.']
        );
        const response = { success: true, message: 'Vault transfer successful.' };
        await completeIdempotent(client, idem, 200, response);
        await client.query('COMMIT');
        transaction = false;
        return res.json(response);
    } catch (err) {
        if (transaction) {
            try { await client.query('ROLLBACK'); } catch (rollback) { console.error('Company vault rollback:', rollback); }
        }
        return sendActionError(res, err, 'Company vault failed:');
    } finally { if (client) client.release(); }
});

// --- 2. EDIT COMPANY PROFILE ---
router.post('/update-profile', async (req, res) => {
    const { company_id, user_id, company_name, logo_url } = req.body;
    try {
        const roleRes = await pool.query("SELECT position_role FROM company_employees WHERE company_id=$1 AND employee_id=$2", [company_id, user_id]);
        if (roleRes.rows.length === 0 || roleRes.rows[0].position_role !== 'Director') return res.status(403).json({ error: "Only the Director can do this." });
        if (!company_name || company_name.trim().length < 3) return res.status(400).json({ error: "Invalid company name." });

        await pool.query(`UPDATE player_companies SET company_name = $1, logo_url = $2 WHERE company_id = $3`, [company_name.trim(), logo_url, company_id]);
        await pool.query(`INSERT INTO company_logs (company_id, log_type, log_text) VALUES ($1, 'MAIN', 'Company profile updated.')`, [company_id]);
        res.json({ success: true, message: "Profile updated successfully." });
    } catch (err) { res.status(500).json({ error: "Server error updating profile." }); }
});

// --- 3. MANAGE EMPLOYEES (UPDATE, FIRE, TRAIN) ---
router.post('/manage-employee', async (req, res) => {
    const { company_id, user_id, employee_id, is_npc, target_username, action_type, new_position, new_salary } = req.body;
    const client = await pool.connect();
    try {
        await client.query('BEGIN');
        const roleRes = await client.query("SELECT position_role FROM company_employees WHERE company_id=$1 AND employee_id=$2", [company_id, user_id]);
        if (roleRes.rows.length === 0 || roleRes.rows[0].position_role !== 'Director') throw new Error("Only the Director can manage personnel.");
        if (employee_id === user_id) throw new Error("You cannot perform this action on yourself.");

        if (action_type === 'update') {
            const finalSalary = is_npc ? 0 : (parseInt(new_salary) || 0);
            await client.query(`UPDATE company_employees SET position_role = $1, daily_salary = $2 WHERE company_id = $3 AND employee_id = $4 AND is_npc = $5`, [new_position, finalSalary, company_id, employee_id, is_npc]);
            await client.query(`INSERT INTO company_logs (company_id, log_type, log_text) VALUES ($1, 'STAFF', $2)`, [company_id, `Updated ${target_username}'s contract: ${new_position} at $${finalSalary.toLocaleString()}/day.`]);
        } else if (action_type === 'fire') {
            await client.query(`DELETE FROM company_employees WHERE company_id = $1 AND employee_id = $2 AND is_npc = $3`, [company_id, employee_id, is_npc]);
            if (is_npc) await client.query(`UPDATE user_crew SET assignment = 'Idle' WHERE crew_id = $1`, [employee_id]);
            await client.query(`INSERT INTO company_logs (company_id, log_type, log_text) VALUES ($1, 'STAFF', $2)`, [company_id, `Terminated employee: ${target_username}.`]);
        } else if (action_type === 'train') {
            await client.query(`UPDATE company_employees SET effectiveness_score = LEAST(effectiveness_score + 1, 100) WHERE company_id = $1 AND employee_id = $2 AND is_npc = $3`, [company_id, employee_id, is_npc]);
            await client.query(`INSERT INTO company_logs (company_id, log_type, log_text) VALUES ($1, 'TRAINING', $2)`, [company_id, `Trained ${target_username}. Effectiveness increased.`]);
        }
        await client.query('COMMIT');
        res.json({ success: true, message: `Successfully executed ${action_type} on ${target_username}.` });
    } catch (err) {
        await client.query('ROLLBACK');
        res.status(400).json({ error: err.message || "Failed to manage employee." });
    } finally { client.release(); }
});

// --- 4. TRANSFER DIRECTORSHIP ---
router.post('/change-director', async (req, res) => {
    const { company_id, user_id, new_director_username } = req.body;
    const client = await pool.connect();
    try {
        await client.query('BEGIN');
        const roleRes = await client.query("SELECT position_role FROM company_employees WHERE company_id=$1 AND employee_id=$2", [company_id, user_id]);
        if (roleRes.rows.length === 0 || roleRes.rows[0].position_role !== 'Director') throw new Error("Only the Director can transfer ownership.");

        const targetRes = await client.query("SELECT user_id FROM users WHERE username = $1", [new_director_username]);
        if (targetRes.rows.length === 0) throw new Error("User not found.");
        const targetId = targetRes.rows[0].user_id;

        const empCheck = await client.query("SELECT position_role FROM company_employees WHERE company_id=$1 AND employee_id=$2 AND is_npc=false", [company_id, targetId]);
        if (empCheck.rows.length === 0) throw new Error("The target user must be an employee of this company first.");
        if (empCheck.rows[0].position_role !== 'Unassigned') throw new Error("The target employee must hold the 'Unassigned' role to accept Directorship.");

        await client.query("UPDATE company_employees SET position_role = 'Unassigned', daily_salary = 0 WHERE company_id=$1 AND employee_id=$2", [company_id, user_id]);
        await client.query("UPDATE company_employees SET position_role = 'Director', daily_salary = 0 WHERE company_id=$1 AND employee_id=$2", [company_id, targetId]);
        await client.query("UPDATE player_companies SET owner_id = $1 WHERE company_id = $2", [targetId, company_id]);
        await client.query(`INSERT INTO company_logs (company_id, log_type, log_text) VALUES ($1, 'MAIN', $2)`, [company_id, `Directorship officially transferred to ${new_director_username}.`]);
        await client.query('COMMIT');
        res.json({ success: true, message: `You have transferred the company to ${new_director_username}.` });
    } catch (err) {
        await client.query('ROLLBACK');
        res.status(400).json({ error: err.message || "Failed to transfer directorship." });
    } finally { client.release(); }
});

// --- 5. SELL / LIQUIDATE COMPANY ---
router.post('/sell-company', async (req, res) => {
    const { company_id, user_id } = req.body;
    const client = await pool.connect();
    try {
        await client.query('BEGIN');
        const roleRes = await client.query("SELECT position_role FROM company_employees WHERE company_id=$1 AND employee_id=$2", [company_id, user_id]);
        if (roleRes.rows.length === 0 || roleRes.rows[0].position_role !== 'Director') throw new Error("Only the Director can liquidate the company.");

        const compRes = await client.query(`
            SELECT pc.bank_dirty, pc.bank_clean, ctm.setup_cost
            FROM player_companies pc JOIN company_types_master ctm ON pc.type_id = ctm.type_id
            WHERE pc.company_id=$1
        `, [company_id]);
        const comp = compRes.rows[0];
        const liquidationValue = Math.floor(comp.setup_cost * 0.75) + parseInt(comp.bank_dirty);

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
    } finally { client.release(); }
});

// --- 6. UPDATE PRICING: exact non-negative integer and known inventory.
router.post('/update-pricing', async (req, res) => {
    try {
        const companyId = req.managedCompanyId;
        const productId = integer(req.body?.item_id, { field: 'Product ID', min: 1n, max: 9223372036854775807n }).toString();
        const price = integer(req.body?.product_price, { field: 'Product price', min: 0n, max: 1000000000000n });
        const changed = await pool.query(
            'UPDATE company_inventory SET price_per_unit = $1::numeric WHERE company_id = $2 AND product_id = $3 RETURNING product_id',
            [price.toString(), companyId, productId]
        );
        if (!changed.rowCount) throw new ActionError(404, 'Product not in company inventory.');
        await pool.query(
            "INSERT INTO company_logs (company_id, log_type, log_text) VALUES ($1, 'MAIN', $2)",
            [companyId, 'Director set product ' + productId + ' price to ' + price.toString() + '.']
        );
        return res.json({ success: true, message: 'Pricing updated.' });
    } catch (err) { return sendActionError(res, err, 'Company pricing error:'); }
});

// --- 7. ORDER STOCK: only blueprint products, server price, owner funds.
router.post('/order-stock', async (req, res) => {
    let client, transaction = false;
    try {
        const actor = actorId(req);
        const idempotencyKey = requireIdempotencyKey(req);
        const companyId = req.managedCompanyId;
        const productId = integer(req.body?.item_id, { field: 'Product ID', min: 1n, max: 9223372036854775807n }).toString();
        const quantity = integer(req.body?.order_quantity, { field: 'Order quantity', min: 1n, max: 100000n });

        client = await pool.connect();
        await client.query('BEGIN');
        transaction = true;
        const player = await client.query(
            'SELECT user_id FROM users WHERE user_id = $1 FOR UPDATE', [actor]
        );
        if (player.rowCount !== 1) throw new ActionError(404, 'Player not found.');
        const idem = await beginIdempotent(
            client, actor, 'company.order_stock', idempotencyKey,
            { companyId, productId, quantity: quantity.toString() }
        );
        if (idem.replay) {
            await client.query('COMMIT');
            transaction = false;
            return res.status(idem.status).json(idem.response);
        }
        const company = await client.query(
            'SELECT owner_id, type_id, bank_dirty, is_active FROM player_companies WHERE company_id = $1 FOR UPDATE',
            [companyId]
        );
        if (company.rowCount !== 1 || String(company.rows[0].owner_id) !== actor) {
            throw new ActionError(403, 'Company ownership changed.');
        }
        if (!company.rows[0].is_active) throw new ActionError(409, 'Company is inactive.');

        // These blueprint associations have not been recovered from the old
        // database. Fail closed until this source is reliably reconstructed.
        const allowed = await client.query(
            'SELECT 1 FROM blueprint_products WHERE type_id = $1 AND product_id = $2 AND is_input = true',
            [company.rows[0].type_id, productId]
        );
        if (!allowed.rowCount) throw new ActionError(503, 'Company blueprint inventory is not configured.');

        const product = await client.query(
            'SELECT base_cost FROM company_products_master WHERE product_id = $1',
            [productId]
        );
        if (!product.rowCount) throw new ActionError(400, 'Product not listed.');
        const base = dbInteger(product.rows[0].base_cost, { field: 'System product cost' });
        if (base < 0n) throw new Error('Invalid product catalog price.');
        const unitCost = base * 120n / 100n; // Existing 20% supplier markup, rounded down.
        const total = unitCost * quantity;
        if (total > 999999999999999999999999n) throw new ActionError(400, 'Order exceeds database limit.');
        if (dbInteger(company.rows[0].bank_dirty) < total) throw new ActionError(409, 'Insufficient company Dirty Cash.');

        const debited = await client.query(
            'UPDATE player_companies SET bank_dirty = bank_dirty - $1::numeric WHERE company_id = $2 AND bank_dirty >= $1::numeric RETURNING company_id',
            [total.toString(), companyId]
        );
        if (debited.rowCount !== 1) throw new ActionError(409, 'Company funds changed during order.');
        await client.query(
            "INSERT INTO company_shipments (company_id, product_id, quantity, total_cost, arrival_date) VALUES ($1, $2, $3::bigint, $4::numeric, NOW() + INTERVAL '1 day')",
            [companyId, productId, quantity.toString(), total.toString()]
        );
        await client.query(
            "INSERT INTO company_logs (company_id, log_type, log_text) VALUES ($1, 'STOCK', $2)",
            [companyId, 'Ordered ' + quantity.toString() + ' units of product ' + productId + '.']
        );
        const response = { success: true, message: 'System order placed.' };
        await completeIdempotent(client, idem, 200, response);
        await client.query('COMMIT');
        transaction = false;
        return res.json(response);
    } catch (err) {
        if (transaction) {
            try { await client.query('ROLLBACK'); } catch (rollback) { console.error('Stock order rollback:', rollback); }
        }
        return sendActionError(res, err, 'Company stock order failed:');
    } finally { if (client) client.release(); }
});

// --- 8. UPDATE ADVERTISING: validate server-side budget limit.
router.post('/update-advertising', async (req, res) => {
    try {
        const companyId = req.managedCompanyId;
        const budget = integer(req.body?.ad_budget, { field: 'Advertising budget', min: 0n, max: 1000000000000n });
        const updated = await pool.query(
            'UPDATE player_companies SET advertising_budget = $1::numeric WHERE company_id = $2 RETURNING company_id',
            [budget.toString(), companyId]
        );
        if (!updated.rowCount) throw new ActionError(404, 'Company no longer exists.');
        await pool.query(
            "INSERT INTO company_logs (company_id, log_type, log_text) VALUES ($1, 'FUNDS', $2)",
            [companyId, 'Daily advertising budget set to ' + budget.toString() + '.']
        );
        return res.json({ success: true, message: 'Advertising budget updated.' });
    } catch (err) { return sendActionError(res, err, 'Company advertising error:'); }
});

// --- 9. BUY UPGRADE ---
router.post('/buy-upgrade', async (req, res) => {
    const { company_id, user_id, upgrade_type, cost } = req.body;
    const client = await pool.connect();
    try {
        await client.query('BEGIN');
        const roleRes = await client.query("SELECT position_role FROM company_employees WHERE company_id=$1 AND employee_id=$2", [company_id, user_id]);
        if (roleRes.rows.length === 0 || roleRes.rows[0].position_role !== 'Director') throw new Error("Unauthorized.");

        const compRes = await client.query("SELECT bank_dirty FROM player_companies WHERE company_id=$1", [company_id]);
        if (compRes.rows[0].bank_dirty < cost) throw new Error("Insufficient corporate Dirty Cash.");

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
    } finally { client.release(); }
});

// --- 10. FETCH NPC CREW ---
router.get('/:company_id/available-crew/:user_id', async (req, res) => {
    try {
        const { user_id } = req.params;
        const crewRes = await pool.query(`SELECT crew_id, npc_name, tier, assignment, cur_acu, cur_ops, cur_pre, cur_res FROM user_crew WHERE user_id = $1 ORDER BY tier DESC`, [user_id]);
        res.json({ success: true, crew: crewRes.rows });
    } catch (err) { res.status(500).json({ error: "Failed to fetch crew." }); }
});

// --- 11. ASSIGN NPC ---
router.post('/assign-crew', async (req, res) => {
    const { company_id, crew_id } = req.body || {};
    const actingUserId = req.player.userId; // verified Supabase identity
    const client = await pool.connect();
    try {
        await client.query('BEGIN');
        const director = await client.query(
            `SELECT 1 FROM company_employees
             WHERE company_id = $1 AND employee_id = $2
               AND is_npc = false AND position_role = 'Director'`,
            [company_id, actingUserId]
        );
        if (director.rowCount !== 1) throw new Error('Only the company director can assign recruits.');

        const company = await client.query(
            `SELECT t.max_employees
             FROM player_companies c
             JOIN company_types_master t ON c.type_id = t.type_id
             WHERE c.company_id = $1 FOR UPDATE OF c`,
            [company_id]
        );
        if (company.rowCount !== 1) throw new Error('Company not found.');

        const staff = await client.query(
            'SELECT count(*) AS total FROM company_employees WHERE company_id = $1',
            [company_id]
        );
        if (Number(staff.rows[0].total) >= Number(company.rows[0].max_employees)) {
            throw new Error('Company is at maximum capacity.');
        }

        // Recruit ownership and assignment state are checked under a row lock.
        // Never trust a client-supplied user_id for this operation.
        const crew = await client.query(
            'SELECT crew_id, assignment FROM user_crew WHERE crew_id = $1 AND user_id = $2 FOR UPDATE',
            [crew_id, actingUserId]
        );
        if (crew.rowCount !== 1) throw new Error('Recruit not found or not yours.');
        if (!['Idle', 'UNASSIGNED', 'Unassigned'].includes(crew.rows[0].assignment)) {
            throw new Error('Recruit is already assigned.');
        }

        await client.query(
            'UPDATE user_crew SET assignment = $1 WHERE crew_id = $2 AND user_id = $3',
            [`Company: ${company_id}`, crew_id, actingUserId]
        );
        await client.query(
            `INSERT INTO company_employees
             (company_id, employee_id, is_npc, position_role, daily_salary, effectiveness_score)
             VALUES ($1, $2, true, 'Unassigned', 0, 100)`,
            [company_id, crew_id]
        );
        await client.query(
            `INSERT INTO company_logs (company_id, log_type, log_text)
             VALUES ($1, 'STAFF', 'Assigned an NPC recruit to the company.')`,
            [company_id]
        );
        await client.query('COMMIT');
        return res.json({ success: true, message: 'NPC assigned.' });
    } catch (err) {
        await client.query('ROLLBACK');
        return res.status(400).json({ error: err.message || 'Recruit assignment failed.' });
    } finally {
        client.release();
    }
});

// --- 12. RECALL NPC ---
// Only the director can recall a recruit *owned by that director*, and only
// from the specified company. Do not update unrelated players' recruits.
router.post('/recall-crew', async (req, res) => {
    const { company_id, crew_id } = req.body || {};
    const actingUserId = req.player.userId;
    const client = await pool.connect();
    try {
        await client.query('BEGIN');
        const director = await client.query(
            `SELECT 1 FROM company_employees
             WHERE company_id = $1 AND employee_id = $2
               AND is_npc = false AND position_role = 'Director'`,
            [company_id, actingUserId]
        );
        if (director.rowCount !== 1) throw new Error('Only the company director can recall recruits.');

        const ownedCrew = await client.query(
            'SELECT crew_id FROM user_crew WHERE crew_id = $1 AND user_id = $2 FOR UPDATE',
            [crew_id, actingUserId]
        );
        if (ownedCrew.rowCount !== 1) throw new Error('Recruit not found or not yours.');

        const removed = await client.query(
            `DELETE FROM company_employees
             WHERE company_id = $1 AND employee_id = $2 AND is_npc = true
             RETURNING employee_id`,
            [company_id, crew_id]
        );
        if (removed.rowCount !== 1) throw new Error('Recruit is not assigned to that company.');

        await client.query(
            `UPDATE user_crew SET assignment = 'Idle'
             WHERE crew_id = $1 AND user_id = $2`,
            [crew_id, actingUserId]
        );
        await client.query(
            `INSERT INTO company_logs (company_id, log_type, log_text)
             VALUES ($1, 'STAFF', 'Recalled an NPC recruit from the company.')`,
            [company_id]
        );
        await client.query('COMMIT');
        return res.json({ success: true, message: 'NPC recalled.' });
    } catch (err) {
        await client.query('ROLLBACK');
        return res.status(400).json({ error: err.message || 'Recruit recall failed.' });
    } finally {
        client.release();
    }
});

// --- 13. MANAGE APPLICANT ---
router.post('/manage-applicant', async (req, res) => {
    const { company_id, user_id, application_id, target_user_id, action } = req.body;
    const client = await pool.connect();
    try {
        await client.query('BEGIN');
        const roleRes = await client.query("SELECT position_role FROM company_employees WHERE company_id=$1 AND employee_id=$2", [company_id, user_id]);
        if (roleRes.rows.length === 0 || roleRes.rows[0].position_role !== 'Director') throw new Error("Unauthorized.");

        if (action === 'accept') {
            const compRes = await client.query("SELECT max_employees FROM player_companies c JOIN company_types_master t ON c.type_id = t.type_id WHERE company_id=$1", [company_id]);
            const currentEmps = await client.query("SELECT count(*) as total FROM company_employees WHERE company_id=$1", [company_id]);
            if (parseInt(currentEmps.rows[0].total) >= compRes.rows[0].max_employees) throw new Error("Company is at maximum capacity.");

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
    } finally { client.release(); }
});

module.exports = router;