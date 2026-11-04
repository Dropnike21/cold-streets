# Crime Replay Safety, Daily City Job Settlement & University Entitlement Consumers — 2026-11-05

**Status: DRAFT source changes only on top of the isolated development database. Not deployed and not gameplay-tested.**

This branch stacks on `security/jail-university-info-events-20261105` (draft PR #10).

## 1. Crime execution is now replay-safe

The master `POST /crimes/execute` route now:

- derives the actor only from the verified session;
- requires an `Idempotency-Key` UUID;
- locks the authenticated player before the idempotency ledger;
- hashes the authoritative crime ID plus the Pickpocketing activity name when present;
- replays a committed result before entering a crime engine.

The three implemented engines — Searching, Shoplifting and Pickpocketing — now commit every terminal result through `utils/crimeSettlement.js`.

Terminal results covered:
- success;
- escaped failure;
- hospitalized failure;
- jailed failure;
- automatic 100%-Heat arrest.

The committed response is stored in `economic_idempotency` in the same PostgreSQL transaction as cash, Nerve, Heat, HP, jail/hospital state, loot, crime statistics and Kevin-contract progress.

A retry with the same key cannot:
- reroll success/failure;
- reroll cash;
- duplicate loot;
- consume Nerve twice;
- increment crime/mission progress twice;
- produce a different hospital/jail branch.

### Crime RNG

The three engines no longer use `Math.random()`.

`utils/crimeSettlement.js` uses `node:crypto.randomInt` for:
- percentile rolls;
- inclusive cash ranges;
- flavor-text selection;
- Pickpocketing critical-flavor selection.

The city-time/environment calculations in Searching and Shoplifting remain unchanged.

### Achievement side effects

Achievement tracking still runs after the crime transaction commits. It is intentionally outside the financial/state transaction. If an achievement side effect fails synchronously, the already-committed crime response is still returned rather than attempting to roll back a committed result.

## 2. Daily City Job settlement

### Source support

The project sources support these facts:

- GDD: **City Jobs earn Clean Cash and Working Stats**.
- `job_ranks`: every rank has `daily_pay` and `daily_incentives`.
- Recovery specification: `users.daily_job_claimed_at` records the active job's **latest payout event**.
- `user_job_data.incentive_balance` is the player's stored Job Point balance.

The source does **not** explicitly state that the spreadsheet's `gain_acu/gain_ops/gain_pre/gain_res` columns are awarded at the daily payout event. This branch therefore does **not** add those stat gains to salary settlement.

### `POST /jobs/claim-daily`

The endpoint:

1. derives the authenticated player;
2. requires persistent idempotency;
3. locks the player row;
4. requires a current City Job;
5. requires at least 24 hours since `daily_job_claimed_at`, unless it is NULL;
6. locks the current `user_job_data` row;
7. loads the current rank's `daily_pay` and `daily_incentives` from `job_ranks`;
8. credits `daily_pay` to **Clean Cash**;
9. credits `daily_incentives` to Job Points;
10. updates `daily_job_claimed_at = NOW()`;
11. commits the balances and replay response together.

A duplicate keyed request replays the original payout response.

### First payout boundary

There is no recovered `employment_started_at` timestamp and no source rule defining a first-pay waiting period. Therefore:

- if `daily_job_claimed_at IS NULL`, the first explicit claim is currently eligible immediately;
- after that, the server enforces a strict 24-hour interval.

This is a provisional compatibility choice, not a claim that the original design explicitly specified immediate first-day pay. If a future source establishes a hiring timestamp or first-pay delay, change this rule before production.

### Flutter

The City Job dashboard now:
- shows whether daily pay is ready;
- shows a coarse next-pay countdown when not ready;
- calls `POST /jobs/claim-daily`;
- synchronizes returned Clean Cash;
- refreshes the dashboard to show the new Job Point balance and payout timestamp.

## 3. University entitlements

The normalized `education_courses_master.rewards_jsonb` remains the canonical source.

A new `utils/educationEntitlements.js` reads only completed courses and provides:

- `hasEducationUnlock(...)` for exact string unlock checks;
- `listEducationEntitlements(...)` for source-preserving per-course `perks` and `unlocks`.

It does **not** aggregate numeric perks, choose strongest values, add percentages, or infer stacking rules.

The University dashboard now returns an `entitlements` collection containing only completed courses with source-defined perks or unlocks.

## 4. First explicit University unlock consumer: Medical Revive

Source row:

- course 82: **Combat Medic Training**
- stats: +150 OPS, +100 RES
- unlock: `revive_ally`

Hospital `POST /revive` now authorizes the ability when either:

1. the player has mastered the **City Hospital** City Job; or
2. the player has completed a University course whose normalized unlock list contains `revive_ally`.

The existing source-backed **75 Energy** revive cost is unchanged.

The response identifies the authorization path as:
- `city_hospital_mastery`, or
- `university_revive_ally`.

## 5. University mechanics intentionally NOT activated

The following normalized source entries remain declarative until their exact interaction/stacking rules are defined:

- `bail_discount`
- `bank_interest`
- `gym_gains`
- `energy_regen_bonus`
- `job_payout_boost`
- `hacking_success`
- `inventory_capacity`
- `max_nerve`
- `heat_reduction`
- and other numeric/boolean perks.

Likewise these unlocks are recorded but not globally enforced yet unless an explicit consumer exists:

- `city_bank`
- `city_pharmacy`
- `jail_bust_out`
- `use_advanced_meds`
- hacking/smuggling/forgery access;
- crafting/location/store unlocks.

Examples of unresolved questions:
- Does a 10% and 20% `bail_discount` stack, take the maximum, or replace?
- Is `bank_interest: 0.05` +5 percentage points or a multiplier?
- Are `max_nerve` values cumulative?
- How do University `gym_gains` combine with City Job mastery bonuses?
- Does `jail_bust_out` govern self-escape, busting another inmate, or both?

No generic perk interpreter was introduced.

## 6. Database state

No new schema migration was required in this branch.

Existing server-only infrastructure used:
- `economic_idempotency`;
- normalized University `rewards_jsonb`;
- completed-course primary key `(user_id, course_id)`.

Development readback confirmed:
- course 82 = Combat Medic Training / `revive_ally`;
- all 50 City Job rank rows have daily pay and incentive values.

## 7. Remaining priority work

1. Decide canonical meaning/stacking for individual University perks before enabling them.
2. Reconstruct/approve City Job working-stat gain timing.
3. Resolve City Job mastery active rewards against the real item/resource catalog.
4. Define bounty settlement / PvP claim lifecycle.
5. Define crew crime completion scheduling.
6. Resolve remaining paused company-management workflows.
7. Canonicalize Jail & Heat balance and scheduler cadence.
8. When testing is authorized: crime retry/concurrency, daily-pay replay/race tests, entitlement authorization tests, Node runtime checks and Flutter analyze/build.

No runtime tests, Flutter builds, gameplay tests or public deployment were performed in this pass.
