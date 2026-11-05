# Cold Streets Operational Stabilization Closeout — 2026-11-05

## Scope

This document closes the static HTTP, PostgreSQL, upstream-call, shutdown,
release-configuration and operational-observability lane.

It does not duplicate the parallel mutation-contract, gameplay-economy,
Flutter/API, schema/catalog or backlog-closeout audits.

No runtime test, build, migration replay, load test, deployment or production
change was performed.

## External-call timeout audit

Repository-wide static inspection found one active outbound HTTP dependency:

- Supabase Auth user verification in
  `middleware/playerIdentity.js`.

Its boundary is explicit:

- native `fetch`;
- 10-second `AbortSignal.timeout`;
- incoming-request abort is combined with the upstream signal so client
  disconnects cancel the Auth request immediately;
- upstream non-2xx service failures return a generic 503;
- bearer tokens and upstream response bodies are not logged.

No additional active `fetch`, axios, got, undici, raw HTTP, net or TLS outbound
client was found in backend routes/workers/utilities.

## HTTP failure-path audit

### Malformed JSON

Express's strict JSON parser is global for JSON media types. Parse failures enter
the final error boundary and are represented as generic HTTP 400 responses.

### Oversized request bodies

JSON bodies are capped at 64 KiB. Body-size failures enter the final error
boundary and are represented as generic HTTP 413 responses.

### Oversized/malformed headers

Node's HTTP parser is capped at 16 KiB of header bytes and 100 headers. The
application does not install a custom `clientError` response path; malformed
parser traffic is therefore left to Node's bounded default socket/parser
handling rather than being routed through Express.

### Slow clients

The listener has explicit:

- 10-second header timeout;
- 20-second complete-request receive timeout;
- 30-second socket inactivity timeout.

These are transport/input bounds. PostgreSQL and Supabase Auth have independent
downstream bounds.

### Client disconnect/reset

Request observability now records `http_request_aborted` when a response closes
before completion, without logging tokens, request bodies, player IDs, remote IP
addresses or other private request data.

Supabase Auth verification is canceled when the incoming request aborts.

### Late handler failures

If an error occurs after the client has disconnected, the final error boundary
logs it and does not attempt a response.

If response headers were already sent, the error is logged and the response is
destroyed rather than attempting an invalid second JSON error write.

### Unexpected Express errors

Before headers are sent:

- known transient DB/network failures become generic retryable 503 responses;
- known 4xx parser/request errors retain bounded client-error status;
- other unexpected failures return generic 500;
- stack traces, SQL, request bodies and credentials are not returned.

## PostgreSQL pool and transaction audit

The backend has one `pg.Pool` construction: `cold_streets_backend/db.js`.

Static inspection found no second `pg.Pool` or `pg.Client` construction in
active routes, workers or utilities.

Therefore all route and worker acquisition paths inherit:

- connection acquisition timeout: 5 seconds;
- statement timeout: 15 seconds;
- node-postgres query timeout: 20 seconds;
- lock timeout: 5 seconds;
- idle-in-transaction timeout: 15 seconds;
- idle pool timeout: 30 seconds;
- max pool clients: 10;
- connection lifetime/rotation settings.

The active State Duration worker uses the same shared pool. Crew Crime
automation is intentionally paused at the current stabilization head and is not
started.

The readiness probe uses the same pool but tightens the transaction locally to:

- 2-second statement timeout;
- 1-second lock timeout.

## Overload/backpressure audit

The pool exposes queued waiter count through `pool.waitingCount`.

When queued waiters reach 20:

- gameplay work is rejected before authentication/gameplay handlers;
- response is HTTP 503;
- `Retry-After: 1`;
- `Connection: close`;
- pool counts are structured-log fields only.

`/healthz` is mounted before this middleware and remains database-independent.

`/readyz` is also mounted before it, but performs its own saturation check. If
the wait queue is already saturated, readiness returns 503 without adding
another `pool.connect()` waiter.

No active route constructs a database connection outside the common pool, so
there is no route-level bypass of this queue boundary.

## Graceful-shutdown audit

The shutdown path is shared by:

- SIGTERM;
- SIGINT;
- uncaught exceptions;
- unhandled promise rejections.

Source-level order:

1. mark runtime shutting down so readiness becomes false;
2. stop worker scheduling;
3. workers stop their current batch after the current individual DB transaction
   and do not begin another settlement;
4. stop accepting new HTTP work;
5. close idle keep-alive connections;
6. drain/end the PostgreSQL pool;
7. exit.

If the asynchronous startup DB acquisition completes after shutdown begins, it
does not start workers.

A 25-second forced-exit guard bounds a pathological drain.

The active DB transaction itself remains bounded by the configured statement,
query, lock and idle-transaction timeouts.

## Release configuration contract

Canonical runtime/configuration documentation is now
`docs/NODE_STAGING_RUNBOOK.md`.

The release contract includes:

