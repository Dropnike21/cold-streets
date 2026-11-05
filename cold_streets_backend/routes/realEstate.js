const express = require('express');
const { createHash } = require('node:crypto');
const router = express.Router();

const db = require('../db');
const { requireOwnedPlayerParam } = require('../middleware/playerIdentity');
const {
    ActionError,
    integer,
    dbInteger,
    exactJsonAmount,
    actorId,
    sendActionError
} = require('../utils/economyValidation');
const {
    requireIdempotencyKey,
    beginIdempotent,
    completeIdempotent
} = require('../utils/idempotency');

router.param('userId', requireOwnedPlayerParam);

const PROPERTY_CATALOG_ROWS = 25;
const PROPERTY_CATALOG_FINGERPRINT = '88ebc5b22740eec9063f344154f56fea';

const LIFECYCLE_BLOCKERS = Object.freeze([
    'player_market_settlement_currency',
    'sale_listing_fee_or_tax',
    'sale_cancellation_rules',
    'lease_contract_terms',
    'gift_transfer_rules',
    'upkeep_payment_currency_and_cadence',
    'property_bonus_stack_order'
]);

function catalogFingerprint(rows) {
    const serialized = rows.map(row => [
        row.id,
        row.tier ?? '',
        row.name,
        row.cost ?? '',
        row.upkeep_type ?? '',
        row.upkeep_val ?? '',
        row.hp_bonus ?? '',
        row.gym_bonus ?? '',
        row.available_upgrades_json ?? ''
    ].map(value => String(value ?? '')).join('|')).join('\n');

    return createHash('md5').update(serialized).digest('hex');
}

function assertPropertyCatalog(rows) {
    if (
        rows.length !== PROPERTY_CATALOG_ROWS ||
        catalogFingerprint(rows) !== PROPERTY_CATALOG_FINGERPRINT
    ) {
        throw new ActionError(
            503,
            'Property catalog changed and requires source reconciliation.'
        );
    }
}

function parseUpgradeCatalog(source) {
    if (source === null || source === undefined || source === '') return {};
    if (typeof source !== 'string') {
        throw new ActionError(503, 'Property upgrade catalog format is unsupported.');
    }

    let parsed;
    try {
        parsed = JSON.parse(source);
    } catch {
        throw new ActionError(503, 'Property upgrade catalog is malformed.');
    }

    if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) {
        throw new ActionError(503, 'Property upgrade catalog must be an object.');
    }

    const normalized = {};
    for (const [upgradeId, spec] of Object.entries(parsed)) {
        if (!/^[a-z][a-z0-9_]{0,63}$/.test(upgradeId)) {
            throw new ActionError(503, 'Property upgrade catalog contains an invalid ID.');
        }
        if (!spec || typeof spec !== 'object' || Array.isArray(spec)) {
            throw new ActionError(503, 'Property upgrade catalog contains an invalid rule.');
        }

        const cost = integer(spec.cost, {
            field: 'Property upgrade catalog cost',
            min: 1n
        });
        const upkeepIncrease = integer(spec.upkeep_increase ?? 0, {
            field: 'Property upgrade upkeep increase',
            min: 0n
        });

        normalized[upgradeId] = {
            id: upgradeId,
            cost: exactJsonAmount(cost),
            upkeep_increase: exactJsonAmount(upkeepIncrease),
            hp_bonus: spec.hp_bonus ?? null,
            gym_bonus: spec.gym_bonus ?? null,
            capacity: spec.capacity ?? null,
            unlocks: Array.isArray(spec.unlocks)
                ? spec.unlocks.map(value => String(value))
                : []
        };
    }

    return normalized;
}

function normalizeInstalledUpgrades(installed, available) {
    if (!installed || typeof installed !== 'object' || Array.isArray(installed)) {
        throw new ActionError(503, 'Owned property upgrade state is malformed.');
    }

    let upkeepIncrease = 0n;
    const ids = [];

    for (const [upgradeId, enabled] of Object.entries(installed)) {
        if (enabled !== true) continue;
        const spec = available[upgradeId];
        if (!spec) {
            throw new ActionError(
                503,
                'Owned property contains an upgrade not present in the recovered catalog.'
            );
        }
        ids.push(upgradeId);
        upkeepIncrease += integer(spec.upkeep_increase, {
            field: 'Property upgrade upkeep increase',
            min: 0n
        });
    }

    ids.sort();
    return {
        ids,
        upkeepIncrease
    };
}

