# Cold Streets Production Monitoring Checklist — 2026-11-05

## Purpose

This checklist defines the minimum operational telemetry to establish before
production gameplay traffic is enabled.

Thresholds below are initial operational defaults to validate in staging, not
game-mechanics rules.

## Availability

Monitor separately:

- process liveness (`/healthz`);
- traffic readiness (`/readyz`);
- HTTP request success/error rate.

Alert candidates:

- any instance failing liveness repeatedly;
- readiness 503 for two or more consecutive probe intervals;
- all replicas unready;
- repeated process restart/crash loop.

Do not treat liveness success as proof that gameplay dependencies are healthy.

## HTTP outcomes

Dashboard by:

- route template;
- status class;
- latency percentiles;
- request volume.

At minimum distinguish:

- 2xx;
- expected 4xx;
- 409 business/state conflicts;
- 429 if introduced later;
- 503 dependency/backpressure/paused behavior;
- 5xx unexpected failures.

Initial alert candidates:

- unexpected 5xx > 1% over 5 minutes;
- sustained gameplay 503 above normal maintenance/paused-route baseline;
- sharp latency increase near the 15–20 second DB/request bounds.

Paused mechanics intentionally returning 503 must be separable from operational
503s in dashboards, preferably by route.

## Structured log events

Track counts for at least:

- `unhandled_request_error`;
- `action_failed`;
- `auth_verification_failed`;
- `auth_upstream_backpressure`;
- `player_identity_lookup_failed`;
- `state_gatekeeper_failed`;
- `database_bootstrap_failed`;
- `database_pool_error`;
- `readiness_database_probe_failed`;
- `database_pool_backpressure`;
- `worker_poll_failed`;
- `worker_rollback_failed`;
- `uncaught_exception`;
- `unhandled_rejection`;
- `shutdown_forced`.

Any recurring uncaught exception/unhandled rejection is release-blocking.

Logs must remain free of:

- access tokens;
- Authorization headers;
- request bodies;
- passwords/secrets;
- raw emails/Auth UUIDs;
- raw player IDs in access logs.

## PostgreSQL pool

Expose/collect through application telemetry or infrastructure tooling:

- total clients;
- idle clients;
- waiting callers;
- acquisition failures/timeouts;
- connection errors.

Source-level backpressure currently rejects new gameplay work at:

`waitingCount >= 20`

Operational warning should occur well before that threshold, for example sustained
queue depth >= 10, so operators have time to investigate.

Do not immediately raise pool size as the first response; inspect slow queries,
locks and database capacity first.

## PostgreSQL execution

Monitor:

- statement cancellations/timeouts;
- lock wait/timeout events;
- idle-in-transaction termination;
- slow queries;
- deadlocks;
- connection churn.

Investigate any query regularly approaching:

- 5 s lock timeout;
- 15 s statement timeout;
- 20 s client query timeout.

No gameplay path should rely on routinely hitting a timeout for flow control.

## Supabase Auth dependency

Monitor:

- verification latency;
- non-2xx upstream responses;
- 10-second verification timeouts;
- `auth_upstream_backpressure` events;
- local in-flight verification saturation.

The current per-process ceiling is 50 concurrent Auth verifications.

Sustained saturation indicates either:

- upstream degradation;
- traffic spike/abuse;
- insufficient replica capacity;
- overly frequent client reauthentication.

## State Duration worker

Monitor:

- started/healthy state;
- poll failures;
- rollback failures;
- last successful poll age;
- settlements per interval.

Readiness already goes false when the worker is unhealthy.

An increasing backlog of due `user_state_episodes` despite healthy polling
should be treated as a settlement incident.

The Crew Crime worker is intentionally disabled and should not appear as active
production work.

## Idempotency / economic safety

Operational diagnostics should track:

- idempotency conflicts/hash mismatches;
- replay counts;
- settlement failures after idempotency reservation;
- unexpected ledger invariant errors.

Never alert solely on a high replay count without context—mobile retries are
expected—but a sudden change can indicate client/network regressions.

## Database security boundary

Periodically verify:

- RLS still enabled for exposed public tables;
- anon/authenticated direct grants remain absent;
- public function execution remains revoked;
- no new SECURITY DEFINER API surface appears unexpectedly.

Run Supabase security advisors as part of release/change review.

## Process / container

Monitor:

- CPU;
- RSS/heap;
- event-loop lag if added;
- open connections/sockets;
- restart count;
- termination duration.

A shutdown that reaches `shutdown_forced` is an incident even if the
orchestrator eventually replaces the process.

## Capacity / overload staging test

Before setting production alert thresholds, an authorized staging load test
should establish:

- normal request latency distribution;
- DB queue depth at expected concurrency;
- Auth verification concurrency;
- memory behavior;
- point where application backpressure begins;
- recovery after load is removed.

Production limits should be based on this observed envelope.

## Dashboard minimum

Recommended first dashboard panels:

1. ready replicas / total replicas;
2. request rate and p50/p95/p99 latency;
3. 4xx/503/5xx rate;
4. DB pool total/idle/waiting;
5. DB timeout/lock/deadlock events;
6. Supabase Auth latency/failures/backpressure;
7. State Duration worker health/failures/backlog;
8. process restarts and forced shutdowns.

## Ownership

Before production, assign a human/operator owner for:

- release approval;
- database/migration incidents;
- Auth/Supabase incidents;
- gameplay economy incidents;
- rollback decision.

Monitoring without an explicit response owner is not a complete operational
control.
