# Company Laundering & Cash-Flow Reconciliation — 2026-11-05

## Scope

This pass reconciles company vault funding, laundering, payroll conversion, Tier-3 sales revenue, advertising spend, bankruptcy/runway, and financial auditing against:

- the archived Cold Streets GDD;
- the Player-Owned Companies & Enterprise Canvas;
- the recovered `company&position_master` spreadsheet tab;
- current and historical Node/Express company code;
- the reconstructed development PostgreSQL schema.

No runtime/gameplay/build tests or deployment were performed.

## High-level result

The only active company money movement retained by this pass is:

**authenticated owner Dirty Cash -> the same active company's Dirty Cash bank**

That operation is denomination-preserving. It does not itself create Clean Cash.

Everything that converts, spends, distributes, withdraws, or manufactures company value remains paused until its formula and settlement timing are source-backed.

## Source-backed economy model

### GDD

The archived GDD establishes:

- crimes generate Dirty Cash;
- legitimate activity and laundered money generate Clean Cash;
- businesses are laundering fronts;
- players deposit Dirty Cash into businesses;
- Dirty Cash converts to Clean Cash over time;
- conversion applies a "Laundering Tax";
- higher Acumen (ACU) reduces that tax.

The GDD does **not** provide:

- base laundering tax percentage;
- ACU reduction formula;
- minimum/maximum tax;
- conversion capacity;
- exact settlement cadence;
- which company types are eligible;
- whether conversion happens independently of product sales/payroll.

Therefore no generic Dirty -> Clean conversion formula is implemented.

### Player-Owned Companies Canvas

The company canvas adds these explicit cash-flow statements:

- the owner deposits Dirty Cash into the Company Bank;
- real players require negotiated Clean Cash salaries;
- on the automated daily loop, salaries are deducted from company Dirty Cash and paid to employees as Clean Cash;
- Distribution companies sell units to the global market;
- Distribution sales revenue is deposited as Clean Cash;
- bankruptcy runway is:
  `(Dirty Cash + Clean Cash) / (Daily Salaries + Upkeep)`;
- if runway reaches 2.0 days, the company declares bankruptcy;
- remaining cash is distributed to employees as severance and the company becomes inactive.

These statements establish the shape of the system, but do not provide enough information to settle payroll, sales, or bankruptcy safely.

Unresolved items include negotiated-salary acceptance, exact daily boundary/time zone, unit-volume formulas, effectiveness weighting, sale pricing, severance distribution formula, mixed-currency severance denomination, and interactions between the GDD laundering tax and payroll/sales conversion.

## Recovered company spreadsheet

The `company&position_master` worksheet contains exactly 120 company types:

- 40 Tier-1 Production companies;
- 40 Tier-2 Processing companies;
- 40 Tier-3 Distribution companies.

All 40 Tier-3 rows contain legacy `products_json` text with one or more `clean_ratio` values.

No Tier-1 or Tier-2 row contains `clean_ratio`.

Six Tier-3 rows contain laundering-themed special descriptions:

- type 81 — Boutique Jewelry — `Swiss Accounts: Launder $500k Dirty Cash`;
- type 82 — Nuclear Power Grid — `Energy Laundering: Clean 10% of total revenue automatically`;
- type 86 — Front Pharmacy — `Cook the Books: Exchange 25 JP to launder $100k Dirty Cash`;
- type 88 — Nightclub — `VIP: Doubles launder for 24h`;
- type 95 — Real Estate Agency — `Money: Double launder speed`;
- type 100 — Dispensary — `Rush: Launder +25% for 12h`.

These remain legacy text fields in `company_types_master`.

They are **not** interpreted generically because:

- `company_specials_master` currently contains 0 normalized rows;
- `blueprint_products` currently contains 0 normalized rows;
- `company_positions_master` currently contains 0 normalized rows;
- the special descriptions do not define common machine semantics;
- several use Job Points, durations, rates, or speed effects whose interaction rules are not normalized.

The GDD uses Car Wash as an example laundering front, but no Car Wash exists in the recovered 120-row company catalog. Nightclub does exist as type 88.

## Current development data

At reconciliation time:

- company types: 120;
- company products: 20;
- normalized company positions: 0;
- normalized company specials: 0;
- blueprint-product links: 0;
- player companies: 0;
- company employees: 0;
- company inventory rows: 0;
- company shipments: 0;
- company cash-ledger rows: 0.

