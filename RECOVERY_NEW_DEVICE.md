# Cold Streets — New Device Recovery & Development Pause

**Paused:** 2026-11-06
**Repository:** Dropnike21/cold-streets
**Runtime candidate branch:** feature/flutter-supabase-auth-20261104
**Runtime candidate PR:** #5
**Last code commit before this recovery document:** 34ba4c818e72a6f3d093cb2b7d2c1ae0caf45c4d

This file is the recovery checklist for resuming Cold Streets on a new development machine. It intentionally contains no private database password, secret key, or local certificate.

## Current project state

Verified before pausing:

- Supabase Auth works.
- The Node API starts with gameplay enabled.
- The Node API connects successfully to the Supabase PostgreSQL session pooler using TLS.
- Runtime bootstrap reaches listener_started, gameplay_runtime_bootstrap_ready, and worker state_duration.
- Windows Flutter app built and ran.
- Android Flutter APK built successfully.
- The last Android install failure was emulator storage exhaustion, not a compile failure.
- Android login had already reached the first tutorial screen.
- A likely first-frame PostgreSQL numeric to Dart String/int mismatch in LevelUpOverlay was fixed in commit 34ba4c818e72a6f3d093cb2b7d2c1ae0caf45c4d.
- The yellow text lines seen on Android were Flutter debug baseline visualization, not intended UI styling.

Do not deploy or merge to production immediately on resume. Continue runtime verification first.

Crew Crime remains intentionally paused because its source/mechanics are unresolved.

## Recovery branch

A dated archive branch is created for this pause:

~~~text
archive/development-pause-20261106
~~~

The active runtime candidate remains:

~~~text
feature/flutter-supabase-auth-20261104
~~~

## Clone on a new computer

~~~powershell
git clone https://github.com/Dropnike21/cold-streets.git
cd cold-streets
git switch archive/development-pause-20261106
git status
~~~

To return to the active candidate later:

~~~powershell
git switch feature/flutter-supabase-auth-20261104
git pull --ff-only
~~~

## Known-good toolchain

| Component | Known-good version/state |
| --- | --- |
| Flutter | 3.47.9 stable |
| Dart | 3.13.7 |
| Node.js | 24.14.1 |
| npm | 11.11.0 |
| Java/JDK | 25.0.3 |
| Gradle wrapper | 9.4.1 |
| Android Gradle Plugin | 9.2.1 |
| Kotlin Gradle Plugin | 2.2.20 |
| Android emulator tested | Android 16 / API 36 |
| PostgreSQL | Supabase hosted Postgres 17 |

Backend package.json requires Node >=24 <25.

Flutter currently declares Dart SDK ^3.11.4.

Flutter 3.47.9 warned that Kotlin 2.2.20 support will eventually be dropped and recommended Kotlin 2.3.20+ / Built-in Kotlin. This was not the cause of the last Android failure; the APK compiled successfully.

## Install on the new device

Required:

1. Git
2. Flutter SDK
3. Node.js 24.x
4. Android Studio
5. Android SDK / platform tools
6. JDK 25 if keeping the currently verified Android stack

Optional for Windows desktop testing: Visual Studio / Build Tools with the Windows desktop C++ workload and Windows SDK.

After cloning:

~~~powershell
flutter doctor -v
flutter pub get
flutter devices
~~~

Start with one Flutter target at a time.

## Android emulator recommendation

Create a fresh AVD rather than restoring the old nearly-full emulator.

The previous AVD had only about 487 MB free and was 92% full before the laptop became unstable.

Recommended:

- Android 16 / API 36 or another currently supported stable image
- hardware virtualization enabled
- enough virtual internal storage for repeated debug APK installs
- keep at least 1–2 GB free while testing
- do not run Windows Flutter plus the Android emulator simultaneously until the new machine is known to handle the load

Android application ID:

~~~text
com.sixson.coldstreets.cold_streets
~~~

## Supabase project

~~~text
Project ref: qbrntyrlzxhilwrbcriq
Project URL: https://qbrntyrlzxhilwrbcriq.supabase.co
Region: ap-northeast-2
PostgreSQL: 17
~~~

The schema, catalog, auth data, and development database are remote and do not depend on the old laptop.

Flutter requires these build-time values:

~~~text
SUPABASE_URL
SUPABASE_PUBLISHABLE_KEY
~~~

Retrieve the current publishable key from the Supabase dashboard when resuming.

Example:

~~~powershell
flutter run -d <device-id> --dart-define=SUPABASE_URL=https://qbrntyrlzxhilwrbcriq.supabase.co --dart-define=SUPABASE_PUBLISHABLE_KEY=<CURRENT_PUBLISHABLE_KEY>
~~~

Never put a service_role key, sb_secret_ key, database password, or other server credential in Flutter.

## Backend private environment file

The backend environment file is ignored by Git.

Location:

~~~text
cold_streets_backend/.env
~~~

Start from cold_streets_backend/.env.example.

For local development, the important values are:

~~~dotenv
PORT=3000
NODE_ENV=development
ENABLE_GAMEPLAY_API=true

SUPABASE_URL=https://qbrntyrlzxhilwrbcriq.supabase.co
SUPABASE_PUBLISHABLE_KEY=<CURRENT_PUBLISHABLE_KEY>

CORS_ALLOWED_ORIGINS=http://localhost:5173,http://127.0.0.1:3000

