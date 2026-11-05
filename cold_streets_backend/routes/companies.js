const express = require('express');
const router = express.Router();
// Route parameters are parsed after app-level middleware; enforce actor ownership here.
const { requireOwnedPlayerParam } = require('../middleware/playerIdentity');
router.param('user_id', requireOwnedPlayerParam);

const pool = require('../db');
const { ActionError, integer, dbInteger, exactJsonAmount, actorId, sendActionError } = require('../utils/economyValidation');
const { requireIdempotencyKey, beginIdempotent, completeIdempotent } = require('../utils/idempotency');
const { assertPositionEligibility } = require('../utils/companyEmployment');

// --- 1. GET ALL COMPANY BLUEPRINTS ---
router.get('/blueprints', async (_req, res) => {
    try {
        const result = await pool.query(`
            SELECT ctm.*,
                   cu.upgrade_id,
                   cu.upgrade_key,
                   cu.cost AS upgrade_cost,
                   cu.upkeep_increase AS upgrade_upkeep_increase,
                   cu.bonus_key AS upgrade_bonus_key,
                   cu.bonus_value AS upgrade_bonus_value,
                   cu.semantics_status AS upgrade_semantics_status,
                   (SELECT COUNT(*) FROM company_positions_master cp
                     WHERE cp.type_id = ctm.type_id) AS position_count,
                   (SELECT COUNT(*) FROM company_specials_master cs
                     WHERE cs.type_id = ctm.type_id) AS special_count,
                   (SELECT COUNT(*) FROM company_product_rules_master cpr
                     WHERE cpr.type_id = ctm.type_id) AS source_product_rule_count,
                   (SELECT COUNT(*) FROM company_affiliations_master ca
                     WHERE ca.type_id = ctm.type_id
                       AND ca.resolution_status <> 'exact') AS unresolved_affiliation_count
              FROM company_types_master ctm
              LEFT JOIN company_upgrades_master cu ON cu.type_id = ctm.type_id
             ORDER BY ctm.tier ASC, ctm.setup_cost ASC, ctm.type_id ASC
        `);
        res.json({
            success: true,
            catalog_status: 'source_normalized_partial',
            incorporation_available: false,
            incorporation_currency_status: 'source_conflict',
            incorporation_blocker:
                'Incorporation setup currency conflicts across recovered sources: the GDD says Clean Cash buys legitimate businesses while the legacy backend charged Dirty Cash.',
            blueprints: result.rows
        });
    } catch (err) {
        console.error("Error fetching blueprints:", err);
        res.status(500).json({ error: "Server error fetching commercial registry." });
    }
});

