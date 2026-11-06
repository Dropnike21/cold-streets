# Cold Streets — Future Development Master TODO

**Development paused:** 2026-11-06  
**Purpose:** single restart roadmap for future Cold Streets development  
**Companion recovery guide:** `RECOVERY_NEW_DEVICE.md`

This document is the master "what next" list. It combines the stabilization backlog, mechanics-decision register, runtime verification plan, current Flutter/backend state, and the remaining feature roadmap.

The central rule when development resumes is:

> **Do not start by adding new features. Finish runtime verification, close current defects, and decide blocked mechanics first.**

---

# Status vocabulary

- **VERIFIED_PARTIAL** — successfully exercised in the current development environment, but not fully tested.
- **IMPLEMENTED_UNVERIFIED** — source implementation exists but still needs runtime/integration/concurrency validation.
- **PARTIAL_SAFE** — a safe subset exists; unresolved behavior remains intentionally unavailable.
- **DECISION_REQUIRED** — mechanics/design/source conflict must be resolved before implementation.
- **NOT_STARTED** — feature/system has not yet been implemented authoritatively.
- **DEFER** — deliberately not needed for the next development phase.
- **FAIL_CLOSED** — UI/API may expose read-only information, but value-changing gameplay remains disabled.

---

# 0. FIRST THING TO DO WHEN DEVELOPMENT RESUMES

Do these before adding gameplay features.

## 0.1 Recreate the development environment

Follow `RECOVERY_NEW_DEVICE.md`.

- [ ] Clone the repository.
- [ ] Inspect `archive/development-pause-20261106`.
- [ ] Install the known-good Flutter/Node/Android toolchain.
- [ ] Recreate the backend private `.env`.
- [ ] Download the Supabase PostgreSQL CA certificate.
- [ ] Create a fresh Android emulator with adequate storage.
- [ ] Run `flutter doctor -v`.
- [ ] Run `flutter pub get`.
- [ ] Run backend release preflight.
- [ ] Confirm the Supabase development project is still the intended test project.

## 0.2 Freeze the new runtime candidate before testing

- [ ] Record exact backend/Flutter commit SHA.
- [ ] Confirm no production secrets are present.
- [ ] Confirm unresolved mechanics remain fail-closed.
- [ ] Do not merge to `main` yet.

---

# 1. P0 — FINISH CURRENT RUNTIME/STABILIZATION WORK

This is the highest priority.

## 1.1 Backend runtime verification

Current state: **VERIFIED_PARTIAL**

Already observed successfully:

- Node starts.
- gameplay mode can be enabled.
- Supabase PostgreSQL Session Pooler connection works.
- TLS CA verification works.
- runtime bootstrap reaches `gameplay_runtime_bootstrap_ready`.
- State Duration worker starts.

Still required:

- [ ] Verify `/healthz` returns the expected healthy result.
- [ ] Verify `/readyz` returns healthy after DB bootstrap.
- [ ] Verify gameplay-disabled startup with `ENABLE_GAMEPLAY_API=false`.
- [ ] Verify malformed critical configuration fails safely.
- [ ] Verify DB unavailable at boot -> readiness failure -> automatic recovery after DB returns.
- [ ] Verify State Duration worker starts exactly once.
- [ ] Verify Crew Crime worker remains disabled.
- [ ] Verify graceful SIGTERM shutdown.
- [ ] Verify HTTP body/header/socket/request limits.
- [ ] Verify PostgreSQL statement/query/lock/idle-transaction timeout behavior.
- [ ] Verify DB pool backpressure/recovery.
- [ ] Verify Supabase Auth timeout and local concurrency protection.

## 1.2 Authentication boundary

Current state: **VERIFIED_PARTIAL**

Already observed:

- Supabase signup works.
- email confirmation works.
- confirmed account can sign in.
- Flutter can reach the authenticated game flow.
- backend can establish gameplay runtime against Supabase.

Still required:

- [ ] Missing bearer token test.
- [ ] Malformed bearer token test.
- [ ] Expired token test.
- [ ] Valid confirmed account test.
- [ ] Auth upstream unavailable test.
- [ ] Auth timeout test.
- [ ] Auth concurrency/backpressure test.
- [ ] Confirm tokens/emails/secrets never appear in logs.
- [ ] Verify logout/token-expiration behavior.

### Auth email/deep-link cleanup

Current state: **IMPLEMENTED_UNVERIFIED / configuration incomplete**

