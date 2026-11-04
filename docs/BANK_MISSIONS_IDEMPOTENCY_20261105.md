# Banking, Mission Progress, Company Catalog & Idempotency — P0 follow-up

**Working date:** 2026-11-05 (Asia/Manila)  
**Status:** source changes and isolated development-database migration only. No public deployment or gameplay test.

This branch stacks on `security/economy-resource-integrity-20261105` (draft PR #7).

## 1. Banking reconciliation

The previous bank draft PR fixed transaction boundaries but lived on an older branch and still depended on caller-supplied player IDs. This branch reconciles those fixes with verified Supabase identity and the shared exact-money utilities:

- `POST /bank/deposit`: one PostgreSQL client/transaction, authenticated actor, exact `BigInt` interest math, account row lock, database one-active-deposit invariant, and server trust-level validation.
- `POST /bank/claim-check`: row-locks player + check and performs one conditional pending→claimed transition before adding clean cash.
- **New `POST /bank/claim-deposit`:** explicit, one-time settlement for a matured time deposit. The recovery specification states no trustworthy maturation worker was present. `GET /bank/status` stays read-only.
- Matured deposits pay the stored `total_payout` into Clean Cash. The active row is marked `claimed` in the same transaction.
- Flutter bank UI now exposes **CLAIM MATURED DEPOSIT** when its local unlock timestamp has passed.

## 2. Server-authoritative Kevin contract progress

The old `active_contract.progress` object was never updated by the crime/gym routes, so TURN_IN could not safely verify completion.

`utils/missionProgress.js` now updates Kevin progress inside the same PostgreSQL transaction as the successful gameplay action:

- successful Searching / Pickpocketing / Shoplifting crime → `progress.crimes + 1`, capped at `reqs.crimes`;
- successful Gym `/train` request → `progress.gym + 1`, capped at `reqs.gym`.

Kevin `TURN_IN` now:
1. locks the authenticated player,
2. requires both server-maintained requirements to be complete,
3. pays the server-generated `reward_cash`,
4. increases Kevin reputation by 2,
5. clears `active_contract`,
6. commits all changes once.

`PARTIAL` remains paused because no source-backed threshold exists. Anonymous tutorial `VERIFY` also remains paused because every recovered `missions_master.reqs_json` row is empty and the old tutorial state is partly client-local.

### Gym transaction correction

Gym membership purchase and training now use one acquired `pg` client for `BEGIN/COMMIT/ROLLBACK`; the old route used `pool.query('BEGIN')` followed by unrelated pool queries. Training also verifies the gym is both owned and currently active before applying stat/experience changes.

## 3. Company catalog reconciliation — no fabricated seeds

The connected Google Sheet tab `company&position_master` is a valid source but represents a different product model from the recovered PostgreSQL company-product table:

- 120 company types;
- 179 structured position entries;
- 122 structured special entries;
- products_json shapes: 40 `main/by_products`, 40 `requires/output`, 40 `sales`;
- 120 distinct product string values appear in those product structures;
- the recovered `company_products_master` contains 20 products;
- **only one exact product name overlaps: `Crude Oil`**.

Therefore `blueprint_products` cannot be safely reconstructed by name similarity. Incorporation and supplier orders continue to return 503 for unseeded types rather than charge players for an invented supply chain. See `docs/COMPANY_CATALOG_RECONCILIATION_20261105.md`.

## 4. Persistent economic idempotency

A new server-only table was applied to the isolated Supabase development database:

- Supabase migration version: `20261104182655`
- migration name: `economic_idempotency_20261105`
- GitHub mirror: `supabase/migrations/20261104182655_economic_idempotency_20261105.sql`

Key = `(user_id, action_scope, idempotency_key UUID)`. Each row stores a SHA-256 request hash and the committed HTTP response. A duplicate key with identical normalized request data replays the first committed response; the same key with different request data is rejected.

RLS is enabled and `anon` / `authenticated` grants are revoked. The security advisor reports the expected `rls_enabled_no_policy` informational notice; the table is intentionally server-only.

### Endpoints currently protected by persistent idempotency

- Bank: deposit, claim matured deposit, claim pending check.
- Market: bulk purchase.
- Casino: Perya roll, Slots spin, High/Low start, guess, cashout.
- Property: agency purchase, upgrade, move-in.
- Company: vault transfer, supplier stock order, incorporation.

The lock order for integrated routes is **authenticated player row → idempotency row → action resources**, reducing cross-route deadlock risk.

## 5. Flutter request keys

`lib/services/game_http.dart` on the Flutter auth branch now creates a UUIDv4 with `Random.secure()` for every POST unless the caller already supplied an `Idempotency-Key`. This allows a caller to deliberately reuse the same key when implementing an HTTP retry later. The Node CORS configuration permits this header.

A new key per distinct user action does **not** prevent a player from intentionally submitting two separate actions; it prevents replay of the *same keyed request*. Any future automatic retry mechanism must reuse the original key.

## Remaining P0/P1 work

- Reconcile the Flutter auth branch with this stacked backend branch before merging to main.
- Add integration/concurrency tests when testing is authorized: duplicate keys, mismatched payloads, simultaneous check/deposit claims, market stock race, casino retry/replay, and High/Low guess replay.
- Audit remaining monetized routes: syndicate recruit payouts, Credit Broker upgrades, hospital/city-hall charges, job payouts, inventory consumables and any cross-player transfers.
- Design the canonical company economy (detailed spreadsheet production chain vs recovered 20-product PostgreSQL model).
- Rebuild anonymous tutorial objective evidence on the server before re-enabling tutorial reward settlement.
- Add retention/cleanup policy for old idempotency records only after replay-window requirements are decided.
- The staging API remains disabled by default and legacy automatic ticks remain disabled in production.
