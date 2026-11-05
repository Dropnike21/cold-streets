const { ActionError, dbInteger } = require('./economyValidation');

const BASE_CASINO_DAILY_TOKEN_SPEND_CAP = 100n;
const VIP_CASINO_DAILY_TOKEN_SPEND_CAP = 150n;

const BASE_CITY_MARKET_DAILY_ITEM_LIMIT = 100n;
const SUBSCRIBER_CITY_MARKET_BONUS_PERCENT = 20n;
const SUBSCRIBER_CITY_MARKET_DAILY_ITEM_LIMIT =
    BASE_CITY_MARKET_DAILY_ITEM_LIMIT +
    ((BASE_CITY_MARKET_DAILY_ITEM_LIMIT * SUBSCRIBER_CITY_MARKET_BONUS_PERCENT) / 100n);

const VIP_MAX_ENERGY_TARGET = 200n;
const VIP_NERVE_BONUS_PERCENT = 20n;
const SUBSCRIBER_MONTHLY_VIP_PACK_QUANTITY = 1n;
const SUBSCRIBER_MONTHLY_BOOK_QUANTITY = 1n;

async function getPremiumStatus(client, userId) {
    const [userRes, subscriptionRes, entitlementRes, inventoryRes] =
        await Promise.all([
            client.query(
                'SELECT user_id FROM users WHERE user_id = $1',
                [userId]
            ),
            client.query(
                `SELECT subscription_tier, status, current_period_start,
                        current_period_end, cancel_at_period_end, source_ref,
                        (
                          status = 'active'
                          AND current_period_start <= NOW()
                          AND current_period_end > NOW()
                        ) AS is_active
                   FROM user_subscriptions
                  WHERE user_id = $1`,
                [userId]
            ),
            client.query(
                `SELECT benefit_tier, starts_at, ends_at, source_type, source_ref
                   FROM user_premium_entitlements
                  WHERE user_id = $1
                    AND starts_at <= NOW()
                    AND ends_at > NOW()
                  ORDER BY ends_at DESC, entitlement_id DESC`,
                [userId]
            ),
            client.query(
                `SELECT i.pack_key, c.display_name, i.quantity,
                        i.reserved_quantity, c.duration_days, c.is_tradable,
                        c.activation_available
                   FROM user_premium_pack_inventory i
                   JOIN premium_pack_catalog c
                     ON c.pack_key = i.pack_key
                  WHERE i.user_id = $1
                    AND i.quantity > 0
                  ORDER BY c.display_name, i.pack_key`,
                [userId]
            )
        ]);

    if (userRes.rowCount !== 1) {
        throw new ActionError(404, 'Player not found.');
    }

    const subscription = subscriptionRes.rows[0] || null;
    const subscriberActive = Boolean(
        subscription &&
        subscription.subscription_tier === 'subscriber' &&
        subscription.is_active === true
    );

    const activeEntitlements = entitlementRes.rows;
    const vipPackActive = activeEntitlements.some(
        row => row.benefit_tier === 'vip'
    );
    const kingpinPackActive = activeEntitlements.some(
        row => row.benefit_tier === 'kingpin'
    );

    // User-defined semantics: Subscriber includes the VIP-level benefit set.
    const vipBenefitsActive = subscriberActive || vipPackActive;

    const casinoDailyCap = vipBenefitsActive
        ? VIP_CASINO_DAILY_TOKEN_SPEND_CAP
        : BASE_CASINO_DAILY_TOKEN_SPEND_CAP;

    const cityMarketDailyLimit = subscriberActive
        ? SUBSCRIBER_CITY_MARKET_DAILY_ITEM_LIMIT
        : BASE_CITY_MARKET_DAILY_ITEM_LIMIT;

    return {
        subscriberActive,
        subscription,
        vipPackActive,
        kingpinPackActive,
        vipBenefitsActive,
        activeEntitlements,
        packInventory: inventoryRes.rows.map(row => ({
            ...row,
            quantity: dbInteger(row.quantity, {
                field: 'Premium pack inventory quantity'
            }),
            reserved_quantity: dbInteger(row.reserved_quantity, {
                field: 'Premium pack reserved quantity'
            })
        })),
        effectiveBenefits: {
            casinoDailyTokenSpendCap: casinoDailyCap,
            cityMarketDailyItemLimit: cityMarketDailyLimit,
            maxEnergyTarget: vipBenefitsActive ? VIP_MAX_ENERGY_TARGET : null,
            nerveBonusPercent: vipBenefitsActive ? VIP_NERVE_BONUS_PERCENT : null,
            nerveSemantics: vipBenefitsActive
                ? 'unresolved_exact_application'
                : null
        }
    };
}

module.exports = {
    BASE_CASINO_DAILY_TOKEN_SPEND_CAP,
    VIP_CASINO_DAILY_TOKEN_SPEND_CAP,
    BASE_CITY_MARKET_DAILY_ITEM_LIMIT,
    SUBSCRIBER_CITY_MARKET_BONUS_PERCENT,
    SUBSCRIBER_CITY_MARKET_DAILY_ITEM_LIMIT,
    VIP_MAX_ENERGY_TARGET,
    VIP_NERVE_BONUS_PERCENT,
    SUBSCRIBER_MONTHLY_VIP_PACK_QUANTITY,
    SUBSCRIBER_MONTHLY_BOOK_QUANTITY,
    getPremiumStatus
};
