# Company Supply-Chain Compatibility Audit — 2026-11-05

## Boundary
This change adds an authenticated, read-only catalog reconciliation endpoint:

`GET /companies/supply-chain-audit/:type_id`

It is mounted behind the existing gameplay feature flag, verified-player middleware, and free-player state gate. It does not create, debit, credit, reserve, price, or transfer any product or currency.

## Verified current schema
- `company_product_rules_master` contains source-native product names and source relation types.
- `company_products_master` contains legacy runtime `product_id` identities.
- `company_inventory.product_id` refers to the legacy runtime identity.

Consequently, a source recipe cannot safely mutate runtime company inventory merely by assuming the product name maps to a legacy ID.

## Response
For one recovered company type, return:
- source company identity and tier;
- each source product rule, including relation type and unmodified source Clean Ratio;
- zero, one or multiple **exact legacy name matches**, if any;
- number of source rules without exact legacy names;
- number of rules with multiple exact legacy names;
- source affiliations and their exact/unresolved resolution flags;
- global source-rule/unique-name and legacy catalog counts;
- explicit false flags for incorporation, production, stock ordering and sales settlement.

Exact-name overlap is *informational only*. It is not an approved mapping, and it cannot be used as an inventory foreign key, recipe input, product value, price, payout or production authorization.

The read model preserves conflicting records and does not silently merge `Logistics Company` into `Logistics Co`.

## Next canonical decisions required
1. Choose a canonical runtime product identity model and migration of legacy product references.
2. Define authoritative quantities and timing for Tier-1 output/byproducts and Tier-2 input/output.
3. Define Tier-3 `clean_ratio` currency and gross/net/tax settlement rules.
4. Resolve three company-affiliation name conflicts from the recovered catalog.
5. Define inventory reservations, supplier obligations, shipment settlement, price provenance, and immutable accounting.

Until these are supported by primary project sources, leave incorporation and all product/finance settlement paths disabled.

## Testing / release
This is a source/static implementation only. No runtime, gameplay, concurrency, build, or Flutter tests; no staging or production deployment; no database migration.
