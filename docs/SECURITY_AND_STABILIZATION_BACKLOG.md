# Cold Streets — critical-path stabilization backlog

Updated 2026-11-04. This is a **source audit / proposed order**, not a claim that systems have passed testing. No live environment was used.

## Release gates

- **G0 — Reproducible isolated database:** proposed catalog and state schemas reviewed; private catalog dump imported with row counts; missing seeds obtained or recreated; no player data lost.
- **G1 — Authorized identity:** every state-changing and player-specific API endpoint verifies an authenticated account ID on the backend. A client-supplied `user_id` must never authorize itself.
- **G2 — Economic integrity:** financial, inventory, reward, timer and transfer actions validate server-side price/eligibility and are atomic, replay-safe and concurrency-safe.
- **G3 — Playable core:** one account can use tutorial → crimes → gym → inventory/market → level progression, and state persists after relogin.
- **G4 — Feature audit:** each visible menu action is either implemented and validated or explicitly marked planned.

No gate is currently verified complete.

## Module order and source findings

| Order | Area | Current source / issue to address |
| --- | --- | --- |
| P0-1 | Database recovery | Recovered SQL is data-only, with invalid pseudo-JSON in several catalogs and missing state DDL. Proposed migrations are on separate draft PR. |
| P0-2 | Auth and account ownership | `routes/auth.js` uses password comparison but returns user data without a signed session; state routes trust client-provided IDs. Map Supabase Auth UUID to internal player ID, verify token and resolve actor on server. |
| P0-3 | Banking | Deposits and pending-check payouts were not transactional, and PostgreSQL NUMERIC operations were unsafe. Draft transaction fix is in separate PR; still not authenticated or tested. |
| P0-4 | Market & inventory | Validate bulk purchase quantities, server prices, stock reservation, inventory eligibility and response consistency. Verify `ON CONFLICT(user_id,item_id)` index in restored schema. |
| P0-5 | Casino | Protect slots, high/low and perya bet placement and payout with authoritative RNG, row locks, one-time settlement and audit ledger. Rate limit spins and guard against repeated cashout. |
| P0-6 | Missions/tutorial | `/missions/action` allows VERIFY without authoritative objective completion; Kevin turn-in similarly needs progress validation and one-time reward ledger. |
| P0-7 | Companies & properties | Reject client-authorized upgrade costs/stock orders. Transactions, director permissions, property sales, and ownership transfers require server enforcement and audit continuity. |
| P0-8 | Syndicate recruits | Hiring and passive job payouts trust client-supplied recruit values and claimed payout amounts. Server must issue offer IDs and calculate rewards. |
| P1-1 | Job/interview progression | Data has four requirement columns, while promotion code selects `stat_req_value`; job ID mapping conflicts with hospital logic. Resolve intended requirements with design references. |
| P1-2 | University & gym | Course rewards stored as pseudo-JSON, while graduate logic expects scalar rewards. Gym seed script has mismatched columns and destructive TRUNCATE. |
| P1-3 | Crimes, jail, hospital | Check crime catalog requirements against each engine, control heat/resource updates and cooldowns; avoid multi-claim and conflicting custody statuses. |
| P1-4 | Game timers & server | `server.js` uses in-process test cadence for health/resource regeneration and restocking. Introduce one authoritative idempotent scheduled mechanism before using multiple instances. |
| P1-5 | Achievements & Credit Broker | Audit achievement tracker mappings, one-time unlock rewards and absent broker upgrade purchase path. |
| P1-6 | City Hall, Info Broker, Events | Verify rows and permissions; bounties/classifieds need cost checks and ownership validation. City grants/policies source data is empty. |
| P1-7 | Flutter app | Update API base URL for remote staging, route widgets to verified sessions, and align client data parsers with database NUMERIC/JSON fields. |
| P2 | Expanded gameplay | PvP wars, politics, airports, full stock market and advanced multiplayer remain future systems. Do not confuse design documents with implemented features. |

## Proposed Supabase Auth integration

1. Create a private development Supabase project and configure a server-only database connection using environment secrets.
2. Use Supabase Auth for user identity. Preserve internal integer player IDs by mapping `auth.users.id` (UUID) to `public.users.supabase_auth_uid`; do not renumber accounts or expose service credentials in Flutter.
3. When the user signs in, send a valid bearer access token to Node.js. **Verify its signature, issuer, audience and expiry** with supported Supabase tooling; do not decode an unverified JWT as proof of identity.
4. Node.js resolves the internal user record for the verified UUID. Put the trusted ID on the request context. For every route, replace or check body/query/path `user_id` or `userId` against that trusted ID.
5. Distinguish the acting player from intentional targets (`target_user_id`, `company_id`, property ID, crew ID), checking target ownership and actor permissions separately.
6. Guard all player state reads, writes, game rewards, money transfers and private assets. Add negative tests later: user A must not read/mutate user B or cause duplicate reward claims.
7. Keep RLS deny-by-default on gameplay tables unless a specific direct-client read is documented; never use Supabase service-role credentials in the Flutter app.

Do not deploy the original unauthenticated backend to an internet-reachable URL.

## Working agreement until testing resumes

- Draft PRs for source changes; do not merge or deploy without review.
- Keep SQL catalog dump, passwords, credentials and player records out of public GitHub.
- No destructive database operations against old game data.
- Record implementation status separately from design intent; `code exists` is not equivalent to `feature works`.
- In a later test phase, run database import checks, backend route/concurrency tests, Flutter analyze/widget tests and first-player gameplay walkthrough.
