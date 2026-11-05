# Property Ownership Lifecycle Reconciliation — 2026-11-05

## Scope

This pass reconciles the Real Estate / property ownership lifecycle against:

- the original Assets & Lifestyle Canvas;
- the recovered `properties_master` Google Sheet;
- the current Node/Express implementation;
- the reconstructed development PostgreSQL schema;
- the current Flutter Real Estate and My Properties screens.

No runtime/gameplay/build tests or production deployment were performed.

## Source conflict: two property catalogs

The property system has a material source conflict and must not silently treat either source as canonical.

### Older Assets & Lifestyle design

The original Assets Canvas defines seven housing tiers:

1. Cardboard Box — $0 — +0% Gym
2. Rented Trailer — $15,000 — +1% Gym
3. Grimy Apartment — $75,000 — +2% Gym
4. Suburban Home — $500,000 — +4% Gym
5. Luxury Penthouse — $5,000,000 — +6% Gym
6. Fortified Mansion — $25,000,000 — +8% Gym
7. Private Island — $150,000,000 — +10% Gym (MAX)

It also states:

- property bonuses are passive Gym multipliers;
- the property Gym bonus is hard-capped at +10%;
- properties require upkeep;
- upkeep scales with upgrades;
- failing to pay upkeep for 7 consecutive days permanently strips all property upgrades.

### Recovered spreadsheet catalog

The recovered `properties_master` worksheet contains 25 tiers.

Examples:

- Cardboard Box — $0
- Sleeping Bag in an Alley — $50
- Pop-up Tent — $200
- Trailer — $5,000
- Suburb House — $150,000
- Luxury Apartment — $1,000,000
- Penthouse Suite — $5,000,000
- Beachfront Mansion — $100,000,000
- Private Island — $2,500,000,000

The worksheet uses:

- `upkeep_type = daily_cash`;
- explicit base `upkeep_val`;
- `hp_bonus`;
- `gym_bonus`;
- per-property `available_upgrades_json`;
- per-upgrade `cost`;
- per-upgrade `upkeep_increase`;
- optional upgrade `capacity`, `hp_bonus`, `gym_bonus`, and `unlocks`.

Its property `gym_bonus` rises as high as 0.35, which directly conflicts with the older +10% hard cap.

The current development database matches the 25-row spreadsheet with fingerprint:

`88ebc5b22740eec9063f344154f56fea`

This fingerprint is a drift detector for the recovered spreadsheet state. It does **not** declare the spreadsheet to be the final gameplay authority.

## Shared safe fact: starter property

Both property source families agree on:

- Cardboard Box;
- zero acquisition cost.

Account creation already grants property type 1 exactly once.

This remains enabled.

The registration transaction now records that grant in `property_transactions` as:

- seller: NULL (system/agency, not a player);
- buyer: created player;
- transaction type: `STARTER_GRANT`;
- amount: 0.

## Agency purchase status

The main GDD states that Clean Cash is used to buy high-end properties.

The current backend also used Clean Cash and the `properties_master.cost` value.

However, the two property catalogs disagree materially on both available properties and prices.

Therefore non-starter agency purchases are now **fail-closed**.

`POST /real-estate/buy-agency` returns 503 and spends nothing until the catalog conflict is resolved.

The recovered spreadsheet catalog remains visible as reference data, but every row reports:

`ownership_purchase_available: false`

## Property upgrades

The old Flutter My Properties screen contained a separate hardcoded upgrade list such as:

- Burner Phone Farm;
- Advanced Locks;
- Lobbying Office;
- Police Scanner;
- Panic Room;
- Syndicate Command;
- Chief on Payroll;
- custom vaults and airstrips.

That list does not match the recovered spreadsheet's per-property upgrade catalog.

The hardcoded client catalog has been removed.

The backend now strictly parses the recovered `available_upgrades_json` and exposes those definitions read-only.

Upgrade purchases remain paused because:

1. the older and spreadsheet property bonus models conflict;
2. installed upgrade effects are not consumed authoritatively by the gameplay systems;
3. upgrade `upkeep_increase` is not yet collected;
4. bonus stacking/order with Gym, University, Syndicate and other perks is unresolved.

`POST /real-estate/upgrade` therefore returns 503 and spends nothing.

## Upkeep

The source supports these facts:

- upkeep exists;
- spreadsheet base upkeep is daily;
- upgrade definitions can add upkeep;
- 7 consecutive missed days strip installed upgrades.

The backend can therefore safely expose a **reference calculation**:

`base upkeep + installed upgrade upkeep_increase`

It does not yet charge it.

Unresolved mechanics include:

