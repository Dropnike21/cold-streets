# Company Source Product Namespace — 2026-11-05

## Scope

This pass establishes a source-native product identity and storage foundation for
the recovered 120-company supply chain.

It deliberately does **not** map source products onto the incompatible legacy
`company_products_master` IDs and does not enable production, stock ordering,
pricing, sales, shipments, incorporation, or cash settlement.

No runtime/gameplay/build tests or deployment were performed.

## Reconciliation result

The normalized source rules contain:

- 120 distinct exact product names;
- 282 product-rule rows;
- 67 source names referenced by more than one rule;
- 0 case-fold name collisions.

Comparison with the legacy 20-row company product catalog found:

- 1 exact-name overlap;
- 119 source products with no legacy exact-name match.

The single overlap is not treated as an approved mapping. The two generations
remain separate.

## Source-native product namespace

Migration:

`20261105081444_company_source_product_namespace_20261105.sql`

creates:

`company_source_products_master`

The exact recovered product name is the identity key. No synthetic gameplay ID
or inferred legacy product ID is introduced.

The migration populates the namespace directly from the distinct normalized
`company_product_rules_master.product_name` values and adds a foreign key from
all source product rules back to that namespace.

A case-fold unique index makes future source drift fail rather than allowing two
product identities that differ only by capitalization.

Development readback:

- source products: 120;
- orphan source rules: 0.

## Source inventory storage

The same migration creates:

`company_source_inventory`

Key:

- company ID;
- exact source product name.

Stored quantities:

- total quantity;
- reserved quantity.

Database constraints require:

- nonnegative quantities;
- nonnegative reservations;
- reserved quantity cannot exceed total quantity.

The table is intentionally empty and has no enabled mutation route.

Development readback:

- source inventory rows: 0.

This storage is a neutral future target for production/escrow work. Nothing in
this pass decides how units are produced, purchased, shipped, consumed, sold, or
priced.

## Security

Both new tables:

- have RLS enabled;
- grant no direct `anon` or `authenticated` access;
- are accessed only through the server database connection when future
  authoritative consumers are implemented.

Supabase advisor review shows no new security or performance finding for either
new table.

## Audit API

The existing authenticated read-only endpoint:

`GET /companies/supply-chain-audit/:type_id`

now reports:

- source namespace readiness;
- source inventory storage readiness;
- current source inventory row count;
- source inventory mutation availability = false;
- production/stock-ordering/sales/incorporation availability = false.

Exact legacy-name overlap remains informational only.

## Still blocked

Before executable company production can open, project sources must establish:

1. recipe quantities;
2. production cadence;
3. byproduct quantity semantics;
4. Tier-2 input/output quantities;
5. supplier/contract shipment rules;
6. inventory reservation/release rules;
7. Tier-3 `clean_ratio` cash denomination and settlement formula;
8. product pricing provenance;
9. the three unresolved `Logistics Company` affiliation references.

The legacy 20-row product catalog remains isolated.

## Verification boundary

Performed:

- source/legacy catalog count reconciliation;
- development migration application/readback;
- static backend readback;
- Supabase security/performance advisor review.

Not performed by instruction:

- Node runtime/startup tests;
- production/inventory integration tests;
- concurrency tests;
- Flutter analyze/build/widget tests;
- deployment;
- production changes.