- [ ] Replace default localhost email-confirmation redirect.
- [ ] Define Cold Streets custom deep-link callback.
- [ ] Add redirect to Supabase Auth allowed redirect URLs.
- [ ] Pass the redirect from Flutter signup.
- [ ] Configure Android deep-link handling.
- [ ] Configure Windows deep-link handling if retained.
- [ ] Customize confirmation/reset email templates later.
- [ ] Configure branded sender/custom SMTP later if desired.

This is useful, but it is not a blocker for local gameplay testing once an account is already confirmed.

## 1.3 Flutter runtime validation

Current state: **VERIFIED_PARTIAL**

Already observed:

- Windows Flutter application built and launched.
- Android debug APK compiled successfully.
- Android authenticated flow reached the tutorial screen.
- Supabase build-time configuration works.
- Android emulator can reach local backend through `10.0.2.2`.
- likely LevelUpOverlay numeric/string first-frame bug has been patched.

Still required:

- [ ] Re-run `flutter analyze` on the final candidate and close actual errors.
- [ ] Record remaining warnings separately from errors.
- [ ] Build Windows candidate again.
- [ ] Build Android candidate again.
- [ ] Verify the LevelUpOverlay numeric parsing fix on-device.
- [ ] Capture and fix any remaining red-screen exceptions.
- [ ] Test first-login/new-player flow end-to-end.
- [ ] Test returning-player login flow.
- [ ] Verify tutorial progression persists correctly.
- [ ] Verify app reconnect/restart behavior.
- [ ] Verify logout.
- [ ] Verify token expiration/session refresh.
- [ ] Verify paused screens are visibly unavailable.
- [ ] Verify no client-side payout/cost/reward math has reappeared.

### Android development maintenance

- [ ] Migrate Kotlin 2.2.20 to a Flutter-supported future version (2.3.20+ when appropriate).
- [ ] Plan migration to Android Built-in Kotlin when plugin ecosystem supports it.
- [ ] Upgrade shared_preferences_android / url_launcher_android when compatible Built-in Kotlin versions exist.
- [ ] Remove temporary compatibility flags only after the Android build stack supports doing so.
- [ ] Use an emulator with adequate disk storage.
- [ ] Keep Flutter debug baseline/debug paint off during visual QA.

These are maintenance items, not reasons to rewrite the current Android project immediately.

---

# 2. P0 — API CONTRACT, IDEMPOTENCY, CONCURRENCY, ECONOMY TESTING

Do this before enabling additional settlement systems.

## 2.1 API smoke contract

For every active route family:

- [ ] Valid request.
- [ ] Malformed body.
- [ ] Unexpected body field.
- [ ] Unexpected mutation query parameter.
- [ ] Foreign actor/resource access.
- [ ] Paused mechanic response.
- [ ] Verify server derives authenticated actor identity.
- [ ] Verify client cannot choose reward IDs, prices, payouts, quantities, or ownership.

## 2.2 Idempotency replay

Prioritize:

- [ ] Bank check claim.
- [ ] City NPC market purchase.
- [ ] Gym purchase/activation/training.
- [ ] Searching crime.
- [ ] Shoplifting crime.
- [ ] inventory use.
- [ ] inventory equip.
- [ ] City Job daily settlement.
- [ ] company owner funding.
- [ ] employment actions.
- [ ] University enrollment/completion.
- [ ] Hospital revive.

For every replay-sensitive route:

- [ ] first request settles once.
- [ ] identical retry returns original settlement.
- [ ] same key + changed payload fails.
- [ ] concurrent duplicates cannot double settle.

## 2.3 Economy/resource conservation

For every enabled mutation verify exact before/after state:

- [ ] correct currency denomination.
- [ ] correct balance delta.
- [ ] correct inventory/resource delta.
- [ ] ledger/source record exists.
- [ ] no negative balances.
- [ ] no duplicate grant/debit.
- [ ] server catalog value matches settlement.
- [ ] retry cannot mint resources.
- [ ] client cannot create or destroy value.

## 2.4 Concurrency and lock ordering

Controlled races:

- [ ] same wallet + simultaneous market purchases.
- [ ] duplicate Bank claim.
- [ ] duplicate consumable use.
- [ ] Gym train vs another same-player mutation.
- [ ] simultaneous company funding.
- [ ] employee/crew transfer races.
- [ ] State Duration expiry vs revive/new penalty.
- [ ] multiple State Duration worker replicas.

Verify:

