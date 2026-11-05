# Cold Streets Operational Stabilization Closeout — 2026-11-05

## Status

**HTTP / PostgreSQL / release-operations static stabilization: CLOSED**

This is the operational counterpart to
`STABILIZATION_MASTER_CLOSEOUT_20261105.md`.

No runtime/build/concurrency/deployment testing was performed.

## Completed

### HTTP

- Node 24 runtime contract;
- bounded headers/request/socket/keep-alive behavior;
- strict JSON size/media-type handling;
- simple query parsing;
- explicit CORS allowlist;
- no-store/security headers;
- request correlation and structured access/error logs;
- graceful shutdown.

### External dependency

Supabase Auth is the only runtime outbound HTTP call.

It has:

- 10-second timeout;
- 50 in-flight calls/process cap;
- local overload 503 + Retry-After;
- no credential logging.

### PostgreSQL

Single shared pool only.

Bounded:

- acquisition;
- statements;
- client queries;
- lock waits;
- idle transactions;
- connection lifetime/reuse.

Includes:

- pool queue backpressure;
- bounded readiness probe;
- pool failure telemetry;
- TLS enforcement in production;
- runtime validation of DB_SSL and DB_PORT.

### Startup/recovery

- gameplay disabled by default;
- critical configuration validated at startup;
- failed DB bootstrap leaves readiness false;
- automatic 5-second bootstrap retry;
- State Duration worker starts once after DB recovery;
- retry cancelled on shutdown;
- Crew Crime worker remains disabled.

### Release

- deterministic npm lockfile install;
- release preflight;
- migration history/source aligned;
- canonical operator runbook;
- monitoring checklist;
- future runtime verification plan.

## Final operational source scan

- backend JS files scanned: 58;
- PostgreSQL pools: 1;
- runtime outbound HTTP call sites: 1;
- enabled polling loops: 1;
- mutable legacy timers: 0;
- runtime ad-hoc console logging: 0.

The remaining console output is limited to the explicit operator preflight
script.

## Remaining work is not static stabilization

The following are intentionally outside the completed source-only phase:

1. execute the runtime verification plan;
2. select the populated-database unique-item baseline policy;
3. decide gameplay mechanics in the mechanics decision register;
4. deploy only after authorized verification.

No additional gameplay feature should be enabled merely to make the project
look more complete.

## Handoff files

- `STABILIZATION_MASTER_CLOSEOUT_20261105.md`
- `MECHANICS_DECISIONS_REQUIRED_20261105.md`
- `HTTP_POSTGRES_OPERATIONAL_HARDENING_20261105.md`
- `OPERATIONAL_RELEASE_RUNBOOK_20261105.md`
- `PRODUCTION_MONITORING_CHECKLIST_20261105.md`
- `RUNTIME_VERIFICATION_PLAN_20261105.md`

Together these define the completed static baseline and the next authorized
phase.
