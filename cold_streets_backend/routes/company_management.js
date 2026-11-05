const express = require('express');
const router = express.Router();
// Route parameters are parsed after app-level middleware; enforce actor ownership here.
const { requireOwnedPlayerParam } = require('../middleware/playerIdentity');
router.param('user_id', requireOwnedPlayerParam);

const pool = require('../db');
const { ActionError, integer, dbInteger, exactJsonAmount, actorId, sendActionError } = require('../utils/economyValidation');
const { requireIdempotencyKey, beginIdempotent, completeIdempotent } = require('../utils/idempotency');
const { assertPositionEligibility, assertCrewPositionEligibility } = require('../utils/companyEmployment');
const { handleCrewDomainTransfer } = require('../utils/crewDomain');

// Central actor/company ownership check. The original route checks allowed
// some company_id operations with no director authorization at all.
const pausedManagementActions = new Set([
    '/manage-employee', '/change-director', '/sell-company',
    '/order-stock', '/buy-upgrade', '/update-advertising',
    '/update-pricing'
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
               AND pc.is_active = true
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


// --- 1. COMPANY CASH FUNDING ---
// Source-backed safe subset:
// - the Company Canvas explicitly says the owner deposits Dirty Cash into the
//   Company Bank;
// - this action preserves denomination and does not itself launder value.
//
// Clean deposits, any withdrawals, payroll conversion, sales revenue,
// laundering tax, and bankruptcy settlement remain paused.
router.post('/funds', async (req, res) => {
    let client, transaction = false;
    try {
        const actor = actorId(req);
        const idempotencyKey = requireIdempotencyKey(req);
        const companyId = req.managedCompanyId;

        // The route itself represents the only source-reconciled transfer:
        // owner Dirty Cash -> company Dirty Cash. The client does not choose a
        // denomination or transfer direction.
        const amount = integer(req.body?.amount, {
            field: 'Dirty Cash funding amount',
            min: 1n
        });

        client = await pool.connect();
        await client.query('BEGIN');
        transaction = true;

        // Lock order: actor -> idempotency -> company.
        const user = await client.query(
            'SELECT dirty_cash FROM users WHERE user_id = $1 FOR UPDATE',
            [actor]
        );
        if (user.rowCount !== 1) throw new ActionError(404, 'Player not found.');

        const idem = await beginIdempotent(
            client,
            actor,
            'company.owner_dirty_funding',
            idempotencyKey,
            { companyId, amount: amount.toString() }
        );
        if (idem.replay) {
            await client.query('COMMIT');
            transaction = false;
            return res.status(idem.status).json(idem.response);
        }

        const company = await client.query(
            `SELECT owner_id, bank_dirty, bank_clean, is_active
               FROM player_companies
              WHERE company_id = $1
              FOR UPDATE`,
            [companyId]
        );
        if (
            company.rowCount !== 1 ||
            String(company.rows[0].owner_id) !== actor ||
            company.rows[0].is_active !== true
        ) {
            throw new ActionError(403, 'Company is no longer active under this owner.');
        }

        const playerDirty = dbInteger(user.rows[0].dirty_cash, {
            field: 'Player Dirty Cash'
        });
        if (playerDirty < amount) {
            throw new ActionError(409, 'Insufficient Dirty Cash.');
        }

        const debit = await client.query(
            `UPDATE users
                SET dirty_cash = dirty_cash - $1::numeric
              WHERE user_id = $2
                AND dirty_cash >= $1::numeric
              RETURNING dirty_cash`,
            [amount.toString(), actor]
        );
        if (debit.rowCount !== 1) {
            throw new ActionError(409, 'Player wallet changed before company funding.');
        }

        const funded = await client.query(
            `UPDATE player_companies
                SET bank_dirty = bank_dirty + $1::numeric
              WHERE company_id = $2
                AND owner_id = $3
                AND is_active = true
              RETURNING bank_dirty, bank_clean`,
            [amount.toString(), companyId, actor]
        );
        if (funded.rowCount !== 1) {
            throw new ActionError(409, 'Company state changed before funding.');
        }

        await client.query(
            `INSERT INTO company_cash_ledger (
                company_id,
                actor_user_id,
                event_type,
                dirty_delta,
                clean_delta,
                dirty_balance_after,
                clean_balance_after,
                source_ref
             )
             VALUES (
                $1, $2, 'OWNER_DIRTY_DEPOSIT',
                $3::numeric, 0,
                $4::numeric, $5::numeric, $6
             )`,
            [
                companyId,
                actor,
                amount.toString(),
                funded.rows[0].bank_dirty,
                funded.rows[0].bank_clean,
                idempotencyKey
            ]
        );

        await client.query(
            `INSERT INTO company_logs (company_id, log_type, log_text)
             VALUES ($1, 'FUNDS', $2)`,
            [
                companyId,
                'Owner deposited ' + amount.toString() +
                    ' Dirty Cash into the company bank.'
            ]
        );

        const response = {
            success: true,
            message: 'Dirty Cash deposited into the company bank.',
            cash_flow_status: 'funding_only',
            laundering_settlement_available: false,
            player_dirty_cash: exactJsonAmount(
                dbInteger(debit.rows[0].dirty_cash, {
                    field: 'Player Dirty Cash'
                })
            ),
            company_bank_dirty: exactJsonAmount(
                dbInteger(funded.rows[0].bank_dirty, {
                    field: 'Company Dirty Cash'
                })
            ),
            company_bank_clean: exactJsonAmount(
                dbInteger(funded.rows[0].bank_clean, {
                    field: 'Company Clean Cash'
                })
            )
        };

        await completeIdempotent(client, idem, 200, response);
        await client.query('COMMIT');
        transaction = false;
        return res.json(response);
    } catch (err) {
        if (transaction) {
            try {
                await client.query('ROLLBACK');
            } catch (rollback) {
                console.error('Company Dirty Cash funding rollback:', rollback);
            }
        }
        return sendActionError(res, err, 'Company cash funding failed:');
    } finally {
        if (client) client.release();
    }
});

// --- 2. EDIT COMPANY PROFILE ---
router.post('/update-profile', async (req, res) => {
    let client, transaction = false;
    try {
        const actor = actorId(req);
        const companyId = req.managedCompanyId;
        const idempotencyKey = requireIdempotencyKey(req);
        const companyName = typeof req.body?.company_name === 'string'
            ? req.body.company_name.trim()
            : '';
        const logoUrl = req.body?.logo_url == null
            ? null
            : String(req.body.logo_url).trim();

        if (companyName.length < 3 || companyName.length > 80) {
            throw new ActionError(400, 'Company name must contain 3–80 characters.');
        }
        if (logoUrl !== null && logoUrl.length > 1000) {
            throw new ActionError(400, 'Company logo URL is too long.');
        }

        client = await pool.connect();
        await client.query('BEGIN');
        transaction = true;
        const player = await client.query(
            'SELECT user_id FROM users WHERE user_id = $1 FOR UPDATE', [actor]
        );
        if (player.rowCount !== 1) throw new ActionError(404, 'Player not found.');
        const idem = await beginIdempotent(
            client, actor, 'company.update_profile', idempotencyKey,
            { companyId, companyName, logoUrl }
        );
        if (idem.replay) {
            await client.query('COMMIT');
            transaction = false;
            return res.status(idem.status).json(idem.response);
        }

        const updated = await client.query(
            `UPDATE player_companies
                SET company_name = $1, logo_url = $2
              WHERE company_id = $3 AND owner_id = $4
              RETURNING company_id, company_name, logo_url`,
            [companyName, logoUrl, companyId, actor]
        );
        if (updated.rowCount !== 1) {
            throw new ActionError(403, 'Company ownership changed.');
        }
        await client.query(
            "INSERT INTO company_logs (company_id, log_type, log_text) VALUES ($1, 'MAIN', 'Company profile updated.')",
            [companyId]
        );

        const response = {
            success: true,
            message: 'Profile updated successfully.',
            company: updated.rows[0]
        };
        await completeIdempotent(client, idem, 200, response);
        await client.query('COMMIT');
        transaction = false;
        return res.json(response);
    } catch (err) {
        if (transaction) {
            try { await client.query('ROLLBACK'); }
            catch (rollback) { console.error('Company profile rollback:', rollback); }
        }
        return sendActionError(res, err, 'Company profile update failed:');
    } finally {
        if (client) client.release();
    }
});

// --- 3. MANAGE EMPLOYEES ---
router.post('/manage-employee', (_req, res) => {
    // Position thresholds, salary-contract acceptance, and training settlement
    // are not fully recovered in the normalized company catalog.
    return res.status(503).json({
        error: 'Employee contract management is paused pending company position and training reconciliation.'
    });
});

// --- 4. TRANSFER DIRECTORSHIP ---
router.post('/change-director', (_req, res) => {
    // The recovered company design does not define target acceptance or the
    // interaction with a player owning multiple companies in a supply chain.
    return res.status(503).json({
        error: 'Directorship transfer is paused pending ownership-transfer semantics.'
    });
});

// --- 5. SELL / LIQUIDATE COMPANY ---
router.post('/sell-company', (_req, res) => {
    // The legacy 75% setup-cost refund is not established by the recovered
    // company design, and severance/bankruptcy settlement is still unresolved.
    return res.status(503).json({
        error: 'Company liquidation is paused pending source-backed settlement rules.'
    });
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

// --- 7. ORDER STOCK ---
router.post('/order-stock', (_req, res) => {
    // blueprint_products is currently unrecovered/empty, and the legacy
    // system-supplier markup does not match the recovered supply-contract
    // model closely enough to activate by inference.
    return res.status(503).json({
        error: 'Company stock ordering is paused pending product blueprint and supplier-contract recovery.'
    });
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
router.post('/buy-upgrade', (_req, res) => {
    // Upgrade definitions remain legacy text in company_types_master and the
    // old endpoint trusted a client-supplied cost. Never settle that path.
    return res.status(503).json({
        error: 'Company upgrades are paused pending normalized upgrade catalog recovery.'
    });
});

// --- 10. FETCH NPC CREW + SOURCE POSITION ELIGIBILITY ---
router.get('/:company_id/available-crew/:user_id', async (req, res) => {
    try {
        const actor = actorId(req);
        const companyId = integer(req.params.company_id, {
            field: 'Company ID', min: 1n, max: 9223372036854775807n
        }).toString();

        const company = await pool.query(
            `SELECT pc.owner_id, pc.type_id, pc.is_active
               FROM player_companies pc
              WHERE pc.company_id = $1`,
            [companyId]
        );
        if (
            company.rowCount !== 1 ||
            String(company.rows[0].owner_id) !== actor
        ) {
            throw new ActionError(403, 'Only the company owner may inspect recruit staffing.');
        }

        const [crewRes, positionsRes, rosterRes] = await Promise.all([
            pool.query(
                `SELECT uc.crew_id, uc.npc_name, uc.tier, uc.assignment,
                        uc.current_domain, uc.last_transfer_at,
                        uc.cur_acu, uc.cur_ops, uc.cur_pre, uc.cur_res,
                        uc.max_acu, uc.max_ops, uc.max_pre, uc.max_res,
                        cca.crime_id AS scheduled_crime_id
                   FROM user_crew uc
                   LEFT JOIN crew_crime_assignments cca
                     ON cca.crew_id = uc.crew_id
                  WHERE uc.user_id = $1
                  ORDER BY uc.tier DESC, uc.crew_id ASC`,
                [actor]
            ),
            pool.query(
                `SELECT position_id, role_key,
                        req_stat_primary, req_amount_primary,
                        req_stat_secondary, req_amount_secondary
                   FROM company_positions_master
                  WHERE type_id = $1
                  ORDER BY position_id ASC`,
                [company.rows[0].type_id]
            ),
            pool.query(
                `SELECT employee_id, position_role
                   FROM company_employees
                  WHERE company_id = $1
                    AND is_npc = true`,
                [companyId]
            )
        ]);

        const assignedHere = new Map(
            rosterRes.rows.map(row => [
                String(row.employee_id),
                row.position_role
            ])
        );

        const crew = crewRes.rows.map(row => {
            const eligiblePositionIds = [];
            for (const position of positionsRes.rows) {
                try {
                    assertCrewPositionEligibility(row, position);
                    eligiblePositionIds.push(position.position_id);
                } catch (err) {
                    if (!(err instanceof ActionError) || err.status !== 409) {
                        throw err;
                    }
                }
            }

            return {
                ...row,
                assigned_to_this_company: assignedHere.has(String(row.crew_id)),
                company_position_role:
                    assignedHere.get(String(row.crew_id)) || null,
                eligible_position_ids: eligiblePositionIds,
                assignment_available:
                    company.rows[0].is_active === true &&
                    row.scheduled_crime_id == null &&
                    !assignedHere.has(String(row.crew_id)) &&
                    eligiblePositionIds.length > 0,
                effectiveness_status: 'unresolved',
                salary_clean: 0
            };
        });

        return res.json({
            success: true,
            company_id: companyId,
            company_active: company.rows[0].is_active === true,
            npc_salary_rule: 'zero',
            effectiveness_status: 'unresolved',
            positions: positionsRes.rows.map(row => ({
                position_id: row.position_id,
                role_key: row.role_key,
                req_stat_primary: row.req_stat_primary,
                req_amount_primary: exactJsonAmount(
                    dbInteger(row.req_amount_primary, {
                        field: 'Primary position requirement'
                    })
                ),
                req_stat_secondary: row.req_stat_secondary,
                req_amount_secondary: exactJsonAmount(
                    dbInteger(row.req_amount_secondary, {
                        field: 'Secondary position requirement'
                    })
                )
            })),
            crew
        });
    } catch (err) {
        return sendActionError(res, err, 'Company recruit staffing fetch failed:');
    }
});

// --- 11. ASSIGN NPC TO SOURCE POSITION ---
// Source-backed subset:
// - NPC Crew may occupy company positions;
// - they work for zero salary;
// - source position stat requirements are enforced;
// - weighted effectiveness is intentionally left unresolved.
router.post('/assign-crew', async (req, res) => {
    let client, transaction = false;
    try {
        const actor = actorId(req);
        const companyId = req.managedCompanyId;
        const idempotencyKey = requireIdempotencyKey(req);
        const crewId = integer(req.body?.crew_id, {
            field: 'Crew ID', min: 1n, max: 9223372036854775807n
        }).toString();
        const positionId = integer(req.body?.position_id, {
            field: 'Position ID', min: 1n, max: 9223372036854775807n
        }).toString();

        client = await pool.connect();
        await client.query('BEGIN');
        transaction = true;

        // Crew scheduler lock order: schedule -> crew -> owner.
        const schedule = await client.query(
            `SELECT crew_id, crime_id
               FROM crew_crime_assignments
              WHERE crew_id = $1
              FOR UPDATE`,
            [crewId]
        );
        if (schedule.rowCount) {
            throw new ActionError(
                409,
                'Recall this recruit from its crime automation before company assignment.'
            );
        }

        const crew = await client.query(
            `SELECT crew_id, user_id, assignment, current_domain,
                    last_transfer_at,
                    cur_acu, cur_ops, cur_pre, cur_res
               FROM user_crew
              WHERE crew_id = $1
                AND user_id = $2
              FOR UPDATE`,
            [crewId, actor]
        );
        if (crew.rowCount !== 1) {
            throw new ActionError(404, 'Recruit not found or not yours.');
        }

        const player = await client.query(
            'SELECT user_id FROM users WHERE user_id = $1 FOR UPDATE',
            [actor]
        );
        if (player.rowCount !== 1) {
            throw new ActionError(404, 'Player not found.');
        }

        const idem = await beginIdempotent(
            client,
            actor,
            'company.assign_crew',
            idempotencyKey,
            { companyId, crewId, positionId }
        );
        if (idem.replay) {
            await client.query('COMMIT');
            transaction = false;
            return res.status(idem.status).json(idem.response);
        }

        const company = await client.query(
            `SELECT pc.owner_id, pc.type_id, pc.is_active,
                    ctm.max_employees
               FROM player_companies pc
               JOIN company_types_master ctm ON ctm.type_id = pc.type_id
              WHERE pc.company_id = $1
              FOR UPDATE OF pc`,
            [companyId]
        );
        if (
            company.rowCount !== 1 ||
            String(company.rows[0].owner_id) !== actor ||
            company.rows[0].is_active !== true
        ) {
            throw new ActionError(403, 'Company ownership or active state changed.');
        }

        const existingRoster = await client.query(
            `SELECT company_id
               FROM company_employees
              WHERE employee_id = $1
                AND is_npc = true
              FOR UPDATE`,
            [crewId]
        );
        if (existingRoster.rowCount) {
            throw new ActionError(
                409,
                'Recruit is already assigned to a company. Recall it before reassignment.'
            );
        }

        const staff = await client.query(
            'SELECT COUNT(*)::bigint AS total FROM company_employees WHERE company_id = $1',
            [companyId]
        );
        if (BigInt(staff.rows[0].total) >= BigInt(company.rows[0].max_employees)) {
            throw new ActionError(409, 'Company is at its recovered base staff capacity.');
        }

        const position = await client.query(
            `SELECT position_id, role_key,
                    req_stat_primary, req_amount_primary,
                    req_stat_secondary, req_amount_secondary
               FROM company_positions_master
              WHERE position_id = $1
                AND type_id = $2`,
            [positionId, company.rows[0].type_id]
        );
        if (position.rowCount !== 1) {
            throw new ActionError(404, 'Position is not part of this company type.');
        }

        const eligibility = assertCrewPositionEligibility(
            crew.rows[0],
            position.rows[0]
        );

        await handleCrewDomainTransfer(
            client,
            actor,
            crewId,
            'COMPANY'
        );

        await client.query(
            `INSERT INTO company_employees (
                company_id,
                employee_id,
                is_npc,
                position_role,
                daily_salary,
                effectiveness_score
             )
             VALUES ($1, $2, true, $3, 0, NULL)`,
            [companyId, crewId, position.rows[0].role_key]
        );

        await client.query(
            `UPDATE user_crew
                SET assignment = $1,
                    current_domain = 'COMPANY'
              WHERE crew_id = $2
                AND user_id = $3`,
            ['Company: ' + companyId, crewId, actor]
        );

        await client.query(
            `INSERT INTO company_logs (company_id, log_type, log_text)
             VALUES ($1, 'STAFF', $2)`,
            [
                companyId,
                'Assigned NPC recruit to role ' +
                    position.rows[0].role_key +
                    ' at 0 Clean Cash salary.'
            ]
        );

        const response = {
            success: true,
            message: 'NPC recruit assigned to company position.',
            crew_id: crewId,
            position_id: positionId,
            role_key: position.rows[0].role_key,
            salary_clean: 0,
            effectiveness_status: 'unresolved',
            requirements: {
                primary: {
                    stat: eligibility.primary.stat,
                    required: exactJsonAmount(eligibility.primary.required),
                    actual: exactJsonAmount(eligibility.primary.actual)
                },
                secondary: {
                    stat: eligibility.secondary.stat,
                    required: exactJsonAmount(eligibility.secondary.required),
                    actual: exactJsonAmount(eligibility.secondary.actual)
                }
            }
        };

        await completeIdempotent(client, idem, 200, response);
        await client.query('COMMIT');
        transaction = false;
        return res.json(response);
    } catch (err) {
        if (transaction) {
            try { await client.query('ROLLBACK'); }
            catch (rollback) {
                console.error('Company recruit assignment rollback:', rollback);
            }
        }
        return sendActionError(res, err, 'Company recruit assignment failed:');
    } finally {
        if (client) client.release();
    }
});

// --- 12. RECALL NPC ---
// Recall remains available as an escape hatch for any legacy/manual company
// roster row even while new NPC company assignment is paused.
router.post('/recall-crew', async (req, res) => {
    let client, transaction = false;
    try {
        const actor = actorId(req);
        const companyId = req.managedCompanyId;
        const idempotencyKey = requireIdempotencyKey(req);
        const crewId = integer(req.body?.crew_id, {
            field: 'Crew ID', min: 1n, max: 9223372036854775807n
        }).toString();

        client = await pool.connect();
        await client.query('BEGIN');
        transaction = true;

        // Match the crew-crime worker lock order before touching shared crew
        // state: schedule -> crew -> user. A stale schedule is removed below.
        await client.query(
            'SELECT crew_id FROM crew_crime_assignments WHERE crew_id = $1 FOR UPDATE',
            [crewId]
        );
        const crew = await client.query(
            `SELECT crew_id, user_id, assignment, current_domain
               FROM user_crew
              WHERE crew_id = $1 AND user_id = $2
              FOR UPDATE`,
            [crewId, actor]
        );
        if (crew.rowCount !== 1) {
            throw new ActionError(404, 'Recruit not found or not yours.');
        }
        const player = await client.query(
            'SELECT user_id FROM users WHERE user_id = $1 FOR UPDATE',
            [actor]
        );
        if (player.rowCount !== 1) throw new ActionError(404, 'Player not found.');

        const idem = await beginIdempotent(
            client, actor, 'company.recall_crew', idempotencyKey,
            { companyId, crewId }
        );
        if (idem.replay) {
            await client.query('COMMIT');
            transaction = false;
            return res.status(idem.status).json(idem.response);
        }

        const company = await client.query(
            `SELECT company_id, owner_id
               FROM player_companies
              WHERE company_id = $1
              FOR UPDATE`,
            [companyId]
        );
        if (company.rowCount !== 1 || String(company.rows[0].owner_id) !== actor) {
            throw new ActionError(403, 'Company ownership changed.');
        }

        const roster = await client.query(
            `SELECT employee_id
               FROM company_employees
              WHERE company_id = $1
                AND employee_id = $2
                AND is_npc = true
              FOR UPDATE`,
            [companyId, crewId]
        );
        if (roster.rowCount !== 1) {
            throw new ActionError(409, 'Recruit is not assigned to that company.');
        }

        await client.query(
            'DELETE FROM crew_crime_assignments WHERE crew_id = $1',
            [crewId]
        );
        await client.query(
            `DELETE FROM company_employees
              WHERE company_id = $1 AND employee_id = $2 AND is_npc = true`,
            [companyId, crewId]
        );
        await client.query(
            `UPDATE user_crew
                SET assignment = 'UNASSIGNED',
                    current_domain = 'COMPANY'
              WHERE crew_id = $1 AND user_id = $2`,
            [crewId, actor]
        );
        await client.query(
            `INSERT INTO company_logs (company_id, log_type, log_text)
             VALUES ($1, 'STAFF', 'Recalled an NPC recruit from the company.')`,
            [companyId]
        );

        const response = {
            success: true,
            message: 'NPC recalled.',
            crew_id: crewId
        };
        await completeIdempotent(client, idem, 200, response);
        await client.query('COMMIT');
        transaction = false;
        return res.json(response);
    } catch (err) {
        if (transaction) {
            try { await client.query('ROLLBACK'); }
            catch (rollback) {
                console.error('Company recruit recall rollback:', rollback);
            }
        }
        return sendActionError(res, err, 'Company recruit recall failed:');
    } finally {
        if (client) client.release();
    }
});

// --- 13. PROPOSE REAL-PLAYER EMPLOYMENT CONTRACT ---
// The recovered company design explicitly requires negotiated Clean Cash
// salaries for real players. An application is not employment consent.
// Directors propose an exact source role + salary; the applicant accepts later
// under their own authenticated identity.
router.post('/employment-offer', async (req, res) => {
    let client, transaction = false;
    try {
        const actor = actorId(req);
        const companyId = req.managedCompanyId;
        const idempotencyKey = requireIdempotencyKey(req);
        const applicationId = integer(req.body?.application_id, {
            field: 'Application ID', min: 1n, max: 9223372036854775807n
        }).toString();
        const positionId = integer(req.body?.position_id, {
            field: 'Position ID', min: 1n, max: 9223372036854775807n
        }).toString();
        const salary = integer(req.body?.daily_salary_clean, {
            field: 'Negotiated Clean Cash salary', min: 1n
        });

        client = await pool.connect();
        await client.query('BEGIN');
        transaction = true;

        // Lock order: authenticated actor -> idempotency -> company ->
        // application -> target player -> dependent rows.
        const actorRow = await client.query(
            'SELECT user_id FROM users WHERE user_id = $1 FOR UPDATE',
            [actor]
        );
        if (actorRow.rowCount !== 1) throw new ActionError(404, 'Player not found.');

        const idem = await beginIdempotent(
            client,
            actor,
            'company.employment_offer.create',
            idempotencyKey,
            {
                companyId,
                applicationId,
                positionId,
                salary: salary.toString()
            }
        );
        if (idem.replay) {
            await client.query('COMMIT');
            transaction = false;
            return res.status(idem.status).json(idem.response);
        }

        const company = await client.query(
            `SELECT pc.company_id, pc.owner_id, pc.type_id, pc.is_active,
                    ctm.max_employees
               FROM player_companies pc
               JOIN company_types_master ctm ON ctm.type_id = pc.type_id
              WHERE pc.company_id = $1
              FOR UPDATE OF pc`,
            [companyId]
        );
        if (
            company.rowCount !== 1 ||
            String(company.rows[0].owner_id) !== actor ||
            company.rows[0].is_active !== true
        ) {
            throw new ActionError(403, 'Company ownership or active state changed.');
        }

        const application = await client.query(
            `SELECT application_id, user_id, status
               FROM company_applicants
              WHERE application_id = $1::bigint
                AND company_id = $2
              FOR UPDATE`,
            [applicationId, companyId]
        );
        if (application.rowCount !== 1) {
            throw new ActionError(404, 'Application not found for this company.');
        }
        if (application.rows[0].status !== 'Pending') {
            throw new ActionError(409, 'Application is no longer pending.');
        }

        const targetId = String(application.rows[0].user_id);
        const target = await client.query(
            `SELECT current_job_id, stat_acu, stat_ops, stat_pre, stat_res
               FROM users
              WHERE user_id = $1
              FOR UPDATE`,
            [targetId]
        );
        if (target.rowCount !== 1) {
            throw new ActionError(409, 'Applicant account no longer exists.');
        }
        if (target.rows[0].current_job_id !== null) {
            throw new ActionError(409, 'Applicant has joined a City Job since applying.');
        }

        const employed = await client.query(
            `SELECT company_id
               FROM company_employees
              WHERE employee_id = $1
                AND is_npc = false
              LIMIT 1`,
            [targetId]
        );
        if (employed.rowCount) {
            throw new ActionError(409, 'Applicant is already employed by a company.');
        }

        const staff = await client.query(
            'SELECT COUNT(*)::bigint AS total FROM company_employees WHERE company_id = $1',
            [companyId]
        );
        if (BigInt(staff.rows[0].total) >= BigInt(company.rows[0].max_employees)) {
            throw new ActionError(409, 'Company is at its recovered base staff capacity.');
        }

        const position = await client.query(
            `SELECT position_id, type_id, role_key,
                    req_stat_primary, req_amount_primary,
                    req_stat_secondary, req_amount_secondary
               FROM company_positions_master
              WHERE position_id = $1
                AND type_id = $2`,
            [positionId, company.rows[0].type_id]
        );
        if (position.rowCount !== 1) {
            throw new ActionError(404, 'Position is not part of this company type.');
        }

        const eligibility = assertPositionEligibility(
            target.rows[0],
            position.rows[0]
        );

        const inserted = await client.query(
            `INSERT INTO company_employment_offers (
                application_id,
                company_id,
                employee_id,
                offered_by,
                position_id,
                daily_salary_clean,
                source_ref
             )
             VALUES ($1, $2, $3, $4, $5, $6::numeric, $7::uuid)
             RETURNING offer_id, created_at, status`,
            [
                applicationId,
                companyId,
                targetId,
                actor,
                positionId,
                salary.toString(),
                idempotencyKey
            ]
        );

        await client.query(
            `INSERT INTO company_logs (company_id, log_type, log_text)
             VALUES ($1, 'STAFF', $2)`,
            [
                companyId,
                'Director proposed role ' + position.rows[0].role_key +
                    ' at ' + salary.toString() + ' Clean Cash per day.'
            ]
        );

        const response = {
            success: true,
            message: 'Employment offer sent. The applicant must accept it.',
            offer_id: inserted.rows[0].offer_id,
            application_id: applicationId,
            employee_id: targetId,
            position_id: positionId,
            role_key: position.rows[0].role_key,
            daily_salary_clean: exactJsonAmount(salary),
            status: inserted.rows[0].status,
            created_at: inserted.rows[0].created_at,
            payroll_settlement_available: false,
            requirements: {
                primary: {
                    stat: eligibility.primary.stat,
                    required: exactJsonAmount(eligibility.primary.required),
                    actual: exactJsonAmount(eligibility.primary.actual)
                },
                secondary: {
                    stat: eligibility.secondary.stat,
                    required: exactJsonAmount(eligibility.secondary.required),
                    actual: exactJsonAmount(eligibility.secondary.actual)
                }
            }
        };

        await completeIdempotent(client, idem, 200, response);
        await client.query('COMMIT');
        transaction = false;
        return res.json(response);
    } catch (err) {
        if (transaction) {
            try { await client.query('ROLLBACK'); }
            catch (rollback) {
                console.error('Employment offer create rollback:', rollback);
            }
        }
        return sendActionError(res, err, 'Employment offer failed:');
    } finally {
        if (client) client.release();
    }
});

// --- 14. WITHDRAW PENDING EMPLOYMENT OFFER ---
router.post('/employment-offer/withdraw', async (req, res) => {
    let client, transaction = false;
    try {
        const actor = actorId(req);
        const companyId = req.managedCompanyId;
        const idempotencyKey = requireIdempotencyKey(req);
        const offerId = integer(req.body?.offer_id, {
            field: 'Employment offer ID', min: 1n, max: 9223372036854775807n
        }).toString();

        client = await pool.connect();
        await client.query('BEGIN');
        transaction = true;

        const actorRow = await client.query(
            'SELECT user_id FROM users WHERE user_id = $1 FOR UPDATE',
            [actor]
        );
        if (actorRow.rowCount !== 1) throw new ActionError(404, 'Player not found.');

        const idem = await beginIdempotent(
            client,
            actor,
            'company.employment_offer.withdraw',
            idempotencyKey,
            { companyId, offerId }
        );
        if (idem.replay) {
            await client.query('COMMIT');
            transaction = false;
            return res.status(idem.status).json(idem.response);
        }

        const company = await client.query(
            `SELECT owner_id, is_active
               FROM player_companies
              WHERE company_id = $1
              FOR UPDATE`,
            [companyId]
        );
        if (
            company.rowCount !== 1 ||
            String(company.rows[0].owner_id) !== actor
        ) {
            throw new ActionError(403, 'Company ownership changed.');
        }

        const offer = await client.query(
            `SELECT offer_id, status
               FROM company_employment_offers
              WHERE offer_id = $1
                AND company_id = $2
              FOR UPDATE`,
            [offerId, companyId]
        );
        if (offer.rowCount !== 1) {
            throw new ActionError(404, 'Employment offer not found.');
        }
        if (offer.rows[0].status !== 'pending') {
            throw new ActionError(409, 'Employment offer is no longer pending.');
        }

        await client.query(
            `UPDATE company_employment_offers
                SET status = 'withdrawn',
                    responded_at = NOW()
              WHERE offer_id = $1`,
            [offerId]
        );
        await client.query(
            `INSERT INTO company_logs (company_id, log_type, log_text)
             VALUES ($1, 'STAFF', 'Director withdrew a pending employment offer.')`,
            [companyId]
        );

        const response = {
            success: true,
            message: 'Employment offer withdrawn.',
            offer_id: offerId,
            status: 'withdrawn'
        };
        await completeIdempotent(client, idem, 200, response);
        await client.query('COMMIT');
        transaction = false;
        return res.json(response);
    } catch (err) {
        if (transaction) {
            try { await client.query('ROLLBACK'); }
            catch (rollback) {
                console.error('Employment offer withdraw rollback:', rollback);
            }
        }
        return sendActionError(res, err, 'Employment offer withdrawal failed:');
    } finally {
        if (client) client.release();
    }
});

// --- 15. MANAGE APPLICANT ---
// Rejection can be immediate. Direct acceptance is intentionally removed:
// real players require a negotiated Clean Cash salary and source role, so the
// Director must create an employment offer and the applicant must accept it.
router.post('/manage-applicant', async (req, res) => {
    let client, transaction = false;
    try {
        const actor = actorId(req);
        const companyId = req.managedCompanyId;
        const idempotencyKey = requireIdempotencyKey(req);
        const applicationId = integer(req.body?.application_id, {
            field: 'Application ID', min: 1n, max: 9223372036854775807n
        }).toString();
        const action = req.body?.action;

        if (action === 'accept') {
            throw new ActionError(
                409,
                'Direct acceptance is disabled. Send a negotiated employment offer instead.'
            );
        }
        if (action !== 'reject') {
            throw new ActionError(400, 'Applicant action must be reject.');
        }

        client = await pool.connect();
        await client.query('BEGIN');
        transaction = true;

        const actorRow = await client.query(
            'SELECT user_id FROM users WHERE user_id = $1 FOR UPDATE',
            [actor]
        );
        if (actorRow.rowCount !== 1) throw new ActionError(404, 'Player not found.');

        const idem = await beginIdempotent(
            client,
            actor,
            'company.manage_applicant.reject',
            idempotencyKey,
            { companyId, applicationId }
        );
        if (idem.replay) {
            await client.query('COMMIT');
            transaction = false;
            return res.status(idem.status).json(idem.response);
        }

        const company = await client.query(
            `SELECT owner_id
               FROM player_companies
              WHERE company_id = $1
              FOR UPDATE`,
            [companyId]
        );
        if (
            company.rowCount !== 1 ||
            String(company.rows[0].owner_id) !== actor
        ) {
            throw new ActionError(403, 'Company ownership changed.');
        }

        const application = await client.query(
            `SELECT status
               FROM company_applicants
              WHERE application_id = $1::bigint
                AND company_id = $2
              FOR UPDATE`,
            [applicationId, companyId]
        );
        if (application.rowCount !== 1) {
            throw new ActionError(404, 'Application not found for this company.');
        }
        if (application.rows[0].status !== 'Pending') {
            throw new ActionError(409, 'Application is no longer pending.');
        }

        const pendingOffer = await client.query(
            `SELECT offer_id
               FROM company_employment_offers
              WHERE application_id = $1::bigint
                AND status = 'pending'
              FOR UPDATE`,
            [applicationId]
        );
        if (pendingOffer.rowCount) {
            throw new ActionError(
                409,
                'Withdraw the pending employment offer before rejecting this application.'
            );
        }

        await client.query(
            `UPDATE company_applicants
                SET status = 'Rejected'
              WHERE application_id = $1::bigint
                AND company_id = $2`,
            [applicationId, companyId]
        );
        await client.query(
            `INSERT INTO company_logs (company_id, log_type, log_text)
             VALUES ($1, 'STAFF', 'Rejected a pending player application.')`,
            [companyId]
        );

        const response = {
            success: true,
            message: 'Applicant rejected.',
            application_id: applicationId,
            status: 'Rejected'
        };
        await completeIdempotent(client, idem, 200, response);
        await client.query('COMMIT');
        transaction = false;
        return res.json(response);
    } catch (err) {
        if (transaction) {
            try { await client.query('ROLLBACK'); }
            catch (rollback) {
                console.error('Applicant rejection rollback:', rollback);
            }
        }
        return sendActionError(res, err, 'Applicant management failed:');
    } finally {
        if (client) client.release();
    }
});

module.exports = router;