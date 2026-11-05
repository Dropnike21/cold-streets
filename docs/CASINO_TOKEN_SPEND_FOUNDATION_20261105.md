# Casino Token Spend Foundation — 2026-11-05

## Scope

This foundation keeps Category 1 Casino accounting server-authoritative while
Casino gameplay remains paused.

Source-backed rules now reconciled:

- Category 1 NPC-vs-player games use Casino Tokens.
- Base daily Token spend cap is 100.
- Active VIP-level benefits raise the effective cap to 150.
- Subscriber includes the VIP-level benefit set.
- Perya, Syndicate Slots and High-Low are Token Games.

The exact Token issuance/replenishment rules and complete game paytables remain
unresolved.

## Premium entitlement source

VIP is no longer represented by a standalone player boolean.

The effective 150/day Casino cap is derived from:

1. an active 30-day VIP Pack entitlement; or
2. an active Subscriber billing period.

The premium resolver uses PostgreSQL time for both entitlement and subscription
windows.

Kingpin Pack does not inherit VIP behavior by assumption. Its exact benefit set
is still unresolved.

## Immutable Token spend ledger

Migration:

`20261105084348_casino_token_spend_foundation_20261105.sql`

creates `casino_token_spend_ledger`.

Each row stores authenticated player, server-approved Token game key, exact
integer Token amount, immutable server source reference and server timestamp.

Database invariants enforce:

- positive integer spend amount up to the maximum supported effective cap (150);
- nonempty game/source identity;
- one source reference per player;
- immutable UPDATE/DELETE behavior;
- RLS enabled;
- no direct anon/authenticated access.

## Daily limit

The source says "per day" but does not define a game timezone. PostgreSQL
`CURRENT_DATE` remains the deterministic accounting boundary.

This is a **spend cap**, not a daily Token grant. No Token balance refill or
issuance rule is inferred.

## Read-only Casino status

`GET /casino/status` returns:

- Token balance;
- base daily cap;
- whether VIP-level benefits are active;
- whether Subscriber is active;
- effective daily cap;
- spent/remaining amount for the database day;
- preserved Token game identities;
- unresolved gameplay blockers.

Every Casino game mutation remains 503.

## Still unresolved

- Casino Token issuance/replenishment;
- Perya gross-vs-profit multiplier semantics;
- Slots paytable, jackpot seed/reset and atomic jackpot payout;
- High-Low multiplier/cashout schedule;
- Category 2 PvP Casino escrow and settlement.

## Verification boundary

Performed:

- source reconciliation;
- schema/constraint readback;
- premium entitlement integration readback;
- Supabase advisor review;
- static backend readback.

Not performed by instruction:

- Casino gameplay/runtime tests;
- replay/concurrency tests;
- Flutter build/analyze tests;
- deployment;
- production changes.