// --- 2. INCORPORATION PREFLIGHT (READ ONLY) ---
// The recovered company catalog provides an exact setup_cost, but sources
// conflict on its denomination:
// - GDD: Clean Cash buys legitimate businesses;
// - legacy backend: incorporation debited Dirty Cash.
// Do not choose a currency by inference. This endpoint reports exact source
// readiness and both wallet balances without moving value.
router.post('/incorporation-preflight', async (req, res) => {
    try {
        const actor = actorId(req);
        const typeId = integer(req.body?.type_id, {
            field: 'Company type ID', min: 1n, max: 9223372036854775807n
        }).toString();
        const companyName = typeof req.body?.company_name === 'string'
            ? req.body.company_name.trim()
            : '';
        if (companyName.length < 3 || companyName.length > 80) {
            throw new ActionError(400, 'Company name must be 3 to 80 characters.');
        }

        const [player, blueprint, employment] = await Promise.all([
            pool.query(
                `SELECT clean_cash, dirty_cash, current_job_id
                   FROM users
                  WHERE user_id = $1`,
                [actor]
            ),
            pool.query(
                `SELECT ctm.type_id, ctm.industry_type, ctm.tier,
                        ctm.setup_cost,
                        (SELECT COUNT(*)::bigint
                           FROM company_positions_master p
                          WHERE p.type_id = ctm.type_id) AS position_count,
                        (SELECT COUNT(*)::bigint
                           FROM company_product_rules_master r
                          WHERE r.type_id = ctm.type_id) AS product_rule_count,
                        (SELECT COUNT(*)::bigint
                           FROM company_affiliations_master a
                          WHERE a.type_id = ctm.type_id
                            AND a.resolution_status <> 'exact')
                          AS unresolved_affiliation_count
                   FROM company_types_master ctm
                  WHERE ctm.type_id = $1`,
                [typeId]
            ),
            pool.query(
                `SELECT company_id, position_role
                   FROM company_employees
                  WHERE employee_id = $1
                    AND is_npc = false
                  ORDER BY company_id`,
                [actor]
            )
        ]);

        if (player.rowCount !== 1) {
            throw new ActionError(404, 'Player not found.');
        }
        if (blueprint.rowCount !== 1) {
            throw new ActionError(404, 'Company blueprint not found.');
        }

        const bp = blueprint.rows[0];
        const setupCost = dbInteger(bp.setup_cost, {
            field: 'Company setup cost'
        });
        if (setupCost < 0n) {
            throw new Error('Company setup cost cannot be negative.');
        }

        const cleanCash = dbInteger(player.rows[0].clean_cash, {
            field: 'Player Clean Cash'
        });
        const dirtyCash = dbInteger(player.rows[0].dirty_cash, {
            field: 'Player Dirty Cash'
        });

        return res.json({
            success: true,
            preflight_status: 'currency_conflict_fail_closed',
            mutation_available: false,
            actor_state: {
                current_job_id: player.rows[0].current_job_id,
                company_roles: employment.rows
            },
            proposed_company: {
                type_id: typeId,
                industry_type: bp.industry_type,
                tier: bp.tier,
                company_name: companyName,
                setup_cost: exactJsonAmount(setupCost)
            },
            catalog_readiness: {
                position_count: String(bp.position_count),
                product_rule_count: String(bp.product_rule_count),
                unresolved_affiliation_count:
                    String(bp.unresolved_affiliation_count),
                source_product_namespace_ready: true,
                source_inventory_storage_ready: true
            },
            currency_reconciliation: {
                status: 'source_conflict',
                gdd_rule: 'Clean Cash buys legitimate businesses.',
                legacy_backend_rule: 'Incorporation debited Dirty Cash.',
                clean_cash_balance: exactJsonAmount(cleanCash),
                dirty_cash_balance: exactJsonAmount(dirtyCash),
                sufficient_if_clean_cash: cleanCash >= setupCost,
                sufficient_if_dirty_cash: dirtyCash >= setupCost
            },
            blockers: [
                'Canonical incorporation setup currency is unresolved.',
                'No setup cost may be debited until that source conflict is adjudicated.',
                'Production, stock ordering, sales settlement and company laundering remain separate paused mechanics.'
            ]
        });
    } catch (err) {
        return sendActionError(res, err, 'Company incorporation preflight failed:');
    }
});

// --- 2. INCORPORATE ---
// Source product identity/storage is now normalized, but setup currency remains
// contradictory across primary project sources. Fail closed rather than
// charging either wallet by inference.
router.post('/incorporate', (_req, res) => {
    return res.status(503).json({
        error: 'Company incorporation is paused until the setup-cost currency conflict is resolved.'
    });
});