- [ ] no deadlocks.
- [ ] deterministic winner/conflict behavior.
- [ ] no double settlement.
- [ ] retries recover safely.

---

# 3. P0 — MIGRATIONS, DATA BASELINE, RELEASE OPERATIONS

## 3.1 Fresh migration replay

Current source baseline previously showed 41 Git migrations aligned with development history.

Still required:

- [ ] Replay all migrations on a disposable empty database.
- [ ] Verify migration names/history exactly.
- [ ] Verify indexes, constraints, triggers, RLS, functions.
- [ ] Verify anon/authenticated direct table access remains denied.
- [ ] Run Supabase Security Advisor after replay.
- [ ] Test rollback/recovery procedure where applicable.

## 3.2 Unique-item lifetime baseline — DECISION REQUIRED

Before applying lifetime discovery tracking to a populated production database choose one policy:

- [ ] Start lifetime tracking from migration date.
- [ ] Import a trusted historical acquisition source.
- [ ] Use current inventory as a documented baseline while explicitly changing the semantic.

Do not silently claim current inventory is true lifetime history.

## 3.3 Production operations

Not needed until staging verification is substantially complete:

- [ ] Select hosting/provider.
- [ ] Production HTTPS/TLS configuration.
- [ ] Production PostgreSQL pooler sizing.
- [ ] Production environment/secrets management.
- [ ] Monitoring dashboards.
- [ ] alert thresholds.
- [ ] backup verification.
- [ ] restore drill.
- [ ] release/rollback owner.
- [ ] immutable release commit recording.
- [ ] staging deployment.
- [ ] production rollout.

---

# 4. P1 — MECHANICS DECISIONS BLOCKING ALREADY-MODELED SYSTEMS

These should be decided before coding the corresponding missing behavior.

## 4.1 Vital regeneration — DECISION REQUIRED

Define:

- [ ] Energy regeneration amount.
- [ ] Energy cadence.
- [ ] Nerve regeneration amount.
- [ ] Nerve cadence.
- [ ] HP regeneration amount.
- [ ] HP cadence.
- [ ] interaction with Max Energy / Max Nerve / Max HP.
- [ ] VIP Max Energy interaction.
- [ ] offline/catch-up behavior.
- [ ] durable worker/scheduled-settlement design.

Do not restore the old single-process timer.

## 4.2 Recruit generation/pricing — DECISION REQUIRED

Recruits Canvas conflicts with legacy generation.

Define:

- [ ] tier current-stat ranges.
- [ ] tier max-potential ranges.
- [ ] stat focus/weighting.
- [ ] Stat Value Multiplier.
- [ ] Potential Multiplier.
- [ ] level gates.
- [ ] board size.
- [ ] refresh allowance.
- [ ] refresh reset cadence.
- [ ] recruitment cooldown.
- [ ] authoritative price formula.

Recruit generation/hiring should remain paused until this is resolved.

## 4.3 Crew Crime automation — DECISION REQUIRED

Resolve conflict between Recruits Canvas and `crimes_master`:

- [ ] fixed 60-second loop vs per-crime cooldown.
- [ ] flat 1% mortality vs per-crime casualty risk.
- [ ] average target payout vs crime-specific settlement.
- [ ] whether tools are required-only or consumed.
- [ ] behavior if a required tool disappears.
- [ ] stat growth cadence.
- [ ] event/provenance rules.

Crew recall may remain active. Assignment/payout worker stays paused.

## 4.4 City Job resignation — DECISION REQUIRED

Define:

- [ ] clean-exit Job Point retention.
- [ ] mastery/incentive retention.
- [ ] Final Heist payout formula.
- [ ] Final Heist payout currency.
- [ ] Final Heist Heat.
- [ ] City Job ban duration.
- [ ] rank gate/eligibility.

Do not revive the removed code-only values without an explicit design decision.

## 4.5 Pickpocket target lifecycle — DECISION REQUIRED

Define server-owned:

- [ ] target instance ID.
- [ ] activity assignment.
- [ ] activity duration/expiry.
- [ ] actor binding.
- [ ] persistence.
- [ ] replay rules.
- [ ] success modifier binding.
- [ ] disappearance/refresh semantics.

Pickpocket execution remains paused until the client no longer authors target state.

---

# 5. P1 — MAJOR ECONOMY/SYSTEM DECISIONS

## 5.1 Casino — DECISION REQUIRED / PARTIAL_SAFE

Already present:

