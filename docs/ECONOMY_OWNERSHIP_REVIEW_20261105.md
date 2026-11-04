# Cold Streets — P0 Economy & Resource Authorization Review

**November 5, 2026 (Asia/Manila)**  
**STATUS: development source changes only. Not merged, deployed, gameplay-tested, or reviewed in a running Node server.**

## Context and dependency

This branch is stacked on `infra/node-staging-safety-20261105` (draft staging PR #6), itself based on `security/supabase-auth-ownership-20261104` (draft auth PR #4). It relies on `req.player.userId` resolved from a verified Supabase session. Its default staging API remains closed, and legacy mutation timers remain disabled.

The 53-table **isolated Supabase development database** contains all **2,093 records** in the 18 recovered catalog tables; the original DDL, original player records, non-catalog company relationships, and historic functions are not recovered. Database data was inspected **read-only** in this work; no schema migration, user account, or balance was changed.

## Implemented source changes

| Area | Changes | Safety boundary |
| --- | --- | --- |
| Shared money validation | `utils/economyValidation.js` validates exact positive integer IDs/amounts, parses PostgreSQL `NUMERIC` into `BigInt`, and formats safely sized results. | Reject malformed quantities, coercion, negative amounts, floats and unsafe JS money arithmetic. |
| Market | `routes/market.js` uses `req.player.userId`, server catalog price and `source='city_market'`, sorted row locks, one transaction for debit/stock/inventory/purchase history, and atomic inventory upsert. | Requires item inventory uniqueness (`user_id,item_id`), currently present in reconstructed schema. Cart max 100 lines / 10,000 units pending design review. |
| Properties | `routes/realEstate.js` keeps portfolio GET read-only, locks authenticated wallet for agency purchases, charges **server** catalog cost, atomically moves in and writes audit rows. Upgrades must belong to player, be offered for that property in the legacy catalog, and be purchased only once. | Upgrade pricing is extracted by a **strict, non-evaluating parser** from the historical pseudo-JSON `available_upgrades_json`. Client `cost` is ignored. Unparseable offers fail closed. |
| Starter residence | `routes/auth.js` grants a single catalog ID #1 `Cardboard Box` property in the verified account creation transaction, not from a GET request. | Does not auto-migrate legacy accounts or grant unlimited homes on repeated reads. |
| High/Low casino | `routes/casino/highlow.js` charges tokens + cash atomically, maintains the single active session, serializes guesses, consumes the session before cashout, and calculates decimal multipliers/payouts exactly. | Cryptographic randomness via `crypto.randomInt`; one-time settlement is protected by row locks and the user-keyed session. |
| Perya and Slots | `utils/casinoEconomy.js`, `routes/casino/perya.js` and `routes/casino/slots.js` share transactional cash/token charges, secure randomness and exact integer payouts. Slots locks the jackpot row to prevent concurrent duplicate jackpot awards. | Audit rows and payouts commit/rollback with wagers. A repeated paid spin is still a new wager; network retry idempotency remains future work. |
| Missions | `routes/missions.js` refuses unaudited tutorial VERIFY, Kevin TURN_IN and PARTIAL payout requests. Contract REQUEST is serialized and no longer overwrites an active contract; ABORT works without a cash reward. | **Rewards intentionally paused:** all recovered anonymous tutorial `reqs_json` are `{}`, and existing crime/gym routes do not maintain reliable contract-progress evidence. Re-enabling rewards requires tracked objectives and tested one-time settlement. |
| Companies | `routes/company_management.js` enforces current owner/Director permission on all management POSTs; locked vault transfers use exact amounts and strict currency/action enums. Supplier orders validate the company's blueprint relationship and calculate cost from `company_products_master`. Pricing and advertising reject malformed/negative values. | **Paused:** employee management, directorship transfer, liquidation, company upgrades, and applicant management. These need stronger ownership/consent or authoritative price and archival rules. |
| Company dashboard visibility | `routes/companies.js` now verifies the actor is a **real player employee** (`is_npc = false`) before displaying a company's private management details. NPC crew IDs may overlap with player IDs, so this condition prevents accidental cross-account visibility. | Player/NPC roster joins also distinguish real employees from recruits. |
| Incorporation | `routes/companies.js` locks the user's wallet, uses exact `company_types_master.setup_cost`, and refuses to charge until `blueprint_products` contains the company's product mapping. | The recovered dump does not include `blueprint_products` rows. Incorporation intentionally returns 503 rather than creating a paid empty company. |

## Server-side limitations and known release blockers

1. **Not production-safe yet.** The security changes have had source review only, no app/runtime, database migration replay, integration, concurrency, or gameplay tests. Do not expose the Node API.
2. **Other economic routes not audited in this PR** include banking (separate draft PR #3), syndicate recruitment, credit upgrades, hospitals, City Hall, inventory consumables, jobs, gyms and crime rewards. Shared actor middleware does **not** make these operations financially authoritative.
3. **Missing company seed catalogs:** `blueprint_products`, `company_positions_master`, and `company_specials_master` were not in the 18-table data-only dump and are still empty in development. Company orders/incorporation remain blocked until these are reconstructed and validated.
4. **Mission rules unavailable:** all anonymous `missions_master.reqs_json` records in recovered source are empty. Neither a client-provided VERIFY nor an untracked contract-progress object can justify money/reputation. Rebuild the server-side progress ledger before re-enabling settlement.
5. **Economic idempotency:** Market buy and Slots/Perya spins atomically charge each accepted request; a repeated client request could still be a **second paid action**. Define and enforce idempotency keys for interrupted/retried financial requests, ideally with a database uniqueness constraint.
6. **Bank and cross-route locking:** Prior `bank.js` remained nontransactional on the auth/staging base branch. Draft PR #3 must be reconciled with this PR's uniform user-first lock order before release.
7. **Property catalog effects:** Upgrade availability/price is read from historical pseudo-JSON text, but downstream stat/maintenance bonuses and account-property migration require a separate mechanics review.
8. **Company audit atomicity:** Some non-money changes (profile/pricing/budget) still perform the change and log in separate SQL calls. Consolidate these into transactions during company stabilization.
9. **Legacy server ticks:** Staging PR #6 disables old automatic regen and market restocking in production. A safe scheduled replacement is required before gameplay balancing.
10. **Provider secrets and hosting:** No server credentials were written to GitHub; hosting provider, private pooler host, TLS config and Node deployment are not yet configured.

## Deferred verification cases

- Account A cannot access account B's wallet, property instance, company, recruit or game session.
- Market rejects duplicate item lines, noninteger/negative/zero quantities, non-city-market item IDs, overspending, and insufficient stock; concurrent carts cannot produce negative stock.
- Property GET does not mint a starter residence; account creation gives one, and agency purchase, upgrade and move-in roll back fully on failure.
- Two concurrent High/Low cashout attempts cannot both pay, and a user cannot start a second active session before settling the first.
- Slots jackpots are unique under concurrent jackpot wins; losing and winning rolls emit one complete audit per committed paid spin.
- Mission VERIFY, TURN_IN and PARTIAL fail closed until objective evidence exists; REQUEST cannot reroll an existing contract.
- Company vault rejects negative/fractional transfer amounts and unknown currencies; company orders refuse unseeded blueprints.
- Cross-route concurrency including banking and market uses consistent transaction isolation and account locks.

## Rollout ordering

1. Review auth/staging branch dependencies and release blockers; do not merge independent PRs blindly.
2. Recover company relationship seeds, authoritative tutorial requirements and accounting/idempotency rules.
3. Reconcile banking PR #3 with this transaction model.
4. Authorize later test phase, run schema/contract validation and multi-client concurrency tests.
5. Enable the API only after operational and security review; gameplay remains disabled by default.

**Public-facing claims of security or feature stability are not warranted until these gates are complete.**
