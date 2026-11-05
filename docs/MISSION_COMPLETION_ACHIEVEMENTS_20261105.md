# Mission Completion Achievement Telemetry — 2026-11-05

## Scope

This pass enables the recovered `missions_completed` achievement family from
the authoritative mission-progress ledger.

It does not create new missions, resolve Kevin contracts, or invent mission
rewards.

## Source catalog

The recovered achievement catalog contains exactly 25
`missions_completed` rows.

Pinned fingerprint:

`48a32b3e9c2ba831ffb9ad45b019d02c`

Thresholds span 5 through 125 completed missions.

If the 25-row catalog changes, the achievement engine fails closed and requires
reconciliation.

## Authoritative telemetry

Progress is:

`COUNT(user_mission_progress WHERE status = 'completed' AND completed_at IS NOT NULL)`

The ledger already enforces:

- one row per player + mission;
- status only `active` or `completed`;
- completed rows require `completed_at`;
- active rows require `completed_at IS NULL`.

The client cannot submit an achievement counter.

## Transactional unlock

Anonymous mission VERIFY already:

1. locks the authenticated player;
2. uses persistent idempotency;
3. validates the current source-pinned mission;
4. validates server-owned objective progress;
5. settles the mission reward;
6. marks the mission ledger row completed.

This pass adds achievement evaluation immediately after step 6 and before the
same transaction commits.

Retries cannot duplicate mission completion or achievement rows.

Future mission systems may contribute automatically only if they settle through
the same authoritative `user_mission_progress` ledger.

Kevin remains paused and contributes no fabricated progress.

## Achievement read model

The Achievements API now exposes `missions_completed` as a supported tracker
and derives its displayed progress directly from the completed mission ledger.

No Flutter-specific parser change is required because the existing achievement
UI already renders backend-provided generic tracker availability/progress.

## Development state

At reconciliation:

- users: 0;
- mission progress rows: 0;
- completed mission rows: 0;
- `missions_completed` achievement rows: 25.

No backfill is required in the current development database.

## Verification boundary

Performed:

- achievement catalog fingerprint readback;
- mission ledger constraint review;
- development data readback;
- static backend readback.

Not performed by instruction:

- mission gameplay/runtime tests;
- idempotency/concurrency tests;
- Flutter analyze/build/widget tests;
- deployment;
- production changes.
