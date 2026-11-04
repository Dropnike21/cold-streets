# Remaining Economy / Resource Route Stabilization — 2026-11-05

**Status: DRAFT source work + isolated Supabase development migrations. Not deployed and not gameplay-tested.**

This branch stacks on `security/banking-missions-company-seeds-20261105` (draft PR #8).

## Syndicate / recruits

### Critical defects found
- `POST /syndicate/hire` trusted the complete client-provided recruit object, including price and all stats.
- `POST /syndicate/complete_job` trusted a client-provided payout and could mint arbitrary Dirty Cash.
- Domain transfer logic selected `user_crew` by `crew_id` without proving ownership before mutating its domain.
- Company assignment accepted a client-provided position role while the canonical company position catalog remains unresolved.

### Changes
- Added backend-only `recruitment_offers`.
- Board generation persists five server-generated offers for 15 minutes and returns an `offer_id`.
- Hiring accepts only the authenticated player's `offer_id`, then reloads price, tier and all 16 current/max stat fields from the locked database offer.
- Board generation and hiring use persistent idempotency.
- Recruit RNG now uses `node:crypto.randomInt`, not `Math.random`.
- Crew assignment verifies the crew belongs to the authenticated player and the crime title exists.
- Company crew assignment returns 503 until company position data is canonical.
- `complete_job` returns 503. The recovered design confirms recruit crime completion is a code path but provides no authoritative server completion interval. The former arbitrary payout parameter is removed from the reachable behavior.

## City Jobs

### Source/schema conflicts found
- Backend promotion queried `job_ranks.stat_req_value`, which does not exist in the recovered schema.
- Recovered rank requirements are `req_acu`, `req_ops`, `req_pre`, `req_res`.
- Legacy code labeled **job 1 as City Hospital**, but recovered catalog says:
  - job 1 = Armed Forces
  - job 2 = City Hospital
- Legacy Job Specials mapped item IDs 101/102 to Bandage/Morphine, but recovered items are:
  - 101 = Combat Knife
  - 102 = Aluminum Bat
- PostgreSQL dump stores interview `options` as quote-lost pseudo-array TEXT. Some answers contain commas, so comma splitting is not valid.

### Source-backed interview normalization
The connected Google Sheet tab **job interviews** contains all 140 questions with valid four-string JSON option arrays. Migration `20261104190622_normalize_job_interview_options_20261105`:
- preserves legacy `options` TEXT;
- adds `options_json JSONB`;
- populates **140/140** rows directly from the spreadsheet;
- enforces NOT NULL after complete source-backed population.

### Interview authority
Added backend-only `job_interview_sessions`:
- GET interview creates a 15-minute server session containing exactly the five issued question IDs;
- API returns `interview_id`;
- submit requires that UUID plus exactly five unique answers matching the issued set;
- correct answers are read from the same job's catalog rows;
- the interview is consumed once before hire/ban state is committed.

### Promotions / resignation
- Promotion checks all four rank requirements.
- Promotion Job Point cost is taken from `promotion_incentive_cost`.
- Promotion and resignation use authenticated actor identity, row locks and persistent idempotency.
- Heist resignation payout remains the existing server rule `rank × 10,000`, never a client amount.
- Legacy Job Specials exchange is paused because its job/item mapping is demonstrably wrong.

## City Hospital

Recovered City Hospital source:
- catalog job: **2 / City Hospital**
- mastery passive: **Medical Revive**
- mastery rule: **75 Energy**

Revive now:
- derives actor from verified authentication;
- resolves mastery through `jobs_master.job_name = 'City Hospital'`, not a magic job ID;
- requires `is_mastered = true`;
- rejects self-revive because the source explicitly describes reviving others;
- locks actor/target in deterministic user-ID order;
- requires and deducts exactly 75 Energy;
- verifies target is still hospitalized;
- clears hospital state and raises HP to at least 20;
- is protected by persistent idempotency.

The City Hospital active mastery description and its recovered pseudo-JSON reward ID conflict (description says Trauma Kit, logic points at item 268 / Medical Grade Morphine). No active mastery exchange was implemented.

## Inventory

### Catalog mismatch
Recovered `items_master.effects` is TEXT pseudo-JSON, not JSONB. It contains a broad mechanics language including:
- direct healing/energy/nerve;
- buffs/debuff removal;
- hospital/jail modification;
- transformations;
- drugs/addiction/overdose;
- nested stat penalties;
- training modifiers and other effects.

The former backend treated `effects` as a JavaScript object and therefore could not correctly execute the recovered data.

### Safe subset now supported
The server uses a strict, non-evaluating parser and consumes an item only if **every** effect is a supported positive integer direct effect:
- `instant_heal`
- `energy_gain`
- `energy_restore`
- `nerve_gain`

If any unknown key, nested object, string value, decimal, duplicate key, or unsupported mechanic is present, the request returns 503 **before inventory is consumed**.

Supported item use:
- authenticates the player;
- locks player then idempotency then inventory;
- checks cooldown;
- applies direct effects with HP/max-HP and Nerve/max-Nerve caps plus the existing 100 Energy cap;
- conditionally decrements one inventory unit;
- adds cooldown;
- commits the response to the idempotency ledger in the same transaction.

Equipment now uses the authenticated actor and verifies inventory ownership plus catalog category before updating an allowlisted equipment column.

Inventory valuation also avoids division-by-zero when `baseline_stock = 0`.

## Credit Broker / City Hall

- Credit Broker currently has **GET-only** backend behavior. There is no purchase mutation endpoint to secure in this pass.
- City Hall currently exposes **GET-only leaderboards**. There is no City Hall charge route in the current backend.
- Neither system was given invented write behavior.

## Development database migrations

Applied to isolated project `qbrntyrlzxhilwrbcriq`:
- `20261104190444 server_issued_offers_and_interviews_20261105`
- `20261104190622 normalize_job_interview_options_20261105`

Readback:
- recruitment offer table exists;
- job interview session table exists;
- 140 interview rows / 140 normalized option rows;
- zero unvalidated public foreign keys;
- RLS is enabled on all public tables; advisor reports 56 `rls_enabled_no_policy` INFO notices, intentionally backend-only with no direct client policies.

## Flutter companion changes

On the Flutter auth branch / draft PR #5:
- Syndicate hire now sends only `offer_id` and uses the returned server balance.
- Jobs stores `interview_id` and sends it with the five answers.
- Promotion button checks all four requirement values returned by the server.
- Hospital immediately synchronizes actor Energy after a successful revive.
- Existing authenticated HTTP adapter continues generating `Idempotency-Key` UUIDv4 values for POSTs.

## Still blocked / next audits

1. **Crew crime scheduling:** define persisted assignment start/completion times and server payout execution before re-enabling `complete_job`.
2. **Company NPC roles:** resolve canonical company position/product catalog before `assign_company`.
3. **Job Specials:** reconstruct canonical rank/mastery special mappings and resolve description/reward-ID conflicts.
4. **Consumables:** implement explicit schemas/mechanics for drugs, buffs, transformations, hospital/jail reducers, addiction, overdose, training buffs and debuffs. Do not use `eval` or generic pseudo-JSON execution.
5. **Daily City Job salary/incentive settlement:** no authoritative claim route exists in the inspected backend; design a one-time server settlement before adding one.
6. **Other economy routes:** jail/bail, university costs/rewards, information broker purchases, events, and any remaining cross-player transfers still require the same actor/price/idempotency review.
7. **Verification:** no Node runtime tests, Flutter build/analyze, gameplay tests or concurrency tests were run in this phase, per project direction.
