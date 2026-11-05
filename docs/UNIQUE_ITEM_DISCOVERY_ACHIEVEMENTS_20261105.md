# Unique Item Discovery Achievements — 2026-11-05

## Scope

This pass enables the recovered `unique_items_found` achievement family from an
immutable first-acquisition ledger.

The source achievement descriptions explicitly say **"Find or acquire N unique
items."** This is therefore lifetime acquisition, not current inventory size and
not purchase count.

No runtime/gameplay/build tests or deployment were performed.

## Source catalog

The recovered achievement catalog contains exactly 25
`unique_items_found` rows.

Pinned fingerprint:

`453804215f82daa77f8d8a003adf8842`

Thresholds span 5 through 125 distinct items.

If this 25-row source catalog changes, the Node achievement engine fails closed.

## Persistent discovery ledger

Migration:

`20261105084100_unique_item_discovery_20261105.sql`

creates `user_item_discoveries` keyed by:

- authenticated player ID;
- canonical `items_master.item_id`.

A row records only the first time a player acquires that item. Reacquiring an
item after consuming, selling, or otherwise losing it does not increase the
lifetime distinct-item count.

The ledger is populated by server-side database triggers on positive
`user_inventory` INSERTs and quantity UPDATEs. The trigger function is
`SECURITY INVOKER`, uses an empty search path, and inserts with
`ON CONFLICT DO NOTHING`.

The ledger has RLS enabled and direct `anon` / `authenticated` access is
revoked.

The existing `user_inventory` table was also verified to have RLS enabled and
no direct client SELECT/INSERT/UPDATE privileges.

## Populated-database guard

Current development state at migration time:

- users: 0;
- inventory rows: 0;
- positive inventory rows: 0.

The migration deliberately raises an exception if it is applied to a database
that already contains users. A populated environment needs an explicit lifetime
backfill decision because current inventory cannot reconstruct items that were
historically acquired and later consumed/sold.

This prevents silently undercounting legacy players.

## Current authoritative acquisition hooks

Achievement evaluation is refreshed transactionally after the active backend
actually grants inventory through:

1. City NPC Market bulk purchase;
2. source-reconciled City Job mastery item reward;
3. successful Shoplifting loot grant;
4. successful Pickpocketing loot grant.

Searching currently has no inventory-grant path.

Trade Network mutations remain paused, so there is no buyer acquisition yet.
Syndicate routes only read player inventory for tool ownership; they do not
grant items.

The database trigger still guarantees that any future positive inventory write
records the first acquisition. Future mutation routes must also call the
achievement refresh helper before commit so unlock events happen immediately.

## Achievement progress

Progress is:

`COUNT(user_item_discoveries WHERE user_id = actor)`

The Achievements API reports that exact count for `unique_items_found`.

Unlocks are inserted with the existing unique/idempotent
`user_achievements` path and emit the normal achievement event.

## Security / integrity

- client cannot submit discovery count;
- client cannot insert discovery rows;
- item identity comes from authoritative inventory writes;
- repeated acquisition cannot increment the distinct count;
- acquisition and achievement evaluation occur inside the same gameplay
  transaction for the currently active writers;
- populated-database migration fails closed rather than inventing history.

Supabase readback after migration:

- discovery rows: 0;
- RLS enabled;
- anon SELECT: false;
- authenticated SELECT: false;
- insert trigger present;
- quantity-update trigger present;
- no new security/performance advisor finding for the ledger.

## Verification boundary

Performed:

- source achievement fingerprint readback;
- inventory-writer route audit;
- development migration application/readback;
- static backend readback;
- Supabase security/performance advisor review.

Not performed by instruction:

- inventory acquisition runtime tests;
- trigger integration tests;
- achievement integration tests;
- concurrency tests;
- Flutter analyze/build/widget tests;
- deployment;
- production changes.
