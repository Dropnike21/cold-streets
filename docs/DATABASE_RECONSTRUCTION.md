# Cold Streets — database reconstruction status

**Working draft: 2026-11-04. No live database was accessed, no migrations were executed and no gameplay tests were run.**

## Objective and authority

Build an isolated, server-only PostgreSQL development schema for a future Supabase project, using:

1. The existing GitHub `main` branch backend's SQL statements.
2. The private Google Drive `cold_streets_game_data.sql` PostgreSQL 18 data-only dump.
3. `Cold Streets — PostgreSQL Database Recovery Specification v0.1` and game design references.

**This is reconstruction, not an exact recovery of the old server.** The complete original DDL, private accounts, triggers, stored functions, deployment secrets and database runtime state have not been recovered.

## Deliverables on this branch

- `supabase/migrations/20261104000100_recovered_catalog_schema.sql`: table and column definitions for all **18** dump catalog tables.
- `supabase/migrations/20261104000200_reconstructed_game_state.sql`: **35** provisional player/economy/state tables inferred from current backend queries, including authorization-identity mapping placeholder `users.supabase_auth_uid`.

All 53 reconstructed tables enable Row Level Security with **no end-user policies** and explicitly revoke direct `anon` and `authenticated` table privileges. The intended data access path remains a **private Node.js backend**, not arbitrary direct Flutter SQL/table access. Do not install this into the old database.

## Evidence inventory

The recovered file contains **2,093 rows** across 18 tables. Three of those tables are empty: `city_grants`, `city_policies` and `map_tiles`. The dump is in PostgreSQL `COPY ... FROM stdin` format with psql directives; it is **not** a Supabase SQL Editor paste-in script. It contains no `CREATE TABLE` commands and no player account records.

Table counts: achievements_master 400; casino_jackpots 1; city_grants 0; city_policies 0; company_products_master 20; company_types_master 120; credit_upgrades_master 18; crimes_master 273; education_tracks_master 18; education_courses_master 220; gyms_master 80; items_master 711; jobs_master 10; job_interviews 140; job_ranks 50; map_tiles 0; missions_master 7; properties_master 25.

The old Drive binary backup `cold_streets_full_backup_2026-11-02.backup` was listed at **0 bytes**. It cannot be treated as a restorable backup.

## Important JSON recovery decision

The following source columns are **not valid JSON in the recovered rows**. They have been provisionally stored as `TEXT`, even when their names include `_json`:

| Table | Source fields | Affected rows |
| --- | --- | ---: |
| company_types_master | positions_json, specials_json, affiliations_json, upgrades_json, products_json | 120/120 for each |
| education_courses_master | rewards_json | 220/220 |
| gyms_master | req_item_json | 10 non-placeholder values; remaining 70 contain `NONE` |
| items_master | effects | 711/711 |
| jobs_master | opportunity_json, mastery_logic_json | 10/10 for each |
| job_interviews | options | 140/140 |
| properties_master | available_upgrades_json | 23/25 |

`crimes_master`'s six JSON columns and `missions_master.reqs_json`/`rewards_json` **did** parse as valid JSON in every recovered row and are modeled as `JSONB`. Any conversion of pseudo-JSON must be a separate, explicit and lossless transformation: **do not** apply global search-and-replace to quote keys because values contain spaces, punctuation and nested structures.

## Known backend incompatibilities — do not hide with fake data

- `jobs.js` reads `job_ranks.stat_req_value`, but the recovered data has four columns: `req_acu`, `req_ops`, `req_pre` and `req_res`. The gameplay rule must be resolved in code, **not** by inventing a historical column.
- `university.js` expects scalar `reward_stat_1`, `reward_amount_1`, `reward_stat_2`, `reward_amount_2`; the recovered `education_courses_master` instead has non-JSON `rewards_json`.
- `seed_gyms.js` references gym multipliers and includes a destructive `TRUNCATE` against the game's gym data. Do not run it.
- The spreadsheet has job ID 1 = Armed Forces; code in hospital/jobs mechanics assumes a different job mapping in some paths. Preserve source IDs and resolve semantics before changing those paths.
- Starter property ID 1 in recovered data is **Cardboard Box**. UI/code comments call it a trailer. Do not rename or re-number without a design decision.
- `company_positions_master`, `company_specials_master`, and `blueprint_products` are used by company routes but do not have catalog rows in the recovered 18-table dump. Their data must be reconstructed separately from source references.
- `company_management.js` hard-deletes companies, while the proposed financial/company-history tables have restrictive foreign keys. This conflict must be resolved through a deliberate liquidation/archival policy; do not cascade-delete audit logs.
- `user_properties` and `owned_properties` are distinct objects in the current backend. The original contents of `user_properties` are unknown.
- Exact database types, defaults, indexes, constraints, triggers and account balances are unverified. For now, monetary values use `NUMERIC(24,0)`, which `node-postgres` returns as strings: API money math must avoid number/string concatenation.
- The existing backend has **no verified account-authentication middleware**; requests accept client-supplied IDs. This draft schema must NOT be deployed with public API access.

## Supabase setup when an account is available

No Supabase project or credentials have been created or configured through this work.

1. Create a dedicated **development** Supabase project separate from any existing/live database.
2. Review both SQL migrations and the unresolved assumptions above. Run migrations **only** against this empty development project after review.
3. Transfer the recovered dump privately from its original Drive source to an authenticated development shell. **Do not commit the dump to public GitHub** or paste it into chat.
4. Import the dump with compatible `psql` (the source uses PostgreSQL 18 psql directives) through a trusted database connection. Never run it against a nonempty/live database. Use `ON_ERROR_STOP=1` and keep a record of any import errors.
5. Validate row counts and FK relationships before loading any player data. Recheck all generated identity sequences if an import explicitly supplies their IDs.
6. Store DB access details in the hosting provider's secret store or an encrypted password manager; not in Flutter, Google Docs plaintext, GitHub code or issues.
7. Only then connect the private Node.js server. Add verified Supabase Auth token handling and server-side user ownership checks before external access.

**Do not execute these migrations, load data, expose APIs or consider gameplay stable until a separate review-and-test phase has been authorized.**

## Work order after schema review

1. P0: Set up disposable Supabase DB, resolve missing seed sources and fix authoritative account identity/ownership.
2. P0: Lock down banking, market, casino, mission payouts, companies and real estate with transactions, validation and idempotency.
3. P1: Reconcile jobs, university, gyms, crime data, inventory and tutorial rules; bring each existing action into agreement with catalogs.
4. P1: Run backend/Flutter/schema checks **when testing is authorized**, then implement focused fixes based on failures.
5. P2: Cosmetic UI work and optional new systems after core systems are stable.

## Scope control

No new gameplay feature has been added. No secrets, private player data or raw database dumps have been uploaded to the public repository. This branch is only a proposed foundation for future deployment and compatibility fixes.
