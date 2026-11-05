# Economy / Resource Conservation Audit — 2026-11-05

## Scope

Final static conservation review of every currently active Cold Streets mutation
that creates, destroys, transfers, or changes an authoritative player resource.

The purpose is not to decide balance values. It is to ensure an active mutation
has a single authoritative source, exact settlement, replay protection when
needed, and no client-controlled payout/cost.

No runtime/concurrency testing was performed.

## Conservation model

Each active mutation is classified as one of:

- **source** — creates a resource from an authoritative catalog/rule;
- **sink** — destroys/spends a resource for an authoritative catalog/rule;
- **transfer** — moves value between authoritative accounts without creating it;
- **state-only** — changes ownership/state with no economic issuance;
- **read/preflight** — performs no authoritative settlement.

## Active sources

### Searching / Shoplifting crimes

Creates:

- Dirty Cash;
- Character EXP;
- Crime EXP;
- source-defined loot where reconciled.

Authority:

- authenticated actor;
- `crimes_master` catalog;
- secure RNG;
- persisted idempotency;
- one transaction.

Pickpocket is excluded and paused because target activity previously came from
the client and changed success probability.

### Anonymous tutorial verification

Creates only the reward deltas encoded by the reconciled current mission rule:

- Dirty Cash;
- Clean Cash;
- Energy;
- Nerve;
- Anonymous reputation.

The player, mission progress and idempotency state are settled transactionally.

### City Job daily settlement

Creates:

- Clean Cash;
- Job Incentives.

The amount comes from the authenticated player's current job/rank catalog, not
the client. Daily eligibility is persisted and replay-safe.

### Reconciled City Job mastery actives

Only source/catalog-fingerprinted mastery actives execute.

They consume Job Incentives and grant the exact reconciled reward/effect.
Unreconciled mastery actives remain 503.

### Deferred payout/check claim

Creates Dirty or Clean Cash only from a persisted `pending_checks` issuer
contract containing:

- issuer_type;
- source_ref;
- payout_currency;
- positive exact amount.

Claim is actor-owned, row-locked, idempotent and atomically marked claimed.

## Active sinks

### City NPC Market

Consumes:

- player Dirty Cash;
- catalog stock.

Creates:

- exact purchased inventory quantity;
- purchase-ledger rows;
- unique-item discovery telemetry where applicable.

Prices and source identity come from `items_master`. The client submits only
item IDs and quantities. Stock, wallet, daily limit and inventory settle in one
transaction.

### Gym purchase

Consumes server catalog Dirty Cash unlock cost and grants membership.

### Gym training

Consumes Energy and creates:

- battle-stat growth;
- Character EXP;
- Gym EXP;
- achievement/tutorial progress.

The stat-growth formula is server-owned. The client chooses only stat, Energy
amount and active Gym identity; ownership and active Gym are revalidated.

### Info Broker classified ad

Consumes the server-defined Clean Cash ad cost and creates a persisted ad.

### University enrollment

Consumes the course's server catalog Dirty Cash cost and persists enrollment.

### Character level-up

Consumes server-calculated EXP and increments level/max HP.

### City Job promotion

Consumes catalog Job Incentives and advances rank.

### Inventory consumables

Consumes one owned inventory item and applies only explicitly reconciled
server-parsed effects. Unsupported effect shapes fail closed.

### Hospital revive

Consumes the authoritative revive resource/cost and changes target hospital
state under row locks/idempotency.

## Active transfers

### Player -> company funding

The only active company cash movement is:

`player Dirty Cash -> company Dirty Cash`

The client cannot select denomination or direction.

The debit and company credit occur in the same transaction with an immutable
company cash ledger entry and persistent idempotency.

No Clean Cash conversion or laundering occurs in this action.

## Active state-only / monotonic mutations

Examples:

- inventory equip;
- property move-in;
- event mark-read;
- tutorial navigation observation;
- company profile;
- company application/offer lifecycle;
- NPC company assignment/recall;
- University dropout/graduation entitlement state;
- Syndicate crew recall.

These do not mint an economic reward by retrying.

Replay-sensitive state changes retain persistent idempotency where appropriate.

## Read/preflight-only POST surfaces

Examples:

- company incorporation preflight;
- Trade listing preflight.

They validate ownership/catalog compatibility without settling cash or assets.

## Economy paths intentionally paused by this closeout

### City Job resignation

The recovered City Job sheet/GDD do not define:

- clean-exit Job Point retention;
- Final Heist payout;
- Final Heist Heat;
- Final Heist employment ban.

The former 50%, rank × 10,000, 100 Heat and 30-day values were code-only.
Settlement is now 503.

### Recruit generation / hiring

Recruits Canvas defines different stat ranges from the legacy generator and
describes a dynamic price formula without defining its multipliers.

No recruit can currently be generated or purchased.

### Crew crime automation

Recruits Canvas says:

- fixed 60-second loop;
- mathematical average crime payout;
- flat 1% mortality.

The recovered crime catalog contains per-crime automation cooldown and casualty
risk values.

Because these source families conflict, assignment and the payout worker are
paused. Existing assignments can still be recalled.

### Other previously paused economy surfaces

Remain closed:

- Casino game wagers/payouts;
- Trade listing/fill/cancel settlement;
- bounty/PvP escrow settlement;
- Bank time-deposit creation/claim semantics;
- property purchase/upgrades/market/lease/gift/upkeep;
- company sales/pricing/advertising/stock/payroll/laundering/upgrades;
- premium purchase/consume/subscription/monthly grants;
- Credit Broker purchase;
- Jail bail/breakout/yard settlement;
- Kevin contracts.

## Exact-value conclusion

Active money, Job Point, inventory quantity and similar economic settlement uses
integer/NUMERIC parsing rather than JavaScript floating-point arithmetic.

No active endpoint accepts client reward IDs, payout amounts, catalog prices or
economic actor IDs.

The current active static economy therefore has no known retry/client-input path
that can mint or destroy cash/items outside its documented source/sink/transfer
contract.

This conclusion is static and must still be validated under authorized
concurrency/runtime tests.
