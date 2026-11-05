# Achievement and Cred Reconciliation — 2026-11-05

## Scope

This pass reconciles the recovered `achievements_master` catalog against the actual server telemetry and removes the unsupported hardcoded achievement-to-Cred payout.

Sources used:

- recovered Google Sheet `achievements_master`;
- Project Master Recovery reference, conflict C-04;
- current PostgreSQL schema;
- current backend event writers.

No gameplay/runtime/build tests or production deployment were performed.

## Recovered catalog

The source sheet contains **400 achievements** in **16 tracker families**, 25 achievements per family.

The source columns are:

- `achievement_id`
- `title`
- `description`
- `category`
- `stat_tracker`
- `threshold_value`
- `rarity`
- `global_count`

There is **no achievement reward/Cred column** in the recovered source.

Therefore the old backend behavior:

```text
achievement unlock -> +1 Cred
```

is not source-backed and has been removed. Achievement unlock events no longer claim or grant Cred.

## Tracker reconciliation

| Catalog tracker | Server source | Status | Reason |
|---|---|---|---|
| `gym_trains` | `user_statistics.total_gym_trains` | ENABLED | One successful server Gym training action is one session. |
| `attacks_won` | none | PAUSED | Authoritative PvP terminal-result lifecycle is not implemented. |
| `total_damage_dealt` | none | PAUSED | No authoritative lifetime weapon-damage telemetry. PvP remains incomplete. |
| `player_level` | `users.level` | ENABLED | Direct authoritative player state. |
| `competitions_won` | none | PAUSED | City competition system is not implemented. |
| `cash_on_hand` | ambiguous | PAUSED | “Active wallet” is not canonically defined as Dirty Cash, Clean Cash, combined cash, or another balance. |
| `courses_completed` | count of `user_completed_courses` | ENABLED | Graduation ledger is unique and server-owned. |
| `unique_items_found` | none | PAUSED | Current inventory is not a lifetime unique-acquisition ledger; consumed/sold items would be lost from the count. |
| `crimes_successful` | `user_crime_records.total_successes` | ENABLED | Successful crime settlement is server authoritative. |
| `drugs_used` | none | PAUSED | No reconciled lifetime drug-use telemetry or canonical item-to-drug classification consumer. |
| `casino_spins` | none | PAUSED | Casino economy is fail-closed in PR #17 and no authoritative spin counter exists. |
| `days_in_jail` | none | PAUSED | No lifetime served-duration ledger; Jail timing/balance remains partially unresolved. |
| `missions_completed` | incomplete | PAUSED | Anonymous completion is now durable, but Kevin completion is not represented by a universal lifetime mission ledger. |
| `hospital_hours` | none | PAUSED | No lifetime served-duration ledger. |
| `flights_taken` | none | PAUSED | Airport/international travel remains design-only. |
| `friends_count` | none | PAUSED | No authoritative friends/social graph system exists. |

Unsupported trackers remain visible in the achievement catalog, but the API marks them `tracking_available: false` and does not fabricate progress.

## Catalog drift protection

The four enabled tracker groups are fingerprinted against the recovered source fields:

- ID
- title
- description
- category
- tracker key
- threshold
- rarity

Expected fingerprints:

- `gym_trains`: `8ee92e728cedc162e62bd7feb8d2f6f1`
- `crimes_successful`: `01b96511878f1afa4f88591ee99364e7`
- `player_level`: `333212151aba8634b4672f695298b121`
- `courses_completed`: `b057568304caf960a3f75c6f84cc963e`

Each group must still contain exactly 25 rows. A catalog change fails closed until the group is re-reconciled.

The fingerprint is a drift detector, not an authentication primitive.

## Atomic achievement settlement

The legacy achievement helper opened a second transaction after gameplay settlement and accepted a SQL column name dynamically.

It also caused a concrete telemetry bug:

1. a successful crime incremented `user_crime_records.total_successes` in the crime transaction;
2. after commit, the achievement helper incremented the same column a second time;
3. it then searched `achievements_master.stat_tracker = 'total_successes'`;
4. the source tracker is actually `crimes_successful`, so no crime achievement unlocked.

Result: successful-crime telemetry could be doubled while achievements remained locked.

That path has been removed.

### Crimes

Searching, Shoplifting and Pickpocketing now:

- increment `total_successes` exactly once;
- read the resulting total from the same SQL statement;
- evaluate `crimes_successful` achievements inside the same transaction;
- insert unlocks with `ON CONFLICT DO NOTHING`;
- write the achievement notification in the same transaction;
- commit the crime outcome and achievement state together.

### Gym

Successful Gym training now updates, in the training transaction:

- `total_gym_trains += 1`;
- `total_energy_spent += exact server-validated Energy`;
- `gym_trains` achievement thresholds.

The old post-commit helper calls were removed.

### Player level

An authoritative `UPGRADE` level transaction checks `player_level` achievements using the resulting `users.level` before committing the idempotent response.

`HOLD` does not create level progress.

### University

Successful graduation inserts the unique completed-course ledger row, counts completed courses, and evaluates `courses_completed` achievements before the graduation transaction commits.

## Cred

Cred remains a separate currency with no newly invented earning path.

This pass adds a database constraint requiring:

- `cred >= 0`
- integral Cred values only.

The development database contained:

- 0 users;
- 0 awarded achievements;
- 0 nonzero Cred balances

before this change, so no historical Cred or achievement data required migration.

The existing Credit Broker remains read-only/partial; this pass does not invent an upgrade-purchase or Cred-earning rule.

## Database integrity

Migration `20261104224000_achievement_cred_integrity_20261105.sql` adds:

- positive integer threshold constraint on `achievements_master.threshold_value`;
- nonnegative integer constraint on `users.cred`;
- `achievements_master(stat_tracker, threshold_value, achievement_id)` lookup index;
- `user_achievements(achievement_id)` FK/supporting index.

Supabase advisor readback shows the `user_achievements.achievement_id` unindexed-FK notice is resolved. Existing backend-owned RLS/no-policy notices remain informational and unchanged in access model.

## Flutter companion

Draft PR #5 now:

- builds filter tabs from the actual source categories rather than hardcoded categories that did not match the catalog;
- renders unsupported trackers with a neutral “TRACKING PENDING” state;
- uses `tracking_available` returned by the backend;
- no longer relies on a hardcoded achievement reward field.

## Verification boundary

Performed:

- source/catalog reconciliation;
- database schema/catalog readback;
- dependency scan for the removed legacy helper;
- static GitHub readback;
- Supabase security/performance advisor review.

Not performed by instruction:

- Node runtime tests;
- gameplay tests;
- concurrency tests;
- Flutter analyze/build/widget tests;
- deployment;
- production migration/backfill.
