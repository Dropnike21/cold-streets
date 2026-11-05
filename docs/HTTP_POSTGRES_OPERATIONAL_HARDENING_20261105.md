# HTTP / PostgreSQL Operational Hardening — 2026-11-05

## Scope

This pass bounds transport, request, database, lock, transaction, and pool
failure modes for the canonical Node backend.

No server startup, health-call runtime test, DB load test, concurrency test,
Flutter build/analyze, deployment, or production change was performed.

## Runtime generation

The backend now declares:

`node >=24.6 <25`

The container already tracks the Node 24 Bookworm-slim line.

The release preflight now fails below Node 24.6 or on a Node major other than 24.

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
- keep-alive timeout buffer: 1 second;
- TCP keepalive enabled with a 10-second initial delay;
- maximum requests per socket: 500;
- maximum accepted connections: 256;
- strict HTTP parser explicitly retained;
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
- `Expires: 0`;
- `X-Content-Type-Options: nosniff`;
- `X-DNS-Prefetch-Control: off`;
- `X-Permitted-Cross-Domain-Policies: none`;
- `Cross-Origin-Opener-Policy: same-origin`;
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

When the PostgreSQL pool already has at least 20 queued waiters, readiness now
fails immediately instead of enqueueing another probe. That saturation result
makes the current readiness response 503 without falsely treating the database
itself as permanently failed.

The probe no longer relies on an unsupported per-query `query_timeout` field.

## Pool backpressure

node-postgres exposes the number of callers queued waiting for a client.

Before authentication/gameplay handling, the API now rejects new gameplay work
when:

`pool.waitingCount >= 20`

Response:

- HTTP 503;
- `Retry-After: 1`;
- `Connection: close`;
- generic busy message.

The structured log records only pool counts and request correlation ID.

`/healthz` remains independent of PostgreSQL. `/readyz` stays outside the
middleware but performs the same saturation check before attempting a DB
connection.

## Retryable PostgreSQL / network failure classification

Transient infrastructure errors are now classified centrally rather than being
returned as undifferentiated transaction failures.

The shared classifier recognizes:

- PostgreSQL connection-class SQLSTATEs;
- too-many-connections/configuration-limit failures;
- lock timeout/contention;
- statement/query cancellation;
- serialization failures and deadlocks;
- PostgreSQL shutdown/cannot-connect states;
- common TCP reset/refused/timeout/unreachable errors;
- narrow node-postgres acquisition/query timeout messages.

Authoritative handlers that use `sendActionError`, plus the final Express error
boundary, now return HTTP 503 with `Retry-After: 1` and a generic retry message
for those transient failures. SQL text, host information, relation names,
credentials, and stack details remain server-side.

Business-rule failures and non-transient programming/data-integrity failures are
not converted into retryable 503s.

## Graceful shutdown alignment

The forced-shutdown guard was extended from 10 to 25 seconds.

That gives in-flight PostgreSQL work enough time to hit the configured
15-second statement / 20-second query bounds before the process is force-killed.

Normal shutdown still:

1. marks readiness false;
2. stops workers;
3. closes the listener and explicitly closes idle keep-alive connections;
4. drains/closes the DB pool;
5. exits.

## Release preflight additions

The non-network release preflight now validates:

- Node >=24.6 and <25;
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
- saturated DB request queues;
- transient PostgreSQL/network failures with explicit retry semantics;
- excessive accepted TCP connections.

These boundaries are independent from unresolved gameplay mechanics.