DB_HOST=aws-0-ap-northeast-2.pooler.supabase.com
DB_PORT=5432
DB_NAME=postgres
DB_USER=postgres.qbrntyrlzxhilwrbcriq
DB_PASSWORD=<PRIVATE_SUPABASE_DATABASE_PASSWORD>
DB_SSL=true
DB_SSL_CA_FILE=certs/supabase-ca.crt
~~~

Never commit DB_PASSWORD, .env, service-role/secret keys, or local certificate material.

The repository .gitignore already excludes .env files and cold_streets_backend/certs/*.crt and *.cer.

## Supabase PostgreSQL connection

Use the Supabase Session pooler, not the old local PostgreSQL database.

~~~text
host=aws-0-ap-northeast-2.pooler.supabase.com
port=5432
database=postgres
user=postgres.qbrntyrlzxhilwrbcriq
~~~

Retrieve the actual database password from Supabase. Do not store it in GitHub.

Cold Streets uses pg.Pool. Do not replace cold_streets_backend/db.js with the generic Supabase postgres package example.

### TLS certificate

The previous machine initially failed with SELF_SIGNED_CERT_IN_CHAIN.

The secure fix is already implemented:

1. Supabase dashboard -> Database -> Settings -> SSL Configuration.
2. Download the Supabase database CA/root certificate.
3. Create cold_streets_backend/certs/.
4. Save the certificate as, for example, cold_streets_backend/certs/supabase-ca.crt.
5. Set DB_SSL=true and DB_SSL_CA_FILE=certs/supabase-ca.crt.

Do not use DB_SSL=false or rejectUnauthorized:false to bypass certificate validation.

## Backend startup

~~~powershell
cd cold_streets_backend
npm install
npm run release:preflight
npm start
~~~

Successful startup should include:

~~~text
listener_started
gameplay_enabled: true
gameplay_runtime_bootstrap_ready
workers: state_duration
~~~

Then verify:

~~~powershell
curl.exe http://127.0.0.1:3000/healthz
curl.exe http://127.0.0.1:3000/readyz
~~~

Do not proceed to gameplay testing if readyz is unhealthy.

## Flutter API routing

Current development defaults:

- Windows/native non-Android: http://127.0.0.1:3000
- Android emulator: http://10.0.2.2:3000
- web/local: http://127.0.0.1:3000

Android debug has local cleartext support for the development API. Production remote API traffic should use HTTPS.

## First runtime verification after recovery

Use this order:

1. Start only the Node backend.
2. Confirm healthz and readyz.
3. Launch one Flutter target only.
4. Sign in with a development/test account.
5. Confirm the client reaches auth/session.
6. Confirm the main hub/tutorial loads.
7. Watch the Flutter console for runtime exceptions.
8. Only after one platform is stable, test another platform.

A Flutter red error screen may disappear, but the console preserves its exception and stack trace.

## Auth redirect cleanup still pending

Email confirmation succeeded, but the default confirmation redirect was still pointing at localhost and could show a browser error after confirmation.

Future cleanup:

- configure a Cold Streets deep-link callback
- add it to Supabase Auth Additional Redirect URLs
- pass the intended redirect from Flutter signup
- configure Android/Windows deep-link handling

This did not prevent the already-confirmed test account from signing in.

## Intentionally unresolved mechanics

Do not invent behavior to make these appear complete.

Known areas still requiring authoritative mechanics decisions include:

- Casino settlement/paytables
- Trade settlement
- company economics
- Crew Crime
- properties mechanics
- premium/VIP details
- Credit Broker rules/effects
- Jail/Heat formulas
- PvP mechanics
- other recovered catalog entries with ambiguous semantics

The stabilization policy is to fail closed when rules or catalog mappings are not authoritative.

## Git and PR context

At the pause point:

- PR #5 is the current Flutter/runtime candidate.
- PR #44 contains backend stabilization/integration work.
- PR #45 was considered stale/divergent and should not be used as the test candidate.
- main was intentionally kept clean pending runtime verification.

Resume runtime verification before merging.

## Possible old-laptop-only branch

A historical local backup branch was discussed:

~~~text
backup/laptop-work-20261106
~~~

As of the pause, that branch was not found on GitHub.

If the old laptop is ever usable again, check:

~~~powershell
git branch --list
git status
~~~

If backup/laptop-work-20261106 exists locally and contains useful work, push it separately before discarding the old drive.

The dated archive branch preserves the current remote runtime candidate, but it cannot contain unpushed files that existed only on the old laptop.

## Resume checklist

- [ ] Clone the repository.
- [ ] Switch to archive/development-pause-20261106 to inspect the frozen snapshot.
- [ ] Install the known-good toolchain.
- [ ] Run flutter doctor -v.
- [ ] Run flutter pub get.
- [ ] Create a fresh Android AVD with adequate storage.
- [ ] Recreate cold_streets_backend/.env.
- [ ] Retrieve the current Supabase publishable key.
- [ ] Retrieve/set the private database password.
- [ ] Download the Supabase CA certificate.
- [ ] Run backend preflight.
- [ ] Start backend and verify healthz / readyz.
- [ ] Test one Flutter platform at a time.
- [ ] Capture and fix remaining runtime exceptions.
- [ ] Continue stabilization/runtime verification before merging.
- [ ] Only then return to gameplay mechanics work.

## Security reminder

GitHub is the source of truth for code and recovery instructions, but not for secrets.

Keep private credentials in a password manager or another secure private store. On a new machine, recreate local secrets from Supabase instead of committing them to GitHub.
