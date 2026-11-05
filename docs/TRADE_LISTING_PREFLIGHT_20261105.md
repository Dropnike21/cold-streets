# Trade Listing Preflight — 2026-11-05

## Scope

This pass advances the Player Bazaar / Trade Network to an authenticated,
read-only listing preflight for two canonical asset namespaces:

- ordinary recovered items;
- premium packs.

It does **not** reserve inventory, create a listing, choose settlement currency,
charge a fee, transfer an asset, or issue seller proceeds.

No runtime/gameplay/build tests or deployment were performed.

## Source / owner-defined facts

Recovered project sources establish:

- `items_master.is_tradable` controls normal item participation;
- the Player Bazaar exists;
- the city NPC market daily purchase cap does not apply to the Player Bazaar.

The project owner further established:

- VIP Pack is a tradable premium asset;
- Kingpin Pack is a separate tradable premium asset;
- a player may hold/sell a pack instead of consuming it.

Premium packs use `premium_pack_catalog.is_tradable` and
`user_premium_pack_inventory`; they are not mapped onto legacy numeric
`items_master` IDs.

## Asset-aware escrow schema

Migration:

`20261105095957_trade_asset_namespace_20261105.sql`

extends `trade_listings` with:

- `asset_namespace` = `item` or `premium_pack`;
- nullable `item_id`;
- nullable `premium_pack_key`;
- a database check requiring exactly the identity appropriate to the namespace.

Existing ordinary item listings remain compatible through the default
`asset_namespace = 'item'`.

The development table was empty when this migration was applied.

The listing/event tables remain server-only with RLS/direct-access protections.

## Trade read model

The Trade Network now returns:

- tradable ordinary inventory;
- tradable premium-pack inventory;
- owned quantity;
- premium-pack reserved quantity;
- existing seller listings from either namespace;
- explicit paused settlement state.

VIP Pack and Kingpin Pack can therefore be represented as Bazaar assets without
pretending they are recovered ordinary items.

## Listing preflight

`POST /trade-network/listing-preflight`

### Regular item intent

Accepted shape:

- optional/default `asset_namespace = item`;
- `item_id`;
- `quantity`.

Checks:

- item is owned;
- quantity is sufficient;
- `items_master.is_tradable = true`;
- item is not currently equipped.

### Premium pack intent

Accepted shape:

- `asset_namespace = premium_pack`;
- `pack_key`;
- `quantity`.

Checks:

- pack is owned;
- requested quantity does not exceed
  `quantity - reserved_quantity`;
- `premium_pack_catalog.is_tradable = true`.

No ordinary item ID is accepted for premium-pack intent and no premium pack key
is accepted for ordinary-item intent.

## Existing listing rows

Preflight reports nonterminal draft/open/reserved listing rows for the exact
asset namespace + identity.

It does not treat those rows as inventory reservation. A future mutation must
atomically reserve/debit the relevant inventory namespace.

Premium pack inventory already contains a `reserved_quantity` field so future
market escrow can reserve packs without consuming them.

## Bazaar access flag

`users.has_bazaar` remains diagnostic only.

Recovered sources do not define how the flag is acquired or whether it must
hard-gate listing/buying. It therefore neither authorizes nor rejects
settlement in the preflight.

## Settlement remains fail-closed

Actual listing, purchase and cancellation stay 503 because the project still
does not establish:

1. Dirty Cash vs Clean Cash settlement;
2. listing fee/tax;
3. partial-fill semantics;
4. listing expiry;
5. seller proceeds timing;
6. Bazaar access semantics;
7. equipped-item listing semantics.

The generic deferred-payout contract remains available for future seller
proceeds once these rules are reconciled.

## Snapshot boundary

Preflight is non-locking and non-reserving. A successful preflight is not an
authorization token.

A future listing mutation must:

- authenticate the actor;
- lock the correct inventory namespace;
- revalidate catalog/tradability/equipment state;
- reserve inventory atomically;
- persist idempotency;
- use exact integer quantities/prices;
- create the listing/event rows in the same transaction.

## Verification boundary

Performed:

- Bazaar and premium-pack rule reconciliation;
- development asset-namespace schema update/readback;
- direct-access/RLS review;
- static backend readback.

Not performed by instruction:

- listing/runtime tests;
- escrow concurrency tests;
- premium pack trading integration tests;
- Flutter build/analyze tests;
- deployment;
- production changes.
