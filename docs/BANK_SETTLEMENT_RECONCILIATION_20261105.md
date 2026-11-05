# Bank / Time Deposit Settlement Reconciliation — 2026-11-05

## Scope

This pass reconciles the Bank's time-deposit and pending-check settlement paths against:

- the original GDD economy model;
- the Project Master recovery reference;
- the Database Recovery Specification;
- current and historical Bank backend/client code;
- the reconstructed development PostgreSQL schema.

No runtime/gameplay/build tests or production deployment were performed.

## High-level result

The Bank is now **read-only for financial liabilities**.

Paused mutations:

- new time-deposit creation;
- matured time-deposit settlement;
- pending-check claims.

This is deliberate. The recovered implementation contains multiple economy rules that exist only as code constants or conflict with the GDD.

## Development state

At reconciliation time the development project contains:

- 0 users;
- 0 time-deposit rows;
- 0 pending-check rows;
- 0 users with nonzero bank trust.

Therefore no development-player liabilities needed migration or settlement.

## Time-deposit rules are not master data

The Database Recovery Specification confirms that the Bank terms are code constants, not recovered master rows.

Historical/current code uses five duration indexes:

- 0 → 7 days
- 1 → 14 days
- 2 → 30 days
- 3 → 90 days
- 4 → 180 days

Historical/current nominal rates:

- 0.5%
- 1.1%
- 2.5%
- 9%
- 22%

Historical/current code also uses:

- a 2,000,000,000 deposit cap;
- `users.bank_trust_level` as the duration unlock gate;
- one active deposit per user.

These facts describe the recovered implementation. They are **not treated as canonical design values** in this pass.

No source-backed Bank terms table or progression table was recovered.

## Interest-method conflict

The commit that introduced the Bank describes the backend as calculating **compound interest**.

The actual implementation does not compound.

It calculates one flat payout increment:

`principal × rate`

The current hardened route similarly used integer basis points and one multiplication.

Because the prose and executable behavior disagree, this pass does not preserve either interest method as canonical.

## Critical economy conflict: Bank as laundering path

The historical Bank implementation drains a requested deposit in this order:

1. Dirty Cash first;
2. Clean Cash second.

At maturity, the entire stored payout is credited to:

**Clean Cash**

That means depositing Dirty Cash into the Bank converts it into Clean Cash and also earns interest.

The original GDD assigns laundering to **player-owned business fronts**, where Dirty Cash converts to Clean Cash over time minus a laundering tax.

The Bank path therefore conflicts with the recovered economy model and could bypass the intended laundering system.

This is treated as a P0 economy blocker.

### Result

`POST /bank/deposit`

returns 503 and spends nothing.

`POST /bank/claim-deposit`

returns 503 and pays nothing.

The Bank does not currently convert Dirty Cash into Clean Cash.

## Existing time-deposit liabilities

The physical `time_deposits` table contains:

- deposit_id;
- user_id;
- dirty_deposited;
- clean_deposited;
- total_payout;
- duration_index;
- unlocks_at;
- status;
- created_at.

The Bank status API now exposes recorded rows read-only, including:

- Dirty principal recorded;
- Clean principal recorded;
- recorded payout;
- recorded duration index;
- creation timestamp;
- unlock timestamp;
- current stored status;
- whether the unlock timestamp has passed.

Passing the timestamp does **not** make settlement available.

This distinction matters because a stored `total_payout` may reflect the disputed historical conversion/interest rules.

For a future restored database containing real legacy deposits, those liabilities require an explicit migration/adjudication policy before payout is re-enabled.

## Bank Trust

`users.bank_trust_level` exists physically.

No authoritative backend route was found that increases it.

The old Bank UI and backend use the value as a duration gate, but no recovered master source defines:

- how Bank Trust is earned;
- maximum Bank Trust;
- reset/decay behavior;
- whether trust is account-wide or tied to deposit history;
- exact term unlock thresholds beyond the historical array index convention.

The field remains visible as recorded state only.

It does not currently unlock executable deposit terms.

## University Bank Interest interaction

The recovered education system contains Bank-related reward data elsewhere in the project, but the Bank implementation does not provide a reconciled stacking/order rule for external interest bonuses.

The old Flutter Bank client had a hardcoded `_perkBonus = 0.0`.

No server-authoritative Bank perk consumer exists in the reconciled route.

Therefore external Bank-interest perk application remains unresolved and is not invented here.

## Pending checks

The physical `pending_checks` table contains:

- id;
- user_id;
- source;
- amount;
- expires_at;
- status;
- created_at.

Historical Bank code claims:

