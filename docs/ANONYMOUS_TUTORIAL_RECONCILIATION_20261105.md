# Anonymous Tutorial Progress Reconciliation — 2026-11-05

## Scope

This pass replaces client-local Anonymous tutorial completion state with a server-owned progression ledger for the six recovered guided tutorial steps.

Sources reconciled:

- recovered `missions_master` rows;
- the current Flutter tutorial checklist/beacon logic;
- the archived GDD early-game loop;
- the Project Master Recovery reference.

No gameplay/build/runtime tests or deployment were performed.

## Recovered sequence

The six executable guided steps are:

1. **GET YOUR BEARINGS** — visit Vitals and Assets.
2. **KNOW YOUR STASH** — visit Inventory, Properties and Achievements.
3. **FIRST BLOOD** — visit Searching, Shoplifting and Pickpocketing, and complete 20 successful crimes.
4. **IRON AND BLOOD** — visit the Gym and spend 150 Energy on each STR, DEF, DEX and SPD.
5. **FOLLOW THE MONEY** — visit Bank and Real Estate.
6. **INTO THE SHADOWS** — visit Credit Broker and Casino.

The development migration normalizes these requirements into the existing `missions_master.reqs_json` column. The migration checks the exact recovered IDs/reputation levels/titles before changing the six empty requirement payloads.

## Server-owned progression

Migration `20261104222500_anonymous_tutorial_progress_20261105.sql` adds:

`user_mission_progress(user_id, mission_id, status, progress_jsonb, started_at, updated_at, completed_at)`

Properties:

- primary key `(user_id, mission_id)`;
- FKs to authenticated users and the mission catalog;
- active/completed state constraint;
- JSON-object progress constraint;
- completion timestamp consistency;
- RLS enabled;
- no direct `anon` or `authenticated` table grants.

The table is backend-owned and contains no rows after migration/readback because no gameplay was executed.

## Navigation evidence

Pure navigation objectives do not have an economic backend action from which they can be inferred.

The authenticated client therefore records one allowlisted navigation event through:

`POST /missions/tutorial/visit`

The request accepts only:

```json
{ "visit": "<fixed visit key>" }
```

The backend:

- derives the actor only from authentication;
- locks that player;
- resolves the player's current Anonymous reputation;
- loads the exact reconciled mission;
- verifies that the visit key is part of that current mission;
- sets only that boolean visit flag;
- accepts no reward, progress count, reputation, mission ID, or completion boolean from the client.

This is the narrow server-observable representation of an inherently UI-only objective. It is naturally idempotent.

## Gameplay evidence

Economic/gameplay objectives are not accepted as client progress.

### FIRST BLOOD

Only a successful server-settled Searching, Shoplifting or Pickpocketing transaction can:

- mark that crime category as visited/used;
- increment `successful_crimes`;
- increment at most to the recovered requirement of 20.

The tutorial update occurs in the same transaction as the successful crime and its replay-safe settlement.

Failed, jailed, hospitalized, escaped or replayed outcomes do not increment tutorial success progress.

### IRON AND BLOOD

Only a successful Gym training transaction can add tutorial Energy.

The backend uses the already-validated:

- authenticated player;
- selected STR/DEF/DEX/SPD stat;
- exact `energy_spent` amount.

Each stat counter is capped at the recovered requirement of 150. Training also proves the Gym visit.

## Anonymous VERIFY settlement

`POST /missions/action` with `anonymous / VERIFY` is re-enabled only for reputation steps 1–6.

It:

1. derives the actor from authentication;
2. requires a persistent `Idempotency-Key`;
3. locks the player;
4. opens/replays the persistent idempotency record;
5. reloads the current source mission;
6. verifies the mission ID/title/requirements/rewards still exactly match the reconciled rule;
7. locks the matching progress row;
8. verifies every current objective is complete;
9. reads only the server-owned reward catalog;
10. credits only supported exact integer reward types: Dirty Cash, Clean Cash, Energy and Nerve;
11. increments Anonymous reputation once;
12. marks the mission progress row completed;
13. commits reward, reputation, progress and replay response atomically.

No client-supplied reward amount, reputation value, mission ID, progress count or completion flag is authoritative.

Mission Energy/Nerve rewards are deliberately not clamped to normal maximums because the recovery specification notes that tutorial rewards may temporarily exceed normal resource caps.

## Catalog drift protection

The runtime recognizes only the six reconciled mission tuples.

A change to any executable mission's:

- mission ID;
- reputation level;
- title;
- normalized requirements;
- normalized reward payload

causes verification/progress recording to fail closed until re-reconciled.

## Rep 7 conflict remains blocked

Recovered row 7, **END OF THE LINE**, is not executable.

Its fields conflict:

- `reward_text = "None"`;
- `rewards_json = {"clean_cash": 1000}`.

There is also an unresolved progression conflict:

- the row text says Kevin is available after this tutorial;
- the current Flutter contact gate historically requires Anonymous reputation 50;
- no recovered mission rows 8–49 exist.

This pass does not choose a Kevin threshold or award the conflicting row-7 reward.

## Flutter companion

Draft Flutter PR #5 now:

- sends authenticated allowlisted navigation events;
- mirrors tutorial beacon state from server progress;
- stops deriving crime/Gym completion from local telemetry deltas;
- renders Anonymous checklist completion from `GET /missions/details/.../anonymous` progress;
- no longer loads mission progress from `SharedPreferences`.

The generic authenticated POST adapter continues supplying UUIDv4 idempotency keys for VERIFY.

## Verification boundary

Performed:

- source/catalog reconciliation;
- development migration application;
- development schema/catalog readback;
- static GitHub readback.

Not performed by instruction:

- Node runtime tests;
- Flutter analyze/build/widget tests;
- gameplay tests;
- concurrency/replay tests;
- deployment or production changes.
