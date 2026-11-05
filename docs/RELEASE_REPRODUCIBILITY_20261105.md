# Release Reproducibility / Configuration Stabilization — 2026-11-05

## Scope

This pass makes the integrated backend branch reproducible from source without
changing unresolved gameplay mechanics.

No gameplay/API runtime tests, concurrency tests, Flutter build/analyze, or
deployment were performed.

## Migration history: fully reconciled

Final development readback:

- Git migration files: 41;
- Supabase migration-history rows: 41;
- name/version mismatches: 0;
- Git-only migrations: 0;
- database-only migrations: 0.

The final three reconciled versions are:

- `20261105095946_vip_casino_cap_20261105.sql`;
- `20261105095957_trade_asset_namespace_20261105.sql`;
- `20261105100004_data_api_privilege_hardening_20261105.sql`.

Those changes were safe to replay because their SQL had first been made
idempotent where necessary. They were then applied through Supabase's normal
migration mechanism and the Git filenames were renamed to the versions actually
recorded by development Supabase.

The migration-history table was never edited manually.

## Backend dependency reproducibility

Top-level Node dependencies are now pinned to the exact versions already present
in `package-lock.json`:

- bcrypt 6.0.0;
- cors 2.8.6;
- dotenv 17.4.1;
- express 5.2.1;
- pg 8.20.0.

The lockfile root requirements were updated to the same exact versions.

Container installation continues to use:

`npm ci --omit=dev`

so dependency resolution is lockfile-driven.

## Standard startup path

`package.json` now defines:

- `npm start` -> `node server.js`;
- `npm run release:preflight` -> static environment/configuration validation.

The Docker image now starts the same `npm start` entrypoint instead of carrying
a separate direct Node command.

## Release configuration preflight

`cold_streets_backend/scripts/release_preflight.js`

performs configuration-only validation. It does not connect to the database or
make gameplay HTTP calls.

It checks:

- retired legacy timer flag is not enabled;
- CORS wildcard is not configured;
- required server variables exist when gameplay is enabled;
- Supabase URL is valid HTTPS;
- a secret/service-role key is not being used in the publishable-key slot;
- production cannot use `DB_SSL=false`;
- warns when gameplay is disabled or production browser origins are absent.

The preflight script was added but **not executed** in this pass because runtime
testing remains unauthorized.

## Fail-closed defaults

The backend/container continues to default:

`ENABLE_GAMEPLAY_API=false`

With gameplay disabled:

- only `/healthz` is available;
- gameplay workers do not start;
- authenticated gameplay routes remain 503.

The retired legacy timer flag is not present as an enabled configuration option,
and `server.js` explicitly throws if a stale deployment attempts to set it true.

## Database access boundary

The reconciled Data API hardening migration maintains:

- all gameplay tables RLS-enabled;
- no direct anon/authenticated gameplay table access;
- no client sequence access;
- no public/client RPC execution;
- future postgres-owned public objects deny client grants by default.

All current public gameplay objects are postgres-owned.

## Suggested future release sequence

When testing/deployment is explicitly authorized, the release procedure should
be deterministic:

1. use the reviewed integration commit;
2. install with `npm ci`;
3. run `npm run release:preflight`;
4. verify migration history equals the 41 committed files;
5. run database/security advisors;
6. keep `ENABLE_GAMEPLAY_API=false` during infrastructure smoke checks;
7. perform authorized API/concurrency/Flutter tests;
8. enable gameplay only after those checks pass.

This document does not authorize any of those runtime/deployment steps.

## Verification performed

- Git/Supabase migration-history equality check;
- migration application through normal Supabase history;
- package/lockfile static alignment;
- Docker/startup source readback;
- release configuration source review;
- database advisor/readback work from the stabilization stack.

Not performed:

- npm install;
- release preflight execution;
- Node server startup;
- HTTP/API testing;
- Flutter build/analyze;
- deployment;
- production changes.


## Operational hardening follow-up

The reviewed runtime contract now requires Node 24.x and the release preflight
checks that major explicitly.

Transport/database limits are documented in:

- `docs/HTTP_POSTGRES_OPERATIONAL_HARDENING_20261105.md`;
- `docs/MUTATION_CONTRACT_AUDIT_20261105.md`.

The release candidate now includes explicit HTTP header/request/socket bounds,
PostgreSQL statement/query/lock/idle-transaction bounds, connection rotation,
DB-pool backpressure, strict active-mutation request field allowlists, and a
fail-closed registry for future mutation endpoints.

These additions were reviewed statically only; the preflight and server were not
executed.
