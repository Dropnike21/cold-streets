# Company Incorporation Preflight — 2026-11-05

## Scope

This pass advances incorporation only to a server-authoritative **read-only
preflight**.

It does **not** debit a player, create a company, create a Director row, or seed
inventory.

## Why incorporation remains fail-closed

Recovered sources disagree on setup-cost denomination:

- GDD Master: **Clean Cash** is used to buy legitimate businesses.
- Legacy backend implementation: incorporation debited **Dirty Cash**.

The recovered 120-row company sheet supplies exact `setup_cost` values but does
not identify the setup currency.

Because choosing either wallet would silently resolve a source conflict, the
mutation remains unavailable.

## Catalog state

The development catalog contains:

- 120 company types;
- no negative setup costs;
- no fractional setup costs;
- setup-cost range: 250,000 through 50,000,000.

PR #37 already established the separate 120-product source namespace and empty
source inventory storage, so the former legacy-product identity blocker is no
longer the immediate incorporation blocker.

## Preflight API

`POST /companies/incorporation-preflight`

Client may supply only:

- company type ID;
- proposed company name.

The authenticated actor is derived from the verified session.

The endpoint returns:

- exact source setup cost;
- industry and tier;
- current Clean Cash and Dirty Cash balances;
- whether each wallet would be sufficient **if** that currency were selected;
- source position/product-rule counts;
- unresolved affiliation count;
- current City Job ID and existing real-player company roles;
- explicit source-product namespace/storage readiness;
- explicit `mutation_available: false`.

It never selects a currency, reserves funds, or creates gameplay state.

## Incorporation mutation

`POST /companies/incorporate`

continues to return 503.

The blocker message now reflects the actual remaining issue: setup-cost currency
conflict rather than the already-separated legacy product catalog.

## Verification boundary

Performed:

- GDD / legacy-code reconciliation;
- development catalog readback;
- static backend readback.

Not performed by instruction:

- runtime/gameplay tests;
- incorporation transaction tests;
- Flutter analyze/build/widget tests;
- deployment;
- production changes.
