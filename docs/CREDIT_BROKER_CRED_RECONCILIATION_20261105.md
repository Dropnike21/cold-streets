# Cred and Credit Broker Reconciliation — 2026-11-05

## Scope

This pass separates four concepts that the recovered project currently conflates:

1. **Cred** — a player balance stored in `users.cred`.
2. **Credit Broker upgrade catalog** — 18 recovered permanent-upgrade definitions plus `user_credit_upgrades`.
3. **Credit/loan broker design** — an original design reference that places loans in the Underworld / Credit Broker sector.
4. **Premium currency / Gold Credits** — a monetization brainstorm currency that is not safely equivalent to `users.cred`.

No source permits these concepts to be silently merged.

No gameplay/runtime/build tests or production deployment were performed.

## Recovered evidence

### Current implementation history

Git commit `5a28797ff9f94562baa46d5777d73a32ec50a6be` (2026-04-24) introduced the current Credit Broker implementation together with the achievement engine.

Its commit description explicitly says:

- the backend added `credit_broker.js`;
- auth began syncing a `cred` currency;
- Credit Broker relational tables were created;
- the UI became a Credit Broker black-market terminal;
- the UI used dynamic cost scaling.

The current route subsequently derives a legacy next cost as:

`current level + 1`

However, that cost is **not stored in the recovered catalog**.

### Recovered data-only PostgreSQL dump

`cold_streets_game_data.sql` contains 18 `credit_upgrades_master` rows:

Player:
1. Nerve Capacity — +1 per level
2. Crime Experience — +2% per level
3. Health Regeneration — +2% per level
4. Vitality — +5% per level
5. Lethality — +0.5% per level
6. Speed Reader — +2% per level
7. Bank Interest — +2% per level
8. Stealth — +1% per level
9. Employee Effectiveness — +1% per level

Combat:
10. Brute Strength — +3% per level
11. Lightning Speed — +3% per level
12. Deft Dexterity — +3% per level
13. Iron Defense — +3% per level

Weapon:
14. Melee Mastery — +2% per level
15. Pistol Mastery — +2% per level
16. Rifle Mastery — +2% per level
17. Shotgun Mastery — +2% per level
18. Heavy Mastery — +2% per level

Every recovered upgrade has maximum level 10.

The live development catalog matches the data-only dump and has fingerprint:

`315a202546541b313fdb1679e1545f9e`

There are currently zero `user_credit_upgrades` rows in the development database.

### No recovered price column

The physical `credit_upgrades_master` schema contains:

- `upgrade_id`
- `category`
- `title`
- `description`
- `max_level`
- `val_per_level`
- `suffix`

It contains **no Cred cost or price-curve field**.

Therefore `next level = Cred cost` is a code convention from the partial implementation, not a catalog-owned price rule.

### No effect consumers

The backend has no consumer of `user_credit_upgrades` outside the Credit Broker read route.

That means the catalog describes bonuses, but purchasing a row today would not authoritatively modify:

- max Nerve;
- crime EXP gain;
- health regeneration;
- max HP;
- critical chance;
- University duration;
- Bank interest;
- attack anonymity;
- employee effectiveness;
- battle-stat effectiveness;
- weapon damage/accuracy.

Charging Cred before these interactions are defined would create a nonfunctional permanent money sink.

## Source conflicts

### Credit Broker = upgrades

The 2026-04-24 implementation clearly treats the Credit Broker as a Cred-funded permanent-upgrade terminal.

### Credit Broker = loans

The later Stock Market design names **Apex Credit & Loan [ACL]** as:

- sector: **The Underworld / Credit Broker**;
- volatility driver: number of loans taken globally;
- shareholder perk: reduced loan interest.

This describes a lending/credit service rather than the current permanent-upgrade terminal.

### Credit Broker = premium market

A later Flutter intel string described the Credit Broker as:

- trading premium Credits with players;
- buying restricted items;
- checking fluctuating market rates.

No matching backend marketplace exists.

### Premium currency != safely Cred

The Monetization Brainstorm separately proposes a supporter currency explicitly called **Gold Credits** for premium consumables and supporter-shop services.

That is insufficient evidence to identify `users.cred` as the monetization currency.

### Achievement Cred earning

The legacy achievement engine hardcoded +1 Cred per unlock, and it was introduced in the same implementation period as the Credit Broker.

However:

- the recovered `achievements_master` source has no reward field;
- the Project Master identifies tracker alignment but does not canonize a +1 Cred reward;
- later client prose described achievements as milestones/permanent boosts/titles rather than a precise Cred payout rule.

PR #20 therefore correctly removed the hardcoded payout pending an explicit canonical rule.

## Safe implementation in this pass

### Read-only catalog

`GET /credit-broker/:user_id` now:

- derives the player from authenticated identity;
- returns the authoritative server Cred balance;
- verifies all 18 recovered catalog rows against the source fingerprint;
- validates owned levels against each catalog maximum;
- computes display-only current/next bonus values using PostgreSQL NUMERIC arithmetic;
- returns `purchase_available: false`;
- returns no invented Cred price.

Top-level status is explicit:

- `broker_status: catalog_only`
- `pricing_status: unresolved`
- `effect_application_status: unimplemented`
- `cred_earning_status: unresolved`

### Purchase endpoint

`POST /credit-broker/purchase` exists only as an authenticated fail-closed boundary.

It returns 503 until all three are reconciled:

1. Cred earning;
2. pricing;
3. upgrade effect semantics and interactions.

It accepts and spends nothing.

## Database integrity

Migration `20261104225500_credit_broker_catalog_integrity_20261105.sql` adds:

- `max_level > 0`;
- `val_per_level >= 0`;
- `user_credit_upgrades.current_level >= 0`;
- supporting index on `user_credit_upgrades(upgrade_id)`.

The existing primary key `(user_id, upgrade_id)` already prevents duplicate ownership rows.

No upgrade ownership rows existed when this migration was applied.

## Flutter companion

Draft PR #5 now:

- displays the server-returned Cred balance;
- shows the 18 recovered upgrade definitions as a catalog;
- removes the old locally inferred level-cost purchase button;
- displays an explicit catalog-only / reconciliation notice;
- labels the drawer entry simply **Credit Broker**, not **Credit Broker / Item Market**;
- removes stale intel claiming premium-Credit trading/restricted-item market behavior;
- removes stale achievement wording that conflated “street cred” with undefined permanent rewards.

## What remains before purchases can be enabled

A future implementation must explicitly settle:

1. **Cred acquisition**
   - achievements?
   - mission milestones?
   - PvP/competition?
   - another progression source?

2. **Price curve**
   - level number?
   - cumulative curve?
   - category-specific prices?
   - catalog-owned cost values?

3. **Effect application**
   - exact formulas;
   - additive vs multiplicative semantics;
   - stacking with University perks, properties, jobs and syndicates;
   - caps and ordering;
   - which combat/weapon systems consume each bonus.

4. **Credit Broker product identity**
   - permanent upgrade terminal;
   - lending/loan service;
   - market;
   - or separate named systems.

These must not be merged implicitly.

## Verification boundary

Performed:

- recovered SQL/catalog reconciliation;
- Git implementation-history review;
- original Drive design comparison;
- development schema/data readback;
- migration application;
- static client/backend readback.

Not performed by instruction:

- gameplay tests;
- Node runtime tests;
- Flutter analyze/build/widget tests;
- concurrency tests;
- deployment;
- production migration.
