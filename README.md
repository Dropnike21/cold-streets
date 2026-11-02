# Cold Streets

A cross-platform, persistent, interface-driven crime RPG built with Flutter, an Express backend and PostgreSQL.

## Repository layout

- `lib/` — Flutter client and gameplay views.
- `assets/` — checked-in game art and map resources.
- `cold_streets_backend/` — Node.js API, routes and game systems.
- `test/` — Flutter smoke tests.
- `docs/REMOTE_DEVELOPMENT.md` — development setup, recovery status, safety constraints and first milestones.

## Getting started

For local client development:

```sh
flutter pub get
flutter test
flutter run -d chrome --dart-define=API_BASE_URL=http://127.0.0.1:3000
```

For the API:

```sh
cd cold_streets_backend
npm ci
# Copy .env.example to .env and supply your development-only DB settings.
npm start
```

The backend requires a verified PostgreSQL schema. The recovered Drive SQL data dump is **not** a standalone database restore. See the remote-development guide before setting up a new database.

**Security:** This repo is not production-ready. The existing backend needs account authentication and authorization, transaction safety and further tests before it is reachable by untrusted users. Never commit credentials or private database dumps.

Reference game design documentation is kept separately in the Cold Streets Google Drive folder.