- whether `daily_cash` means Clean Cash, Dirty Cash, or another balance;
- manual payment vs automatic debit;
- exact daily settlement boundary/time zone;
- whether missed days accrue while a property is idle;
- how a restored payment resets the missed-day count;
- whether the 7-day strip occurs at the seventh missed settlement or after seven full overdue days.

No upkeep ledger/timer is invented.

`POST /real-estate/upkeep/pay` returns 503.

## Property bonuses

The backend and Flutter client now label HP/Gym values as **source values**, not active bonuses.

This avoids implying that:

- `hp_bonus` is definitely flat HP vs percentage HP;
- spreadsheet Gym values override the older +10% cap;
- installed upgrade bonuses currently affect gameplay.

Move-in remains an ownership-state action only.

`POST /real-estate/move-in` remains enabled because its semantics are unambiguous:

- authenticated owner only;
- deterministic user lock;
- persistent idempotency;
- owned property lock;
- one active residence.

The response explicitly marks bonus application as unresolved.

## Sale / player market

The physical schema already contains:

- `property_market`;
- `property_transactions`.

At reconciliation time the development database contains:

- 25 property catalog rows;
- 0 owned property rows;
- 0 property market rows;
- 0 property transaction rows;
- 0 legacy `user_properties` ownership rows.

The Project Master identifies sale listing and P2P settlement as unfinished.

Recovered sources do not unambiguously specify:

- player-market settlement currency;
- listing fee or transaction tax;
- sale cancellation rules;
- sale expiry;
- whether upgrades affect asking-price restrictions;
- whether the active residence must be vacated before listing;
- seller proceeds timing.

The market is therefore read-only.

`GET /real-estate/market` returns any recovered rows with:

- `purchase_available: false`;
- `lease_available: false`.

Fail-closed mutation boundaries:

- `POST /real-estate/market/list-sale`
- `POST /real-estate/market/buy`
- `POST /real-estate/market/cancel`

all return 503 and mutate nothing.

## Lease and gift

The historical Flutter surface exposed Lease and Give controls but there is no recovered authoritative contract model.

No source-backed answers were found for:

### Lease

- rent denomination;
- contract duration;
- payment cadence;
- deposit;
- eviction/default;
- who receives property bonuses;
- owner/renter simultaneous residence rules;
- renewal/cancellation.

### Gift

- recipient eligibility;
- cooldowns;
- active-residence behavior;
- whether upgraded properties can transfer;
- anti-abuse restrictions;
- transaction denomination/audit classification.

Both remain paused:

- `POST /real-estate/lease`
- `POST /real-estate/give`

## Database integrity

Migration:

`20261104232000_property_lifecycle_integrity_20261105.sql`

adds:

- nonnegative integer property catalog costs;
- nonnegative integer base upkeep;
- nonnegative HP source values;
- nonnegative integer transaction amounts;
- nullable `property_transactions.seller_id -> users(user_id)` FK;
- unique partial index enforcing at most one `active_residence` per user;
- missing FK-supporting indexes for property ownership, market and transaction relationships.

Migration:

`20261104232500_property_transaction_instance_integrity_20261105.sql`

adds:

- `property_transactions.instance_id -> owned_properties(id)`;
- supporting instance index.

The agency/system seller is represented with NULL rather than a fake player ID such as 0.

## Legacy table

`user_properties` currently contains only `user_id` and no ownership data.

It is not treated as the property ownership source of truth.

`owned_properties` remains the instanced ownership ledger.

## Flutter companion

Draft PR #5 now:

- removes the hardcoded property upgrade catalog;
- displays recovered per-property upgrade definitions read-only;
- labels upgrade purchase as paused;
- corrects `daily_cash` display so base upkeep is not incorrectly multiplied by property price;
- displays total upkeep as reference only;
- replaces active Sale controls with a reconciliation-paused explanation;
- marks Lease, Give and Upkeep as paused with explicit blockers;
- disables Player Market Buy/Rent controls;
- removes the old assumption that property type 1 is a default Trailer;
- labels portfolio value as a catalog-cost reference;
- labels HP/Gym figures as source values rather than guaranteed active bonuses;
- disables non-starter agency purchase while the two property catalogs conflict.

## Verification boundary

Performed:

- source comparison against the Assets Canvas;
- exact `properties_master` worksheet read;
- current backend/client implementation review;
- development database schema/data inspection;
- migration application and constraint/index readback;
- static Git readback;
- Supabase advisor review.

Not performed by instruction:

- Node runtime tests;
- gameplay tests;
- concurrency tests;
- Flutter analyze/build/widget tests;
- deployment;
- production migrations.