function formatCatalogRow(row) {
    const upgrades = parseUpgradeCatalog(row.available_upgrades_json);
    return {
        id: row.id,
        tier: row.tier,
        name: row.name,
        cost: exactJsonAmount(dbInteger(row.cost, { field: 'Property cost' })),
        upkeep_type: row.upkeep_type,
        base_upkeep: exactJsonAmount(
            dbInteger(row.upkeep_val, { field: 'Property base upkeep' })
        ),
        hp_bonus_source_value: exactJsonAmount(
            dbInteger(row.hp_bonus, { field: 'Property HP bonus source value' })
        ),
        gym_bonus_source_value: row.gym_bonus === null ? null : String(row.gym_bonus),
        available_upgrades: Object.values(upgrades),
        ownership_purchase_available: dbInteger(row.cost, { field: 'Property cost' }) > 0n,
        bonus_application_status: 'unresolved_source_conflict',
        upkeep_collection_status: 'unimplemented'
    };
}

async function loadCatalog(client = db) {
    const result = await client.query(
        `SELECT id, tier, name, cost, upkeep_type, upkeep_val,
                hp_bonus, gym_bonus, available_upgrades_json
           FROM properties_master
          ORDER BY id ASC`
    );
    assertPropertyCatalog(result.rows);
    return result.rows;
}

// 1. RECOVERED PROPERTY CATALOG
router.get('/catalog', async (req, res) => {
    try {
        const rows = await loadCatalog();
        return res.status(200).json({
            catalog_status: 'recovered_spreadsheet_catalog',
            catalog_semantics_status: 'conflicts_with_older_assets_design',
            player_market_status: 'settlement_paused',
            upkeep_status: 'payment_unresolved',
            bonus_status: 'application_unresolved',
            lifecycle_blockers: LIFECYCLE_BLOCKERS,
            catalog: rows.map(formatCatalogRow)
        });
    } catch (error) {
        return sendActionError(res, error, 'Property catalog fetch failed:');
    }
});

// 2. PLAYER PORTFOLIO
router.get('/portfolio/:userId', async (req, res) => {
    try {
        const userId = actorId(req);

        const catalogRows = await loadCatalog();
        const byId = new Map(catalogRows.map(row => [String(row.id), row]));

        const result = await db.query(
            `SELECT op.id AS instance_id,
                    op.property_type_id,
                    op.status,
                    op.upgrades
               FROM owned_properties op
              WHERE op.user_id = $1
              ORDER BY op.id ASC`,
            [userId]
        );

        const portfolio = result.rows.map(row => {
            const catalogRow = byId.get(String(row.property_type_id));
            if (!catalogRow) {
                throw new ActionError(503, 'Owned property references missing catalog data.');
            }

            const available = parseUpgradeCatalog(catalogRow.available_upgrades_json);
            const installed = normalizeInstalledUpgrades(row.upgrades || {}, available);
            const baseUpkeep = dbInteger(catalogRow.upkeep_val, {
                field: 'Property base upkeep'
            });
            const totalUpkeep = baseUpkeep + installed.upkeepIncrease;

            return {
                instance_id: row.instance_id,
                property_type_id: row.property_type_id,
                status: row.status,
                name: catalogRow.name,
                tier: catalogRow.tier,
                acquisition_cost_reference: exactJsonAmount(
                    dbInteger(catalogRow.cost, { field: 'Property cost' })
                ),
                upkeep_type: catalogRow.upkeep_type,
                base_upkeep_reference: exactJsonAmount(baseUpkeep),
                upgrade_upkeep_increase_reference: exactJsonAmount(installed.upkeepIncrease),
                total_upkeep_reference: exactJsonAmount(totalUpkeep),
                hp_bonus_source_value: exactJsonAmount(
                    dbInteger(catalogRow.hp_bonus, {
                        field: 'Property HP bonus source value'
                    })
                ),
                gym_bonus_source_value:
                    catalogRow.gym_bonus === null ? null : String(catalogRow.gym_bonus),
                installed_upgrade_ids: installed.ids,
                available_upgrades: Object.values(available),
                bonus_application_status: 'unresolved_source_conflict',
                upkeep_collection_status: 'unimplemented',
                sale_available: false,
                lease_available: false,
                gift_available: false
            };
        });

        return res.status(200).json({
            portfolio_status: 'ownership_active_lifecycle_partial',
            market_settlement_status: 'paused',
            upkeep_status: 'payment_unresolved',
            bonus_status: 'application_unresolved',
            lifecycle_blockers: LIFECYCLE_BLOCKERS,
            portfolio
        });
    } catch (error) {
        return sendActionError(res, error, 'Property portfolio fetch failed:');
    }
});

