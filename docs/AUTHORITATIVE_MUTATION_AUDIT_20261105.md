# Authoritative Mutation Safety Audit — 2026-11-05

## Scope

This audit reviews currently reachable backend mutation surfaces on the
stabilization integration branch.

Audit criteria:

1. authenticated actor identity must come from the verified session;
2. economic/resource mutations use one database transaction;
3. replay-sensitive actions use persistent idempotency;
4. lock order is deterministic;
5. client inputs do not own payout/cost/reward values;
6. paused mechanics remain fail-closed;
7. GET/read routes should not provide rerollable state-creation side effects;
8. naturally idempotent state-setting writes are distinguished from additive
   economy/progression mutations.

No runtime/gameplay/build tests or deployment were performed.

## Canonical lock order

All scanned endpoints using `beginIdempotent` now acquire the authenticated
player row lock before the idempotency ledger.

Canonical order:

`player -> economic_idempotency -> action resources`

A mechanical scan found no idempotency endpoint whose first `FOR UPDATE` occurs
after `beginIdempotent`.

## Stabilization fixes

### Gym purchase

Before:

- transaction and player lock existed;
- retry had no persistent idempotency.

Risk:

A client/network retry could re-enter the purchase path after the original
commit and return a different error rather than the original authoritative
response.

Now:

- requires valid `Idempotency-Key`;
- actor row locks first;
- scope `gym.purchase`;
- replay returns the original response;
- wallet debit, ownership insert, active-gym update and idempotency completion
  remain atomic.

### Gym activation

Before:

- direct UPDATE without transaction/idempotency.

Now:

- actor-first transaction;
- scope `gym.activate`;
- locked gym state;
- ownership revalidation;
- persistent response replay.

### Gym training

Before:

- actor/gym locks and transaction existed;
- Energy/stat/EXP mutations could be repeated by retry.

Now:

- scope `gym.train`;
- replay is resolved after actor lock and before gym/resource checks;
- Energy debit, stat/EXP gain, tutorial progress, gym achievement telemetry and
  idempotency response complete in one transaction.

### Starter Gym provisioning

The dashboard's starter-gym provisioning is now serialized by the player row and
uses conflict-safe inserts.

Verified schema keys:

- `user_gym_stats`: primary key `user_id`;
- `user_owned_gyms`: primary key `(user_id, gym_id)`.

Concurrent dashboard reads cannot create duplicate starter rows.

### City Job interview submission

Before:

- transaction/session lock existed;
- no persistent replay contract;
- retry after a successful interview could fail because the session was already
  consumed or the player was now employed.

Now:

- scope `jobs.interview_submit`;
- canonical answer payload is sorted by question identity;
- player lock precedes idempotency;
- replay is resolved before employment/session-consumed checks;
- session consumption is conditional;
- successful employment update is conditional;
- original result is replayed exactly.

### City Job interview issuance

The existing client-compatible GET route historically created a new random
five-question session on every request.

Risk:

- page refresh could reroll questions;
- multiple live sessions could accumulate.

Now:

- player row serializes issuance;
- database `NOW()` determines ban/session timing;
- an existing live session for the same player/job is returned first;
- its exact persisted question set is reconstructed from the catalog;
- only when no live session exists is a new random session issued.

The route remains GET for client compatibility, but refresh is now stable and
does not reroll a live interview.

### Inventory equip

Before:

- transaction and inventory lock existed;
- no persistent replay contract.

Now:

- scope `inventory.equip`;
- actor lock precedes idempotency;
- replay occurs before inventory/catalog checks;
- inventory ownership and slot/category validation are rechecked;
- equipment update and response ledger commit atomically.

### Market retry ordering

The premium/subscriber work had already exposed a replay-order issue in
`POST /market/buy-bulk`.

The stabilization head retains the correction:

- actor row locks;
- idempotency replay is resolved;
- only then is the daily market usage/cap evaluated.

A retry of a successful purchase therefore cannot be rejected because the
original purchase itself consumed the daily allowance.

### Jail/Hospital legacy timer race

The optional non-production legacy timer previously cleared Jail/Hospital user
timestamps directly while the persisted state-duration worker also owns state
expiry.

Those writes were removed from the timer. State expiry now has one authoritative
worker path.

## Active mutations reviewed as already compliant

The audit confirmed the existing transaction/idempotency pattern on active
resource/economy paths including:

- Bank deferred payout claim;
- character level-up;
- company owner Dirty Cash funding;
- company profile update;
- company crew assign/recall;
- company employment offer create/withdraw/respond and applicant review;
- crime execution settlement;
- Hospital revive;
- Info Broker classifieds;
- consumable use where reconciled;
- City Job daily pay, promotion, quit and reconciled mastery activation;
- city NPC market purchase;
- Anonymous mission verification/reward settlement;
- property move-in;
- Syndicate crew assignment/unassignment/board/hire flows;
- University enrollment/dropout/graduation.

The source values/costs/rewards for these paths are server-derived where the
feature is enabled.

## Naturally idempotent writes

Two POST writes do not use the economic idempotency ledger because their
database behavior is set-membership/state-setting rather than additive
settlement.

### Tutorial visit

`POST /missions/tutorial/visit`:

- locks the authoritative player/progress state;
- sets the named allowed mission visit flag to `true`;
- retry does not increment currency, items, counters or rewards.

### Mark events read

`POST /events/mark_read`:

- updates only rows where `is_read = false`;
- sets them to `true`;
- a retry produces no additional resource/progression effect.

These are intentionally classified separately from replay-sensitive economy
mutations.

## Fail-closed routes confirmed

Examples include:

- Bank time-deposit create/claim;
- Casino gameplay;
- Credit Broker purchase;
- bounty placement;
- company pricing/advertising/stock/upgrades/liquidation/directorship changes;
- company incorporation;
- Jail bail/breakout/yard training;
- premium pack consumption/subscription activation;
- property purchase/upgrades/market/lease/gift/upkeep;
- Trade list/buy/cancel;
- Kevin contracts;
- legacy Syndicate client-triggered job settlement.

The presence of legacy handler code behind a blocking middleware does not make
the mutation reachable.

## GET side-effect audit

Two controlled GET-side provisioning behaviors remain for client compatibility:

1. the Gym dashboard may provision the source-backed starter Gym when the
   player's Gym rows are missing;
2. the City Job interview route may issue a new interview session when no live
   session exists.

Both are now serialized by the authenticated player row. Starter Gym inserts
are conflict-safe, and interview refresh reuses the same live persisted
question set rather than rerolling it.

No other scanned GET handler performs an authoritative SQL INSERT/UPDATE/DELETE
side effect.

## Remaining static risks for later stabilization batches

This pass did not attempt to resolve game mechanics. The next engineering-only
areas remain:

- database/RLS/direct-grant full audit;
- backend-to-Flutter API contract reconciliation;
- worker retry/lease/observability review;
- legacy writer shutdown search outside mounted routes;
- structured error/event logging and release configuration checklist;
- authorized runtime/concurrency tests when testing is explicitly permitted.

## Verification boundary

Performed:

- endpoint-level static route scan;
- transaction/idempotency/lock-order inspection;
- hidden-write GET scan;
- relevant schema constraint readback;
- route/worker source readback after patches.

Not performed:

- API/runtime execution;
- race tests;
- deadlock tests;
- load tests;
- Flutter build/analyze;
- deployment;
- production changes.
