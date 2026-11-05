# Cold Streets Stabilization Master Closeout — 2026-11-05

## Status

**Static/source-level stabilization: CLOSED**

This document marks the end of the current no-runtime-test stabilization phase.

It does not claim that the application has passed build, API, concurrency,
migration-replay, load, or deployment tests.

## Canonical review stack

Backend:

- draft PR #44;
- `stabilization/backend-integration-20261105`.

Flutter:

- draft PR #5;
- `feature/flutter-supabase-auth-20261104`;
- based on PR #44.

## Completed stabilization domains

### Security / identity

- verified Supabase bearer identity;
- server-derived gameplay actor;
- no direct client gameplay DB access;
- all public gameplay tables RLS-enabled;
- client table/sequence/RPC grants removed;
- public SECURITY DEFINER exposure absent.

### Mutation safety

- all POST routes classified active or paused;
- exact active request-field allowlists;
- mutation query parameters rejected;
- persistent idempotency for replay-sensitive settlement;
- deterministic shared-row lock ordering reviewed;
- client reward/cost/payout authority removed.

### Economy/resource conservation

- active sources/sinks/transfers documented;
- exact integer money/resource settlement;
- known source-conflicted reward/economy paths fail closed;
- no known client/retry resource-mint path remains statically.

### Randomness / legacy writers

- no runtime `Math.random`;
- legacy Vital/restock timers retired;
- destructive Gym seeder retired;
- legacy Casino settlement retired;
- client-authoritative Pickpocket engine retired;
- source-conflicted crew payout worker hard-disabled;
- dormant company pricing/advertising SQL writers removed.

### Workers

Enabled:

- State Duration worker.

Paused:

- Crew Crime settlement worker.

The enabled worker uses persisted DB state and multi-replica-safe row claiming.

### Flutter/API

- Flutter actor IDs removed from mutation authority;
- paused backend mechanics shown as unavailable;
- stale Casino/Jail/bounty/company/Trade/etc. mutation surfaces closed;
- newly discovered resignation/recruit/crew/Pickpocket conflicts closed;
- Flutter branch topology inherits the canonical backend without overwriting it.

### Migrations / schema

- 41 Git migrations;
- 41 development history entries;
- zero drift;
- 74/74 public tables RLS-enabled;
- current Data API boundary deny-all for gameplay tables.

### Operational hardening

- Node 24 runtime contract;
- deterministic dependency installation;
- liveness/readiness;
- structured request/error/worker logging;
- graceful shutdown;
- HTTP request/socket/header bounds;
- PostgreSQL statement/query/lock/transaction bounds;
- pool backpressure;
- bounded Supabase Auth verification (10-second timeout + per-process concurrency cap);
- automatic gameplay-runtime bootstrap recovery after transient startup DB failure;
- runtime-enforced port/TLS/flag/CORS/Auth configuration validation;
- release configuration preflight;
- canonical release runbook, monitoring checklist, and future runtime verification plan.

## What is deliberately not complete

### Runtime verification

Still not executed because testing has not been authorized:

- Node startup;
- release-preflight execution;
- /healthz and /readyz calls;
- API smoke tests;
- fresh migration replay on a clean database;
- duplicate-request/idempotency runtime tests;
- concurrency/deadlock tests;
- multi-replica worker tests;
- Flutter analyze/build/widget tests;
- load/overload tests;
- deployment smoke tests.

### Mechanics decisions

Unresolved game-rule decisions are listed in
`MECHANICS_DECISIONS_REQUIRED_20261105.md`.

They are not stabilization defects because affected mutations are now
fail-closed.

### Release/data decision

The lifetime unique-item-discovery migration still requires an explicit
populated-database baseline/backfill policy. Current inventory cannot prove
historical lifetime discoveries, so the code correctly refuses to invent them.

## Exit criteria for this phase

The no-test stabilization phase is complete when:

- unresolved mechanics cannot settle value;
- client input cannot choose server rewards/prices/actor identity;
- legacy duplicate writers are disabled;
- DB/client exposure is closed;
- migration source/history are aligned;
- remaining gaps are documented.

Those criteria are now met statically.

## Next phase

The project should not add more gameplay settlement until either:

1. runtime verification is explicitly authorized; or
2. the owner begins selecting the mechanics decisions in the decision register.

Once a decision is made, its implementation should follow the same
server-authoritative/idempotent/conservation rules established by this
stabilization stack.


## Operational handoff

The final operational handoff is split into three documents:

- `OPERATIONAL_RELEASE_RUNBOOK_20261105.md` — deterministic operator sequence,
  configuration contract, health gates, enable/disable procedure and rollback;
- `PRODUCTION_MONITORING_CHECKLIST_20261105.md` — signals, event names,
  dashboards and alert conditions to establish before production;
- `RUNTIME_VERIFICATION_PLAN_20261105.md` — exact test order for the first
  explicitly authorized runtime validation pass.

The static operational lane has no remaining known source-level blocker.
