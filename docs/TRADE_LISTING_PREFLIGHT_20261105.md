# Trade Listing Preflight — 2026-11-05

## Scope

This pass advances the Player Bazaar / Trade Network to an authenticated,
read-only listing preflight.

It does **not** reserve inventory, create a listing, choose a settlement
currency, charge a fee, transfer an item, or issue seller proceeds.

No runtime/gameplay/build tests or deployment were performed.

## Source-backed facts

Recovered project sources establish:

- `items_master.is_tradable` is the canonical per-item participation flag;
- the Player Bazaar exists;
- the NPC city-market 100-item daily purchase limit does **not** apply to the
  Player Bazaar.

Recovered sources do not establish:

- whether Bazaar settlement uses Dirty Cash or Clean Cash;
- listing fee/tax;
- partial-fill rules;
- listing expiry;
- seller proceeds timing;
- whether `users.has_bazaar` is a hard access gate;
- whether an equipped item can be listed.

Those unresolved mechanics remain fail-closed.

## Existing escrow foundation

The existing `trade_listings` table already supports:

- seller and item foreign keys;
- positive total quantity;
- bounded remaining quantity;
- optional exact-integer asking price;
- optional Dirty/Clean settlement currency;
- draft/open/reserved/closed/cancelled/voided lifecycle;
- open/reserved rows requiring both price and currency.

Direct client access remains disabled:

- RLS enabled;
- anon SELECT: false;
- authenticated SELECT: false;
- authenticated INSERT: false.

Development state at reconciliation: 0 listing rows.

The schema is therefore a future escrow substrate, not an active marketplace.

## Listing preflight

`POST /trade-network/listing-preflight`

Accepted client intent is limited to:

- `item_id`;
- `quantity`.

The authenticated actor comes from the verified session.

The endpoint reads:

- current owned quantity;
- canonical item identity and metadata;
- `is_tradable`;
- current equipment state;
- current nonterminal listing rows for the same item;
- the existing `has_bazaar` flag.

It returns an inventory snapshot and explicit blockers.

### Fail-closed checks

The inventory snapshot is considered ready only when:

1. the item is in the actor's inventory;
2. quantity is positive and sufficient;
3. the canonical catalog marks the item tradable;
4. the item is not currently equipped.

Equipped items are blocked because source semantics for equipped-item listing are
not explicit.

## Existing listing rows

The preflight reports existing draft/open/reserved quantity but does **not**
subtract it from owned inventory or call it reserved.

The current escrow design says a future authoritative listing mutation should
atomically debit/reserve inventory. Until that mutation exists, treating a
listing row itself as physical reservation would invent semantics.

## Bazaar access flag

`users.has_bazaar` is returned as diagnostic state only.

The source confirms the Player Bazaar exists and is unlimited by the NPC market
daily cap, but does not define when/how `has_bazaar` becomes true or whether it
must gate listing/buying.

Therefore:

- `has_bazaar = false` does not create a fabricated authorization failure in
  preflight;
- `has_bazaar = true` does not authorize settlement;
- actual listing/purchase mutations remain unavailable.

## Snapshot boundary

Preflight is intentionally non-locking and non-reserving.

Inventory may change after the response. A future listing mutation must re-lock
the authenticated player/inventory, revalidate all catalog/equipment state,
reserve inventory atomically, and use persistent idempotency.

The preflight response must never be treated as an authorization token.

## Still blocked

Before listing creation can open, project sources must resolve:

1. settlement currency;
2. listing fee/tax;
3. partial-fill semantics;
4. listing expiry;
5. seller proceeds timing;
6. Bazaar access semantics;
7. equipped-item listing semantics.

Purchase and cancellation remain paused as well.

## Verification boundary

Performed:

- recovered Bazaar source reconciliation;
- trade listing schema/constraint inspection;
- direct-access/RLS readback;
- static backend readback.

Not performed by instruction:

- listing runtime tests;
- inventory race/concurrency tests;
- escrow integration tests;
- Flutter analyze/build/widget tests;
- deployment;
- production changes.
