# Cold Streets Stabilization Master Backlog — 2026-11-05

Status vocabulary:
- DONE_SOURCE: source reconciliation and development implementation complete; still untested/unmerged.
- PARTIAL_SAFE: safe subset enabled; unresolved mechanics remain fail-closed.
- PAUSED_SOURCE: blocked by source conflict/missing semantics.
- NOT_STARTED: not yet reconciled in the current stabilization stack.
- TEST_BLOCKED: implementation exists but project instruction currently forbids gameplay/build/runtime tests.

## Current draft stack

Backend:
#4 auth/security boundary
#6 staging safety
#7 authoritative economy routes
#8 bank/mission/company/idempotency foundations
#9 recruits/interviews/revive/inventory
#10 jail/university/info broker/events
#11 replay-safe crimes, City Job settlement, University entitlements
#12 City Job mastery active rewards
#13 University jail-bust entitlement
#14 crew crime scheduler
#15 company workflows/applicant review
#16 jail/crime state reconciliation
#17 casino fail-closure
#18 bounty/PvP lifecycle fail-closure
#19 Anonymous tutorial
#20 achievements/Cred
#21 Credit Broker/Cred
#22 Trade Network read boundary
#23 property lifecycle
#24 Kevin handoff
#25 Bank settlement
#26 company cash flow/laundering boundary
#27 generic deferred payout contract
#28 company source catalog normalization

Flutter companion remains draft PR #5.

## P0 settlement / economy

