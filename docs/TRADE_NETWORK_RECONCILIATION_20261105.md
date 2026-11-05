# Trade Network / Player Bazaar Reconciliation — 2026-11-05

## Scope

This pass replaces the mock Trade Network with a source-backed read boundary and records the settlement rules that remain unresolved.

No player-to-player money or item transfer is enabled in this pass.

No gameplay/runtime/build tests or production deployment were performed.

## Recovered evidence

### Original item design

The original **Master Items Canvas** explicitly states:

- city NPC markets have a strict 100-item-per-day purchase limit;
- the **Player Bazaar remains unlimited**.

The recovered item catalog also has an explicit `items_master.is_tradable` flag.

Development catalog counts at reconciliation time:

- 643 tradable items;
- 68 non-tradable items;
- 0 rows with unspecified tradability.

The 643 tradable rows span the recovered catalog categories:

- ARTIFACTS
- CONSUMABLES
- GEAR
- GENERAL
- MATERIALS
- SPECIAL ITEMS
- SUPPLY PACKS
- TOOLS
- VEHICLES
- WEAPONS

Therefore `is_tradable = true` is the only currently authoritative item-eligibility rule for a future P2P item market.

### Technical Master

The original Technical Master establishes the security model for trading/economy actions:

- economy logic, including **trading**, must use PostgreSQL transactions;
- server authority is required rather than trusting client state.

That supports the future transaction/locking/idempotency design but does not define the P2P currency or fee rules.

### Project recovery reference

The recovery Project Master identifies the Trade Network as partial:

- mock listing data;
- stub purchase callback;
- no real trading API/escrow.

Its M3 target requires a Trade Network with escrow.

This is a recovery requirement, not evidence for missing economic values.

## Critical unresolved rule: settlement currency

Cold Streets has separate:

- Dirty Cash;
- Clean Cash.

The current Trade Network mock UI displays generic dollar prices but does not establish which balance is debited/credited.

The recovered original sources found in this pass do not unambiguously specify whether Player Bazaar settlement uses:

- Dirty Cash;
- Clean Cash;
- seller-selectable currency;
- or another rule.

Because those balances have different game purposes, the implementation must not infer one from the generic `$` symbol.

This blocks purchase settlement.

## Other unresolved rules

The source set also does not currently establish:

1. listing fee or transaction tax;
2. whether partial stack purchases are allowed;
3. listing expiration duration;
4. cancellation/refund rules;
5. precise `users.has_bazaar` unlock/access semantics;
6. whether an equipped item can be listed and, if so, how equipment is atomically cleared;
7. whether listing price has any required relationship to catalog `base_value`;
8. seller proceeds timing (immediate settlement vs claimable escrow balance).

These are not invented.

## Current database state

There was no recovered P2P trade/listing/escrow table in the development schema.

The only table matching trade/market/listing/escrow naming was `property_market`, which belongs to the property system and is not reused for item trading.

`user_inventory` already has:

- primary key on `inventory_id`;
- unique `(user_id, item_id)`;
- foreign keys to `users` and `items_master`;
- `quantity >= 0`.

The development database currently has no player rows, so there is no existing P2P trade state to migrate.

## Backend changes

New route:

`GET /trade-network/:user_id`

It:

- requires authenticated actor ownership;
- reads only the authenticated player's inventory;
- returns only rows whose catalog item has `is_tradable = true`;
- returns quantities using exact integer handling;
- returns catalog base value as **reference data only**, never as a listing price;
- reports whether an item is currently equipped;
- returns the existing `has_bazaar` flag as information only;
- returns both cash balances for state visibility but performs no transfer;
- explicitly reports settlement/listing/escrow as paused.

The response includes:

- `network_status: reconciliation_paused`
- `listing_creation_available: false`
- `purchase_available: false`
- `cancellation_available: false`
- `escrow_status: not_created`
- `settlement_currency_status: unresolved`
- `bazaar_access_status: unresolved`

### Fail-closed mutation boundaries

The following authenticated endpoints now exist but return 503 and mutate nothing:

- `POST /trade-network/list`
- `POST /trade-network/buy`
- `POST /trade-network/cancel`

No listing or escrow table is created yet because doing so before the settlement model is defined would either lock items into unusable listings or bake an unsupported currency/partial-fill model into the schema.

## Database hardening

Migration:

`20261104230500_trade_network_inventory_index_20261105.sql`

adds:

`user_inventory(item_id)`

This supports item-centric inventory joins and covers the existing `user_inventory_item_id_fkey` performance warning.

No trade settlement schema is introduced.

## Flutter companion

Draft PR #5 now removes the mock Trade Network marketplace.

Removed behavior/data includes:

- fake sellers;
- fake listing IDs;
- fake prices;
- fake circulation values;
- hardcoded category/subcategory taxonomy;
- fixed 500-page pagination;
- stub purchase snackbar.

The view now:

- calls the authenticated Trade Network backend;
- displays the player's real `is_tradable=true` stash;
- shows quantity;
- shows catalog category/subcategory;
- shows whether the item is equipped;
- shows catalog base value explicitly as a reference;
- displays the source-reconciliation blockers;
- does not expose listing/buy controls.

The drawer label is now simply **Trade Network**.

## Security requirements for the future settlement implementation

Once the missing rules are made canonical, listing/buy/cancel must use:

- authenticated actor identity only;
- client-supplied item ID/quantity/requested listing price only where the design explicitly allows seller choice;
- server-verified `is_tradable`;
- exact integer cash and quantity handling;
- one transaction per mutation;
- deterministic row locks;
- inventory reservation/escrow so listed stock cannot be spent twice;
- persistent idempotency for create/buy/cancel;
- no self-purchase;
- conditional balance updates preventing negative balances;
- immutable settlement history;
- fail-closed behavior on stale/closed listings.

## Verification boundary

Performed:

- original Drive source reconciliation;
- current Git implementation review;
- development schema/catalog inspection;
- development migration application;
- static backend/client readback;
- Supabase advisor review.

Not performed by instruction:

- gameplay tests;
- Node runtime tests;
- concurrency tests;
- Flutter analyze/build/widget tests;
- deployment;
- production changes.