// 3. AGENCY PURCHASE
// Source-backed behavior retained:
// - properties are legitimate assets purchased with Clean Cash;
// - property type and price come only from the recovered catalog;
// - starter property (cost 0) is granted exactly once at account creation.
router.post('/buy-agency', async (req, res) => {
    let client;
    let transaction = false;

    try {
        const userId = actorId(req);
        const idempotencyKey = requireIdempotencyKey(req);
        const propertyTypeId = integer(req.body?.propertyTypeId, {
            field: 'Property ID',
            min: 1n,
            max: 9223372036854775807n
        }).toString();

        if (typeof req.body?.autoMoveIn !== 'boolean') {
            throw new ActionError(400, 'autoMoveIn must be a boolean.');
        }

        client = await db.connect();
        await client.query('BEGIN');
        transaction = true;

        const user = await client.query(
            'SELECT clean_cash FROM users WHERE user_id = $1 FOR UPDATE',
            [userId]
        );
        if (user.rowCount !== 1) throw new ActionError(404, 'Player not found.');

        const idem = await beginIdempotent(
            client,
            userId,
            'property.buy_agency',
            idempotencyKey,
            { propertyTypeId, autoMoveIn: req.body.autoMoveIn }
        );

        if (idem.replay) {
            await client.query('COMMIT');
            transaction = false;
            return res.status(idem.status).json(idem.response);
        }

        const catalogRows = await loadCatalog(client);
        const item = catalogRows.find(row => String(row.id) === propertyTypeId);
        if (!item) throw new ActionError(400, 'Property not listed by agency.');

        const cost = dbInteger(item.cost, { field: 'Property catalog price' });
        if (cost <= 0n) {
            throw new ActionError(400, 'Starter properties cannot be purchased again.');
        }

        const balance = dbInteger(user.rows[0].clean_cash, {
            field: 'Clean Cash balance'
        });
        if (balance < cost) throw new ActionError(409, 'Insufficient Clean Cash.');

        const debit = await client.query(
            `UPDATE users
                SET clean_cash = clean_cash - $1::numeric
              WHERE user_id = $2
                AND clean_cash >= $1::numeric
              RETURNING clean_cash`,
            [cost.toString(), userId]
        );
        if (debit.rowCount !== 1) {
            throw new ActionError(409, 'Balance changed before purchase.');
        }

        if (req.body.autoMoveIn) {
            await client.query(
                `UPDATE owned_properties
                    SET status = 'idle'
                  WHERE user_id = $1
                    AND status = 'active_residence'`,
                [userId]
            );
        }

        const finalStatus = req.body.autoMoveIn ? 'active_residence' : 'idle';
        const property = await client.query(
            `INSERT INTO owned_properties (user_id, property_type_id, status)
             VALUES ($1, $2, $3)
             RETURNING id`,
            [userId, propertyTypeId, finalStatus]
        );
        const instanceId = property.rows[0].id;

        // Agency/system acquisition has no player seller.
        await client.query(
            `INSERT INTO property_transactions
                (instance_id, seller_id, buyer_id, transaction_type, amount)
             VALUES ($1, NULL, $2, 'AGENCY_BUY', $3::numeric)`,
            [instanceId, userId, cost.toString()]
        );

        const response = {
            message: 'Property purchased successfully.',
            newInstanceId: instanceId,
            status: finalStatus,
            charged_clean_cash: exactJsonAmount(cost),
            clean_cash: exactJsonAmount(
                dbInteger(debit.rows[0].clean_cash, {
                    field: 'Clean Cash balance'
                })
            ),
            bonus_application_status: 'unresolved_source_conflict',
            upkeep_collection_status: 'unimplemented'
        };

        await completeIdempotent(client, idem, 200, response);
        await client.query('COMMIT');
        transaction = false;
        return res.status(200).json(response);
    } catch (error) {
        if (transaction) {
            try {
                await client.query('ROLLBACK');
            } catch (rollback) {
                console.error('Agency rollback failed:', rollback);
            }
        }
        return sendActionError(res, error, 'Agency purchase failed:');
    } finally {
        if (client) client.release();
    }
});

// 4. PROPERTY UPGRADES
// Recovered upgrade definitions are visible through catalog/portfolio reads,
// but purchase is paused because source conflicts remain around bonus stacking
// and the required upkeep increase is not yet collected authoritatively.
router.post('/upgrade', (req, res) => {
    try {
        actorId(req);
        throw new ActionError(
            503,
            'Property upgrades are paused until bonus stacking and upkeep collection semantics are reconciled.'
        );
    } catch (error) {
        return sendActionError(res, error, 'Property upgrade failed:');
    }
});

