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

        const [userRes, inventoryRes] = await Promise.all([
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

        return res.json({
            success: true,
            network_status: 'reconciliation_paused',
            listing_creation_available: false,
            purchase_available: false,
            cancellation_available: false,
            escrow_status: 'not_created',
            settlement_currency_status: 'unresolved',
            bazaar_access_status: 'unresolved',
            has_bazaar_flag: userRes.rows[0].has_bazaar === true,
            balances: {
                dirty_cash: exactCatalogInteger(userRes.rows[0].dirty_cash, 'Dirty Cash'),
                clean_cash: exactCatalogInteger(userRes.rows[0].clean_cash, 'Clean Cash')
            },
            blockers: SETTLEMENT_BLOCKERS,
            tradable_inventory: inventory
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
            'Trade Network ' + action + ' is paused until settlement currency and escrow semantics are reconciled.'
        );
    } catch (err) {
        return sendActionError(res, err, 'Trade Network ' + action + ' failed:');
    }
}

router.post('/list', (req, res) => pausedMutation(req, res, 'listing'));
router.post('/buy', (req, res) => pausedMutation(req, res, 'purchase'));
router.post('/cancel', (req, res) => pausedMutation(req, res, 'cancellation'));

module.exports = router;