- read/status foundation.
- Casino Token spend accounting foundation.
- unsafe settlement is fail-closed.

Decide/implement later:

- [ ] authoritative Casino Token acquisition.
- [ ] exact daily token cap behavior including VIP.
- [ ] Perya paytable/settlement.
- [ ] Slots paytable/settlement.
- [ ] High/Low rules/settlement.
- [ ] wager limits.
- [ ] payout rounding.
- [ ] jackpot rules.
- [ ] replay/idempotency behavior.
- [ ] Lottery ticket rules.
- [ ] Lottery draw rules.
- [ ] Lottery payout/check integration.
- [ ] PvP Casino matchmaking.
- [ ] PvP Casino escrow.
- [ ] PvP Casino winner settlement.
- [ ] rake rules.

## 5.2 Trade / Player Bazaar — DECISION REQUIRED / foundation only

Already present:

- read/preflight boundary.
- Flutter settlement surfaces are fail-closed.

Need:

- [ ] listing/escrow schema.
- [ ] settlement currency.
- [ ] listing fee/tax.
- [ ] price bounds.
- [ ] partial-stack/fill semantics.
- [ ] escrow reservation.
- [ ] expiry.
- [ ] cancellation/refund.
- [ ] seller payout timing.
- [ ] deferred check/proceeds behavior.
- [ ] access requirements.
- [ ] premium pack trading behavior once authoritative.

## 5.3 Auction — NOT_STARTED

Do only after Trade/deferred payout patterns are stable:

- [ ] listing lifecycle.
- [ ] bid lifecycle.
- [ ] bid escrow.
- [ ] cancellation.
- [ ] expiry.
- [ ] winner settlement.
- [ ] seller payout/check integration.
- [ ] fees/tax.

## 5.4 Bank — PARTIAL_SAFE / DECISION REQUIRED

Already present:

- unsafe time-deposit conversions are fail-closed.
- deferred payout/check redemption foundation exists.

Need decisions:

- [ ] funding denomination.
- [ ] duration options.
- [ ] interest formula/rate source.
- [ ] deposit cap.
- [ ] Bank Trust progression.
- [ ] Trust-to-term thresholds.
- [ ] maturity payout.
- [ ] early withdrawal.
- [ ] University/Credit Broker interest stacking.
- [ ] legacy deposit adjudication.
- [ ] expired check fallback.

## 5.5 Property lifecycle — PARTIAL_SAFE / DECISION REQUIRED

Already present:

- source-safe ownership state.
- move-in/starter integrity.

Need:

- [ ] resolve 7-tier vs 25-tier catalog conflict.
- [ ] resolve +10% vs +35% Gym bonus conflict.
- [ ] canonical purchase catalog/prices.
- [ ] nonstarter purchase settlement.
- [ ] bonus application/stacking.
- [ ] property upgrades/effects.
- [ ] upkeep currency/cadence.
- [ ] 7-day missed-upkeep stripping.
- [ ] P2P sale currency.
- [ ] sale listing fee/tax.
- [ ] cancellation.
- [ ] lease.
- [ ] gift transfer.

## 5.6 Company economy — PARTIAL_SAFE / DECISION REQUIRED

Already present:

- owner Dirty Cash funding.
- company cash ledger.
- normalized company type/position/product/upgrade source catalogs.
- consent-based safe employment subset.
- safe NPC position assignment subset where authoritative.

Need source reconciliation:

- [ ] resolve 3 Logistics Company / Logistics Co affiliation conflicts.
- [ ] resolve recovered supply-chain products vs legacy 20-row product catalog.
- [ ] define canonical product runtime model.
- [ ] reopen incorporation only after that model exists.

Need mechanics:

- [ ] incorporation currency.
- [ ] salary negotiation/acceptance contract.
- [ ] position assignment thresholds.
- [ ] NPC effectiveness weighting/cap.
- [ ] payroll cadence.
- [ ] payroll Dirty -> Clean rules.
- [ ] laundering tax base rate.
- [ ] ACU laundering reduction formula.
- [ ] laundering capacity/cadence.
- [ ] Tier-1 production settlement.
- [ ] Tier-2 processing settlement.
- [ ] Tier-3 clean-ratio sales settlement.
- [ ] supply contracts.
- [ ] breach settlement.
- [ ] advertising effect.
- [ ] upgrade effect consumers.
- [ ] upgrade stacking.
- [ ] company withdrawals.
- [ ] bankruptcy/insolvency.
- [ ] two-day bankruptcy enforcement if retained.
- [ ] severance distribution.
- [ ] liquidation/refund.
- [ ] inactivity decay.

