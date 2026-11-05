const express = require('express');
const pool = require('../db');
const router = express.Router();

const { requireOwnedPlayerParam } = require('../middleware/playerIdentity');
const {
    ActionError,
    integer,
    dbInteger,
    exactJsonAmount,
    actorId,
    sendActionError
} = require('../utils/economyValidation');

router.param('user_id', requireOwnedPlayerParam);

const SETTLEMENT_BLOCKERS = Object.freeze([
    'settlement_currency',
    'listing_fee_or_tax',
    'partial_purchase_semantics',
    'listing_expiry',
    'seller_proceeds_timing',
    'bazaar_access_semantics',
    'equipped_item_listing_semantics'
]);

const ASSET_NAMESPACES = Object.freeze([
    'item',
    'premium_pack'
]);

function exactCatalogInteger(value, field) {
    return exactJsonAmount(dbInteger(value, { field }));
}

function normalizeAssetIntent(body) {
    if (!body || typeof body !== 'object' || Array.isArray(body)) {
        throw new ActionError(400, 'Asset identity and quantity are required.');
    }

    const allowed = new Set([
        'asset_namespace',
        'item_id',
        'pack_key',
        'quantity'
    ]);
    const bodyKeys = Object.keys(body);
    if (bodyKeys.some(key => !allowed.has(key))) {
        throw new ActionError(
            400,
            'Listing preflight accepts only asset namespace, canonical asset identity and quantity.'
        );
    }

    const quantity = integer(body.quantity, {
        field: 'Listing quantity',
        min: 1n,
        max: 9223372036854775807n
    });

    const namespace = body.asset_namespace == null
        ? (body.item_id != null ? 'item' : null)
        : String(body.asset_namespace).trim();

    if (!ASSET_NAMESPACES.includes(namespace)) {
        throw new ActionError(400, 'Unsupported Trade asset namespace.');
    }

    if (namespace === 'item') {
        if (body.pack_key != null) {
            throw new ActionError(
                400,
                'Regular item preflight cannot include a premium pack key.'
            );
        }
        return {
            namespace,
            itemId: integer(body.item_id, {
                field: 'Item ID',
                min: 1n,
                max: 9223372036854775807n
            }).toString(),
            packKey: null,
            quantity
        };
    }

    if (body.item_id != null) {
        throw new ActionError(
            400,
            'Premium pack preflight cannot include a regular item ID.'
        );
    }
    if (typeof body.pack_key !== 'string') {
        throw new ActionError(400, 'Premium pack key is required.');
    }
    const packKey = body.pack_key.trim();
    if (packKey.length < 1 || packKey.length > 100 ||
        !/^[a-z0-9_]+$/.test(packKey)) {
        throw new ActionError(400, 'Premium pack key is invalid.');
    }

    return {
        namespace,
        itemId: null,
        packKey,
        quantity
    };
}

