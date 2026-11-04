# Cold Streets — Private Node staging packaging and safety gates

**Status: prepared on GitHub; NOT deployed, NOT tested and NOT merged.**  
Working date: 2026-11-05 (Asia/Manila). This branch stacks on security PR #4.

## Why this is necessary

Supabase supplies managed PostgreSQL and authentication but **does not host our existing Express game server** by itself. That server must eventually run on a private Node-capable hosting platform. We do not have a selected hosting provider, private host configuration, or database credential provisioned here.

The original `server.js` automatically ran a 30-second vital regeneration timer and a 60-second item restocking timer at startup. Connecting that code to the recovered database would modify catalog stock and player data. These timers are not multi-instance-safe and are unacceptable as default hosted behavior.

## Changes in this branch

- **API deny-by-default:** `ENABLE_GAMEPLAY_API=false` (default) causes every application route, including `POST /auth/session`, to return HTTP 503. The only unauthenticated liveness endpoint is `GET /healthz`, which returns a static status and exposes no database details.
- **Legacy background timers disabled:** the two existing `setInterval` jobs run only with `ENABLE_GAMEPLAY_API=true`, `ENABLE_UNSAFE_LEGACY_TIMERS=true`, and `NODE_ENV != production`. A production Node container can never activate them. Replace with idempotent database-backed scheduling after security review.
- **Configuration preflight:** when an operator explicitly enables application routes, the server refuses to start if database or Supabase Auth configuration is missing. It also rejects `DB_SSL=false` in production.
- **Non-root packaging:** `cold_streets_backend/Dockerfile` packages Node 24 + `npm ci --omit=dev` with `node` user and disables the application routes and legacy timers by default.
- **Secret exclusion:** `cold_streets_backend/.dockerignore` excludes `.env`, key material, raw SQL, backups and local modules from the image context.
- **Example settings:** `.env.example` documents private Supabase DB connection and safety flags, with placeholders only.

## Recommended future host configuration

For a persistent Node.js server without IPv6 connectivity, Supabase recommends the **shared session pooler**, port **5432**. Its hostname must be copied from the project's **Connect** dialog, not guessed from its geographic region. The DB username for the shared pooler is `postgres.PROJECT_REF`, not simply `postgres`. Configure TLS certificate verification, and supply the relevant CA certificate if required by the host.

Provide these server-side environment variables through the hosting provider's secret manager, **not GitHub or Flutter**:

```dotenv
NODE_ENV=production
PORT=3000
ENABLE_GAMEPLAY_API=false
ENABLE_UNSAFE_LEGACY_TIMERS=false
SUPABASE_URL=https://YOUR_PROJECT_REF.supabase.co
SUPABASE_PUBLISHABLE_KEY=sb_publishable_REPLACE
DB_HOST=PASTE_EXACT_SESSION_POOLER_HOST
DB_PORT=5432
DB_NAME=postgres
DB_USER=postgres.YOUR_PROJECT_REF
DB_PASSWORD=FROM_PRIVATE_SECRET_STORE_ONLY
DB_SSL=true
CORS_ALLOWED_ORIGINS=
```

The Flutter client will eventually use the Node server's HTTPS base URL (not the Supabase URL) and a **public** Supabase publishable key. No `service_role`, `sb_secret_` or DB password is ever part of the Flutter build.

**Deployment remains withheld.** Even after a hosting provider is chosen, this draft requires explicit API enablement, private networking, verified Auth token and resource ownership rules, banking and casino integrity fixes, rate limiting, and security/integration verification before access from untrusted clients.

## Recorded database state

- Supabase development project: `Cold-streets` (`qbrntyrlzxhilwrbcriq`), PostgreSQL 17.
- **All 2,093 recovered game-catalog records now loaded**, with row counts matching the original private SQL dump (18 source tables, including 3 intentionally empty tables).
- The 14 populated reconstructed catalog identity sequences were synchronized to the maximum restored source ID; e.g. last item ID 731 and last mission ID 11. Do not presume IDs are contiguous.
- 53 tables have RLS enabled; direct anonymous/authenticated access remains disallowed. The 53 `rls_enabled_no_policy` INFO notices are intentional; there are zero unvalidated public foreign keys.
- **Original PostgreSQL schema, original player data, and missing company positions/specials/blueprint relationship rows are NOT recovered.** Catalog recovery is not full application restoration.

## Review gates

1. Merge and validate schema reconstruction PR #2, then account security PR #4 (source-side review) and Flutter PR #5 (stacked on #4).
2. Select a private Node host; set the exact pooler connection, TLS and server environment secrets.
3. Implement an idempotent scheduled worker; do not re-enable in-process legacy ticks in hosted mode.
4. Secure company/property/casino/mission resource authorization and money/reward mutation endpoints. See banking PR #3.
5. When tests are authorized, run isolated authenticated-account tests, DB constraints, API requests, Flutter builds, and economic concurrency tests before enabling gameplay routes.

There are no deployed services or public gameplay endpoints from this branch.
