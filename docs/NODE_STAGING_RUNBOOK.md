# Cold Streets — Node / PostgreSQL Staging and Release Runbook

**Status:** static release contract only. No deployment or runtime authorization is implied.

## Runtime contract

The reviewed backend runtime is:

- Node.js `>=24.6 <25`;
- Express 5.2.1;
- node-postgres 8.20.0;
- one shared PostgreSQL pool from `cold_streets_backend/db.js`;
- `npm ci --omit=dev` for reproducible container installation;
- `npm start` as the canonical server entrypoint.

The container starts with:

`ENABLE_GAMEPLAY_API=false`

Gameplay must never become reachable merely because the process starts.

## Required configuration

Use the hosting platform's secret/configuration store. Do not place private
database credentials in GitHub, Flutter, logs, screenshots, or client builds.

Canonical environment contract:

```dotenv
NODE_ENV=production
PORT=3000
ENABLE_GAMEPLAY_API=false

SUPABASE_URL=https://YOUR_PROJECT_REF.supabase.co
SUPABASE_PUBLISHABLE_KEY=sb_publishable_REPLACE

CORS_ALLOWED_ORIGINS=

DB_HOST=PASTE_EXACT_HOST_FROM_SUPABASE_CONNECT
DB_PORT=5432
DB_NAME=postgres
DB_USER=PASTE_EXACT_POOLER_USER
DB_PASSWORD=PRIVATE_SECRET_STORE_ONLY
DB_SSL=true
```

`ENABLE_UNSAFE_LEGACY_TIMERS` is retired. A deployment that sets it to
`true` is rejected by both the release preflight and server startup.

## Supabase credential boundary

The Node API uses the Supabase publishable/public key only to verify bearer
sessions through `GET /auth/v1/user`.

Do not put any of the following in `SUPABASE_PUBLISHABLE_KEY`:

- `service_role`;
- `sb_secret_` keys;
- database passwords.

The Flutter client may contain a Supabase publishable key. It must never contain
the PostgreSQL password or a privileged Supabase secret.

The Auth verification call has a 10-second abort timeout. If the incoming HTTP
request is abandoned first, the upstream Auth request is aborted immediately.

## PostgreSQL connection contract

Use the exact host/user values supplied by the Supabase Connect dialog. Do not
derive the pooler hostname from region assumptions.

Production requires encrypted PostgreSQL transport:

`DB_SSL=true`

The single shared application pool applies these boundaries to routes and
workers:

- maximum clients: 10;
- acquisition timeout: 5 seconds;
- PostgreSQL statement timeout: 15 seconds;
- node-postgres query timeout: 20 seconds;
- lock timeout: 5 seconds;
- idle-in-transaction timeout: 15 seconds;
- idle pool timeout: 30 seconds;
- connection lifetime: 300 seconds;
- connection-use rotation: 5,000 uses;
- TCP keepalive enabled;
- `application_name=cold-streets-api`.

There is no separate route or worker PostgreSQL client that bypasses this pool.

## HTTP contract

The reviewed HTTP listener enforces:

- 16 KiB maximum header bytes;
- 100 maximum headers;
- 64 KiB JSON body limit;
- strict JSON parsing;
- simple Express query parsing;
- 10-second header timeout;
- 20-second request-receive timeout;
- 30-second socket inactivity timeout;
- 5-second keep-alive timeout plus 1-second buffer;
- maximum 500 requests per socket;
- maximum 256 accepted connections;
- strict HTTP parser and required HTTP/1.1 Host header.

All API responses are non-cacheable. Security headers disable framing,
referrer leakage, MIME sniffing, browser permission features, DNS prefetch and
cross-domain policy files. HSTS is emitted only in production.

## Pool overload behavior

When at least 20 callers are already queued waiting for a PostgreSQL client,
new gameplay requests are rejected before authentication/gameplay handlers add
more work.

The response is:

- HTTP 503;
- `Retry-After: 1`;
- `Connection: close`;
- a generic non-sensitive error.

`/healthz` is independent from PostgreSQL.

`/readyz` remains outside gameplay backpressure middleware, but if the pool is
already saturated it returns 503 without adding another pool acquisition.

Transient PostgreSQL/network failures, lock/statement timeouts, serialization
failures and deadlocks are classified as retryable operational failures and
return a generic HTTP 503 with `Retry-After: 1` through the common error
paths.

## Health probes

### `GET /healthz`

Pure liveness:

- no database request;
- no Auth request;
- no worker requirement;
- returns 200 while the listener/process can answer.

### `GET /readyz`

When gameplay is disabled, the deliberately health-only service may report
ready without PostgreSQL/workers.

When gameplay is enabled, readiness requires:

- PostgreSQL readiness probe success;
- every currently enabled authoritative worker started and healthy;
- service not shutting down.

At this stabilization head, the only required worker is State Duration. Crew
Crime automation is intentionally paused and is not started or required for
readiness until its source semantics are reconciled.

The public response intentionally exposes only booleans/status, not database
hosts, pool counts, worker timestamps, SQL errors, or credentials.

## Startup order

For an eventual authorized staging release:

1. select the reviewed commit/PR head;
2. provision secrets/configuration with `ENABLE_GAMEPLAY_API=false`;
3. install exactly from the lockfile with `npm ci`;
4. run `npm run release:preflight`;
5. verify committed migration history against the target database;
6. apply migrations only through the normal migration mechanism;
7. start the Node service with gameplay still disabled;
8. verify `/healthz` and `/readyz`;
9. perform the authorized runtime verification plan on isolated/staging data;
10. enable gameplay only in the reviewed staging environment after those gates
    pass.

Do not switch gameplay on first and then attempt to diagnose infrastructure.

## Graceful shutdown

SIGTERM, SIGINT, uncaught exceptions and unhandled rejections enter the same
shutdown path:

1. readiness is marked false;
2. worker polling is stopped;
3. an active worker batch stops after its current individual transaction rather
   than starting more settlements;
4. new listener work is stopped;
5. idle HTTP keep-alive connections are closed;
6. the PostgreSQL pool is drained/closed;
7. the process exits.

A 25-second forced-exit guard bounds pathological shutdown hangs.

If the initial database bootstrap completes after shutdown has already started,
workers are not started.

## Release/data blockers that are not runtime mechanics

Before a real release, any migration that intentionally refuses ambiguous
historical reconstruction must have an explicit data policy. In particular,
lifetime discovery/progression backfills must not invent preexisting player
history.

Such decisions belong in the release/data migration plan, not in HTTP
operational code.

## Verification boundary

This runbook records the intended contract only.

Not executed in this stabilization phase:

- release preflight;
- Node startup;
- HTTP malformed/slow/oversize request tests;
- Auth timeout tests;
- PostgreSQL acquisition/statement/lock timeout tests;
- pool saturation/load tests;
- shutdown tests;
- multi-replica worker tests;
- Flutter analyze/build;
- staging or production deployment.