- checks can be claimed before expiry;
- claimed checks become Clean Cash;
- expiry is a strict 24-hour rule.

The Flutter UI also claimed expired funds would automatically liquidate into the player's street wallet.

However:

- no authoritative backend producer for `pending_checks` was recovered;
- no backend writer outside the Bank route was found;
- no auto-liquidation worker was recovered;
- no source defines whether expired checks become Dirty Cash, Clean Cash, another balance, or are forfeited;
- the 24-hour duration is historical code/UI behavior, not recovered master data.

Therefore:

`POST /bank/claim-check`

returns 503 and pays nothing.

The status API exposes recorded pending checks read-only.

An expired timestamp is reported as timestamp state only and does not trigger settlement.

## Backend read model

`GET /bank/status/:userId`

now:

- derives actor identity from authentication;
- verifies the player exists;
- exposes recorded Dirty Cash and Clean Cash exactly;
- exposes recorded Bank Trust;
- exposes all recorded time-deposit rows;
- exposes all recorded pending-check rows;
- performs no state mutation;
- does not calculate new interest;
- does not infer maturity payout;
- does not auto-expire checks;
- explicitly reports all blocked Bank capabilities.

Key status fields include:

- `bank_status: read_only_reconciliation`
- `time_deposit_creation_available: false`
- `time_deposit_claim_available: false`
- `pending_check_claim_available: false`
- `time_deposit_terms_status: historical_code_only`
- `payout_currency_status: unresolved`
- `dirty_to_clean_conversion_status: conflicts_with_gdd_laundering_model`
- `pending_check_creation_status: producer_unrecovered`
- `pending_check_expiry_status: auto_liquidation_unrecovered`

## Database integrity

Migration:

`20261104235500_bank_settlement_integrity_20261105.sql`

adds structural invariants without choosing economic terms:

### time_deposits

- Dirty principal is nonnegative integer-denominated;
- Clean principal is nonnegative integer-denominated;
- recorded payout is nonnegative integer-denominated;
- total principal must be positive;
- unlock timestamp must be after creation;
- supporting `(user_id, created_at DESC)` index.

Existing one-active-deposit-per-user partial uniqueness is retained.

### pending_checks

- amount must be positive integer-denominated;
- expiry must be after creation.

The existing `(user_id, status, expires_at)` index is retained.

### users

Bank Trust is required to be nonnegative.

Follow-up migration:

`20261104235600_bank_trust_constraint_cleanup_20261105.sql`

simplifies the Bank Trust constraint because the physical field is already PostgreSQL INTEGER.

No interest rates, term lengths, 2B cap, 24-hour expiry, status transitions, or payout currencies are encoded by these migrations.

## Flutter companion

Draft PR #5 replaces the transactional Bank UI with a source-reconciliation view.

Removed executable/predictive behavior includes:

- deposit amount input;
- MAX deposit action;
- duration selector;
- historical interest-rate display;
- projected interest calculation;
- projected payout chart;
- deposit confirmation;
- matured deposit claim button;
- pending-check claim button;
- 24-hour auto-liquidation countdown claim;
- local Dirty-first drain simulation;
- local Bank Trust duration gating.

The Bank now displays:

- real server balances;
- recorded Bank Trust;
- recorded time-deposit liabilities;
- recorded pending checks;
- timestamps/statuses;
- explicit settlement blockers.

Money values are formatted from exact server integer strings/integers rather than performing client floating-point financial math.

## What is required before Bank mutations can reopen

A canonical Bank design needs at least:

1. whether the Bank accepts Dirty Cash at all;
2. if Dirty Cash is accepted, what denomination is returned;
3. whether banking is allowed to launder money;
4. canonical deposit terms;
5. canonical interest formula;
6. deposit cap and how it can change;
7. Bank Trust earning/progression;
8. Bank Trust term thresholds;
9. one active deposit vs multiple deposits;
10. early withdrawal/cancellation semantics;
11. University/external interest bonus stacking;
12. pending-check producers;
13. pending-check destination currency;
14. expiry duration;
15. expired-check settlement behavior;
16. immutable financial settlement/audit ledger requirements.

Until those rules are explicit, reopening settlement would risk minting or converting value incorrectly.

## Verification boundary

Performed:

- Drive economy/recovery source review;
- current Bank route/client review;
- historical Bank commit/code review;
- development schema/data inspection;
- development migrations and readback;
- static backend/client reconciliation;
- Supabase advisor review.

Not performed by instruction:

- Node runtime tests;
- gameplay tests;
- Bank settlement tests;
- concurrency tests;
- Flutter analyze/build/widget tests;
- deployment;
- production changes.