## 5.7 Credit Broker / Cred — PARTIAL_SAFE / DECISION REQUIRED

Already present:

- read-only 18-upgrade catalog.

Need:

- [ ] define Cred earning sources.
- [ ] define upgrade price curve.
- [ ] define all 18 effect consumers.
- [ ] stacking rules.
- [ ] respec/refund rules.
- [ ] decide product identity: upgrade terminal vs loans vs market.
- [ ] decide whether separate Gold Credits monetization currency remains.

## 5.8 Premium / monetization — PARTIAL_SAFE / DECISION REQUIRED

Already established:

- VIP Max Energy target 200.
- source-backed Casino daily Token spend cap 150.
- Subscriber city NPC market +20 items/day, 100 -> 120.
- premium packs may eventually be tradable after Trade settlement exists.

Still decide:

### VIP
- [ ] exact +20% Nerve semantic.
- [ ] remaining benefit list.

### Kingpin
- [ ] exact benefit set.
- [ ] relationship to VIP benefits.

### Subscriber
- [ ] monthly VIP/Kingpin choice vs fixed VIP Pack.
- [ ] monthly Book catalog.
- [ ] Book temporary/permanent effects.
- [ ] monthly settlement cadence.
- [ ] catch-up behavior.
- [ ] billing activation.
- [ ] cancellation.
- [ ] grace period.

Do not build real-money billing until gameplay/economy/runtime foundations are stable.

---

# 6. P1/P2 — CURRENT GAMEPLAY SYSTEMS THAT ARE ONLY PARTLY COMPLETE

## 6.1 City Jobs

Already developed:

- daily claim settlement.
- Courthouse mastery active.
- Construction mastery active.
- job catalog/ranks/interviews foundations.

Need:

- [ ] working-stat gain cadence.
- [ ] Armed Forces mastery conflict.
- [ ] City Hospital mastery conflict.
- [ ] Grocery mastery conflict.
- [ ] Grand Casino mastery conflict.
- [ ] Data Entry resource conflict.
- [ ] Logistics mastery conflict.
- [ ] Public Library mastery conflict.
- [ ] Tech Startup mastery conflict.
- [ ] resignation rules (see mechanics section).
- [ ] full runtime/idempotency/concurrency validation.

For each conflicting mastery decide: correct source mapping, replace reward, or retire active.

## 6.2 University

Already developed:

- normalized rewards catalog.
- source-backed course entitlement foundation.
- explicit jail-bust/revive entitlement consumers.

Still blocked/unfinished consumers:

- [ ] energy_regen_bonus.
- [ ] gym_gains.
- [ ] tax_reduction.
- [ ] bank_interest.
- [ ] hacking_success.
- [ ] company_upgrade_discount.
- [ ] job_payout_boost.
- [ ] bail_discount.
- [ ] medical_boost/opponent HP.
- [ ] inventory_capacity.
- [ ] vehicle_upgrades.
- [ ] dump_find_chance.
- [ ] combat/firearm bonuses.
- [ ] max_nerve.
- [ ] heat_reduction.
- [ ] stealth/ghost.
- [ ] overdose_immunity.
- [ ] counterfeit_success.
- [ ] crop_yield_boost.

Do not implement a perk consumer until its stacking/interactions are unambiguous.

## 6.3 Jail / Heat / Hospital

Already developed:

- server-catalog crime penalties.
- state-duration worker foundation.
- source-safe Hospital revive subset.

Need decisions/implementation:

- [ ] Heat decay cadence/rate.
- [ ] state-dependent Heat behavior.
- [ ] bail Clean Cash formula.
- [ ] Juris Doctor/bail-discount interaction.
- [ ] Bust Out/Self Escape Nerve cost.
- [ ] escape success formula.
- [ ] outside-in vs inside-out behavior.
- [ ] failure penalties.
- [ ] prison-yard gain multiplier.
- [ ] prison-yard EXP behavior.
- [ ] canonical revive HP.
- [ ] jail served-duration telemetry.
- [ ] hospital served-duration telemetry.

## 6.4 Crimes

Already developed:

- authoritative Searching subset.
- authoritative Shoplifting subset.
- Pickpocket catalog/flow partially reconciled but executable target flow is paused.

Need:

