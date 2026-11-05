# Mechanics Decisions Required — 2026-11-05

## Purpose

This is the canonical register of gameplay decisions intentionally left
unresolved after static stabilization.

Affected settlement is fail-closed until a decision is made.

Priority reflects how much existing UI/data/code depends on the decision, not
the preferred design answer.

## P0 — decisions blocking already-modeled systems

### 1. Vital regeneration

Decide authoritative:

- Energy regeneration amount and cadence;
- Nerve regeneration amount and cadence;
- HP regeneration amount and cadence;
- cap interaction with Max Energy/Max Nerve/Max HP;
- VIP Max Energy interaction;
- offline/catch-up behavior.

The old single-process timer is retired.

### 2. Recruit generation and pricing

Recruits Canvas conflicts with the legacy generator.

Decide:

- canonical tier current-stat ranges;
- canonical max-potential ranges;
- any tier focus/weighting;
- Stat Value Multiplier;
- Potential Multiplier;
- whether level gates remain;
- board size;
- refresh allowance/reset cadence;
- recruitment cooldown.

Recruit generation/hiring is paused.

### 3. Crew crime automation

Choose between/reconcile:

**Recruits Canvas**
- fixed 60-second loop;
- average target-crime payout;
- flat 1% mortality.

**crimes_master**
- per-crime automation cooldown;
- per-crime NPC casualty risk.

Also decide:

- whether tools are merely required or consumed;
- pause behavior when a required tool disappears;
- whether stat growth occurs on every nonfatal tick;
- exact event text/provenance requirements.

Assignment and payout worker are paused; recall remains active.

### 4. City Job resignation

Define:

- clean-exit Job Point retention;
- whether mastery/frozen incentives survive;
- Final Heist payout formula/currency;
- Final Heist Heat;
- City Job ban duration;
- whether heist is universally available or rank-gated.

Former 50% / rank×10,000 / 100 Heat / 30-day values were code-only and removed.

### 5. Pickpocket target issuance

Define server-owned target lifecycle:

- target instance ID;
- activity assignment;
- activity duration/expiry;
- actor binding;
- persistence/replay rules;
- success-modifier binding;
- whether target disappearance is persisted or ephemeral.

Pickpocket execution is paused.

## P1 — major economy systems

### 6. Casino

Decide per game:

- exact paytables;
- wager limits;
- Token issuance sources;
- jackpot rules;
- payout rounding;
- replay behavior.

For PvP Casino also decide:

- matchmaking;
- escrow;
- winner settlement;
- rake threshold/rate interaction.

Current Token daily spend accounting remains a foundation only.

### 7. Trade / Player Bazaar

Decide:

- settlement currency;
- listing fees/taxes;
- partial fill semantics;
- price bounds;
- expiry;
- cancellation;
- escrow reservation;
- access requirements;
- proceeds delivery/check behavior.

Preflight remains read-only.

### 8. Bank

Decide:

- time-deposit funding denomination(s);
- duration options;
- interest/rate source;
- maturity payout;
- early cancellation if any;
- bank trust effects;
- expired deferred-check fallback.

Deferred checks with complete issuer contracts can currently be claimed; deposit
creation/settlement remains paused.

### 9. Property lifecycle

Resolve competing property source families and decide:

- purchase catalog/prices;
- property bonus application;
- bonus stacking order;
- upkeep currency/cadence;
- upgrades;
- player-market currency;
- listing fee/tax;
- lease;
- gifts;
- market cancellation.

Only source-safe ownership state such as move-in remains active.

### 10. Company economy

Decide:

- incorporation currency;
- company pricing rules;
- advertising budget/effect;
- supplier/stock procurement;
- production/sales settlement;
- company Dirty -> player/company Clean laundering rule;
- laundering tax;
- payroll cadence;
- salary funding/conversion;
- bankruptcy/insolvency;
- liquidation;
- upgrades and stacking;
- NPC effectiveness weighting.

Owner Dirty Cash funding and consent-based employment/NPC position assignment
remain the safe subset.

### 11. Premium / monetization

VIP:
- exact +20% Nerve application semantic;
- remaining benefit list if any.

Kingpin:
- exact benefit set;
- relationship, if any, to VIP benefits.

Subscriber:
- monthly VIP/Kingpin pack choice vs fixed VIP Pack;
- monthly Book catalog;
- Book temporary/permanent effect semantics;
- monthly settlement cadence/catch-up;
- billing activation/cancellation/grace behavior.

Already established:
- VIP Max Energy target 200;
- source-backed Casino daily Token spend cap 150;
- Subscriber city NPC market flat +20 items/day (100 -> 120);
- premium packs may be tradable once Trade settlement exists.

### 12. Credit Broker / Cred

Decide:

- Cred earning sources;
- upgrade prices;
- exact effect consumers/stacking;
- respec/refund if any.

Catalog is read-only.

## P2 — state/combat/progression gaps

### 13. Jail

Decide:

- bail Clean Cash rate;
- Juris Doctor/bail discount interaction;
- Bust Out/Self Escape Nerve cost;
- success probability;
- outside-in vs inside-out rules;
- failure penalties;
- prison-yard gain multiplier and EXP behavior.

### 14. Heat

Decide authoritative Heat decay:

- cadence;
- amount/rate;
- state-dependent behavior;
- max/min boundary interaction.

### 15. City Job mastery actives

Eight recovered mastery rules still conflict with item/effect catalogs.

For each conflict, decide whether to:
- correct the source mapping;
- replace the reward;
- retire the active.

Two fingerprinted actives are currently executable.

### 16. Kevin contracts

Define:

- objective generation;
- eligibility;
- reward curve;
- reputation gain/loss;
- partial completion;
- abort behavior;
- repeat/cooldown rules.

Anonymous handoff to Kevin remains visible but contracts are paused.

### 17. Bounty / PvP combat

Define:

- placement currency/fee;
- target eligibility;
- escrow;
- expiry/cancel;
- attack settlement;
- bounty winner payout;
- PvP combat formulas and state outcomes.

### 18. Achievements still unsupported

Clarify:

- `cash_on_hand`: which currency/aggregation and when sampled;
- drug-use semantics before `drugs_used` is enabled;
- Casino spin definition before `casino_spins` is enabled.

## P3 — operating/release data decisions

### 19. Unique-item lifetime baseline

For an existing populated database, choose one:

- start lifetime discovery tracking from migration date;
- import a trusted historical acquisition source;
- grant a documented baseline from current inventory with an explicit semantic
  change.

Do not silently treat current inventory as true lifetime history.

### 20. Market restocking

Define:

- restock cadence;
- quantity;
- affected sources/items;
- deterministic/random selection;
- price/stock interaction;
- multi-replica ownership.

The legacy random timer is retired.

### 21. Syndicate establishment

Verify/define:

- required member count;
- required capital;
- required company/supply-chain conditions;
- whether requirements consume resources or are gates only.

Legacy Flutter values (150 members, $500M, two businesses) are removed from the
authoritative-looking UI because they were not verified in the recovered source
set.

## Decision workflow

For each item:

1. select the intended mechanic;
2. document the rule and source/version;
3. update normalized catalog/schema if necessary;
4. implement server-side settlement only;
5. add exact request/response contract;
6. add idempotency/locks/conservation invariant;
7. update Flutter to intent/presentation only;
8. run the authorized runtime/concurrency tests before enabling it.

No unresolved item in this register needs to block the static stabilization
baseline because its mutation path is already unavailable.