Therefore no development-player company balances or liabilities required migration.

## Historical corporate tick

Git history contains an April 2026 corporate tick implementation.

That implementation:

- ran on a one-hour testing interval with a comment to later use 24 hours;
- simulated random system customers;
- used a hardcoded 10% "Legitimacy Tax";
- directly credited simulated sales into company Clean Cash;
- deactivated companies at zero funds rather than implementing the 2.0-day design threshold.

The commit message described this as a laundering/sales implementation.

This is useful implementation history, but it conflicts with or under-specifies the design sources:

- the GDD never specifies a 10% laundering tax;
- the GDD says ACU reduces laundering tax, which the historical tick did not implement;
- the company canvas defines a 2.0-day bankruptcy threshold, while the code used zero funds;
- testing cadence comments explicitly show the tick timing was temporary;
- the historical random-customer simulation is not present in the normalized product/supply model.

No part of that historical tick is restored as authoritative settlement behavior.

The current server has no active corporate tick.

## Enabled operation: owner Dirty Cash funding

`POST /company-management/funds` is now narrowed to one source-backed operation:

- actor identity comes from authentication;
- actor must be current owner and Director;
- company must be active;
- `action_type` must be `deposit`;
- `currency_type` must be `dirty`;
- amount must be an exact positive integer;
- player row locks before company row;
- persistent idempotency is required;
- player Dirty Cash is conditionally debited;
- company `bank_dirty` is credited in the same PostgreSQL transaction;
- denomination is unchanged;
- no Clean Cash is created;
- no tax is calculated;
- no laundering timer starts;
- the transfer is written to the structured company cash ledger.

Recognized but paused:

- owner Clean Cash funding;
- Dirty Cash withdrawal;
- Clean Cash withdrawal.

The endpoint returns 503 for those operations.

This is intentionally conservative: the source clearly authorizes Dirty Cash funding, but does not define arbitrary owner withdrawal semantics or Clean Cash funding.

## Structured company cash ledger

Migration:

`20261105001000_company_cashflow_integrity_20261105.sql`

creates `company_cash_ledger`.

Each entry records:

- company;
- actor user when applicable;
- event type;
- exact Dirty Cash delta;
- exact Clean Cash delta;
- Dirty balance after the event;
- Clean balance after the event;
- optional immutable source reference;
- JSON metadata;
- timestamp.

Current event:

`OWNER_DIRTY_DEPOSIT`

The request idempotency key is stored as `source_ref`.

A partial unique index on:

`(company_id, event_type, source_ref)`

prevents duplicate recording for the same referenced event.

The table enforces:

- nonempty event type;
- integer Dirty/Clean deltas;
- at least one nonzero delta;
- nonnegative integer post-event balances;
- nonempty source reference when present;
- JSON-object metadata.

RLS is enabled and direct `anon` / `authenticated` table access is revoked. The ledger is intended for server-side financial authority, not direct client mutation.

The same migration also confirms structural company-money invariants:

- `player_companies.daily_income` nonnegative integer;
- company type tier is 1–3;
- company setup cost is nonnegative integer;
- company daily upkeep is nonnegative integer.

Existing earlier constraints already enforce integer/nonnegative company Dirty/Clean vault balances, advertising budget, salaries, inventory quantities/prices, and shipment costs.

## Payroll laundering

The Player-Owned Companies Canvas explicitly says:

**Daily Salaries are deducted from Dirty Cash and paid to employees as Clean Cash.**

This is not enabled yet.

Reasons:

1. company salary-contract editing is already paused;
2. accepted applicants enter as `Unassigned` with salary 0;
3. normalized positions are empty;
4. the source says player salaries are negotiated, but no acceptance/contract lifecycle is recovered;
5. exact daily settlement boundary is not specified;
6. the interaction between salary conversion and the GDD laundering tax/ACU reduction is ambiguous;
7. insufficient-funds behavior before bankruptcy is not explicit.

No payroll worker is invented.

## Tier-3 sales

The recovered spreadsheet strongly supports the concept that Tier-3 Distribution companies turn product units into Clean Cash.

Every Tier-3 company has legacy `clean_ratio` data.

However sales settlement remains paused because:

- `blueprint_products` is empty;
- normalized company inventory cannot yet be seeded authoritatively;
- `clean_ratio` is embedded in legacy text rather than normalized rules;
- volume/effectiveness formulas are incomplete;
- contract-linked vs system-market sale rules are unresolved;
- the historical random-customer/10%-tax implementation conflicts with the newer supply-chain design.

