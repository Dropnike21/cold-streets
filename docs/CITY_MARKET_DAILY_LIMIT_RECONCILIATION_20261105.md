# City NPC Market Daily Limit & Source Repair — 2026-11-05

## Scope

This pass fixes a concrete source-corruption defect in `routes/market.js` and
implements the explicit Master Items rule that all city NPC markets have a
strict 100-item-per-day purchase limit.

Player Bazaar / Trade Network remains unlimited by this source rule.

No runtime/gameplay/build tests or deployment were performed.

## Source-backed rule

Master Items Canvas update:

- all city NPC markets (examples: Pharmacy, Gun Shop) have a strict
  **100-item per day purchase limit**;
- Player Bazaar remains unlimited.

The existing backend only limited one cart to 10,000 units and therefore did not
enforce the recovered daily rule.

## Source corruption repaired

Static route review found the stacked `market.js` file contained a duplicated,
truncated tail around the bulk-purchase response.

The file had an incomplete string/object followed by an early catch/export and
then a second duplicated response/catch/export sequence.

This pass restores one coherent transaction tail:

- construct response;
- persist idempotent result;
- COMMIT;
- return;
- one catch/rollback;
- one finally/release;
- one module export.

A repository-wide route-tail static scan did not find another duplicate-export
artifact of the same class.

## Purchase ledger integrity

Migration:

`20261105021000_city_market_daily_limit_integrity_20261105.sql`

adds to `user_purchases`:

`purchase_source`

New city-market audit rows use:

`city_market`

This prevents the city NPC limit from being conflated with future Player
Bazaar, auction, or other item-acquisition histories.

Migration also enforces:

- purchase quantity > 0;
- nonempty purchase source;
- index on `(user_id, purchase_source, purchase_date DESC)`.

The development database had zero purchase rows before the migration.

## Deterministic day boundary

The source says "per day" but does not identify an in-game timezone.

This pass uses PostgreSQL `CURRENT_DATE` as the deterministic database
calendar-day boundary.

It is exposed to the client as:

`reset_boundary = database_calendar_day`

No Philippines/user timezone or fictional-city timezone is silently invented.

If a canonical game timezone is later specified, the boundary can be migrated
explicitly.

## Concurrency-safe enforcement

The bulk-buy transaction already locks the authenticated user wallet first.

After that lock, the server sums:

- this actor;
- `purchase_source = city_market`;
- rows inside the current database calendar day.

Because concurrent city-market carts for the same actor must acquire the same
user lock, two requests cannot both observe the same remaining allowance and
overspend the daily quota.

The server rejects a cart when:

`purchased_today + requested_quantity > 100`

The cap is on item units, not cart lines.

The per-request parser also refuses a cart exceeding 100 units because such a
cart can never be legal under the daily rule.

## Settlement

The purchase remains server-authoritative:

- authenticated actor;
- persistent idempotency;
- wallet lock;
- daily-limit check;
- deterministic item locks;
- server catalog source/price;
- stock check;
- Dirty Cash debit;
- stock decrement;
- inventory upsert;
- purchase audit;
- one transaction.

Client prices do not determine settlement.

Each audit row now records `purchase_source = city_market`.

## Market status

New:

`GET /market/status`

returns:

- database day key;
- reset-boundary label;
- daily limit = 100;
- purchased today;
- remaining today;
- Player Bazaar source status = unlimited.

This is informational; the mutation independently rechecks the limit.

## Flutter companion

Draft PR #5 now:

- loads the authoritative daily market status;
- shows purchased / 100 / remaining;
- identifies the database calendar-day boundary;
- states that Player Bazaar is unlimited by source;
- clamps per-item/cart quantity to remaining daily allowance;
- removes the redundant request-body player ID;
- refreshes authoritative usage after a purchase.

The backend remains the enforcement authority.

## Database readback

Confirmed:

- purchase source column;
- positive quantity constraint;
- nonempty source constraint;
- user/source/date index.

Supabase security/performance advisor checks are clean.

## Verification boundary

Performed:

- Master Items source review;
- current route static repair;
- route-tail static repository scan;
- development migration/readback;
- Flutter static readback;
- Supabase advisor review.

Not performed by instruction:

- Node syntax/runtime tests;
- market integration tests;
- concurrent purchase tests;
- Flutter analyze/build/widget tests;
- deployment;
- production changes.
