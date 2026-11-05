# HTTP / PostgreSQL Operational Hardening — 2026-11-05

## Scope

This pass bounds transport, request, database, lock, transaction, and pool
failure modes for the canonical Node backend.

No server startup, health-call runtime test, DB load test, concurrency test,
Flutter build/analyze, deployment, or production change was performed.

## Runtime generation

The backend now declares:

`node >=24 <25`

The container already tracks the Node 24 Bookworm-slim line.

The release preflight now fails when executed under a Node major other than 24.

## HTTP parser / socket boundaries

The listener now uses explicit `node:http.createServer` options rather than
implicit `app.listen` defaults.

Configured boundaries:

- maximum request-header bytes: 16 KiB;
- maximum header count: 100;
- header receive timeout: 10 seconds;
- complete request receive timeout: 20 seconds;
- socket inactivity timeout: 30 seconds;
- keep-alive idle timeout: 5 seconds;
- maximum requests per socket: 500;
- HTTP/1.1 Host header required.

The JSON parser remains capped at 64 KiB and now explicitly accepts only JSON
media types with strict object/array JSON syntax.

The Express query parser is explicitly set to simple mode.

## Response hardening

The API disables:

- Express `X-Powered-By`;
- ETag generation.

Responses set:

- `Cache-Control: no-store`;
- `Pragma: no-cache`;
- `X-Content-Type-Options: nosniff`;
- `X-Frame-Options: DENY`;
- `Referrer-Policy: no-referrer`;
- restrictive Content-Security-Policy;
- Permissions-Policy disabling camera/microphone/geolocation;
- HSTS in production.

CORS is explicitly limited to:

- GET;
- POST;
- OPTIONS;
- configured exact browser origins;
- known API headers.

Bearer authentication remains header-based; CORS credentials/cookies are not
enabled.

## PostgreSQL client boundaries

The `pg` pool now configures:

- max clients: 10;
- connection/pool acquisition timeout: 5 seconds;
- PostgreSQL statement timeout: 15 seconds;
- client query timeout: 20 seconds;
- PostgreSQL lock timeout: 5 seconds;
- idle-in-transaction session timeout: 15 seconds;
- idle pooled-client timeout: 30 seconds;
- maximum client uses before rotation: 5,000;
- maximum pooled connection lifetime: 300 seconds;
- TCP keepalive enabled;
- application_name: `cold-streets-api`.

The server-side statement timeout is intentionally shorter than the client query
timeout so PostgreSQL can cancel long work before the Node client gives up.

## Readiness probe

The readiness DB check now acquires a real pooled client and performs a tiny
transaction with tighter local settings:

- statement timeout: 2 seconds;
- lock timeout: 1 second;
- `SELECT 1`;
- ROLLBACK;
- release client.

A failed acquisition/probe marks database readiness false.

The probe no longer relies on an unsupported per-query `query_timeout` field.

## Pool backpressure

node-postgres exposes the number of callers queued waiting for a client.

Before authentication/gameplay handling, the API now rejects new gameplay work
when:

`pool.waitingCount >= 20`

Response:

- HTTP 503;
- `Retry-After: 1`;
- generic busy message.

The structured log records only pool counts and request correlation ID.

Health/readiness endpoints remain outside this gameplay backpressure middleware.

## Graceful shutdown alignment

The forced-shutdown guard was extended from 10 to 25 seconds.

That gives in-flight PostgreSQL work enough time to hit the configured
15-second statement / 20-second query bounds before the process is force-killed.

Normal shutdown still:

1. marks readiness false;
2. stops workers;
3. closes the listener;
4. drains/closes the DB pool;
5. exits.

## Release preflight additions

The non-network release preflight now validates:

- Node major 24;
- PORT and DB_PORT integer range 1..65535;
- DB_SSL is exactly true/false when supplied;
- every CORS entry is a bare http(s) origin;
- no wildcard CORS origin;
- existing Supabase/DB/gameplay safety checks.

The script was updated only; it was not executed.

## Operational rationale

The backend now has bounded behavior for:

- slow request headers/bodies;
- oversized headers/JSON;
- idle sockets;
- endlessly reused keep-alive sockets;
- DB connection acquisition;
- long SQL statements;
- lock waits;
- abandoned transactions;
- stale pooled connections;
- saturated DB request queues.

These boundaries are independent from unresolved gameplay mechanics.


## External authentication boundary

Supabase Auth token verification is the only runtime outbound HTTP dependency.

It is bounded by:

- 10-second AbortSignal timeout per verification;
- maximum 50 concurrent verification calls per Node process;
- HTTP 503 + `Retry-After: 1` when that local concurrency ceiling is reached.

The access token is never logged.

A backend-wide source scan found no other runtime `fetch()` or
`http(s).request/get` call.

## Runtime configuration enforcement

Critical security settings are now validated by the runtime itself, not only by
the optional preflight script.

`db.js` rejects:

- non-integer/out-of-range DB_PORT;
- DB_SSL values other than exact `true`/`false`;
- any production PostgreSQL configuration that would disable TLS.

`server.js` rejects:

- malformed PORT;
- malformed ENABLE_GAMEPLAY_API values;
- any configured legacy timer flag;
- malformed CORS origins;
- malformed/non-HTTPS Supabase project origins;
- secret/service-role keys in the publishable-key slot.

Production browser CORS origins are also required to be HTTPS by the release
preflight.

## Bootstrap recovery

A transient PostgreSQL outage during process start no longer requires a manual
restart.

When gameplay is enabled:

1. initial DB acquisition is attempted;
2. failure marks database readiness false;
3. the gameplay runtime remains unstarted;
4. bootstrap is retried every 5 seconds;
5. once DB acquisition succeeds, the State Duration worker starts exactly once;
6. readiness can then become healthy.

The retry timer is cancelled during graceful shutdown.

The Crew Crime worker remains deliberately disabled because its mechanics are
source-conflicted.

## Final operational source scan

Backend JavaScript scan:

- PostgreSQL Pool constructors: 1 (`db.js`);
- runtime outbound HTTP calls: 1 (Supabase Auth);
- enabled polling loops: 1 (State Duration worker);
- ad-hoc runtime `console.*`: 0;
- legacy mutable timers: 0.

The only `console.*` calls remaining are in the operator-invoked release
preflight script.

## Static closeout

At source level, every identified network/database wait now has a bounded
failure path or explicit backpressure boundary.

Remaining verification requires actually running the process/load/concurrency
tests described in `RUNTIME_VERIFICATION_PLAN_20261105.md`; those tests were
not authorized or executed in this phase.