// Recovered/user-defined boundary:
// - items_master.is_tradable is authoritative for normal item participation.
// - premium_pack_catalog.is_tradable is authoritative for VIP/Kingpin Packs.
// - Player Bazaar is outside the NPC city-market daily purchase cap.
// - settlement currency/fees/fill/expiry/access semantics remain unresolved.
// Therefore only read/preflight surfaces are open.
router.get('/:user_id', async (req, res) => {
    try {
        const userId = actorId(req);

        const [
            userRes,
            inventoryRes,
            premiumInventoryRes,
            listingsRes
        ] = await Promise.all([
            pool.query(
                'SELECT has_bazaar, dirty_cash, clean_cash FROM users WHERE user_id = $1',
                [userId]
            ),
            pool.query(
                `SELECT
                    ui.item_id,
                    ui.quantity,
                    im.name,
                    im.category,
                    im.sub_category,
                    im.description,
                    im.base_value,
                    im.rarity,
                    im.source,
                    im.is_tradable,
                    CASE
                        WHEN ue.primary_weapon_id = ui.item_id
                          OR ue.secondary_weapon_id = ui.item_id
                          OR ue.melee_weapon_id = ui.item_id
                          OR ue.armor_id = ui.item_id
                        THEN TRUE ELSE FALSE
                    END AS is_equipped
                 FROM user_inventory ui
                 JOIN items_master im ON im.item_id = ui.item_id
                 LEFT JOIN user_equipment ue ON ue.user_id = ui.user_id
                WHERE ui.user_id = $1
                  AND ui.quantity > 0
                  AND im.is_tradable IS TRUE
                ORDER BY im.category ASC NULLS LAST,
                         im.sub_category ASC NULLS LAST,
                         im.name ASC,
                         ui.item_id ASC`,
                [userId]
            ),
            pool.query(
                `SELECT ppi.pack_key,
                        ppc.display_name,
                        ppi.quantity,
                        ppi.reserved_quantity,
                        ppc.duration_days,
                        ppc.is_tradable,
                        ppc.activation_available
                   FROM user_premium_pack_inventory ppi
                   JOIN premium_pack_catalog ppc
                     ON ppc.pack_key = ppi.pack_key
                  WHERE ppi.user_id = $1
                    AND ppi.quantity > 0
                    AND ppc.is_tradable IS TRUE
                  ORDER BY ppc.display_name, ppi.pack_key`,
                [userId]
            ),
            pool.query(
                `SELECT tl.listing_id,
                        tl.asset_namespace,
                        tl.item_id,
                        tl.premium_pack_key,
                        COALESCE(im.name, ppc.display_name) AS name,
                        tl.quantity_total,
                        tl.quantity_remaining,
                        tl.asking_price,
                        tl.settlement_currency,
                        tl.status,
                        tl.created_at,
                        tl.updated_at,
                        tl.closed_at
                   FROM trade_listings tl
                   LEFT JOIN items_master im
                     ON tl.asset_namespace = 'item'
                    AND im.item_id = tl.item_id
                   LEFT JOIN premium_pack_catalog ppc
                     ON tl.asset_namespace = 'premium_pack'
                    AND ppc.pack_key = tl.premium_pack_key
                  WHERE tl.seller_id = $1
                  ORDER BY tl.created_at DESC, tl.listing_id DESC`,
                [userId]
            )
        ]);

        if (userRes.rowCount !== 1) {
            throw new ActionError(404, 'Player not found.');
        }

        const inventory = inventoryRes.rows.map(row => ({
            asset_namespace: 'item',
            item_id: row.item_id,
            name: row.name,
            category: row.category,
            sub_category: row.sub_category,
            description: row.description,
            quantity: exactCatalogInteger(
                row.quantity,
                'Inventory quantity'
            ),
            base_value_reference: exactCatalogInteger(
                row.base_value,
                'Item base value'
            ),
            rarity: row.rarity,
            source: row.source,
            is_tradable: true,
            is_equipped: row.is_equipped === true,
            listing_available: false
        }));

        const premiumInventory = premiumInventoryRes.rows.map(row => {
            const quantity = dbInteger(row.quantity, {
                field: 'Premium pack inventory quantity'
            });
            const reserved = dbInteger(row.reserved_quantity, {
                field: 'Premium pack reserved quantity'
            });
            return {
                asset_namespace: 'premium_pack',
                pack_key: row.pack_key,
                name: row.display_name,
                quantity: exactJsonAmount(quantity),
                reserved_quantity: exactJsonAmount(reserved),
                available_quantity: exactJsonAmount(quantity - reserved),
                duration_days: row.duration_days,
                is_tradable: true,
                activation_available: row.activation_available === true,
                listing_available: false
            };
        });

        const listings = listingsRes.rows.map(row => ({
            listing_id: row.listing_id,
            asset_namespace: row.asset_namespace,
            item_id: row.item_id,
            premium_pack_key: row.premium_pack_key,
            name: row.name,
            quantity_total: exactCatalogInteger(
                row.quantity_total,
                'Trade listing total quantity'
            ),
            quantity_remaining: exactCatalogInteger(
                row.quantity_remaining,
                'Trade listing remaining quantity'
            ),
            asking_price: row.asking_price == null
                ? null
                : exactCatalogInteger(
                    row.asking_price,
                    'Trade listing asking price'
                ),
            settlement_currency: row.settlement_currency,
            status: row.status,
            created_at: row.created_at,
            updated_at: row.updated_at,
            closed_at: row.closed_at,
            settlement_available: false
        }));

        return res.json({
            success: true,
            network_status: 'reconciliation_paused',
            listing_creation_available: false,
            listing_preflight_available: true,
            purchase_available: false,
            cancellation_available: false,
            escrow_status: 'asset_namespace_ready_mutations_paused',
            escrow_asset_namespaces: ASSET_NAMESPACES,
            escrow_model:
                'future atomic reservation by canonical asset namespace and identity',
            deferred_payout_contract_status:
                'available_for_future_seller_proceeds',
            settlement_currency_status: 'unresolved',
            bazaar_access_status: 'unresolved',
            player_bazaar_npc_daily_cap_status:
                'not_applicable_by_source',
            premium_pack_marketability_status:
                'catalog_and_preflight_ready_settlement_paused',
            has_bazaar_flag: userRes.rows[0].has_bazaar === true,
            balances: {
                dirty_cash: exactCatalogInteger(
                    userRes.rows[0].dirty_cash,
                    'Dirty Cash'
                ),
                clean_cash: exactCatalogInteger(
                    userRes.rows[0].clean_cash,
                    'Clean Cash'
                )
            },
            blockers: SETTLEMENT_BLOCKERS,
            tradable_inventory: inventory,
            tradable_premium_packs: premiumInventory,
            seller_listings: listings
        });
    } catch (err) {
        return sendActionError(res, err, 'Trade Network fetch failed:');
    }
});