// --- 3. PLAYER EMPLOYMENT OFFERS ---
// Real-player company salaries are negotiated in Clean Cash. This read model
// exposes the server-stored offer; no client-side salary or role is authoritative.
router.get('/employment-offers/:user_id', async (req, res) => {
    try {
        const userId = actorId(req);

        const [playerRes, offersRes] = await Promise.all([
            pool.query(
                `SELECT current_job_id, stat_acu, stat_ops, stat_pre, stat_res
                   FROM users
                  WHERE user_id = $1`,
                [userId]
            ),
            pool.query(
                `SELECT o.offer_id,
                        o.application_id,
                        o.company_id,
                        pc.company_name,
                        pc.is_active AS company_is_active,
                        o.position_id,
                        p.role_key,
                        p.req_stat_primary,
                        p.req_amount_primary,
                        p.req_stat_secondary,
                        p.req_amount_secondary,
                        p.gain_primary,
                        p.gain_secondary,
                        o.daily_salary_clean,
                        o.status,
                        o.created_at,
                        o.responded_at
                   FROM company_employment_offers o
                   JOIN player_companies pc ON pc.company_id = o.company_id
                   JOIN company_positions_master p
                     ON p.position_id = o.position_id
                  WHERE o.employee_id = $1
                  ORDER BY
                    CASE WHEN o.status = 'pending' THEN 0 ELSE 1 END,
                    o.created_at DESC,
                    o.offer_id DESC
                  LIMIT 100`,
                [userId]
            )
        ]);

        if (playerRes.rowCount !== 1) {
            throw new ActionError(404, 'Player not found.');
        }

        const player = playerRes.rows[0];
        const offers = offersRes.rows.map(row => {
            let eligible = false;
            let requirements = null;
            try {
                const checked = assertPositionEligibility(player, row);
                eligible = true;
                requirements = {
                    primary: {
                        stat: checked.primary.stat,
                        required: exactJsonAmount(checked.primary.required),
                        actual: exactJsonAmount(checked.primary.actual)
                    },
                    secondary: {
                        stat: checked.secondary.stat,
                        required: exactJsonAmount(checked.secondary.required),
                        actual: exactJsonAmount(checked.secondary.actual)
                    }
                };
            } catch (err) {
                if (!(err instanceof ActionError) || err.status !== 409) throw err;
                requirements = {
                    primary: {
                        stat: row.req_stat_primary,
                        required: exactJsonAmount(
                            dbInteger(row.req_amount_primary, {
                                field: 'Primary position requirement'
                            })
                        ),
                        actual: exactJsonAmount(
                            dbInteger(player['stat_' + row.req_stat_primary], {
                                field: 'Player primary Working Stat'
                            })
                        )
                    },
                    secondary: {
                        stat: row.req_stat_secondary,
                        required: exactJsonAmount(
                            dbInteger(row.req_amount_secondary, {
                                field: 'Secondary position requirement'
                            })
                        ),
                        actual: exactJsonAmount(
                            dbInteger(player['stat_' + row.req_stat_secondary], {
                                field: 'Player secondary Working Stat'
                            })
                        )
                    }
                };
            }

            return {
                offer_id: row.offer_id,
                application_id: row.application_id,
                company_id: row.company_id,
                company_name: row.company_name,
                company_is_active: row.company_is_active === true,
                position_id: row.position_id,
                role_key: row.role_key,
                requirements,
                source_gain_values: {
                    primary: exactJsonAmount(
                        dbInteger(row.gain_primary, { field: 'Primary source gain' })
                    ),
                    secondary: exactJsonAmount(
                        dbInteger(row.gain_secondary, { field: 'Secondary source gain' })
                    )
                },
                daily_salary_clean: exactJsonAmount(
                    dbInteger(row.daily_salary_clean, {
                        field: 'Negotiated Clean Cash salary'
                    })
                ),
                status: row.status,
                created_at: row.created_at,
                responded_at: row.responded_at,
                can_accept:
                    row.status === 'pending' &&
                    row.company_is_active === true &&
                    player.current_job_id === null &&
                    eligible,
                payroll_settlement_available: false
            };
        });

        return res.json({
            success: true,
            employment_contract_status: 'consent_required_payroll_paused',
            offers
        });
    } catch (err) {
        return sendActionError(res, err, 'Employment offers fetch failed:');
    }
});

