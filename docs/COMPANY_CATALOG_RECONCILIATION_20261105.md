# Company Catalog Reconciliation — source conflict (2026-11-05)

This review uses the connected Google Sheet **Cold streets database**, tab **company&position_master**, and the recovered PostgreSQL catalog already loaded into the isolated Supabase development database.

## What the spreadsheet actually contains

The tab has **120 company types**. Its JSON columns parse cleanly for every row:

- `positions_json`: **179 position definitions** in total.
- `specials_json`: **122 special definitions** in total.
- `products_json` has exactly three shapes:
  - 40 rows: `main` + `by_products`
  - 40 rows: `requires` + `output`
  - 40 rows: `sales`

These structures describe a detailed production chain using product names such as `Iron Ore`, `Industrial Steel`, `Circuit Boards`, `Building Modules`, `Aged Wine`, and many others.

## Conflict with recovered PostgreSQL catalog

The recovered `company_products_master` table contains only **20** product rows:

`Raw Crops`, `Raw Minerals`, `Crude Oil`, `Raw Meat`, `Raw Timber`, `Precursor Chemicals`, `Scrap Metal`, `Smuggled Hardware`, `Raw Cotton/Silk`, `Cocoa Leaves`, `Cartel Narcotics`, `Cleaned Diamonds`, `Petrochemicals`, `Bootleg Alcohol`, `Counterfeit Documents`, `Prescription Pills`, `Clean Auto Parts`, `Hacking Botnets`, `Designer Knockoffs`, `Untraceable Firearms`.

Across the **120 distinct string product values** found inside the spreadsheet's `products_json`, only **one exact name matches** that recovered 20-product table: `Crude Oil`. The other **119** do not have an exact recovered product row.

Therefore **`blueprint_products` cannot be reconstructed safely by name matching**. Doing so would require inventing a lossy mapping between two materially different economy catalogs.

## Position / special normalization is also incomplete

The spreadsheet positions contain requirement amounts and gain amounts in addition to stat names (for example `req_amount_1`, `req_amount_2`, `gain_1`, `gain_2`). The currently reconstructed `company_positions_master` table does not have columns for all of these source fields. Filling only the existing columns would silently discard gameplay rules.

The spreadsheet specials contain star keys plus `name` and `desc`. Some descriptions embed gameplay semantics such as passive effects or JP exchange costs, but the reconstructed `company_specials_master` schema splits these into separate fields that are not explicitly present for every source row. Those semantics need a deliberate normalization design rather than inference.

## Current safe behavior

- Company incorporation returns 503 when the selected type has no restored `blueprint_products` mapping.
- Company supplier orders return 503 when the requested input is not backed by a restored blueprint relationship.
- Company position/special-dependent features remain unavailable or display-incomplete rather than fabricated.

## Required design decision

Choose one canonical company-economy model before importing these normalized tables:

1. **Detailed 120-product-chain model** from the spreadsheet, which requires a new/expanded product catalog and normalized schemas for positions, specials, production recipes and sales; or
2. **Recovered 20-product model** from PostgreSQL, which requires authoritative relationship data for those 20 products that is not present in the spreadsheet.

Do not auto-map the two catalogs by similarity. Preserve their source IDs/names until a canonical migration is explicitly designed.
