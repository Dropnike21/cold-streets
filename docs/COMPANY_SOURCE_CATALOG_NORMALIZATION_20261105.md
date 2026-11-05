# Company Source Catalog Normalization — 2026-11-05

## Scope

This pass reconstructs the source-backed company position, special, product-rule,
affiliation and upgrade catalogs from the recovered Google Sheet tab:

`company&position_master`

It deliberately does not force the recovered 120-company supply-chain generation
into the older 20-row `company_products_master` generation.

No gameplay/build/runtime tests or deployment were performed.

## Recovered source shape

The sheet contains exactly:

- 120 company types;
- 40 Tier 1;
- 40 Tier 2;
- 40 Tier 3.

All 120 rows have valid JSON for:

- `positions_json`;
- `specials_json`;
- `affiliations_json`;
- `upgrades_json`;
- `products_json`.

### Positions

Recovered:

- 179 position definitions;
- 61 company types with one source role;
- 59 company types with two source roles.

Every position uses the same exact fields:

- `req_stat_1`;
- `req_stat_2`;
- `req_amount_1`;
- `req_amount_2`;
- `gain_1`;
- `gain_2`.

Only the four Working Stats appear:

- `acu`;
- `ops`;
- `pre`;
- `res`.

Recovered thresholds range up to 15,000.
Recovered gain values range up to 150.

Migration:

`20261105004500_company_positions_specials_normalization_20261105.sql`

adds source-normalized columns to `company_positions_master`:

- `role_key`;
- primary/secondary requirement amounts;
- primary/secondary gain values;
- exact source JSON.

All 179 rows are populated.

The generated `position_id` values are deterministic surrogate identifiers only.
They are not treated as gameplay meaning.

### Specials

Recovered:

- 122 special descriptions;
- 118 company types with one special;
- 2 company types with two specials.

Source star keys are only:

- `1_star` — 98 rows;
- `5_star` — 24 rows.

Every special contains only:

- `name`;
- `desc`.

The source does not provide a universal machine effect schema.

Therefore specials are normalized as:

`semantics_status = source_description_only`

and do not receive invented:

- Job Point costs;
- passive/active classification;
- duration semantics;
- stacking rules;
- effect consumers.

`is_passive` is made nullable so the database does not falsely assert
`false` when the source does not establish the classification.

## Product source generation

The recovered company sheet does not match the existing normalized
`company_products_master` table.

Existing normalized legacy product table:

- 20 products.

Recovered company supply-chain source:

- 80 distinct Tier-1 product names alone;
- 40 Tier-2 processed-output definitions;
- 88 Tier-3 sale-input rows.

The source uses three exact product JSON generations:

### Tier 1

All 40:

`{ main, by_products }`

### Tier 2

All 40:

`{ requires, output }`

### Tier 3

All 40:

`{ sales: [{ input, clean_ratio }, ...] }`

Because the two product generations materially differ, this pass creates a
parallel source-normalized relation table instead of rewriting the old 20-row
catalog.

Migration:

`20261105005000_company_supply_chain_source_normalization_20261105.sql`

creates `company_product_rules_master`.

Recovered rows:

- 282 product-rule rows;
- 88 Tier-3 sale-input rows.

Relation types:

- `tier1_main_output`;
- `tier1_byproduct`;
- `tier2_required_input`;
- `tier2_processed_output`;
- `tier3_sale_input`.

Tier-3 `clean_ratio` is preserved numerically, but:

`semantics_status = source_catalog_only`

No Clean Cash settlement uses it yet.

## Affiliations / supply-chain graph

The same migration creates:

`company_affiliations_master`

Recovered:

- 425 source affiliation entries.

The source arrays are preserved by ordinal rather than deduplicated.

This matters because type 47 contains a duplicate `Hardware Plant` input entry.
The duplicate is retained as source data rather than silently erased.

### Unresolved name conflict

422 affiliation rows resolve exactly to a company type.

Three do not.

Types:

- 49;
- 53;
- 68

each reference:

`Logistics Company`

while the recovered company type catalog contains:

`Logistics Co` — type 91.

This pass does **not** silently equate those names.

Those three rows are stored with:

`resolution_status = unresolved_name_conflict`

and no `related_type_id`.

## Company upgrades

The sheet contains exactly one upgrade definition for every company type:

- 120 upgrades.

Every upgrade has source-backed:

- upgrade key;
- cost;
- upkeep;
- one bonus field/value.

Recovered bonus-key families:

- `bonus` — 89;
- `yield_bonus` — 14;
- `quality_bonus` — 5;
- `speed_bonus` — 4;
- `output_bonus` — 2;
- `stealth_bonus` — 1;
- `waste_reduction` — 1;
- `potency_bonus` — 1;
- `safety_bonus` — 1;
- `sales_bonus` — 1;
- `hack_resist` — 1.

The migration creates:

`company_upgrades_master`

with exact source-backed:

- cost;
- upkeep increase;
- bonus key;
- bonus value;
- source JSON.

Every row is marked:

`semantics_status = source_value_unreconciled`.

Therefore cost/upkeep can be displayed as source data, but purchasing remains
paused until the effect meaning, stacking and settlement semantics are explicit.

## Backend read model

Company blueprint responses now expose:

- normalized position count;
- normalized special count;
- source product-rule count;
- unresolved affiliation count;
- normalized upgrade cost/upkeep/bonus source values;
- explicit incorporation blocker.

Company dashboards now expose:

- exact normalized position requirements/gains;
- source special descriptions and semantics status;
- source product rules;
- supply-chain affiliations and resolution state;
- source upgrade definition;
- existing financial cash-flow status.

Cash-flow blockers now distinguish:

- product-generation conflict;
- Tier-3 clean-ratio semantics unresolved.

## Incorporation remains paused

This pass does not reopen incorporation.

Reason:

The recovered 120-company supply-chain source is internally rich, but the
existing company inventory/shipment implementation still points at the
incompatible legacy 20-row `company_products_master` catalog.

Creating a paid company before choosing the canonical product generation could
create an enterprise whose source products cannot be represented by its runtime
inventory tables.

No setup cost is charged.

## Pricing remains paused

`POST /company-management/update-pricing` now joins the existing paused
management boundary.

Product pricing cannot be authoritative while company inventory still uses the
conflicting legacy product generation.

## Employee management remains paused

Position requirements are now recovered, but the source still does not fully
define:

- salary negotiation/acceptance;
- firing settlement;
- training settlement;
- NPC assignment/efficiency;
- role-weight classification;
- contract consent.

No generic role assignment is enabled merely because role thresholds exist.

## Flutter companion

Draft PR #5 now:

- displays normalized position primary/secondary stat requirements;
- displays exact source Working Stat gain values;
- removes active employee Save/Train/Fire controls;
- keeps applicants visible;
- disables product pricing;
- shows normalized company upgrade cost/upkeep and raw bonus key/value;
- clearly labels upgrade purchase as paused;
- continues to keep stock ordering and other unresolved company mutations paused.

## Verification boundary

Performed:

- full 120-row native Google Sheet parse;
- JSON structure validation;
- source row counts;
- migration application/readback;
- unresolved affiliation readback;
- backend static readback;
- Flutter static readback;
- Supabase security/performance advisor review.

Current development counts:

- positions: 179;
- specials: 122;
- product rules: 282;
- affiliations: 425;
- unresolved affiliations: 3;
- upgrades: 120;
- Tier-3 sale-input rows: 88.

Not performed by instruction:

- Node runtime tests;
- company gameplay tests;
- settlement tests;
- concurrency tests;
- Flutter analyze/build/widget tests;
- deployment;
- production changes.