Stored `daily_income` is displayed only as recorded/reference data.

No client fallback income is fabricated.

## ACU and laundering tax

The canonical qualitative rule is retained:

**higher ACU lowers laundering tax.**

No numeric effect is active.

The project does not currently establish:

- whether owner ACU, Director ACU, weighted employee ACU, or company effectiveness is used;
- the base tax rate;
- the ACU scaling curve;
- tax floor/cap;
- whether special perks modify rate, capacity, or speed;
- ordering relative to Tier-3 `clean_ratio` sales.

A formula will not be invented.

## Advertising

The legacy client exposed:

- daily Dirty Cash advertising budget;
- 40% maximum effectiveness;
- competition-based decay/diminishing returns.

The current backend only stored the budget; no authoritative daily deduction/effect worker was active.

`POST /company-management/update-advertising` is now intercepted by the paused-management boundary and returns 503.

Flutter shows only the recorded budget and states that advertising settlement is paused.

## Bankruptcy / runway

The source-backed runway formula is retained read-only:

`(bank_dirty + bank_clean) / (daily salaries + daily upkeep)`

The backend now calculates the displayed one-decimal runway using exact integer arithmetic rather than JavaScript floating point.

This is a **reference only**.

Automatic bankruptcy remains paused because the settlement consequences are incomplete:

- the company canvas says shutdown at 2.0 days;
- historical code instead shut down only at zero funds;
- severance distribution is unspecified;
- mixed Dirty/Clean vault denomination is unresolved;
- salary settlement itself is paused;
- exact settlement cadence is unresolved.

Flutter labels the value `RUNWAY REFERENCE ONLY` and explicitly states that automatic bankruptcy/severance settlement is paused.

## Legacy cash-flow assumptions removed from Flutter

The Flutter companion branch now removes or disables several unsupported economy claims:

### Funds

- removes Clean Cash funding selector;
- removes all withdrawal controls;
- only allows source-backed Dirty Cash owner funding;
- states clearly that funding does not itself launder money.

### Advertising

- removes active budget editing;
- removes the claimed 40% competitive-effect formula as executable behavior;
- displays recorded budget reference only.

### Stock

- removes the hardcoded +20% system-price claim;
- disables stock ordering;
- labels supplier/contract/markup/delivery rules unresolved.

### Upgrades

- removes client-calculated upgrade purchase prices;
- disables upgrade purchasing;
- states that legacy text definitions are not an authoritative normalized catalog.

### Liquidation

- removes the legacy claims of:
  - 75% setup-cost refund;
  - 75% upgrade refund;
  - 5% lifetime revenue;
  - automatic 100% vault return.
- displays liquidation as paused.

### Dashboard

- removes fabricated fallback daily/weekly income and customer values;
- marks stored income as recorded only;
- exposes sales/payroll settlement status;
- replaces the old bankruptcy-warning implication with reference-only runway;
- replaces the placeholder revenue chart with a cash-flow reconciliation notice.

The management client also stops sending a request-body `user_id` for company mutations; authenticated actor identity remains server authority.

## Still unresolved

Before broader company cash flow can reopen, the project needs canonical rules for:

1. laundering eligibility by company type;
2. base laundering tax;
3. ACU tax-reduction formula;
4. laundering capacity;
5. laundering cadence and settlement boundary;
6. salary negotiation/acceptance;
7. payroll settlement and insufficient-funds handling;
8. normalized company positions;
9. normalized company specials;
10. normalized product/blueprint links;
11. Tier-3 sales volume;
12. Tier-3 `clean_ratio` semantics;
13. supply-contract settlement;
14. system-market settlement;
15. advertising cost/effect;
16. upgrade pricing/effects;
17. bankruptcy timing;
18. severance distribution;
19. company withdrawal rules;
20. liquidation/refund rules.

## Verification boundary

Performed:

- GDD laundering/economy source review;
- Player-Owned Companies Canvas review;
- exact company spreadsheet inspection;
- historical corporate-tick review;
- current backend/client static review;
- development schema/data inspection;
- development migration application/readback;
- RLS confirmation for company cash ledger;
- Supabase security/performance advisor review.

Not performed by instruction:

- Node runtime tests;
- gameplay tests;
- payroll/laundering settlement tests;
- concurrency tests;
- Flutter analyze/build/widget tests;
- deployment;
- production changes.