- [ ] server-authoritative Pickpocket target lifecycle.
- [ ] remaining crime catalog engines.
- [ ] source-safe tool requirements/consumption behavior.
- [ ] full crime runtime/idempotency/economy testing.

## 6.5 Inventory / item effects

Inventory foundation exists, but many effect families remain unresolved:

- [ ] drugs.
- [ ] addiction.
- [ ] overdose.
- [ ] buffs/debuffs.
- [ ] transformations.
- [ ] jail reducers.
- [ ] hospital reducers.
- [ ] training modifiers.
- [ ] nested item effects.
- [ ] item effect stacking rules.
- [ ] timing/expiry rules.
- [ ] durable state for timed effects.

## 6.6 Achievements

Implemented/source-backed categories:

- gym_trains.
- crimes_successful.
- player_level.
- courses_completed.

Still unsupported/decision dependent:

- [ ] attacks_won.
- [ ] total_damage_dealt.
- [ ] competitions_won.
- [ ] cash_on_hand — define currency/aggregation/sampling.
- [ ] unique_items_found — resolve historical baseline.
- [ ] drugs_used — define drug-use semantics.
- [ ] casino_spins — define what counts as a spin.
- [ ] days_in_jail.
- [ ] missions_completed.
- [ ] hospital_hours.
- [ ] flights_taken.
- [ ] friends_count.
- [ ] Achievement reward/Cred semantics.

## 6.7 Missions / contacts

Already developed:

- Anonymous reps 1–6.
- Kevin visible at Anonymous rep 7.
- tutorial progression foundation.

Need:

- [ ] resolve Anonymous rep-7 reward conflict.
- [ ] Kevin objective generation.
- [ ] Kevin eligibility.
- [ ] Kevin reward curve.
- [ ] Kevin reputation gain/loss.
- [ ] partial completion rules.
- [ ] abort rules.
- [ ] repeat/cooldown rules.
- [ ] later-contact progression.
- [ ] full tutorial/mission runtime persistence verification.

## 6.8 Syndicate / crew

Already developed:

- recruitment offer authority foundation.
- persisted crew-crime scheduler foundation.
- crew recall safe path.

Paused/unfinished:

- [ ] resolve recruit generation/pricing.
- [ ] resolve crew-crime rules.
- [ ] recruit company assignment.
- [ ] syndicate establishment requirements.
- [ ] syndicate ranks.
- [ ] treasury.
- [ ] perks.
- [ ] organized-crime settlement.
- [ ] compounds/walls.
- [ ] territory war.

Syndicate establishment still requires authoritative member/capital/company-condition decisions. Do not restore legacy UI thresholds without verification.

---

# 7. P2 — PvP / Bounty / Combat

Current state: **mostly NOT_STARTED / fail-closed**

Already done:

- bounty placement is fail-closed until PvP settlement is authoritative.

Need design first:

- [ ] attack eligibility.
- [ ] turn structure.
- [ ] hit formula.
- [ ] miss formula.
- [ ] damage formula.
- [ ] crit formula.
- [ ] stat interactions.
- [ ] weapon/equipment/armor consumers.
- [ ] status/state outcomes.
- [ ] hospital/jail interactions.
- [ ] attack cooldowns.
- [ ] combat ledger.
- [ ] bounty placement currency.
- [ ] bounty fee.
- [ ] target eligibility.
- [ ] bounty escrow.
- [ ] expiry.
- [ ] cancellation/refund.
- [ ] anonymous surcharge.
- [ ] bounty winner settlement.

Only implement after formulas and state transitions are explicitly documented.

---

# 8. P2 — SCHEDULED WORK / DURABLE WORKERS

Already present:

- State Duration worker.

Need:

- [ ] unified durable scheduled-settlement framework.
- [ ] vital regeneration worker.
- [ ] market restocking worker.
- [ ] company payroll/production workers if rules require them.
- [ ] bank maturity worker if required.
- [ ] premium monthly settlement worker if retained.
- [ ] casino lottery draw worker if retained.
- [ ] recurring event/competition framework.
- [ ] durable retries.
- [ ] distributed claiming/locking.
- [ ] multi-replica tests.
- [ ] worker observability.
- [ ] dead-letter/manual recovery policy where appropriate.

Do not restore unsafe single-process timers for authoritative settlement.

---

# 9. P2 — MARKET RESTOCKING — DECISION REQUIRED

Legacy random timer is retired.

Define:

