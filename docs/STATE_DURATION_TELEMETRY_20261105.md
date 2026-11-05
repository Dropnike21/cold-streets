# Jail / Hospital Duration Telemetry — 2026-11-05

## Scope

This pass adds server-owned timing telemetry for the two recovered achievement
tracker families:

- `days_in_jail`
- `hospital_hours`

It does not change jail duration, hospital duration, bail, breakout, revive HP,
Heat decay, or any other balance rule.

No runtime/gameplay/build tests or deployment were performed.

## Persistent state episodes

Migration:

`20261105081605_state_duration_telemetry_20261105.sql`

adds `user_state_episodes`.

Every episode stores:

- player;
- state: jail or hospital;
- server admission time;
- server scheduled expiry;
- optional actual end time;
- terminal reason;
- server source type;
- immutable source reference.

Integrity rules enforce:

- one open state episode per player;
- scheduled expiry strictly after admission;
- early endings cannot predate admission or exceed scheduled expiry;
- closed episodes require a nonempty reason;
- direct client table access remains revoked.

The development database had 0 users and 0 active jail/hospital states at
migration time, so no legacy episode backfill was required.

## Authoritative admissions

The currently implemented crime engines now record an episode in the same
transaction that commits the player state.

Covered admissions:

- Searching crime jail;
- Searching crime hospitalization;
- Shoplifting jail;
- Shoplifting hospitalization;
- Pickpocketing jail;
- Pickpocketing hospitalization;
- Federal Arrest jail.

The source reference is the server-loaded `crimes_master.id`. The client cannot
supply a duration, admission time, expiry, tracker value, or telemetry source.

If another live episode exists, admission fails closed instead of overwriting
history.

## Early release

Medical Revive closes the target player's hospital episode in the same
transaction that clears `hospital_expires_at`.

The end time is server time capped at the scheduled expiry. The release reason
is `medical_revive`.

Bail and breakout remain paused, so no jail early-release producer is enabled in
this pass.

## Natural expiry worker

`workers/stateDurationWorker.js` settles due open episodes with:

`FOR UPDATE SKIP LOCKED`

This makes expiry settlement safe across multiple Node replicas.

A naturally completed episode is closed exactly at its stored
`scheduled_end_at`, not at worker poll time.

The worker also evaluates duration achievements after settlement.

## Achievement progress

The recovered achievement catalog contains 25 rows for each tracker.

Pinned catalog fingerprints:

- `days_in_jail`: `038e59981575d8ffacaf02aecd823e12`
- `hospital_hours`: `4873d94c74fd540b889eba95233cd556`

Progress is derived from cumulative authoritative elapsed seconds:

- jail: complete elapsed days = floor(total jail seconds / 86,400);
- hospital: complete elapsed hours = floor(total hospital seconds / 3,600).

For an open episode, progress uses the earlier of current server time and its
scheduled expiry. Therefore progress cannot continue past the authoritative
sentence/recovery duration even if the cleanup worker has not yet polled.

The Achievements read model now reports both trackers as available.

## Security / integrity

- no client duration values;
- no client telemetry counters;
- no mutable direct-table access;
- no duplicate open episodes;
- crime idempotency still prevents duplicate admission settlement;
- Medical Revive remains transactionally idempotent;
- achievement inserts remain unique/idempotent.

Supabase readback after migration:

- state episode rows: 0;
- RLS enabled;
- anon SELECT: false;
- authenticated SELECT: false;
- no new security/performance advisor finding for this table.

## Verification boundary

Performed:

- source achievement catalog fingerprint readback;
- development migration application/readback;
- static backend readback;
- Supabase security/performance advisor review.

Not performed by instruction:

- Node runtime/startup tests;
- crime integration tests;
- expiry-worker tests;
- concurrency tests;
- achievement integration tests;
- Flutter analyze/build/widget tests;
- deployment;
- production changes.
