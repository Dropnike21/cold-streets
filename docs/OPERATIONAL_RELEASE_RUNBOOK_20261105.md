# Cold Streets Operational Release Runbook — 2026-11-05

## Purpose

This is the canonical operator handoff for taking the stabilized Cold Streets
backend from reviewed source to an explicitly authorized runtime environment.

It does not authorize deployment or testing by itself.

## Canonical source

Backend:

- draft PR #44;
- branch `stabilization/backend-integration-20261105`.

Flutter:

- draft PR #5;
- branch `feature/flutter-supabase-auth-20261104`;
- based on the canonical backend branch.

Before any release attempt, use reviewed immutable commit SHAs rather than an
unbounded moving branch.

## Runtime contract

Required runtime:

- Node 24.x;
- PostgreSQL 17-compatible Supabase project/pooler;
- lockfile installation with `npm ci --omit=dev`.

Top-level dependency versions are pinned in package.json/package-lock.json.

## Server configuration

### Mandatory when gameplay is enabled

- `SUPABASE_URL`
- `SUPABASE_PUBLISHABLE_KEY`
- `DB_HOST`
- `DB_USER`
- `DB_PASSWORD`
- `DB_NAME`

### Network/runtime

- `PORT`: integer TCP port, default 3000;
- `DB_PORT`: integer TCP port, default 5432;
- `DB_SSL`: exact `true` or `false`;
- production requires PostgreSQL TLS;
- `ENABLE_GAMEPLAY_API`: exact `true` or `false`;
- `CORS_ALLOWED_ORIGINS`: comma-separated exact browser origins.

`ENABLE_UNSAFE_LEGACY_TIMERS` is retired and must not exist in the environment.

### Supabase Auth

`SUPABASE_URL` must be the bare HTTPS project origin.

The publishable-key variable must never contain:

- service_role;
- `sb_secret_` credentials.

Database credentials, service-role credentials and passwords must never be
placed in Flutter, browser bundles, logs or Git.

## Database/migration state

Canonical development baseline at static closeout:

- 41 Git migration files;
- 41 development migration-history rows;
- 0 version/name mismatches;
- 0 Git-only migrations;
- 0 database-only migrations.

Do not manually edit Supabase migration history to make a release appear clean.

A fresh-database migration replay is a required runtime verification step before
production promotion.

## Data API boundary

Current intended model:

- Supabase Auth supplies identity;
- gameplay mutations run through the private Node API;
- gameplay tables are not directly available to anon/authenticated Data API
  clients.

Static baseline:

- 74/74 public tables RLS-enabled;
- no anon/authenticated public table grants;
- no client sequence access;
- no PUBLIC/anon/authenticated public-function execution.

## Safe first startup mode

First infrastructure startup must use:

`ENABLE_GAMEPLAY_API=false`

Expected surface:

- `GET /healthz` -> process liveness;
- `GET /readyz` -> health-only service readiness;
- gameplay routes -> 503.

Gameplay workers do not start in this mode.

This permits network/container/proxy health validation without exposing gameplay.

## Preflight sequence

When runtime testing is explicitly authorized:

1. checkout the reviewed commit;
2. verify Node major 24;
3. install with `npm ci --omit=dev`;
4. configure secrets through the deployment secret store;
5. keep gameplay disabled;
6. run `npm run release:preflight`;
7. verify the migration-history/file set;
8. run the authorized fresh-schema migration replay;
9. start the API in health-only mode;
10. validate liveness/readiness and shutdown;
11. only then proceed to gameplay-enabled staging tests.

Do not skip directly to production gameplay enablement.

## Gameplay-enabled startup

When `ENABLE_GAMEPLAY_API=true`:

- required Auth/DB configuration is validated at startup;
- DB bootstrap is attempted;
- startup DB failure leaves readiness false;
- bootstrap retries every 5 seconds;
- after DB recovery the State Duration worker starts exactly once;
- the Crew Crime worker remains disabled.

Readiness requires:

- PostgreSQL probe success;
- State Duration worker started and healthy;
- process not shutting down.

## HTTP operational bounds

Current source contract:

- header size: 16 KiB;
- max headers: 100;
- headers timeout: 10 s;
- request receive timeout: 20 s;
- inactivity timeout: 30 s;
- keep-alive timeout: 5 s;
- max requests/socket: 500;
- JSON body limit: 64 KiB.

Supabase Auth:

- 10 s timeout;
- 50 concurrent verifications/process maximum;
- overflow returns 503 + Retry-After.

## PostgreSQL operational bounds

Current source contract:

- pool max: 10;
- acquisition timeout: 5 s;
- statement timeout: 15 s;
- client query timeout: 20 s;
- lock timeout: 5 s;
- idle-in-transaction timeout: 15 s;
- pooled idle timeout: 30 s;
- max uses/client: 5,000;
- max connection lifetime: 300 s.

Gameplay request backpressure begins when 20 callers are already waiting for a
pool client; new work returns 503 + `Retry-After: 1`.

## Health probes

### /healthz

Use only for process/listener liveness.

It intentionally does not query PostgreSQL.

### /readyz

Use for traffic readiness.

When gameplay is enabled it checks PostgreSQL with a tighter:

- 2 s local statement timeout;
- 1 s local lock timeout.

Public readiness exposes only safe booleans.

Do not route gameplay traffic to instances returning 503 readiness.

## Graceful shutdown

On SIGTERM/SIGINT:

1. readiness becomes false;
2. bootstrap retry is cancelled;
3. worker polling stops;
4. listener stops accepting new work;
5. PostgreSQL pool closes;
6. process exits.

A 25-second forced-shutdown guard exists.

Deployment termination grace should be longer than that application guard.

## Emergency disable / rollback

The fastest fail-closed gameplay shutdown is:

`ENABLE_GAMEPLAY_API=false`

followed by a controlled process restart/redeployment.

This leaves health endpoints available while all gameplay routes return 503 and
workers remain stopped.

If a release commit itself must be rolled back:

1. disable gameplay first;
2. restore the previous reviewed immutable application commit;
3. do not reverse database migrations casually;
4. assess migration/data compatibility separately;
5. re-run readiness checks before re-enabling gameplay.

Never compensate for a bad application release with manual player-balance or
ledger edits unless a separately reviewed recovery procedure exists.

## Production promotion gate

Production gameplay should remain disabled until all items in
`RUNTIME_VERIFICATION_PLAN_20261105.md` required for the release have passed.

Mechanics listed in `MECHANICS_DECISIONS_REQUIRED_20261105.md` remain
fail-closed and are not production blockers for unrelated safe functionality.

## Current authorization boundary

This runbook is documentation only.

During the stabilization phase that produced it, no server startup, API call,
fresh migration replay, concurrency/load test, Flutter build/analyze, deployment
or production action was performed.
