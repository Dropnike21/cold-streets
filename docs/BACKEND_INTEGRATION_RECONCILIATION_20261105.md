# Backend Integration Reconciliation — 2026-11-05

## Purpose

This stabilization pass creates one reviewable backend integration candidate after
the post-PR-31 development graph split into independent company,
state/progression, and market/inventory/premium/trade tracks.

No existing feature PR was merged or closed. No gameplay/runtime/build tests and
no deployment were performed.

Integration branch:

`stabilization/backend-integration-20261105`

## Canonical topology

Common stabilized ancestor:

- PR #31 — source-backed NPC company staffing.

Post-31 tracks reconciled here:

### Market / inventory / progression / premium / trade track

- #32 University Max Nerve
- #34 city NPC market daily cap
- #35 explicit medkit mechanics
- #40 unique item discovery achievements
- #41 Casino Token daily-spend accounting
- #42 premium packs / Subscriber
- #43 Trade preflight for items and premium packs

### Company track

- #33 company supply-chain compatibility audit
- #37 source-native company product namespace
- #38 company incorporation preflight

### State / progression track

- #36 Jail/Hospital state duration telemetry
- #39 mission completion achievements

The integration branch records the latest #38, #39 and #42 heads as additional
parents of a no-content integration commit. The #43 lineage is already the
first-parent ancestry of the branch.

After the topology commit, Git reports the integration branch ahead of all four
reconciled heads with zero commits behind:

- #38 company head: behind 0;
- #39 state/progression head: behind 0;
- #42 latest premium head: behind 0;
- #43 trade head: behind 0.

This makes the branch a true ancestry integration point rather than a collection
of copied files.

## Manual overlap reconciliation

Several sibling branches touched the same files and required explicit merging.

### server.js

Combined:

- premium route mount;
- state duration worker import/start;
- company supply-chain audit route;
- generic company router;
- existing crew worker and feature flag boundary.

The specific supply-chain audit route is mounted before the generic
`/companies` router so a future parameterized company route cannot shadow it.

The opt-in legacy development timer no longer directly clears Jail/Hospital
expiry timestamps. State expiry is owned by the persisted state-duration worker.

### Achievement engine/read model

The integration head contains all currently source-pinned authoritative trackers:

- `gym_trains`;
- `crimes_successful`;
- `player_level`;
- `courses_completed`;
- `days_in_jail`;
- `hospital_hours`;
- `missions_completed`;
- `unique_items_found`.

Mission completion and unique-item refresh helpers coexist.

### Crime routes

Shoplifting and Pickpocketing preserve both:

- unique-item achievement refresh after actual loot acquisition;
- Jail/Hospital state-episode source identity.

No sibling behavior was intentionally discarded.

## Migration history repair

The repository migration directory had two release-blocking inconsistencies.

### Missing baseline

The feature stack did not contain the three schema-reconstruction migrations on
which every later migration depends.

The stabilization branch now includes them under the exact versions/names
recorded by the development Supabase project:

- `20261104150029_recovered_catalog_schema_20261104.sql`
- `20261104150107_reconstructed_game_state_20261104.sql`
- `20261104150521_identity_and_bank_invariants_20261104.sql`

### Historical version drift

27 migration files had repository timestamps different from their already
applied development-database versions.

Those files were renamed without changing their SQL blobs so repository version
identity now matches the development migration history.

Post-repair readback:

- repository migration files: 41;
- historical name/version mismatches: 0;
- applied development migrations missing from repository: 0.

### Development migration-history reconciliation

The premium, Trade asset-namespace, and Data API hardening changes were first
verified directly against the development schema and later replayed through
Supabase's normal migration mechanism using idempotent SQL.

Their recorded development versions are:

- `20261105095946_vip_casino_cap_20261105.sql`;
- `20261105095957_trade_asset_namespace_20261105.sql`;
- `20261105100004_data_api_privilege_hardening_20261105.sql`.

The Git files were renamed to those exact versions after application.

Final readback:

- repository migrations: 41;
- development migration-history rows: 41;
- name/version mismatches: 0;
- repository-only migrations: 0;
- database-only migrations: 0.

The migration-history table was never edited manually.


## Current integration boundary

This branch integrates existing authoritative/fail-closed feature work only. It
does not resolve gameplay-design questions such as:

- company incorporation currency;
- company production quantities/cadence;
- Trade settlement currency/fees;
- Casino paytables/token issuance;
- VIP Nerve semantics / Kingpin benefits / Books;
- property generation conflict;
- bail/breakout/training formulas;
- PvP terminal fight settlement.

Those systems remain closed where their rules are unresolved.

## Verification performed

Static/repository verification only:

- open PR topology inspection;
- sibling branch comparison;
- manual overlapping-file reconciliation;
- post-integration ancestry comparison;
- migration directory vs development migration-history comparison;
- key route/worker readback.

Not performed:

- gameplay tests;
- runtime/API tests;
- concurrency tests;
- build tests;
- Flutter analyze;
- deployment;
- production changes.
