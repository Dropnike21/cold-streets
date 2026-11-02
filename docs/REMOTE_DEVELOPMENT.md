# Cold Streets — remote development

Status: initial bootstrap, 2026-11-02. These instructions describe a **development** setup, not an approved production deployment.

## Sources of truth

- **Code and version history:** this GitHub repository. Work in feature branches and merge reviewed pull requests into `main`.
- **Game rules and visual references:** the "Cold Streets" Google Drive folder, including the Project Master Reference and the PostgreSQL Database Recovery Specification. Archived game-design documents remain read-only.
- **Private runtime secrets and database backups:** private, access-controlled storage or a secrets manager. Never commit a real `.env`, an unredacted DB export, API keys, or passwords to this public repository.

## Recovered versus missing

The repository includes Flutter code, an Express/PostgreSQL backend, and game assets. The existing Drive file `cold_streets_game_data.sql` is a **data-only** PostgreSQL dump for 18 catalog/configuration tables; it does **not** contain DDL (`CREATE TABLE`) or the `users` table. It cannot initialize an empty database by itself. The Drive file `cold_streets_full_backup_2026-11-02.backup` was listed at **0 bytes** when checked and must not be treated as a valid backup.

Before any database restore, recover/confirm the real schema, including constraints, triggers, functions, sequences, migrations and player-data retention requirements. Work on a disposable development database. Never overwrite a live database with reconstructed schema.

## Develop remotely

1. Open the GitHub repository in a browser-based development environment or clone it to a remotely hosted machine. You do **not** need the old laptop to read or edit committed code.
2. Install a recent Flutter SDK that supports the Dart constraint in `pubspec.yaml`, Node.js compatible with the backend dependencies, and a disposable PostgreSQL instance when the schema has been recovered.
3. From the repository root, run `flutter pub get` and `flutter test`. This repo's Flutter client is in `lib/`.
4. For backend work, run `cd cold_streets_backend`, `npm ci`, and create a local `.env` from `.env.example`. Do **not** use production credentials during feature development.
5. Once the development database schema and catalog data have been safely restored, run `npm start` from `cold_streets_backend`.
6. Start Flutter with a development API URL, for example:

   ```sh
   flutter run -d chrome --dart-define=API_BASE_URL=http://127.0.0.1:3000
   ```

   For a genuinely remote API, replace the URL with an **HTTPS** staging endpoint that you control. The API URL is not a secret. A browser cannot reach the development server on your old laptop via `127.0.0.1`. When running in separate cloud environments, configure the correct forwarded/staging address and CORS origin.

7. Use pull requests; let CI validate backend syntax and the Flutter login-screen smoke test. App, database and gameplay integration still require additional test coverage.

## Security gate before public deployment

**Do not expose the current backend to the public internet.** The current routes accept client-supplied `user_id` and lack enforced account-token authentication and ownership checks. Payment and reward operations need authorization, input validation, row locks, transactions and idempotency tests. Server timers are also still in-process test-mode intervals.

A sensible order of work:

1. M0: preserve data, recover verified DDL, establish staging/CI and reproducible setup.
2. M1: implement server-side authentication/authorization and secure economy transfers.
3. M2: test the complete new-player tutorial, crimes, inventory, market and gym gameplay loop.
4. M3: finish incomplete modules before expanding to multiplayer wars, politics or new economies.

## Safe working agreement

Do not merge or deploy unreviewed changes; do not run destructive SQL against live data; keep private data off GitHub. If a tool cannot access a local-only file on the old laptop, identify the missing artifact rather than assuming it exists in Drive or the repository.