// 5. PLAYER PROPERTY MARKET — READ-ONLY UNTIL SETTLEMENT RULES ARE CANONICAL
router.get('/market', async (req, res) => {
    try {
        const result = await db.query(
            `SELECT pmkt.id AS listing_id,
                    pmkt.listing_type,
                    pmkt.asking_price,
                    pmkt.created_at,
                    pmkt.seller_id,
                    u.username AS owner_name,
                    pmast.name AS prop_name,
                    pmast.tier,
                    op.id AS instance_id,
                    op.status,
                    op.upgrades
               FROM property_market pmkt
               JOIN users u ON pmkt.seller_id = u.user_id
               JOIN owned_properties op ON pmkt.instance_id = op.id
               JOIN properties_master pmast ON op.property_type_id = pmast.id
              ORDER BY pmkt.created_at DESC, pmkt.id DESC`
        );

        const listings = result.rows.map(row => ({
            listing_id: row.listing_id,
            listing_type: row.listing_type,
            asking_price: exactJsonAmount(
                dbInteger(row.asking_price, { field: 'Property asking price' })
            ),
            created_at: row.created_at,
            seller_id: row.seller_id,
            owner_name: row.owner_name,
            prop_name: row.prop_name,
            tier: row.tier,
            instance_id: row.instance_id,
            property_status: row.status,
            installed_upgrade_ids: Object.entries(row.upgrades || {})
                .filter(([, enabled]) => enabled === true)
                .map(([id]) => id)
                .sort(),
            purchase_available: false,
            lease_available: false
        }));

        return res.status(200).json({
            market_status: 'read_only_settlement_paused',
            settlement_currency_status: 'unresolved',
            listing_creation_available: false,
            purchase_available: false,
            lease_available: false,
            cancellation_available: false,
            lifecycle_blockers: LIFECYCLE_BLOCKERS,
            listings
        });
    } catch (error) {
        return sendActionError(res, error, 'Property market fetch failed:');
    }
});

// 6. MOVE IN — OWNERSHIP STATE ONLY
router.post('/move-in', async (req, res) => {
    let client;
    let transaction = false;

    try {
        const userId = actorId(req);
        const idempotencyKey = requireIdempotencyKey(req);
        const instanceId = integer(req.body?.instanceId, {
            field: 'Property instance ID',
            min: 1n,
            max: 9223372036854775807n
        }).toString();

        client = await db.connect();
        await client.query('BEGIN');
        transaction = true;

        const user = await client.query(
            'SELECT user_id FROM users WHERE user_id = $1 FOR UPDATE',
            [userId]
        );
        if (user.rowCount !== 1) throw new ActionError(404, 'Player not found.');

        const idem = await beginIdempotent(
            client,
            userId,
            'property.move_in',
            idempotencyKey,
            { instanceId }
        );

        if (idem.replay) {
            await client.query('COMMIT');
            transaction = false;
            return res.status(idem.status).json(idem.response);
        }

        const property = await client.query(
            `SELECT id
               FROM owned_properties
              WHERE id = $1
                AND user_id = $2
              FOR UPDATE`,
            [instanceId, userId]
        );
        if (property.rowCount !== 1) {
            throw new ActionError(404, 'Property not owned by player.');
        }

        await client.query(
            `UPDATE owned_properties
                SET status = 'idle'
              WHERE user_id = $1
                AND status = 'active_residence'`,
            [userId]
        );

        const moved = await client.query(
            `UPDATE owned_properties
                SET status = 'active_residence'
              WHERE id = $1
                AND user_id = $2
              RETURNING id`,
            [instanceId, userId]
        );
        if (moved.rowCount !== 1) {
            throw new Error('Property could not be activated.');
        }

        const response = {
            message: 'Primary residence updated.',
            instance_id: instanceId,
            bonus_application_status: 'unresolved_source_conflict'
        };

        await completeIdempotent(client, idem, 200, response);
        await client.query('COMMIT');
        transaction = false;
        return res.status(200).json(response);
    } catch (error) {
        if (transaction) {
            try {
                await client.query('ROLLBACK');
            } catch (rollback) {
                console.error('Move-in rollback failed:', rollback);
            }
        }
        return sendActionError(res, error, 'Property move-in failed:');
    } finally {
        if (client) client.release();
    }
});

function pausedLifecycleMutation(req, res, action) {
    try {
        actorId(req);
        throw new ActionError(
            503,
            'Property ' + action + ' is paused until the lifecycle settlement rules are reconciled.'
        );
    } catch (error) {
        return sendActionError(res, error, 'Property ' + action + ' failed:');
    }
}

router.post('/market/list-sale', (req, res) =>
    pausedLifecycleMutation(req, res, 'sale listing')
);
router.post('/market/buy', (req, res) =>
    pausedLifecycleMutation(req, res, 'market purchase')
);
router.post('/market/cancel', (req, res) =>
    pausedLifecycleMutation(req, res, 'market cancellation')
);
router.post('/lease', (req, res) =>
    pausedLifecycleMutation(req, res, 'lease')
);
router.post('/give', (req, res) =>
    pausedLifecycleMutation(req, res, 'gift transfer')
);
router.post('/upkeep/pay', (req, res) =>
    pausedLifecycleMutation(req, res, 'upkeep payment')
);

module.exports = router;
