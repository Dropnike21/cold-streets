# Cold Streets — Supabase Auth & Player Ownership (P0 security draft)

**Status: SOURCE CODE COMMITTED; NOT MERGED, NOT DEPLOYED, NOT TESTED.**
**Date: 2026-11-04**

## Security problem in the original backend

The previous `/auth/login` checked a bcrypt password, returned a player JSON object and did **not** issue a trusted bearer token. Subsequent endpoints trusted a client-supplied `user_id` / `userId`; any client could send another player's ID. Even the previous jail/hospital state gatekeeper resolved state from the untrusted request ID, and skipped GET requests when route parameters were not parsed yet.

**This was an account-takeover / broken-object-level-authorization (BOLA) risk.**

## What this branch implements

- `middleware/playerIdentity.js` checks `Authorization: Bearer <supabase_access_token>` against the project's **Supabase Auth `GET /auth/v1/user`** endpoint using a **publishable** API key. It rejects missing/invalid/expired tokens, disallows anonymous identities, and fails closed if the Auth service/configuration is unavailable. No custom JWT verification code or shared JWT secret is used.
- The verified `auth.users.id` UUID is resolved to `public.users.supabase_auth_uid`. Only the matching internal player ID is permitted for that request; account IDs in JSON bodies and query strings are treated as consistency checks, **never** as authentication.
- Route parameter guards on every current `/:user_id` and `/:userId` player URL reject references to another account. These callbacks run after Express route matching.
- All existing gameplay routers are behind mandatory auth **including** the formerly unguarded inventory, bank, jail, hospital, events, missions, achievements and info-broker routes.
- `utils/stateGatekeeper.js` checks the authenticated player's jail/hospital timers, never a caller-supplied ID.
- `/auth/register` and `/auth/login` return HTTP 410. **Legacy password auth is disabled** to prevent creating a second insecure path.
- `POST /auth/session` accepts a *verified* Supabase bearer token. It returns an existing mapped player profile, or creates a new integer-ID profile and starter state inside a PostgreSQL transaction when supplied a valid `username`. Email comes from Supabase Auth, not request data. Existing legacy accounts with matching emails are **not** silently claimed.
- Company recruit assign/recall now require a director role and recruit ownership, including for the recall endpoint that previously had no acting-player ID.
- Remote PostgreSQL connections support verified TLS (`DB_SSL=true`), and browser CORS origins are allowlisted. **CORS is not a substitute for authorization.**

## Required runtime configuration (server-only)

Copy `cold_streets_backend/.env.example` to a **private** hosting environment:

- `SUPABASE_URL`: `https://YOUR_PROJECT_REF.supabase.co` — the project issuing Auth sessions.
- `SUPABASE_PUBLISHABLE_KEY`: public key for the project's Auth API. Never substitute `service_role` / secret keys.
- `DB_HOST`, `DB_PORT`, `DB_NAME`, `DB_USER`, `DB_PASSWORD`, `DB_SSL=true`: private connection to the **same** project's PostgreSQL database.
- `CORS_ALLOWED_ORIGINS`: comma-separated list of permitted browser origins. Native Flutter normally has no Origin header.

**Do not use a Supabase secret/service-role key in a Flutter app or repository.** The Node database connection itself is privileged and must be protected against public exposure.

## Client flow required before merging

The current Flutter `lib/views/auth_view.dart` still calls the old API password endpoints, and the existing views send requests without bearer tokens. **This branch will intentionally cause those requests to fail. Do NOT merge until the client has been migrated.**

A later Flutter branch must:

1. Add a maintained `supabase_flutter` dependency, update `pubspec.lock`, and initialize the Supabase project using its URL and **publishable** key. Never put database passwords or secret API keys in Flutter.
2. Register via Supabase Auth email/password (respecting email confirmation). Log in with Supabase Auth — initial supported login identifier will be **email**; street-name / numeric-ID login requires a deliberately secured lookup design later.
3. Call `POST /auth/session` with `Authorization: Bearer <access_token>` and chosen `username` on first signup, or without the username for an existing mapped player.
4. Send the current, refreshable access token with **every** game API request. Handle token refresh/expiry and sign-out using the SDK; do not persist plain passwords or long-lived bearer tokens in insecure preferences.
5. Confirm signup, session restoration, switch-account behavior and authenticated gameplay with integration tests before merging.

## Unresolved risks (not solved by this branch)

- **Target resource authorization:** `company_id`, `crew_id`, `target_id`, `application_id`, `instanceId`, `item_id`, etc. remain separate permissions. A valid user token only proves the acting player; it does **not** authorize arbitrary resources. The team must audit each route, especially company management, properties and cross-player actions.
- **Unsafe economics:** market, casino, recruit jobs, mission verification, company and property transactions still include client-controlled price/reward/progress fields or missing transactional guarantees. Keep public API closed. Bank stabilization is in a separate draft PR.
- **Incomplete data:** The development schema is reconstructed, not the original DDL. Only 437 of 2,093 recovered catalog rows were imported in the last verified recovery pass. The gym #1 grant is conditional on that catalog row existing.
- **Legacy accounts:** Never link an old password account solely because an Auth identity has the same email; require explicit verified migration procedures and preserve legacy IDs.
- **No gameplay testing yet:** No API, Flutter, concurrency or Supabase Auth sign-in requests were executed during this branch's implementation. Code review, provider configuration, rate limiting, validation and security testing are release gates.
- **Session revocation semantics:** Supabase Auth validates current tokens on each call; for immediate strict revocation requirements, review `auth.sessions` session-ID validation policies and token expiry.
- **HTTP rate limits:** Add per-IP and per-identity rate limits to signup and high-value game actions before public deployment. CORS does not block non-browser clients.

## Deferred verification matrix

| Scenario | Expected outcome |
| --- | --- |
| No bearer token / malformed bearer | 401 on every gameplay API |
| Supabase Auth key or Auth service missing | Fail closed, 503 |
| Valid bearer token, no player mapping | 403 asking to create profile |
| Valid bearer, mismatched body/query `user_id` / `userId` | 403 |
| Valid bearer, mismatched URL `/:user_id` / `/:userId` | 403 |
| Verified user attempts to recall another player's recruit | Denied |
| User is jailed and calls restricted GET without user ID | Gatekeeper blocks |
| Signed-in new identity creates a profile | Atomic starter records, only once |
| Legacy email conflict with new Supabase account | No automatic takeover |
| Auth token expired or signed out | Denied according to Supabase Auth/session policy |
| Expired/cancelled client session during multi-step purchase | No unauthorized charge or item transfer |

## Branch dependencies and rollout

- **Database:** development Supabase already contains 53 reconstructed tables and `users.supabase_auth_uid` referencing `auth.users(id)`. No SQL migrations are executed by this PR.
- **Code:** this branch is based on `main` and can be reviewed independently of draft schema PR #2 and bank PR #3. It expects the new database schema when eventually deployed.
- **Deployment:** none. There is currently no public game server or Flutter build configured for verified Supabase sessions. Keep this PR draft and retain all existing `main` behavior for now.