- [ ] restock cadence.
- [ ] quantities.
- [ ] affected item sources.
- [ ] deterministic vs random selection.
- [ ] price interaction.
- [ ] stock cap/floor behavior.
- [ ] multi-replica ownership/claiming.
- [ ] catch-up after downtime.

Then implement through durable scheduling.

---

# 10. P3 — LONG-TERM SYSTEMS NOT YET DEVELOPED

These are genuine future features. They should **not** be the first work when development resumes.

## 10.1 City Hall / politics

- [ ] political offices.
- [ ] election eligibility.
- [ ] campaigning.
- [ ] voting.
- [ ] election cadence.
- [ ] policy effects.
- [ ] grants.
- [ ] abuse prevention / alt-account rules.
- [ ] treasury/economy integration.

## 10.2 Stock market

- [ ] asset catalog.
- [ ] issuance model.
- [ ] price model.
- [ ] order/settlement model.
- [ ] manipulation controls.
- [ ] fees/tax.
- [ ] historical price data.

## 10.3 Airport / international travel

- [ ] destination catalog.
- [ ] travel cost.
- [ ] travel duration.
- [ ] travel state restrictions.
- [ ] destination-specific markets/features.
- [ ] flights achievement telemetry.

## 10.4 Vehicles

- [ ] vehicle ownership.
- [ ] purchase/sale.
- [ ] upgrades.
- [ ] University vehicle perk integration.
- [ ] travel/combat/crime use if intended.

## 10.5 Friends / social graph

- [ ] friend requests.
- [ ] accept/reject/remove.
- [ ] privacy rules.
- [ ] block rules.
- [ ] friends_count achievement telemetry.
- [ ] social abuse/rate limits.

## 10.6 Competitions / events

- [ ] event model.
- [ ] eligibility.
- [ ] scoring.
- [ ] settlement.
- [ ] rewards.
- [ ] anti-replay.
- [ ] competition achievement telemetry.

## 10.7 Auction house

See economy section. Build only after Trade/escrow/deferred-payout patterns are proven.

---

# 11. CROSS-CUTTING ENGINEERING WORK

These are not flashy features but are required for a reliable game.

## 11.1 Data/catalog cleanup

- [ ] normalize remaining pseudo-JSON master data.
- [ ] resolve remaining source/catalog naming conflicts.
- [ ] define catalog versioning/provenance policy.
- [ ] prevent display-only rows from becoming executable by accident.
- [ ] document authoritative source for every settlement field.

## 11.2 Legacy player/data migration

- [ ] define legacy-player migration policy.
- [ ] map old balances/inventory/state safely.
- [ ] decide what historical telemetry can/cannot be reconstructed.
- [ ] preserve auditability.
- [ ] test migrations against copied non-production data.

## 11.3 Lock-order and transaction policy

- [ ] finish cross-system lock-order audit.
- [ ] document canonical lock order.
- [ ] enforce shared helper patterns.
- [ ] concurrency tests for every new multi-resource mutation.

## 11.4 Observability

- [ ] structured business-event telemetry.
- [ ] settlement success/failure metrics.
- [ ] idempotency replay metrics.
- [ ] DB pool metrics.
- [ ] worker metrics.
- [ ] Auth latency/error metrics.
- [ ] economy anomaly alerts.
- [ ] suspicious duplicate/replay alerts.

## 11.5 Automated testing

Build a permanent test suite rather than relying only on manual testing:

- [ ] backend unit tests.
- [ ] API integration tests.
- [ ] migration replay CI.
- [ ] authorization tests.
- [ ] idempotency tests.
- [ ] concurrency tests.
- [ ] economy conservation tests.
- [ ] Flutter unit/widget tests.
- [ ] Flutter integration tests.
- [ ] staging smoke suite.
- [ ] CI gate before merge.

---

# 12. UI / UX WORK — AFTER FUNCTIONAL STABILITY

Do not prioritize visual redesign ahead of runtime correctness.

Later:

- [ ] remove debug-only visual artifacts during QA.
- [ ] mobile typography review.
- [ ] responsive layout pass.
- [ ] accessibility/contrast review.
- [ ] consistent loading/error/empty states.
- [ ] consistent fail-closed/paused mechanic presentation.
- [ ] tutorial pacing/presentation.
- [ ] navigation consistency.
- [ ] desktop vs mobile layout consistency.
- [ ] production icons/splash/branding.
- [ ] better auth confirmation/reset UX.

---

