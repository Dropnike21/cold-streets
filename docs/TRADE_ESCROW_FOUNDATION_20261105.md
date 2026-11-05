# Trade Network Escrow Foundation — 2026-11-05

## Scope

This pass adds the database substrate required by the recovered Project Master
requirement that the Player Trade Network use escrow.

It does not activate listing, buying or cancellation because the source set still
does not establish:

- Dirty Cash vs Clean Cash settlement;
- listing fee/tax;
- partial-stack purchase semantics;
- listing expiry;
- seller proceeds timing;
- bazaar access semantics;
- equipped-item listing behavior.

No gameplay/build/runtime tests or deployment were performed.

## Source boundary

Recovered source supports:

- a Player Bazaar / Trade Network exists;
- it is player-to-player;
- NPC market daily caps do not apply to the Player Bazaar;
- `items_master.is_tradable` is the authoritative item eligibility flag;
- Project Master M3 requires real trading with escrow.

Recovered source does **not** establish the settlement denomination.

The generic `$` symbol in the old mock client is not sufficient evidence to
choose Dirty Cash or Clean Cash.

Therefore settlement remains fail-closed.

## Escrow schema

Migration:

`20261105010500_trade_escrow_foundation_20261105.sql`

creates:

### `trade_listings`

Fields include:

- seller;
- item;
- total escrow quantity;
- remaining escrow quantity;
- optional asking price;
- optional settlement currency;
- listing state;
- optional idempotency key;
- timestamps.

The row is designed to become the reserved-item escrow record after a future
listing mutation atomically removes the listed quantity from `user_inventory`.

No inventory debit is implemented in this pass.

Structural constraints enforce:

- positive total quantity;
- remaining quantity between 0 and total;
- positive integer price when present;
- allowlisted cash denomination when present;
- controlled listing states;
- terminal rows require `closed_at`;
- `open` / `reserved` rows cannot exist without both price and currency.

Because currency is unresolved, no current route can create an `open` listing.

Seller + idempotency key is unique when supplied.

### `trade_listing_events`

Immutable-oriented event table for future:

- listing creation;
- reservation;
- fill;
- cancellation;
- close;
- release/refund;
- settlement references.

It stores:

- listing;
- optional actor;
- event type;
- quantity delta;
- optional amount/currency pair;
- optional source reference;
- JSON metadata;
- timestamp.

A per-listing/event/source uniqueness rule supports replay-safe settlement.

No generic client event writer exists.

## RLS

Both new tables:

- have RLS enabled;
- revoke direct `anon` and `authenticated` table access.

The Node backend remains the authority for future escrow mutations.

## Backend read boundary

`GET /trade-network/:user_id` now additionally returns:

- escrow schema status;
- deferred-payout-contract readiness for future seller proceeds;
- the authenticated seller's recorded listing rows, if any.

Current status:

`escrow_status = schema_ready_mutations_paused`

The existing mutation endpoints still return 503:

- `POST /trade-network/list`;
- `POST /trade-network/buy`;
- `POST /trade-network/cancel`.

## Deferred payout integration

PR #27 introduced a generic Bank-cleared deferred-payout contract.

The Trade Network can eventually use that contract for seller proceeds if the
canonical trade design chooses deferred settlement.

This pass does not assume that it must.

Unresolved choices remain:

- immediate seller balance credit;
- Bank check/deferred payout;
- another escrow-release model.

Whichever is selected must derive from source or explicit product direction.

## Flutter companion

Draft PR #5 now:

- reports escrow schema readiness separately from settlement readiness;
- still shows the authenticated player's real tradable stash;
- shows recorded seller listings read-only if any exist;
- does not expose list/buy/cancel controls;
- labels price/currency unresolved when absent.

## Development state

At migration/readback:

- trade listings: 0;
- trade listing events: 0;
- RLS enabled on both new tables.

Supabase security/performance advisor checks are clean.

## Next requirements before activation

A future Trade Network settlement PR still needs:

1. canonical settlement currency;
2. seller-price authority;
3. listing fee/tax;
4. partial-fill behavior;
5. listing expiry;
6. cancellation/release rules;
7. equipped-item handling;
8. bazaar access semantics;
9. seller proceeds timing;
10. no-self-purchase rule;
11. exact lock order;
12. atomic inventory escrow debit/release;
13. buyer balance settlement;
14. immutable settlement event sequence;
15. deferred-payout integration if selected.

## Verification boundary

Performed:

- schema design against existing inventory constraints;
- development migration application/readback;
- RLS confirmation;
- backend static readback;
- Flutter static readback;
- Supabase advisor review.

Not performed by instruction:

- Node runtime tests;
- listing/buy/cancel integration tests;
- concurrency tests;
- Flutter analyze/build/widget tests;
- deployment;
- production changes.
