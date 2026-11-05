const express = require('express');
const pool = require('../db');
const router = express.Router();

const { requireOwnedPlayerParam } = require('../middleware/playerIdentity');
const {
    ActionError,
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

function exactCatalogInteger(value, field) {
    return exactJsonAmount(dbInteger(value, { field }));
}

// Recovered source boundary:
// - items_master.is_tradable is authoritative for whether an item can participate.
// - the Player Bazaar exists and is not subject to the NPC market daily item cap.
// - the project does NOT currently establish whether P2P settlement uses Dirty Cash
//   or Clean Cash, nor the fee/expiry/partial-fill rules.
// Therefore this route exposes real eligible inventory and fails closed on all
// economy mutations until those rules are explicitly reconciled.
router.get('/:user_id', async (req, res) => {
    try {
        const userId = actorId(req);

        const [userRes, inventoryRes, listingsRes] = await Promise.all([
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
                `SELECT tl.listing_id,
                        tl.item_id,
                        im.name,
                        tl.quantity_total,
                        tl.quantity_remaining,
                        tl.asking_price,
                        tl.settlement_currency,
                        tl.status,
                        tl.created_at,
                        tl.updated_at,
                        tl.closed_at
                   FROM trade_listings tl
                   JOIN items_master im ON im.item_id = tl.item_id
                  WHERE tl.seller_id = $1
                  ORDER BY tl.created_at DESC, tl.listing_id DESC`,
                [userId]
            )
        ]);

        if (userRes.rowCount !== 1) {
            throw new ActionError(404, 'Player not found.');
        }

        const inventory = inventoryRes.rows.map(row => ({
            item_id: row.item_id,
            name: row.name,
            category: row.category,
            sub_category: row.sub_category,
            description: row.description,
            quantity: exactCatalogInteger(row.quantity, 'Inventory quantity'),
            base_value_reference: exactCatalogInteger(row.base_value, 'Item base value'),
            rarity: row.rarity,
            source: row.source,
            is_tradable: true,
            is_equipped: row.is_equipped === true,
            listing_available: false
        }));

        const listings = listingsRes.rows.map(row => ({
            listing_id: row.listing_id,
            item_id: row.item_id,
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
                : exactCatalogInteger(row.asking_price, 'Trade listing asking price'),
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
            purchase_available: false,
            cancellation_available: false,
            escrow_status: 'schema_ready_mutations_paused',
            escrow_model: 'listing_row_holds_reserved_item_quantity_after_future_atomic_inventory_debit',
            deferred_payout_contract_status: 'available_for_future_seller_proceeds',
            settlement_currency_status: 'unresolved',
            bazaar_access_status: 'unresolved',
            has_bazaar_flag: userRes.rows[0].has_bazaar === true,
            balances: {
                dirty_cash: exactCatalogInteger(userRes.rows[0].dirty_cash, 'Dirty Cash'),
                clean_cash: exactCatalogInteger(userRes.rows[0].clean_cash, 'Clean Cash')
            },
            blockers: SETTLEMENT_BLOCKERS,
            tradable_inventory: inventory,
            seller_listings: listings
        });
    } catch (err) {
        return sendActionError(res, err, 'Trade Network fetch failed:');
    }
});

function pausedMutation(req, res, action) {
    try {
        actorId(req);
        throw new ActionError(
            503,
            'Trade Network ' + action + ' is paused until settlement currency, fees, partial-fill and expiry semantics are reconciled.'
        );
    } catch (err) {
        return sendActionError(res, err, 'Trade Network ' + action + ' failed:');
    }
}

router.post('/list', (req, res) => pausedMutation(req, res, 'listing'));
router.post('/buy', (req, res) => pausedMutation(req, res, 'purchase'));
router.post('/cancel', (req, res) => pausedMutation(req, res, 'cancellation'));

module.exports = router;