- Node `>=24.6 <25`;
- lockfile-driven install;
- production PostgreSQL TLS;
- exact Supabase Connect host/user rather than guessed pooler values;
- publishable-key versus secret/service-role separation;
- explicit browser CORS origin allowlist;
- gameplay disabled by default;
- retired legacy timer flag rejected;
- health/readiness behavior;
- startup order;
- shutdown semantics.

## Operational observability checklist

A deployed staging/production service should monitor at minimum:

### HTTP

- rate and absolute count of `http_request` with status >= 500;
- 503 rate separately from other 5xx;
- `http_request_aborted`;
- request duration percentiles from structured access logs;
- `http_connection_dropped`.

### PostgreSQL / capacity

- `database_pool_backpressure`;
- `readiness_database_pool_overloaded`;
- `database_pool_error`;
- `database_bootstrap_failed`;
- `readiness_database_probe_failed`;
- `action_operational_failure`;
- PostgreSQL connection count and pooler saturation from provider telemetry;
- statement timeout SQLSTATE 57014;
- lock timeout SQLSTATE 55P03;
- serialization/deadlock SQLSTATE 40001 / 40P01.

### Workers

- `worker_poll_failed`;
- worker unhealthy state through `/readyz`;
- repeated readiness 503 caused by workers;
- unexpectedly long gaps between successful polls using server-side monitoring
  or structured worker logs once runtime metrics are authorized.

### Process / release

- `uncaught_exception`;
- `unhandled_rejection`;
- `shutdown_forced`;
- `database_pool_close_failed`;
- process/container restart count;
- readiness failure rate after deployment/restart;
- release-preflight failure.

No alert threshold is declared canonical before staging traffic/load data exists.
Thresholds should be established from observed staging baselines rather than
invented now.

## Later runtime verification sequence

When runtime testing is explicitly authorized, use this order.

### Gate 1 — static release preflight

1. select exact reviewed commit;
2. install with `npm ci`;
3. run `npm run release:preflight`;
4. verify no uncommitted/generated release drift.

### Gate 2 — gameplay-disabled process smoke

1. start with `ENABLE_GAMEPLAY_API=false`;
2. confirm process stays alive;
3. verify `/healthz`;
4. verify `/readyz`;
5. verify gameplay/auth routes remain 503;
6. exercise graceful SIGTERM shutdown.

### Gate 3 — isolated migration replay

1. create a fresh disposable PostgreSQL/Supabase-compatible test target;
2. replay the complete committed migration sequence from zero;
3. verify schema/catalog constraints and migration history;
4. run database/security advisors;
5. separately test any documented populated-database/backfill policy.

Do not use a production database as the first replay target.

### Gate 4 — HTTP failure paths

Exercise:

- malformed JSON;
- >64 KiB JSON;
- oversized headers;
- slow headers/body;
- connection abort during Auth;
- upstream Auth timeout/failure;
- request abort during DB work;
- unexpected handler failure;
- post-headers failure;
- maximum connection pressure.

Verify status, connection behavior, no sensitive response details and expected
structured logs.

### Gate 5 — PostgreSQL operational limits

Exercise:

- pool acquisition exhaustion;
- 20-waiter backpressure;
- statement timeout;
- lock timeout;
- idle-in-transaction timeout;
- query timeout/client cancellation;
- connection reset;
- PostgreSQL unavailable/recovery;
- readiness behavior during saturation.

Verify retryable failures use 503 + Retry-After and no transaction leaks remain.

### Gate 6 — authenticated API smoke

Use isolated accounts and verify the reviewed active API surfaces, authorization
boundaries and idempotent replay behavior.

### Gate 7 — concurrency/economy tests

Run:

- duplicate Idempotency-Key replay;
- same-key/different-payload rejection;
- concurrent same-player mutations;
- conflicting resource locks;
- economy conservation assertions;
- cross-account authorization attempts;
- retry after transient DB failure.

### Gate 8 — worker tests

For the currently active State Duration worker, run:

- due settlement;
- worker failure/recovery;
- graceful stop during active batch;
- process shutdown during a transaction;
- two application replicas polling the same due state episodes;
- `FOR UPDATE SKIP LOCKED` duplicate-settlement prevention;
- restart/retry behavior.

Also verify Crew Crime automation remains unscheduled/fail-closed while its
source timing and mortality semantics are unresolved.

### Gate 9 — Flutter verification

Run:

- `flutter analyze`;
- Flutter unit/widget tests;
- Android/iOS build as applicable;
- authenticated staging smoke on device/emulator;
- authoritative-response synchronization checks.

### Gate 10 — staging release decision

Only after the preceding gates pass should a reviewed staging deployment enable
`ENABLE_GAMEPLAY_API=true`.

Production enablement requires a separate decision and rollback/backup plan.

## Remaining operational static work

After this closeout, no additional broad operational static audit is currently
identified.

Known residual route-level generic 500 catch blocks in older read-only handlers
are response-normalization cleanup. They are intentionally left for
reconciliation after the parallel route/mutation closeout to avoid conflicting
edits.

The major remaining operational evidence gap is runtime verification, not more
static configuration work.
