# HTTP + PostgreSQL Operational Hardening — 2026-11-05

## Scope

This pass hardens the canonical Cold Streets Node/PostgreSQL service against
slow clients, connection accumulation, PostgreSQL contention, pool saturation,
and transient infrastructure failure.

It is intentionally non-gameplay work. No game formulas, rewards, costs,
catalog semantics, or settlement rules were changed.

No Node startup, HTTP/API calls, database runtime probes, concurrency/load
tests, Flutter build/analyze, deployment, or production change was performed.

Branch:

`stabilization/http-postgres-hardening-20261105`

Base:

canonical integration PR #44 head
`f8b41ad798700ea67a892480745199f982187fa9`.

## Existing baseline retained

The integration branch already had the following useful limits and they remain:

### HTTP

- JSON request body limit: 64 KiB;
- maximum HTTP header bytes: 16 KiB;
- header receive timeout: 10 seconds;
- request receive timeout: 20 seconds;
- HTTP keep-alive idle timeout: 5 seconds;
- socket inactivity timeout: 30 seconds;
- maximum incoming header count: 100;
- maximum requests per socket: 500;
- Host header required;
- Express `X-Powered-By` disabled;
- ETag disabled;
- explicit browser CORS allowlist.

### PostgreSQL / node-postgres

- pool connection/acquisition timeout: 5 seconds;
- PostgreSQL `statement_timeout`: 15 seconds;
- client query timeout: 20 seconds;
- PostgreSQL `lock_timeout`: 5 seconds;
- PostgreSQL `idle_in_transaction_session_timeout`: 15 seconds;
- idle pooled connection timeout: 30 seconds;
- maximum pool clients: 10;
- maximum connection uses: 5,000;
- maximum connection lifetime: 300 seconds;
- TCP keepalive enabled;
- `application_name = cold-streets-api`.

The statement timeout remains intentionally shorter than the node-postgres
query timeout so PostgreSQL has the first opportunity to cancel expensive work
cleanly.

## PostgreSQL pool exhaustion boundary

node-postgres queues `pool.connect()` calls when all pool clients are checked
out.

The backend now gives that queue an explicit service-level boundary:

- maximum PostgreSQL clients remains 10;
- maximum tolerated queued waiters is 20;
- once all 10 clients are checked out and at least 20 callers are waiting, new
  gameplay HTTP requests are rejected before they can add more application work;
- overload response is HTTP 503;
- overload responses include `Retry-After: 1`;
- overload responses request connection close;
- queue/client counts are logged operationally but are not returned to clients.

`/healthz` remains independent from the database.

`/readyz` now fails immediately when the pool is already saturated rather
than adding another readiness query to the PostgreSQL wait queue.

A pool-saturation readiness failure does not by itself mark PostgreSQL as
permanently unhealthy; readiness is false for that probe and can recover after
load falls.

## Retryable database failure classification

A new shared operational classifier recognizes transient infrastructure cases,
including:

- PostgreSQL connection-class SQLSTATEs (`08xxx`);
- too-many-connections / configuration-limit errors;
- lock timeout/contention;
- statement/query cancellation;
- serialization failures;
- deadlocks;
- PostgreSQL shutdown/cannot-connect states;
- common TCP connection reset/refused/timeout/unreachable failures;
- narrow node-postgres pool/query timeout messages.

For common authoritative action handlers using `sendActionError`, these
conditions now produce:

- HTTP 503;
- `Retry-After: 1`;
- a generic retry message;
- no SQL, host, relation, query, credential, or stack detail in the response.

The final Express error boundary applies the same classification to operational
errors that reach it.

Business-rule failures and programmer/data-integrity failures are not
misclassified as transient operational failures; they retain their existing
4xx/500 semantics.

## HTTP socket/connection hardening

The Node HTTP server now explicitly uses:

- strict HTTP parsing (`insecureHTTPParser: false`);
- TCP keepalive enabled;
- 10-second initial TCP keepalive delay;
- 1-second keep-alive timeout buffer;
- maximum 256 concurrent accepted connections;
- connection dropping at the maximum connection boundary;
- structured warning when the connection cap drops a connection.

The 256-connection ceiling is a conservative pre-load-test safety boundary, not
a final capacity target. It should be revisited only after authorized staging
load/concurrency testing.

## Response security/cache headers

All responses now include the prior no-store/security headers plus:

- `Expires: 0`;
- `X-DNS-Prefetch-Control: off`;
- `X-Permitted-Cross-Domain-Policies: none`;
- `Cross-Origin-Opener-Policy: same-origin`.

The existing API-oriented policy remains:

- `Cache-Control: no-store`;
- `Pragma: no-cache`;
- `X-Content-Type-Options: nosniff`;
- `X-Frame-Options: DENY`;
- `Referrer-Policy: no-referrer`;
- restrictive CSP;
- restrictive Permissions-Policy;
- HSTS only in production.

No `Cross-Origin-Resource-Policy` restriction was added because Cold Streets
may have an explicitly allowlisted browser frontend hosted on another origin.

## Graceful shutdown

The HTTP listener now explicitly closes idle keep-alive connections after
`server.close()`.

The existing forced-shutdown guard is 25 seconds. This is long enough to remain
above the current 20-second client query timeout while still bounding shutdown.

The older observability document said 10 seconds; that documentation was stale
relative to the integration code and is corrected in this branch.

## Residual legacy read-handler behavior

A static scan found several older read-only routes that catch database errors
locally and return a generic HTTP 500 rather than allowing the central
operational classifier to produce a retryable 503.

Examples are in older achievement, City Hall, company-directory, crime-list,
Gym-read and inventory-read handlers.

Those handlers were deliberately not broadly rewritten in this parallel branch
because the separate mutation-contract audit is actively editing route files.
The database failure is still bounded by the PostgreSQL/client timeouts; the
remaining issue is response classification, not an unbounded query.

After the mutation-audit branch is reconciled, these local catch blocks should
be normalized in one low-conflict cleanup pass.

## Source verification

The hardening choices were checked against current upstream documentation:

- Node.js 24 HTTP documentation: request/header timeouts, keep-alive controls,
  max requests per socket and connection behavior;
- Node.js 24 net.Server documentation: maxConnections/drop behavior;
- node-postgres documentation: pool queue behavior, pool counts, connection
  acquisition timeout, statement/query/lock/idle-transaction timeouts.

## Verification performed

Performed:

- static source inspection;
- route catch-pattern scan;
- post-edit source readback;
- timeout ordering review;
- pool saturation/failure-path reasoning;
- security-header review.

Not performed by project instruction:

- Node syntax/startup execution;
- HTTP timeout tests;
- pool-exhaustion tests;
- PostgreSQL timeout/lock tests;
- runtime readiness probes;
- load/concurrency tests;
- Flutter build/analyze;
- deployment;
- production changes.
