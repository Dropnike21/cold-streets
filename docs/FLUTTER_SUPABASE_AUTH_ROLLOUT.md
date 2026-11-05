# Cold Streets — Flutter / Supabase Auth client integration

**Draft date: 2026-11-04. Not merged, built, tested or deployed.**

This branch **stacks on** security PR #4 (\`security/supabase-auth-ownership-20261104\`), which replaces insecure password-only Node.js login with verified Supabase access tokens. **Do not merge this branch into main ahead of PR #4.**

## Changes made

- Added \`supabase_flutter: 2.18.3\` as an **exact** dependency, pending lockfile regeneration.
- Added \`lib/supabase_config.dart\` to read public Supabase project URL and publishable key from build-time definitions.
- Added \`lib/services/game_http.dart\`: wraps GET/POST/PUT/DELETE, checks all outgoing gameplay URLs against the configured Node API origin, loads the active Supabase session, refreshes expired access tokens, and replaces any caller Authorization header with a trusted bearer token. Nothing sends tokens to arbitrary hosts.
- Added \`lib/services/player_session.dart\`: calls protected \`POST /auth/session\` and reads the internally mapped player profile.
- Replaced \`lib/views/auth_view.dart\`: Supabase Auth email/password signup and sign-in, email confirmation handling, \`street_name\` signup metadata used only as a *suggestion*, and player profile bootstrap.
- Updated **28 existing gameplay/management view modules** to call the shared authenticated HTTP layer instead of \`package:http\` directly.
- Updated \`MainHubLogic.logout()\` to call Supabase sign-out and clear the navigation stack; exiting the server session now returns the player to the login screen.
- Added HTTPS runtime API endpoint configuration; fallback host addresses remain for local emulators only. Four previously hardcoded emulator-only view URLs were removed (company dashboard, company management, jobs, syndicate). Company-management action and recruit endpoints now use the correct `/company-management` prefix.

## Build environment

Flutter is not currently installed in the ChatGPT execution environment, and the user is working from a mobile device.

Build examples:

\`\`\`bash
flutter pub get
flutter run \
  --dart-define=SUPABASE_URL=https://PROJECT_REF.supabase.co \
  --dart-define=SUPABASE_PUBLISHABLE_KEY=sb_publishable_REPLACE \
  --dart-define=API_BASE_URL=https://YOUR_PRIVATE_NODE_API_HOST
\`\`\`

Only \`SUPABASE_PUBLISHABLE_KEY\` is allowed in Flutter. **Never include DB_PASSWORD, sb_secret_, service_role or other privileged API credentials** in Dart source, git, or Flutter build defines.

The current Node backend is not deployed; **\`API_BASE_URL\` must point to an actual authenticated Node server when one exists**, not to \`https://PROJECT_REF.supabase.co\`.

## Important account behavior

- Supabase Auth uses **email/password sign-in**. Legacy street-name/ID login is removed because PR #4 intentionally disables old unverified password routes. In-game street names continue as display identities. Supporting alternative login identifiers later requires a separate anti-enumeration and account recovery design.
- During signup, the chosen street name is stored as editable Supabase user metadata strictly as a **hint** so it is available after email confirmation. The Node API validates the name, its uniqueness, and verified account ownership before creating game state. It does not grant roles from that metadata.
- Email confirmation may return \`session: null\`; the Flutter UI shows a confirmation prompt and does not call the game API until a session exists. If the name is missing or already claimed, the login form asks for a new street name.
- A user with a confirmed Supabase identity but without a Cold Streets profile will not get access to gameplay until \`/auth/session\` returns a real profile.
- **Sessions are deliberately not persisted** in this first secure development draft (\`persistSession: false\`). Access tokens remain in memory; players sign in again after a restart. Before a public build, choose and review encrypted cross-platform session storage; do not silently fall back to plaintext SharedPreferences.
- The app does not automatically migrate original player accounts. Old accounts remain unmapped until a verified recovery flow is designed.

## Hard blockers before merge or test

1. **Regenerate and commit \`pubspec.lock\`** with the new direct dependency. The old lockfile remains stale; do not claim the Flutter build is reproducible until resolved.
2. **All 2,093 source catalog records have now been imported** into Supabase. The backend PR #4 still checks for starter gym #1 (present, verified). The remaining database gap is the **unrecovered original DDL and missing normalized company seed/relationship tables**. This is not the same as complete game schema compatibility.
3. Configure and securely deploy the Node backend for staging and give Flutter its HTTPS \`API_BASE_URL\`.
4. Finalize the Supabase Auth provider's email confirmation and redirect URLs for iOS, Android, Windows and web. Deep-link callback settings and platform URI registration are **not** implemented here.
5. Audit all remaining resource permission boundaries, client-controlled economy amounts, and idempotency. A signed token is not authorization to mutate arbitrary companies, properties, inventories or users.
6. When gameplay testing is authorized, run \`flutter analyze\`, \`flutter test\`, backend security tests, and account-isolation tests, including valid/invalid token, first signup, email confirmation, logout, session expiration, and profile conflicts.

**No Supabase database schema, authentication settings, user accounts, or production API deployments were changed in this branch.**

## Economic request replay safety addendum — 2026-11-05

- `lib/services/game_http.dart` now attaches a cryptographically generated UUIDv4 `Idempotency-Key` to every POST unless the caller supplied one explicitly. This supports the persistent server ledger introduced by the later banking/economy security branch.
- A future automatic retry must reuse the original key; generating a fresh key represents a new action.
- `lib/views/bank_view.dart` now exposes **CLAIM MATURED DEPOSIT** after the active deposit unlock timestamp and calls `POST /bank/claim-deposit`. Balance responses are parsed safely whether PostgreSQL numeric values arrive as JSON numbers or strings.
- These client changes require the backend idempotency/banking follow-up branch (planned stacked PR after #7). PR #5 alone does not provide the new bank endpoint or replay ledger.

## Remaining-economy API companion — 2026-11-05

The Flutter branch now also contains client adaptations for stacked backend PR #9:

- Syndicate recruitment sends only the server-issued `offer_id`; recruit price/stats are no longer echoed back as authority. The UI uses the server-returned Dirty Cash balance after hire.
- City Job interviews retain the server-issued `interview_id` and submit that UUID with exactly five selected answers.
- City Job promotion eligibility checks all four recovered requirement fields (`acu`, `ops`, `pre`, `res`) instead of the removed `stat_req_value` assumption.
- Hospital revive synchronizes the actor's returned Energy after the source-backed 75-Energy Medical Revive.
- The existing POST adapter supplies `Idempotency-Key`; these screens depend on backend PR #9 plus its parent #8.

Do not merge these client changes to main without reconciling the backend stack. No Flutter build/analyze/gameplay test was run during this source pass.

## Jail / University / Info Broker companion — 2026-11-05

The Flutter branch now also contains client adaptations for stacked backend PR #10:

- Jail uses the server-returned Clean Cash, Influence, Nerve, Heat and jail timer values after bail/breakout.
- University updates the HUD with server-returned tuition/graduation state.
- University course cards render normalized `rewards_jsonb.stats` and show the source-defined perk/unlock counts rather than the nonexistent legacy `reward_stat_1/reward_amount_1` fields.
- Info Broker updates the HUD with the authoritative Clean Cash after a classified purchase and Dirty Cash after bounty placement.
- These screens rely on backend PR #10 and its parent chain (#9 → #8 → #7 → #6 → #4).

Do not merge these client changes to main independently. No Flutter analyze/build/gameplay test was run during this source pass.

## Crime / daily City Job / University entitlement companion — 2026-11-05

The Flutter branch now also contains client adaptation for stacked backend PR #11:

- City Jobs exposes **CLAIM DAILY PAY** when `daily_job_claimed_at` is absent or at least 24 hours old.
- A successful claim synchronizes returned Clean Cash and refreshes Job Points plus the payout timestamp.
- Crime POSTs already receive automatic UUIDv4 `Idempotency-Key` headers through `game_http.dart`; PR #11 now persists/replays those randomized outcomes on the backend.
- Medical Revive may now be authorized by the source-backed University `revive_ally` unlock as well as City Hospital mastery; the mobile request shape is unchanged.
- University perks/unlocks remain source data unless a backend consumer explicitly implements their semantics.

These changes depend on backend PR #11 and its full parent chain. Do not merge this Flutter branch independently. No Flutter build/analyze/gameplay test was run.