- [x] Generic deferred payout/check contract — DONE_SOURCE (#27)
- [ ] Integrate first real deferred-payout issuer — PAUSED_SOURCE
- [ ] Trade Network listing/escrow schema — NOT_STARTED
- [ ] Trade Network settlement currency — PAUSED_SOURCE
- [ ] Trade Network fees/tax — PAUSED_SOURCE
- [ ] Trade Network partial-stack semantics — PAUSED_SOURCE
- [ ] Trade listing expiry/cancel/refund — PAUSED_SOURCE
- [ ] Trade seller payout timing — PAUSED_SOURCE
- [ ] Auction listing/bid/escrow lifecycle — NOT_STARTED
- [ ] Auction seller payout/check integration — NOT_STARTED

## Companies

- [x] Company Dirty Cash owner funding + cash ledger — PARTIAL_SAFE (#26)
- [x] Normalize 179 company positions — DONE_SOURCE (#28)
- [x] Normalize 122 special descriptions — DONE_SOURCE (#28)
- [x] Normalize 282 product rules — DONE_SOURCE (#28)
- [x] Normalize 425 affiliation edges — DONE_SOURCE (#28)
- [x] Normalize 120 upgrade cost/upkeep definitions — DONE_SOURCE (#28)
- [ ] Resolve 3 Logistics Company vs Logistics Co affiliation conflicts — PAUSED_SOURCE
- [ ] Resolve recovered supply-chain products vs legacy 20-row product catalog — PAUSED_SOURCE
- [ ] Reopen incorporation after canonical product runtime model — PAUSED_SOURCE
- [ ] Salary negotiation/acceptance contract — NOT_STARTED
- [ ] Position assignment with source stat thresholds — NOT_STARTED
- [ ] NPC company assignment/efficiency cap — PAUSED_SOURCE
- [ ] Payroll Dirty -> Clean settlement — PAUSED_SOURCE
- [ ] Laundering tax base rate — PAUSED_SOURCE
- [ ] ACU laundering-tax reduction formula — PAUSED_SOURCE
- [ ] Laundering capacity/cadence — PAUSED_SOURCE
- [ ] Tier-1 production settlement — PAUSED_SOURCE
- [ ] Tier-2 processing settlement — PAUSED_SOURCE
- [ ] Tier-3 clean-ratio sales settlement — PAUSED_SOURCE
- [ ] Supply contracts and breach settlement — NOT_STARTED
- [ ] Advertising settlement/effect — PAUSED_SOURCE
- [ ] Upgrade effect consumers/stacking — PAUSED_SOURCE
- [ ] Company withdrawals — PAUSED_SOURCE
- [ ] Bankruptcy 2-day enforcement — PAUSED_SOURCE
- [ ] Severance distribution — PAUSED_SOURCE
- [ ] Liquidation/refund semantics — PAUSED_SOURCE
- [ ] Inactivity decay — PAUSED_SOURCE

## Bank

- [x] Time-deposit unsafe conversion fail-closed — DONE_SOURCE (#25)
- [x] Deferred payout redemption — PARTIAL_SAFE (#27)
- [ ] Canonical time-deposit terms — PAUSED_SOURCE
- [ ] Canonical interest formula — PAUSED_SOURCE
- [ ] Deposit cap — PAUSED_SOURCE
- [ ] Bank Trust progression — PAUSED_SOURCE
- [ ] Trust-to-term thresholds — PAUSED_SOURCE
- [ ] Early withdrawal — PAUSED_SOURCE
- [ ] University/Credit Broker interest stacking — PAUSED_SOURCE
- [ ] Legacy-deposit adjudication — PAUSED_SOURCE
- [ ] Expired-check fallback — PAUSED_SOURCE

## Property

- [x] Ownership/move-in/starter audit integrity — PARTIAL_SAFE (#23)
- [ ] Resolve 7-tier vs 25-tier catalog conflict — PAUSED_SOURCE
- [ ] Resolve +10% vs +35% Gym-bonus conflict — PAUSED_SOURCE
- [ ] Nonstarter purchases — PAUSED_SOURCE
- [ ] Upgrade effect semantics — PAUSED_SOURCE
- [ ] Upkeep currency/cadence — PAUSED_SOURCE
- [ ] 7-day missed-upkeep stripping — PAUSED_SOURCE
- [ ] Property P2P sale settlement — PAUSED_SOURCE
- [ ] Lease/gift transfer model — PAUSED_SOURCE

## Casino

- [x] Unsafe casino economy fail-closed — DONE_SOURCE (#17)
- [ ] Canonical Casino Token acquisition — PAUSED_SOURCE
- [ ] Daily token cap enforcement including VIP — PAUSED_SOURCE
- [ ] Perya settlement — PAUSED_SOURCE
- [ ] Slots settlement — PAUSED_SOURCE
- [ ] High/Low settlement — PAUSED_SOURCE
- [ ] Jackpot rules — PAUSED_SOURCE
- [ ] Lottery ticket/draw rules — NOT_STARTED
- [ ] Lottery payout/check integration — NOT_STARTED

## Cred / Credit Broker

- [x] Read-only 18-upgrade catalog reconciliation — DONE_SOURCE (#21)
- [ ] Cred earning rules — PAUSED_SOURCE
- [ ] Upgrade price curve — PAUSED_SOURCE
- [ ] All 18 upgrade effect consumers — PAUSED_SOURCE
- [ ] Product identity: upgrade terminal vs loans vs market — PAUSED_SOURCE
- [ ] Separate Gold Credits monetization currency if retained — PAUSED_SOURCE

## Achievements

- [x] gym_trains — DONE_SOURCE
- [x] crimes_successful — DONE_SOURCE
- [x] player_level — DONE_SOURCE
- [x] courses_completed — DONE_SOURCE
- [ ] attacks_won — PAUSED_SOURCE
- [ ] total_damage_dealt — PAUSED_SOURCE
- [ ] competitions_won — PAUSED_SOURCE
- [ ] cash_on_hand — PAUSED_SOURCE
- [ ] unique_items_found — PAUSED_SOURCE
- [ ] drugs_used — PAUSED_SOURCE
- [ ] casino_spins — PAUSED_SOURCE
- [ ] days_in_jail — PAUSED_SOURCE
- [ ] missions_completed — PAUSED_SOURCE
- [ ] hospital_hours — PAUSED_SOURCE
- [ ] flights_taken — PAUSED_SOURCE
- [ ] friends_count — PAUSED_SOURCE
- [ ] Achievement reward/Cred semantics — PAUSED_SOURCE

## City Jobs

- [x] Daily claim settlement — DONE_SOURCE
- [x] Courthouse mastery active reward — DONE_SOURCE
- [x] Construction mastery active reward — DONE_SOURCE
- [ ] Armed Forces mastery conflict — PAUSED_SOURCE
- [ ] City Hospital active reward conflict — PAUSED_SOURCE
- [ ] Grocery mastery conflict — PAUSED_SOURCE
- [ ] Grand Casino mastery conflict — PAUSED_SOURCE
- [ ] Data Entry resource conflict — PAUSED_SOURCE
- [ ] Logistics mastery conflict — PAUSED_SOURCE
- [ ] Public Library mastery conflict — PAUSED_SOURCE
- [ ] Tech Startup mastery conflict — PAUSED_SOURCE
- [ ] Working Stat gain cadence — PAUSED_SOURCE

## University

- [x] Normalized rewards catalog — DONE_SOURCE
- [x] explicit jail-bust/revive entitlement consumers — PARTIAL_SAFE
- [ ] energy_regen_bonus consumer — PAUSED_SOURCE
- [ ] gym_gains consumer — PAUSED_SOURCE
- [ ] tax_reduction consumer — PAUSED_SOURCE
- [ ] bank_interest consumer — PAUSED_SOURCE
- [ ] hacking_success consumer — PAUSED_SOURCE
- [ ] company_upgrade_discount consumer — PAUSED_SOURCE
- [ ] job_payout_boost consumer — PAUSED_SOURCE
- [ ] bail_discount consumer — PAUSED_SOURCE
- [ ] medical_boost/opponent HP — PAUSED_SOURCE
- [ ] inventory_capacity consumer — PAUSED_SOURCE
- [ ] vehicle_upgrades consumer — PAUSED_SOURCE
- [ ] dump_find_chance consumer — PAUSED_SOURCE
- [ ] combat/firearm bonuses — PAUSED_SOURCE
- [ ] max_nerve consumer — PAUSED_SOURCE
- [ ] heat_reduction consumer — PAUSED_SOURCE
- [ ] stealth/ghost consumer — PAUSED_SOURCE
- [ ] overdose_immunity consumer — PAUSED_SOURCE
- [ ] counterfeit_success consumer — PAUSED_SOURCE
- [ ] crop_yield_boost consumer — PAUSED_SOURCE

## Jail / Heat / Hospital

- [x] server-catalog crime penalties — DONE_SOURCE
- [ ] Heat decay cadence conflict — PAUSED_SOURCE
- [ ] Bail formula/currency — PAUSED_SOURCE
- [ ] Breakout formula — PAUSED_SOURCE
- [ ] Jail-yard mechanics — PAUSED_SOURCE
- [ ] Canonical revive HP — PAUSED_SOURCE
- [ ] jail/hospital served-duration telemetry — NOT_STARTED

## Crimes / inventory

- [x] Searching/Shoplifting/Pickpocketing authoritative subset — DONE_SOURCE
- [ ] remaining crime catalog engines — NOT_STARTED
- [ ] drugs/addiction/overdose — PAUSED_SOURCE
- [ ] buffs/debuffs — PAUSED_SOURCE
- [ ] transformations — PAUSED_SOURCE
- [ ] jail/hospital reducers — PAUSED_SOURCE
- [ ] training modifiers — PAUSED_SOURCE
- [ ] nested item effects — PAUSED_SOURCE

## PvP / bounty

- [x] Bounty placement fail-closed pending PvP settlement — DONE_SOURCE
- [ ] authoritative turn-based PvP engine — NOT_STARTED
- [ ] hit/miss/damage/crit formulas — PAUSED_SOURCE
- [ ] equipment/weapon/armor consumers — PAUSED_SOURCE
- [ ] combat ledger — NOT_STARTED
- [ ] bounty claim settlement — PAUSED_SOURCE
- [ ] bounty cancellation/expiry/refund — PAUSED_SOURCE
- [ ] anonymous surcharge — PAUSED_SOURCE

## Missions / contacts

- [x] Anonymous reps 1-6 authoritative — DONE_SOURCE
- [x] Kevin visible at rep 7 — DONE_SOURCE
- [ ] Anonymous rep-7 reward conflict — PAUSED_SOURCE
- [ ] Kevin mission catalog — PAUSED_SOURCE
- [ ] Kevin objective/reward/REP rules — PAUSED_SOURCE
- [ ] later-contact progression — PAUSED_SOURCE

## Syndicate / crew

- [x] recruitment offer authority — DONE_SOURCE
- [x] persisted crew crime scheduler subset — DONE_SOURCE
- [ ] remaining crew crime rules — PAUSED_SOURCE
- [ ] recruit company assignment — PAUSED_SOURCE
- [ ] syndicate ranks/treasury/perks — NOT_STARTED
- [ ] territory war — NOT_STARTED
- [ ] compounds/walls — NOT_STARTED
- [ ] organized-crime settlement — NOT_STARTED

## Long-term systems

- [ ] City Hall politics/elections/policies/grants — NOT_STARTED
- [ ] Stock market — NOT_STARTED
- [ ] Airport/international travel — NOT_STARTED
- [ ] Vehicle ownership/upgrades — NOT_STARTED
- [ ] Friends/social graph — NOT_STARTED
- [ ] Competitions/events settlement — NOT_STARTED
- [ ] Auction house — NOT_STARTED

## Cross-cutting infrastructure

- [ ] Replace remaining unsafe in-process timers with durable workers — PARTIAL_SAFE
- [ ] Unified scheduled daily settlement framework — NOT_STARTED
- [ ] Cross-system lock-order audit — PARTIAL_SAFE
- [ ] Economy conservation/audit review — PARTIAL_SAFE
- [ ] Normalize remaining pseudo-JSON master data — PARTIAL_SAFE
- [ ] Legacy-player migration policy — NOT_STARTED
- [ ] Provider/hosting/TLS/pooler production config — NOT_STARTED
- [ ] Monitoring/logging/backup restore runbook completion — NOT_STARTED

## Test / release gate

All current stabilization work remains TEST_BLOCKED by project instruction until explicit authorization.

Eventually required:
- Node runtime/startup tests;
- migration replay;
- integration tests;
- rollback tests;
- idempotency replay tests;
- concurrency/race tests;
- multi-account authorization tests;
- economy conservation tests;
- Flutter analyze/build/widget tests;
- device testing;
- staging deployment;
- scheduled-worker tests;
- production configuration and rollout.

Do not deploy or run gameplay/build tests without explicit authorization.
