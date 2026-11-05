# Cold Streets Runtime Verification Plan — 2026-11-05

## Status

**Prepared, not executed.**

This is the exact next-phase test order once the owner explicitly authorizes
runtime/build/concurrency testing.

Do not use production as the first test environment.

## Phase 0 — immutable test candidate

1. choose exact backend PR #44 commit;
2. choose exact Flutter PR #5 commit;
3. record the development/test Supabase project;
4. confirm no production credentials are present;
5. keep `ENABLE_GAMEPLAY_API=false`.

If code changes during testing, restart the plan from the relevant earlier gate.

## Phase 1 — static release preflight

Run from the backend directory:

- verify Node 24.x;
- `npm ci --omit=dev`;
- `npm run release:preflight`.

Expected result:

- zero preflight errors;
- only understood warnings.

This phase must not mutate gameplay state.

## Phase 2 — fresh migration replay

Use a disposable empty PostgreSQL/Supabase test database.

1. apply all 41 committed migrations in order;
2. verify migration history contains the same 41 names/versions;
3. inspect schema objects, constraints, indexes, triggers and RLS;
4. run Supabase security advisor;
5. verify anon/authenticated access remains denied.

Do not solve a replay failure by manually editing migration history.

### Unique-item migration

Exercise the populated-database guard separately.

Its baseline/backfill policy is a release/data decision and must be selected
before applying it to a populated production dataset.

## Phase 3 — health-only backend startup

Configure:

`ENABLE_GAMEPLAY_API=false`

Start the server.

Verify:

- listener starts;
- `/healthz` -> 200;
- `/readyz` -> 200 health-only readiness;
- gameplay route -> 503;
- no gameplay worker starts;
- malformed/oversized requests respect transport limits;
- SIGTERM completes graceful shutdown.

## Phase 4 — gameplay-enabled dependency startup

Against test infrastructure only:

`ENABLE_GAMEPLAY_API=true`

Verify:

- valid DB/Auth configuration starts;
- malformed critical configuration fails startup;
- DB unavailable at boot -> readiness 503;
- restoring DB -> automatic bootstrap retry succeeds;
- State Duration worker starts exactly once;
- readiness becomes 200;
- Crew Crime worker remains disabled.

## Phase 5 — authentication boundary

Test:

- missing bearer token;
- malformed bearer token;
- expired token;
- valid verified non-anonymous user;
- Auth upstream unavailable;
- Auth request timeout;
- local Auth concurrency/backpressure.

Verify no access token or email appears in logs.

## Phase 6 — API smoke contract

For every active route family:

- valid request;
- malformed body;
- unexpected body field;
- unexpected mutation query parameter;
- foreign user/resource access where applicable;
- paused mechanic response.

Confirm the final 35 active/read-preflight and 37 paused classification.

## Phase 7 — idempotency replay

For every replay-sensitive mutation:

1. submit once with a new Idempotency-Key;
2. repeat identical request with the same key;
3. submit changed payload with the same key;
4. submit concurrent duplicate requests.

Verify:

- identical retry returns the original settlement;
- no duplicate resource mutation;
- payload mismatch fails;
- ledger state remains consistent.

Prioritize:

- Bank check claim;
- market purchase;
- Gym mutations;
- crimes;
- inventory use/equip;
- City Job settlement;
- company funding/employment;
- University;
- Hospital revive.

## Phase 8 — economy conservation assertions

For each enabled economic/resource mutation, compare before/after database state.

Verify:

- currency denomination;
- exact delta;
- inventory/resource delta;
- ledger/source row;
- no duplicate grant/debit;
- no negative balances/quantities;
- server catalog value equals settlement value.

Use SQL assertions rather than visual UI inspection alone.

## Phase 9 — concurrency / lock-order

Run controlled races for shared resources.

At minimum:

- same wallet + two market requests;
- duplicate Bank claim;
- duplicate consumable use;
- Gym train vs same-player mutation;
- company funding concurrency;
- employee/crew transfer concurrency;
- State Duration expiry vs revive/new penalty;
- multiple State Duration worker replicas.

Verify:

- no deadlock;
- no double settlement;
- deterministic winner/409 behavior;
- retries recover cleanly.

## Phase 10 — timeout / overload behavior

Exercise:

- slow headers;
- slow/oversized body;
- DB acquisition saturation;
- long SQL statement in test harness;
- lock wait;
- idle transaction;
- Supabase Auth delay;
- >50 local concurrent Auth verifications;
- DB pool waiting queue reaching backpressure.

Verify:

- bounded latency;
- expected 503/timeout behavior;
- `Retry-After` where configured;
- readiness/liveness distinction remains correct;
- service recovers after dependency/load recovery.

## Phase 11 — graceful shutdown under work

During active requests/worker polling:

1. send SIGTERM;
2. verify readiness changes to not-ready;
3. verify bootstrap retry timer is cancelled;
4. verify worker timer stops;
5. verify listener drains;
6. verify DB pool closes;
7. verify normal completion occurs before the 25-second force guard.

## Phase 12 — Flutter validation

Using the exact Flutter PR #5 candidate:

- dependency resolution;
- `flutter analyze`;
- supported target build(s);
- widget/unit tests if present;
- authenticated session flow;
- API contract smoke against staging.

Verify paused screens remain unavailable and no client-side settlement math has
reappeared.

## Phase 13 — staging end-to-end

With non-production data/accounts:

- account/session establishment;
- active gameplay flows;
- state transitions;
- achievements;
- market/inventory;
- City Jobs;
- University;
- company safe subset;
- Bank check claim;
- logout/token expiration;
- restart/recovery.

Collect monitoring baseline during this phase.

## Phase 14 — release decision

Production gameplay may be enabled only after:

- required test phases pass;
- unresolved failures are closed or explicitly accepted;
- migration/data baseline decision is documented;
- monitoring/alerts exist;
- rollback owner/procedure exists;
- exact immutable application commits are recorded.

## Failure handling

A failed phase does not authorize bypassing the invariant that failed.

Do not:

- manually grant balances/items to make a test pass;
- weaken RLS;
- remove idempotency;
- increase timeouts blindly;
- enable a paused mechanic;
- edit migration history manually.

Fix the underlying source/configuration and repeat the relevant gates.
