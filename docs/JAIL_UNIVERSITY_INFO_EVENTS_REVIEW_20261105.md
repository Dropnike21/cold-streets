# Jail, University, Info Broker, Events & Residual Actor Security — 2026-11-05

**Status: DRAFT source work + isolated Supabase development migration. Not deployed and not gameplay-tested.**

This branch stacks on `security/remaining-economy-routes-20261105` (draft PR #9).

## 1. Jail

### Actor and transaction authority

`POST /jail/bail`, `POST /jail/breakout` and `POST /jail/gym/train` now derive the acting player only from the verified session.

Cross-player bail/breakout locks all affected user rows in deterministic numeric user-ID order before the idempotency row. This avoids trusting the body actor and reduces A→B / B→A deadlock risk.

All three state-changing Jail actions require persistent `Idempotency-Key` handling.

### Bail

The existing gameplay rule is retained:
- bail = **$100 Clean Cash × initial sentence minutes**, rounded up from `jail_initial_seconds`;
- self-bail gives no Influence;
- bailing another player gives the existing **+25 Influence**.

The payer balance, Influence reward and inmate release commit atomically. Bail is recalculated from server state; the client does not send price.

**Important:** the source recovery reference confirms bail/breakout are code-path features but does not establish a replacement economy formula. The university catalog contains `bail_discount` perks, but it does not define whether multiple discounts stack, replace one another, cap, or apply multiplicatively. No discount behavior was invented.

### Breakout

- Existing **5 Nerve** cost retained.
- Existing **40%** success rule retained as the current code-path balance rule.
- RNG changed from `Math.random()` to `crypto.randomInt()`.
- A failed attempt still applies the existing +20 Heat / +1 hour actor penalty.
- A retry with the same idempotency UUID replays the first outcome rather than rerolling.

The 40% chance remains a balancing placeholder until a canonical Jail & Heat rule is recovered/approved.

### Prison yard

- authenticated actor only;
- exact positive integer energy validation;
- idempotent request;
- verifies the actor is still jailed;
- training gain is calculated in PostgreSQL numeric arithmetic and rounded to 2 decimals;
- player EXP and all four physical stats update in the same transaction.

## 2. University

### Source-backed reward normalization

The connected Google Sheet tab `education_course_master` contains **220** course rows. Every `rewards_json` cell parses as valid JSON.

Observed reward structure:
- **176** rows: `stats`
- **20** rows: `stats + unlocks`
- **23** rows: `stats + perks`
- **1** row: `stats + perks + unlocks`

Top-level keys are only `stats`, `perks`, `unlocks`.
All stat keys are only `acu`, `ops`, `pre`, `res`.

Supabase migration:
- `20261104193642 normalize_university_rewards_20261105`

It preserves the recovered pseudo-JSON `rewards_json TEXT` and adds/populates canonical `rewards_jsonb JSONB NOT NULL` directly from the spreadsheet.

Readback: **220/220** course rows have normalized rewards.

### Enrollment

`POST /university/enroll` now:
- uses verified player identity;
- requires idempotency;
- prevents a second simultaneous active course;
- rejects already-completed courses;
- checks the catalog prerequisite;
- charges exact `cost_dirty_cash`;
- uses the catalog `duration_seconds`;
- debits tuition and starts the course atomically.

No client-supplied cost or duration is authoritative.

### Dropout

Dropout is transactionally idempotent. A retry with the same request UUID replays the original completed response and cannot accidentally drop a subsequently enrolled course.

### Graduation

`POST /university/graduate`:
- uses server time to verify course maturity;
- requires the active catalog course;
- inserts `user_completed_courses` once under the existing `(user_id,course_id)` primary key;
- applies only the source-backed four-stat reward;
- clears the enrollment in the same transaction;
- stores/replays the committed response through the idempotency ledger.

The catalog `perks` and `unlocks` are returned as **recorded entitlements** via the completed course relationship, but they are **not automatically activated** yet. Their consuming systems need explicit semantics. Examples include `bank_interest`, `bail_discount`, `max_nerve`, `jail_bust_out`, `revive_ally` and other unlocks.

Do not implement a generic perk interpreter or infer stacking rules.

## 3. Info Broker

### Front page schema correction / privacy

The reconstructed `bounties` table primary key is `id`, not `bounty_id`. The front-page query now selects `b.id AS bounty_id`.

Anonymous bounties return a NULL placer username instead of exposing the placing account in the response.

Classified results expose the actual `classified_ads.id` as `ad_id`.

### Classified ads

Existing rule retained:
- **$10 Clean Cash per trimmed character**
- maximum 150 characters
- 24-hour expiry

Posting:
- derives actor from auth;
- calculates cost server-side;
- locks player balance;
- conditionally debits Clean Cash;
- inserts the ad;
- commits an idempotent response with server balance.

### Bounties

Existing minimum retained:
- **$500 Dirty Cash minimum**

The requested reward is user-selected by design, but it is parsed as an exact positive integer and funded from the authenticated player's locked Dirty Cash.

The server:
- validates target username;
- rejects self-bounties;
- validates `is_anonymous` as boolean;
- conditionally debits funds;
- inserts target/placer/reward atomically;
- uses persistent idempotency.

**Unresolved:** the reconstructed bounty schema has no completion/claim/status lifecycle. This PR secures placement only; it does not invent bounty settlement.

## 4. Events

Event reads use the verified player identity even though the ownership-checked URL still contains a user ID for current Flutter compatibility.

Pagination is bounded:
- limit 1–100;
- nonnegative offset up to 1,000,000.

`POST /events/mark_read` ignores body actor IDs and derives the player from the session. The false→true update is intrinsically idempotent and does not need the financial replay ledger.

## 5. Residual actor-boundary fixes found by backend scan

A scan of all 28 route files found additional active body-actor dependencies.

### Fixed

- **Character `/level-up`:** authenticated actor, strict HOLD/UPGRADE enum, row lock, exact EXP check and persistent idempotency.
- **Gym `/activate`:** authenticated actor and validated owned gym.
- **Crimes master `/execute`:** authenticated actor and validated crime ID before dispatching to the existing category engines.
- **Company `/apply`:** authenticated actor, locked employment state, company validation and persistent idempotency.
- **Company management `/update-profile`:** authenticated owner/director from the existing management middleware; body `user_id` removed, company update + log are atomic and idempotent.

### Deliberately still present but unreachable

Five `company_management.js` handlers still destructure body `user_id`, but the central middleware returns 503 **before those routes execute**:
- manage employee
- change director
- sell/liquidate company
- buy company upgrade
- manage applicant

Those handlers remain paused pending the earlier company catalog / consent / archival design work.

### Crime idempotency still incomplete

The master crime router now authenticates the actor, but Searching / Shoplifting / Pickpocketing engines still resolve and commit randomized outcomes internally. A complete replay-safe crime request requires moving or integrating the idempotency record into each engine's successful/failure settlement path.

Do not claim randomized crime execution is retry-safe yet.

## 6. Flutter companion changes on PR #5 branch

- Jail HUD synchronizes server-returned Clean Cash, Influence, Nerve, Heat and jail timer state.
- University HUD synchronizes server-returned Dirty Cash and full graduated player state.
- University course cards now render normalized `rewards_jsonb.stats` plus source-defined perk/unlock counts instead of nonexistent `reward_stat_1/reward_amount_1` fields.
- Info Broker synchronizes Clean Cash after classified posting and Dirty Cash after bounty placement.
- Existing POST wrapper continues generating UUIDv4 `Idempotency-Key` values.

## 7. Development database checkpoint

After this pass:
- university courses: **220**
- normalized university reward rows: **220**
- unvalidated public foreign keys: **0**
- server-only workflow/idempotency tables remain present
- RLS remains enabled with no direct client policies for backend-only tables
- security advisor: only expected `rls_enabled_no_policy` INFO notices (56)

## 8. Remaining priority work

1. Full idempotency integration inside all three crime engines.
2. University perk/unlock consumers with explicit per-perk semantics and stacking rules.
3. Bounty claim/completion lifecycle if/when PvP settlement is implemented.
4. Canonical Jail & Heat balancing (40% breakout, bail economy, regen/heat scheduler discrepancy).
5. Remaining paused company management actions.
6. Daily City Job pay/incentive settlement.
7. Complex consumables and other deferred gameplay mechanics.
8. When testing is authorized: backend runtime, concurrency/replay tests, Flutter analyze/build, cross-account tests and gameplay tests.

No Node runtime tests, Flutter builds, integration tests or public deployment were performed in this pass.