// --- 4. RESPOND TO EMPLOYMENT OFFER ---
router.post('/employment-offers/respond', async (req, res) => {
    let client, transaction = false;
    try {
        const actor = actorId(req);
        const idempotencyKey = requireIdempotencyKey(req);
        const offerId = integer(req.body?.offer_id, {
            field: 'Employment offer ID', min: 1n, max: 9223372036854775807n
        }).toString();
        const action = req.body?.action;
        if (!['accept', 'reject'].includes(action)) {
            throw new ActionError(400, 'Employment offer action must be accept or reject.');
        }

        client = await pool.connect();
        await client.query('BEGIN');
        transaction = true;

        // Actor first, then idempotency. The actor row also supplies the
        // current Working Stats used for source-position eligibility.
        const player = await client.query(
            `SELECT current_job_id, stat_acu, stat_ops, stat_pre, stat_res
               FROM users
              WHERE user_id = $1
              FOR UPDATE`,
            [actor]
        );
        if (player.rowCount !== 1) {
            throw new ActionError(404, 'Player not found.');
        }

        const idem = await beginIdempotent(
            client,
            actor,
            'company.employment_offer.respond',
            idempotencyKey,
            { offerId, action }
        );
        if (idem.replay) {
            await client.query('COMMIT');
            transaction = false;
            return res.status(idem.status).json(idem.response);
        }

        // Read company ID before row locking so every response locks
        // company -> offer in the same order as Director withdrawal.
        const locator = await client.query(
            `SELECT company_id
               FROM company_employment_offers
              WHERE offer_id = $1`,
            [offerId]
        );
        if (locator.rowCount !== 1) {
            throw new ActionError(404, 'Employment offer not found.');
        }
        const companyId = String(locator.rows[0].company_id);

        const company = await client.query(
            `SELECT pc.company_id, pc.type_id, pc.is_active, ctm.max_employees
               FROM player_companies pc
               JOIN company_types_master ctm ON ctm.type_id = pc.type_id
              WHERE pc.company_id = $1
              FOR UPDATE OF pc`,
            [companyId]
        );
        if (company.rowCount !== 1) {
            throw new ActionError(409, 'Company no longer exists.');
        }

        const offer = await client.query(
            `SELECT offer_id, application_id, company_id, employee_id,
                    position_id, daily_salary_clean, status
               FROM company_employment_offers
              WHERE offer_id = $1
                AND company_id = $2
              FOR UPDATE`,
            [offerId, companyId]
        );
        if (offer.rowCount !== 1) {
            throw new ActionError(404, 'Employment offer not found.');
        }
        const contract = offer.rows[0];

        if (String(contract.employee_id) !== actor) {
            throw new ActionError(403, 'Employment offer belongs to another player.');
        }
        if (contract.status !== 'pending') {
            throw new ActionError(409, 'Employment offer is no longer pending.');
        }

        const application = await client.query(
            `SELECT status
               FROM company_applicants
              WHERE application_id = $1
                AND company_id = $2
                AND user_id = $3
              FOR UPDATE`,
            [contract.application_id, companyId, actor]
        );
        if (application.rowCount !== 1) {
            throw new ActionError(409, 'Employment application no longer matches this offer.');
        }
        if (application.rows[0].status !== 'Pending') {
            throw new ActionError(409, 'Employment application is no longer pending.');
        }

        if (action === 'reject') {
            await client.query(
                `UPDATE company_employment_offers
                    SET status = 'rejected',
                        responded_at = NOW()
                  WHERE offer_id = $1`,
                [offerId]
            );

            const response = {
                success: true,
                message: 'Employment offer rejected. Your application remains pending.',
                offer_id: offerId,
                status: 'rejected'
            };
            await completeIdempotent(client, idem, 200, response);
            await client.query('COMMIT');
            transaction = false;
            return res.json(response);
        }

        if (company.rows[0].is_active !== true) {
            throw new ActionError(409, 'Company is inactive.');
        }
        if (player.rows[0].current_job_id !== null) {
            throw new ActionError(409, 'Resign from your City Job before accepting a company role.');
        }

        const alreadyEmployed = await client.query(
            `SELECT company_id
               FROM company_employees
              WHERE employee_id = $1
                AND is_npc = false
              LIMIT 1`,
            [actor]
        );
        if (alreadyEmployed.rowCount) {
            throw new ActionError(409, 'You are already employed by a company.');
        }

        const staff = await client.query(
            'SELECT COUNT(*)::bigint AS total FROM company_employees WHERE company_id = $1',
            [companyId]
        );
        if (BigInt(staff.rows[0].total) >= BigInt(company.rows[0].max_employees)) {
            throw new ActionError(409, 'Company has reached its recovered base staff capacity.');
        }

        const position = await client.query(
            `SELECT position_id, role_key,
                    req_stat_primary, req_amount_primary,
                    req_stat_secondary, req_amount_secondary
               FROM company_positions_master
              WHERE position_id = $1
                AND type_id = $2`,
            [contract.position_id, company.rows[0].type_id]
        );
        if (position.rowCount !== 1) {
            throw new ActionError(409, 'Offered position no longer belongs to this company type.');
        }

        const eligibility = assertPositionEligibility(
            player.rows[0],
            position.rows[0]
        );
        const salary = dbInteger(contract.daily_salary_clean, {
            field: 'Negotiated Clean Cash salary'
        });
        if (salary <= 0n) {
            throw new Error('Negotiated salary must remain positive.');
        }

        await client.query(
            `INSERT INTO company_employees (
                company_id, employee_id, is_npc, position_role, daily_salary
             )
             VALUES ($1, $2, false, $3, $4::numeric)`,
            [companyId, actor, position.rows[0].role_key, salary.toString()]
        );

        await client.query(
            `UPDATE company_applicants
                SET status = 'Accepted'
              WHERE application_id = $1
                AND company_id = $2`,
            [contract.application_id, companyId]
        );

        await client.query(
            `UPDATE company_employment_offers
                SET status = 'accepted',
                    responded_at = NOW()
              WHERE offer_id = $1`,
            [offerId]
        );

        // Other outstanding offers cannot be accepted after the player takes
        // this job. Close only the offers; do not fabricate application
        // outcomes for other companies.
        await client.query(
            `UPDATE company_employment_offers
                SET status = 'withdrawn',
                    responded_at = NOW()
              WHERE employee_id = $1
                AND offer_id <> $2
                AND status = 'pending'`,
            [actor, offerId]
        );

        await client.query(
            `INSERT INTO company_logs (company_id, log_type, log_text)
             VALUES ($1, 'STAFF', $2)`,
            [
                companyId,
                'Player accepted role ' + position.rows[0].role_key +
                    ' at ' + salary.toString() + ' Clean Cash per day.'
            ]
        );

        const response = {
            success: true,
            message: 'Employment contract accepted. Payroll settlement remains paused.',
            offer_id: offerId,
            company_id: companyId,
            position_id: contract.position_id,
            role_key: position.rows[0].role_key,
            daily_salary_clean: exactJsonAmount(salary),
            status: 'accepted',
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
                console.error('Employment offer response rollback:', rollback);
            }
        }
        return sendActionError(res, err, 'Employment offer response failed:');
    } finally {
        if (client) client.release();
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

        const salaryRes = await pool.query(
            "SELECT COALESCE(SUM(daily_salary), 0) AS total_salaries FROM company_employees WHERE company_id = $1",
            [company_id]
        );
        const totalSalaries = dbInteger(salaryRes.rows[0].total_salaries, {
            field: 'Company daily salaries'
        });
        const dailyUpkeep = dbInteger(company.daily_upkeep, {
            field: 'Company daily upkeep'
        });
        const totalDailyCosts = totalSalaries + dailyUpkeep;

        const bankDirty = dbInteger(company.bank_dirty, {
            field: 'Company Dirty Cash'
        });
        const bankClean = dbInteger(company.bank_clean, {
            field: 'Company Clean Cash'
        });
        const totalFunds = bankDirty + bankClean;

        // Source-backed runway formula is (Dirty + Clean) / (Salaries + Upkeep).
        // Keep the calculation exact by returning one decimal place from integer
        // tenths rather than using JS floating point.
        let runwayDays = null;
        if (totalDailyCosts > 0n) {
            const tenths = totalFunds * 10n / totalDailyCosts;
            runwayDays =
                (tenths / 10n).toString() + '.' + (tenths % 10n).toString();
        }

        const [rosterRes, logsRes, positionsRes, inventoryRes, shipmentsRes, applicantsRes,
            specialsRes, cashLedgerRes, productRulesRes, affiliationsRes, upgradeRes] =
            await Promise.all([
            pool.query(`
                SELECT ce.*, u.username, u.level, u.stat_acu, u.stat_ops, u.stat_pre, u.stat_res
                FROM company_employees ce
                LEFT JOIN users u ON ce.employee_id = u.user_id AND ce.is_npc = false
                WHERE ce.company_id = $1
            `, [company_id]),
            pool.query(`SELECT * FROM company_logs WHERE company_id = $1 ORDER BY created_at DESC LIMIT 50`, [company_id]),
            pool.query(`
                SELECT position_id, type_id, role_name AS name, role_key,
                       req_stat_primary, req_amount_primary,
                       req_stat_secondary, req_amount_secondary,
                       gain_primary, gain_secondary, source_jsonb
                  FROM company_positions_master
                 WHERE type_id = $1
                 ORDER BY position_id ASC
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
                SELECT ca.*,
                       u.username, u.level,
                       u.stat_acu, u.stat_ops, u.stat_pre, u.stat_res,
                       eo.offer_id AS pending_offer_id,
                       eo.position_id AS pending_offer_position_id,
                       eo.daily_salary_clean AS pending_offer_daily_salary_clean,
                       ep.role_key AS pending_offer_role_key
                  FROM company_applicants ca
                  JOIN users u ON ca.user_id = u.user_id
                  LEFT JOIN company_employment_offers eo
                    ON eo.application_id = ca.application_id
                   AND eo.status = 'pending'
                  LEFT JOIN company_positions_master ep
                    ON ep.position_id = eo.position_id
                 WHERE ca.company_id = $1
                   AND ca.status = 'Pending'
                 ORDER BY ca.application_id ASC
            `, [company_id]),
            pool.query(`
                SELECT special_id, type_id, star_requirement AS star,
                       special_name AS name, effect_description AS effect,
                       jp_cost AS cost, is_passive, source_special_key,
                       semantics_status
                  FROM company_specials_master
                 WHERE type_id = $1
                 ORDER BY star_requirement ASC, special_id ASC
            `, [company.type_id]),
            userRole === 'Director'
                ? pool.query(`
                    SELECT entry_id, event_type, dirty_delta, clean_delta,
                           dirty_balance_after, clean_balance_after,
                           source_ref, created_at
                      FROM company_cash_ledger
                     WHERE company_id = $1
                     ORDER BY created_at DESC, entry_id DESC
                     LIMIT 50
                `, [company_id])
                : Promise.resolve({ rows: [] }),
            pool.query(`
                SELECT rule_id, tier, relation_type, product_name,
                       clean_ratio, semantics_status
                  FROM company_product_rules_master
                 WHERE type_id = $1
                 ORDER BY rule_id ASC
            `, [company.type_id]),
            pool.query(`
                SELECT affiliation_id, direction, source_ordinal,
                       related_company_name, related_type_id, resolution_status
                  FROM company_affiliations_master
                 WHERE type_id = $1
                 ORDER BY direction ASC, source_ordinal ASC
            `, [company.type_id]),
            pool.query(`
                SELECT upgrade_id, upgrade_key, cost, upkeep_increase,
                       bonus_key, bonus_value, semantics_status
                  FROM company_upgrades_master
                 WHERE type_id = $1
            `, [company.type_id])
        ]);

        res.json({
            success: true,
            user_role: userRole,
            company,
            runway_days: runwayDays,
            total_daily_costs: exactJsonAmount(totalDailyCosts),
            cash_flow: {
                status: 'funding_only',
                owner_dirty_funding_available: true,
                clean_funding_available: false,
                withdrawals_available: false,
                laundering_conversion_available: false,
                payroll_settlement_available: false,
                sales_settlement_available: false,
                advertising_settlement_available: false,
                bankruptcy_settlement_available: false,
                company_bank_dirty: exactJsonAmount(bankDirty),
                company_bank_clean: exactJsonAmount(bankClean),
                total_daily_salaries_reference: exactJsonAmount(totalSalaries),
                daily_upkeep_reference: exactJsonAmount(dailyUpkeep),
                blockers: [
                    'laundering_tax_formula_unresolved',
                    'acumen_tax_reduction_formula_unresolved',
                    'company_daily_settlement_boundary_unresolved',
                    'employee_salary_contracts_paused',
                    'legacy_product_catalog_conflicts_with_recovered_supply_chain',
                    'tier3_clean_ratio_semantics_unresolved',
                    'bankruptcy_severance_settlement_unresolved'
                ]
            },
            cash_ledger: cashLedgerRes.rows,
            company_catalog: {
                positions_status: 'source_normalized',
                specials_status: 'source_description_only',
                product_rules_status: 'source_normalized_settlement_paused',
                affiliations_status: affiliationsRes.rows.some(
                    row => row.resolution_status !== 'exact'
                ) ? 'contains_unresolved_name_conflicts' : 'source_normalized',
                upgrade_status: 'cost_upkeep_source_normalized_effect_unreconciled',
                product_rules: productRulesRes.rows,
                affiliations: affiliationsRes.rows,
                upgrade: upgradeRes.rows[0] || null
            },
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
        const posRes = await pool.query(`
            SELECT role_name, role_key, req_stat_primary, req_amount_primary,
                   req_stat_secondary, req_amount_secondary,
                   gain_primary, gain_secondary
              FROM company_positions_master
             WHERE type_id = $1
             ORDER BY position_id ASC
        `, [type_id]);
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
