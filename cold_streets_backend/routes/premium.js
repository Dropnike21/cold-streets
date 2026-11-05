const express = require('express');
const pool = require('../db');
const router = express.Router();

const {
    ActionError,
    actorId,
    dbInteger,
    exactJsonAmount,
    sendActionError
} = require('../utils/economyValidation');
const {
    BASE_CASINO_DAILY_TOKEN_SPEND_CAP,
    VIP_CASINO_DAILY_TOKEN_SPEND_CAP,
    BASE_CITY_MARKET_DAILY_ITEM_LIMIT,
    SUBSCRIBER_CITY_MARKET_BONUS_PERCENT,
    SUBSCRIBER_CITY_MARKET_DAILY_ITEM_LIMIT,
    VIP_MAX_ENERGY_TARGET,
    VIP_NERVE_BONUS_PERCENT,
    getPremiumStatus
} = require('../utils/premiumEntitlements');

router.get('/status', async (req, res) => {
    try {
        const userId = actorId(req);
        const [status, catalogRes] = await Promise.all([
            getPremiumStatus(pool, userId),
            pool.query(
                `SELECT pack_key, display_name, duration_days, is_tradable,
                        activation_available, max_energy_override,
                        nerve_bonus_percent, nerve_semantics,
                        casino_daily_spend_cap, benefit_notes
                   FROM premium_pack_catalog
                  ORDER BY pack_key`
            )
        ]);

        const catalog = catalogRes.rows.map(row => ({
            pack_key: row.pack_key,
            display_name: row.display_name,
            duration_days: row.duration_days,
            is_tradable: row.is_tradable === true,
            activation_available: row.activation_available === true,
            max_energy_override: row.max_energy_override == null
                ? null
                : exactJsonAmount(dbInteger(row.max_energy_override, {
                    field: 'Premium pack Max Energy target'
                })),
            nerve_bonus_percent: row.nerve_bonus_percent,
            nerve_semantics: row.nerve_semantics,
            casino_daily_spend_cap: row.casino_daily_spend_cap == null
                ? null
                : exactJsonAmount(dbInteger(row.casino_daily_spend_cap, {
                    field: 'Premium pack Casino daily cap'
                })),
            benefit_notes: row.benefit_notes
        }));

        return res.json({
            success: true,
            premium_status: 'foundation_ready_mutations_paused',
            subscriber_active: status.subscriberActive,
            subscription: status.subscription,
            vip_pack_active: status.vipPackActive,
            kingpin_pack_active: status.kingpinPackActive,
            vip_benefits_active: status.vipBenefitsActive,
            active_entitlements: status.activeEntitlements,
            pack_inventory: status.packInventory.map(row => ({
                pack_key: row.pack_key,
                display_name: row.display_name,
                quantity: exactJsonAmount(row.quantity),
                reserved_quantity: exactJsonAmount(row.reserved_quantity),
                available_quantity: exactJsonAmount(
                    row.quantity - row.reserved_quantity
                ),
                duration_days: row.duration_days,
                is_tradable: row.is_tradable === true,
                activation_available: row.activation_available === true
            })),
            effective_benefits: {
                casino_daily_token_spend_cap: exactJsonAmount(
                    status.effectiveBenefits.casinoDailyTokenSpendCap
                ),
                city_market_daily_item_limit: exactJsonAmount(
                    status.effectiveBenefits.cityMarketDailyItemLimit
                ),
                max_energy_target: status.effectiveBenefits.maxEnergyTarget == null
                    ? null
                    : exactJsonAmount(status.effectiveBenefits.maxEnergyTarget),
                nerve_bonus_percent:
                    status.effectiveBenefits.nerveBonusPercent,
                nerve_semantics:
                    status.effectiveBenefits.nerveSemantics
            },
            source_rules: {
                base_casino_daily_token_spend_cap:
                    exactJsonAmount(BASE_CASINO_DAILY_TOKEN_SPEND_CAP),
                vip_casino_daily_token_spend_cap:
                    exactJsonAmount(VIP_CASINO_DAILY_TOKEN_SPEND_CAP),
                base_city_market_daily_item_limit:
                    exactJsonAmount(BASE_CITY_MARKET_DAILY_ITEM_LIMIT),
                subscriber_city_market_bonus_percent:
                    exactJsonAmount(SUBSCRIBER_CITY_MARKET_BONUS_PERCENT),
                subscriber_city_market_daily_item_limit:
                    exactJsonAmount(SUBSCRIBER_CITY_MARKET_DAILY_ITEM_LIMIT),
                vip_max_energy_target:
                    exactJsonAmount(VIP_MAX_ENERGY_TARGET),
                vip_nerve_bonus_percent:
                    exactJsonAmount(VIP_NERVE_BONUS_PERCENT)
            },
            blockers: [
                'VIP Pack activation remains paused until the +20% Nerve rule has an exact application semantic and the remaining VIP benefit list is final.',
                'Kingpin Pack activation remains paused until its exact benefit set is defined.',
                'Pack purchase/payment issuance is not connected.',
                'Subscriber activation/billing lifecycle is not connected.',
                'Subscriber monthly Book grant is paused until the Book catalog and boost semantics are authoritative.',
                'Subscriber monthly VIP Pack issuance cadence needs a persistent settlement worker before activation.'
            ],
            mutations_available: {
                consume_pack: false,
                buy_pack: false,
                activate_subscription: false,
                subscriber_monthly_grant: false
            },
            vip_pass_catalog_collision: false,
            vip_pass_note:
                'Recovered item named VIP Pass is a separate legacy item and is not treated as VIP Pack.'
        });
    } catch (err) {
        return sendActionError(res, err, 'Premium status failed:');
    }
});

function pausedMutation(req, res, action) {
    try {
        actorId(req);
        throw new ActionError(
            503,
            action + ' is paused pending complete premium benefit and billing reconciliation.'
        );
    } catch (err) {
        return sendActionError(res, err, 'Premium mutation failed:');
    }
}

router.post('/consume-pack', (req, res) =>
    pausedMutation(req, res, 'Premium pack consumption')
);
router.post('/subscribe', (req, res) =>
    pausedMutation(req, res, 'Subscriber activation')
);

module.exports = router;
