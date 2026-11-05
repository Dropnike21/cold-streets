# Observability / Readiness Stabilization — 2026-11-05

## Scope

This pass adds production-health and diagnostic boundaries to the canonical
backend integration branch without changing unresolved gameplay mechanics.

No server startup, HTTP/runtime tests, worker/concurrency tests, Flutter build,
deployment, or production change was performed.

## Request correlation

Every request receives an `X-Request-Id` response header.

Rules:

- a syntactically valid incoming UUID request ID may be preserved;
- otherwise the server generates a cryptographically random UUID;
- correlation IDs are available to authentication, transaction-error and
  request-access logs.

Request logs intentionally do **not** record:

- Authorization headers;
- Supabase access tokens;
- request/response bodies;
- email addresses;
- Auth UUIDs;
- player IDs.

Numeric and UUID path segments are normalized before logging so common resource
identifiers do not become raw access-log data.

Successful `/healthz` and `/readyz` probes are suppressed from access logs to
avoid health-check noise. Failed readiness remains visible.

## Structured logging

`utils/logger.js` emits single-line JSON to stdout/stderr.

Core event families now include:

- listener start/shutdown;
- database bootstrap/pool/readiness failure;
- worker start/batch/error/rollback;
- Supabase Auth verification failure;
- player identity lookup failure;
- state gatekeeper failure;
- central authoritative action failure;
- unhandled request/process failures;
- request completion status/duration.

Error logging is bounded and single-line. Stack traces and request bodies are
not serialized by the shared logger.

## Liveness

`GET /healthz`

Purpose:

- proves only that the Node listener is alive.

Behavior:

- no database query;
- no worker dependency;
- no secret/configuration disclosure;
- always independent from gameplay feature state.

## Readiness

`GET /readyz`

When `ENABLE_GAMEPLAY_API=false`:

- the deliberately health-only process reports ready;
- DB/workers are not required.

When gameplay is enabled:

- PostgreSQL must answer a bounded `SELECT 1` readiness probe;
- the Crew Crime worker must be started and healthy;
- the State Duration worker must be started and healthy;
- shutdown state immediately makes readiness false.

The public readiness response is deliberately minimal:

- ready/not-ready status;
- gameplay enabled boolean;
- shutting-down boolean;
- database-ready boolean;
- worker started/healthy booleans.

Worker timestamps, settlement counts, database host/configuration and error
messages are not exposed by the readiness endpoint.

## Worker health

Both persisted workers now report health through `runtimeHealth`.

On start:

- worker is registered as started/healthy.

On each poll:

- success records healthy state;
- failure marks that worker unhealthy;
- a later successful poll restores health.

If a worker fails while gameplay is enabled, `/readyz` returns 503 until that
worker completes a successful subsequent poll.

Only nonzero settled batches emit informational batch logs.

## Database health

Initial DB connection success marks the database ready.

Failures from:

- startup connection;
- PostgreSQL pool-level errors;
- readiness probe

mark database readiness false.

A later successful readiness probe can restore DB-ready state.

PostgreSQL connections now include:

`application_name = cold-streets-api`

for server-side connection diagnostics.

## Graceful shutdown

SIGTERM/SIGINT and fatal process errors now use the same shutdown path:

1. mark the service shutting down (readiness becomes false);
2. stop both worker polling timers;
3. stop accepting new listener work;
4. close the PostgreSQL pool;
5. exit.

A 10-second forced-exit guard prevents indefinite shutdown hangs.

## Central error boundary

The Express app now has:

- explicit JSON 404 handling;
- a final error handler that logs a request-correlated internal diagnostic;
- no stack trace/database-error exposure to clients.

The existing `sendActionError` helper now routes unexpected authoritative
transaction failures through the structured logger.

## Flutter topology integration

The Flutter companion branch now contains a two-parent integration commit:

- canonical backend PR #44 head;
- previous Flutter PR #5 head.

Its tree was constructed from the PR #44 backend plus **only** the 45
Flutter/root-client files changed by PR #5.

Verification against the PR #44 base showed:

- 45 changed client-side files;
- 0 `cold_streets_backend/` files;
- 0 `supabase/` files.

PR #5 was retargeted to:

`stabilization/backend-integration-20261105`

so GitHub review now reflects the actual dependency rather than the historical
security/#4 base.

## Verification boundary

Performed:

- Git ancestry/diff verification;
- exact client-file overlay verification;
- static source readback;
- structured-log privacy review;
- readiness-state logic review;
- graceful-shutdown source review.

Not performed:

- Node startup;
- HTTP liveness/readiness calls;
- database readiness runtime probe;
- worker polling/runtime tests;
- concurrency tests;
- Flutter analyze/build;
- deployment;
- production changes.