router.post('/listing-preflight', async (req, res) => {
    try {
        const userId = actorId(req);
        const intent = normalizeAssetIntent(req.body);

        const userPromise = pool.query(
            'SELECT has_bazaar FROM users WHERE user_id = $1',
            [userId]
        );

        let assetPromise;
        let listingPromise;

        if (intent.namespace === 'item') {
            assetPromise = pool.query(
                `SELECT ui.quantity,
                        0::bigint AS reserved_quantity,
                        im.item_id,
                        NULL::text AS pack_key,
                        im.name,
                        im.category,
                        im.sub_category,
                        im.base_value,
                        im.rarity,
                        im.source,
                        im.is_tradable,
                        NULL::integer AS duration_days,
                        CASE
                            WHEN ue.primary_weapon_id = ui.item_id
                              OR ue.secondary_weapon_id = ui.item_id
                              OR ue.melee_weapon_id = ui.item_id
                              OR ue.armor_id = ui.item_id
                            THEN TRUE ELSE FALSE
                        END AS is_equipped
                   FROM user_inventory ui
                   JOIN items_master im ON im.item_id = ui.item_id
                   LEFT JOIN user_equipment ue ON ue.user_id = ui.user_id
                  WHERE ui.user_id = $1
                    AND ui.item_id = $2`,
                [userId, intent.itemId]
            );
            listingPromise = pool.query(
                `SELECT COUNT(*)::bigint AS row_count,
                        COALESCE(SUM(quantity_remaining), 0)::bigint
                          AS quantity_remaining
                   FROM trade_listings
                  WHERE seller_id = $1
                    AND asset_namespace = 'item'
                    AND item_id = $2
                    AND status IN ('draft', 'open', 'reserved')`,
                [userId, intent.itemId]
            );
        } else {
            assetPromise = pool.query(
                `SELECT ppi.quantity,
                        ppi.reserved_quantity,
                        NULL::bigint AS item_id,
                        ppi.pack_key,
                        ppc.display_name AS name,
                        'PREMIUM'::text AS category,
                        'PACK'::text AS sub_category,
                        NULL::numeric AS base_value,
                        NULL::text AS rarity,
                        'premium'::text AS source,
                        ppc.is_tradable,
                        ppc.duration_days,
                        FALSE AS is_equipped
                   FROM user_premium_pack_inventory ppi
                   JOIN premium_pack_catalog ppc
                     ON ppc.pack_key = ppi.pack_key
                  WHERE ppi.user_id = $1
                    AND ppi.pack_key = $2`,
                [userId, intent.packKey]
            );
            listingPromise = pool.query(
                `SELECT COUNT(*)::bigint AS row_count,
                        COALESCE(SUM(quantity_remaining), 0)::bigint
                          AS quantity_remaining
                   FROM trade_listings
                  WHERE seller_id = $1
                    AND asset_namespace = 'premium_pack'
                    AND premium_pack_key = $2
                    AND status IN ('draft', 'open', 'reserved')`,
                [userId, intent.packKey]
            );
        }

        const [userRes, assetRes, listingRes] = await Promise.all([
            userPromise,
            assetPromise,
            listingPromise
        ]);

        if (userRes.rowCount !== 1) {
            throw new ActionError(404, 'Player not found.');
        }
        if (assetRes.rowCount !== 1) {
            throw new ActionError(
                409,
                'This Trade asset is not present in your inventory.'
            );
        }

        const asset = assetRes.rows[0];
        const owned = dbInteger(asset.quantity, {
            field: 'Trade asset inventory quantity'
        });
        const reserved = dbInteger(asset.reserved_quantity, {
            field: 'Trade asset reserved quantity'
        });
        if (owned < 1n || reserved < 0n || reserved > owned) {
            throw new ActionError(
                409,
                'This Trade asset has no available inventory.'
            );
        }

        const available = owned - reserved;
        const tradable = asset.is_tradable === true;
        const equipped = asset.is_equipped === true;
        const quantityAvailable = available >= intent.quantity;
        const inventoryPreflightPassed =
            tradable && !equipped && quantityAvailable;

        return res.json({
            success: true,
            preflight_status: inventoryPreflightPassed
                ? 'inventory_snapshot_ready_settlement_blocked'
                : 'inventory_snapshot_blocked',
            mutation_available: false,
            asset: {
                asset_namespace: intent.namespace,
                item_id: asset.item_id,
                pack_key: asset.pack_key,
                name: asset.name,
                category: asset.category,
                sub_category: asset.sub_category,
                rarity: asset.rarity,
                source: asset.source,
                duration_days: asset.duration_days,
                is_tradable: tradable,
                is_equipped: equipped,
                base_value_reference: asset.base_value == null
                    ? null
                    : exactCatalogInteger(
                        asset.base_value,
                        'Item base value'
                    )
            },
            quantity: {
                requested: exactJsonAmount(intent.quantity),
                owned_snapshot: exactJsonAmount(owned),
                reserved_snapshot: exactJsonAmount(reserved),
                available_snapshot: exactJsonAmount(available),
                sufficient_snapshot: quantityAvailable
            },
            existing_nonterminal_listings: {
                rows: exactCatalogInteger(
                    listingRes.rows[0].row_count,
                    'Existing listing row count'
                ),
                quantity_remaining: exactCatalogInteger(
                    listingRes.rows[0].quantity_remaining,
                    'Existing listed quantity'
                ),
                listing_rows_treated_as_inventory_reservation: false
            },
            bazaar: {
                has_bazaar_flag: userRes.rows[0].has_bazaar === true,
                access_semantics_status: 'unresolved',
                npc_daily_purchase_cap_applies: false,
                source_status:
                    'player_bazaar_unlimited_by_npc_market_cap'
            },
            inventory_preflight_passed: inventoryPreflightPassed,
            blockers: [
                ...(tradable
                    ? []
                    : ['Canonical asset catalog marks this asset non-tradable.']),
                ...(equipped
                    ? ['Equipped-item listing semantics are unresolved; fail closed.']
                    : []),
                ...(quantityAvailable
                    ? []
                    : ['Requested quantity exceeds available inventory.']),
                'Settlement currency is unresolved.',
                'Listing fee or tax is unresolved.',
                'Partial-fill semantics are unresolved.',
                'Listing expiry is unresolved.',
                'Seller proceeds timing is unresolved.',
                'Bazaar access semantics are unresolved.'
            ]
        });
    } catch (err) {
        return sendActionError(res, err, 'Trade listing preflight failed:');
    }
});

function pausedMutation(req, res, action) {
    try {
        actorId(req);
        throw new ActionError(
            503,
            'Trade Network ' + action +
                ' is paused until settlement currency, fees, partial-fill and expiry semantics are reconciled.'
        );
    } catch (err) {
        return sendActionError(
            res,
            err,
            'Trade Network ' + action + ' failed:'
        );
    }
}

router.post('/list', (req, res) => pausedMutation(req, res, 'listing'));
router.post('/buy', (req, res) => pausedMutation(req, res, 'purchase'));
router.post('/cancel', (req, res) => pausedMutation(req, res, 'cancellation'));

module.exports = router;
