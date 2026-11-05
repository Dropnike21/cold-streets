# Repository / Route Closure Audit — 2026-11-05

## Scope

Final static repository closure pass for the canonical Cold Streets backend.

No Node startup, API/runtime test, Flutter build/analyze, concurrency test,
deployment, or production change was performed.

## Canonical branches

Backend:

- draft PR #44;
- `stabilization/backend-integration-20261105`.

Flutter companion:

- draft PR #5;
- `feature/flutter-supabase-auth-20261104`;
- based on the canonical backend stabilization branch.

## Mutation-route closure

The route surface remains 72 POST endpoints.

Central mutation registry classification:

- active/read-preflight contracts: 35;
- explicitly paused/legacy contracts: 37;
- unclassified POST endpoints: 0.

No gameplay PUT/PATCH/DELETE handlers are present in the current route stack.

Every active POST route has an exact top-level body allowlist and rejects
mutation query parameters.

Recently reclassified from active to paused after authoritative source review:

- City Job resignation;
- crew crime assignment;
- recruit board generation;
- recruit hiring.

Those routes remain defined so clients receive a deliberate 503 rather than a
404, but their former settlement logic is no longer executable.

## Dormant-code closure

The final pass removed or hard-failed code that would have been dangerous if a
future middleware/mount refactor accidentally reactivated it.

### Retired

- legacy Vital regeneration timer;
- legacy market restock timer;
- destructive Gym seeder;
- legacy Casino Perya settlement;
- legacy Casino Slots settlement;
- legacy Casino High-Low settlement;
- legacy mixed Casino wager helper;
- Pickpocket client-activity settlement engine;
- company pricing writer;
- company advertising writer;
- recruit generator implementation whose ranges/pricing conflict with source;
- crew crime payout worker whose timing/mortality semantics conflict with source.

### Retained fail-closed

- `workers/crewCrimeWorker.js` exists only as an explicit error boundary and is
  not imported/started by `server.js`;
- legacy Casino child routers return 503 even if mounted later;
- `seed_gyms.js` throws immediately;
- unsupported property, Bank, Trade, Casino, Jail, premium, bounty, Credit
  Broker, company and Syndicate settlement endpoints return 410/503.

## Background writer ownership

Only one authoritative polling writer remains enabled:

- State Duration worker.

It owns persisted Jail/Hospital episode expiry and duration achievement refresh.

Crew crime automation is no longer a runtime worker because the recovered
Recruits Canvas conflicts with per-crime automation metadata.

## Randomness and logging

Final runtime-source scan:

- `Math.random`: 0;
- ad-hoc `console.log/warn/error` in runtime backend: 0;
- polling loops outside the State Duration worker: 0.

The standalone `scripts/release_preflight.js` intentionally uses console output
because it is a CLI validation command, not server runtime logging.

Gameplay randomness that remains active uses `node:crypto`.

## Actor and client-authority boundary

No active mutation body uses a client-supplied `user_id` as actor identity.

The authenticated actor is derived from the verified Supabase session.

Client-supplied resource IDs are intent only and are re-authorized/resolved
server-side.

Catalog aliases that could select authoritative rules by mutable text have been
removed where discovered; for example crew crime assignment no longer supports
crime-title lookup.

## HTTP / database operational boundary

The canonical backend also includes:

- Node 24 runtime contract;
- strict JSON/body size limits;
- HTTP header/request/socket timeouts;
- no-store/security headers;
- DB statement/query/lock/idle-transaction timeouts;
- bounded pool acquisition and pool backpressure;
- request correlation and structured logs;
- liveness/readiness separation;
- graceful shutdown.

## Result

No known unsafe legacy writer, duplicate runtime mutation timer, client-selected
actor identity, unclassified POST route, insecure RNG call, or accidentally
mountable legacy Casino/Pickpocket settlement engine remains in the canonical
static backend baseline.

Runtime behavior still requires an explicitly authorized test pass before
release.