# 13. THINGS NOT NEEDED WHEN DEVELOPMENT FIRST RESUMES

Unless a current blocker directly requires one of these, **do not start here**:

- [ ] new City Hall gameplay.
- [ ] stock market.
- [ ] airport/travel.
- [ ] vehicles.
- [ ] new Casino games.
- [ ] new crime categories beyond the current authoritative subset.
- [ ] territory war.
- [ ] syndicate compounds.
- [ ] auction house.
- [ ] competitions.
- [ ] real-money billing.
- [ ] large UI redesign.
- [ ] extra currencies.
- [ ] speculative item effects.
- [ ] more catalog content without executable semantics.
- [ ] production deployment.
- [ ] optimization before profiling.
- [ ] refactors that do not remove a known risk/blocker.

The project already has a large amount of modeled/catalog content. The next goal is **making the existing core reliable and authoritative**, not making the feature list larger.

---

# 14. RECOMMENDED DEVELOPMENT ORDER

When Cold Streets resumes, use this order:

## Phase A — Recovery and runtime closure

1. Restore toolchain/environment.
2. Freeze exact candidate.
3. Finish backend health/readiness/auth tests.
4. Finish Flutter analyze/build/device tests.
5. Fix all observed runtime exceptions.
6. Verify new-player and returning-player session flows.

## Phase B — Safety verification

7. API contract tests.
8. idempotency replay.
9. economy conservation.
10. concurrency/lock-order testing.
11. migration replay.
12. worker/recovery/shutdown tests.

## Phase C — Decide game rules

13. Vital regeneration.
14. recruit generation/pricing.
15. Crew Crime.
16. City Job resignation.
17. Pickpocket target issuance.
18. Bank.
19. Trade.
20. Casino.
21. Property.
22. Company economy.
23. Cred/Credit Broker.
24. Premium.
25. Jail/Heat/PvP.

## Phase D — Complete already-modeled systems

26. implement selected decisions server-side.
27. add idempotency/locks/conservation invariants.
28. update Flutter as presentation/intent only.
29. test each system before enabling it.

## Phase E — Staging and release readiness

30. full staging end-to-end.
31. monitoring/alerts.
32. backup/restore.
33. release/rollback rehearsal.
34. merge/release decision.

## Phase F — New features

Only after the existing core is stable:

35. later contacts/missions.
36. broader crime catalog.
37. full syndicate systems.
38. PvP/bounty if not already completed.
39. auction.
40. travel/vehicles.
41. stock market.
42. City Hall/politics.
43. competitions/events.
44. other expansion systems.

---

# 15. DEFINITION OF "READY TO ADD FEATURES"

Cold Streets is ready for major new feature development when all of the following are true:

- [ ] backend startup/readiness is reliable.
- [ ] authenticated Flutter flow is stable on supported platforms.
- [ ] no known first-load/runtime crash remains.
- [ ] active mutations pass authorization tests.
- [ ] replay-sensitive mutations pass idempotency tests.
- [ ] core economy mutations pass conservation tests.
- [ ] major shared-resource paths pass concurrency tests.
- [ ] migration replay is clean.
- [ ] scheduled workers are durable/multi-replica safe.
- [ ] unresolved mechanics remain explicitly disabled.
- [ ] core game-rule decisions have documented authoritative answers.
- [ ] staging can be restored/recreated reproducibly.
- [ ] monitoring and rollback exist before production.

Until then, "adding features" usually increases uncertainty and should remain secondary.

---

# 16. CANONICAL DOCUMENTS TO CONSULT WHEN RESUMING

Use this master TODO for ordering, then consult the detailed source documents as needed:

- `RECOVERY_NEW_DEVICE.md`
- `docs/STABILIZATION_MASTER_CLOSEOUT_20261105.md`
- `docs/STABILIZATION_MASTER_BACKLOG_20261105.md`
- `docs/MECHANICS_DECISIONS_REQUIRED_20261105.md`
- `docs/RUNTIME_VERIFICATION_PLAN_20261105.md`
- `docs/CLIENT_SCHEMA_CATALOG_CLOSURE_20261105.md`
- `docs/FLUTTER_BACKEND_CONTRACT_RECONCILIATION_20261105.md`
- `docs/OPERATIONAL_RELEASE_RUNBOOK_20261105.md`
- `docs/PRODUCTION_MONITORING_CHECKLIST_20261105.md`

This file is the high-level execution order. The dated reconciliation documents preserve the evidence and reasoning behind individual decisions.
