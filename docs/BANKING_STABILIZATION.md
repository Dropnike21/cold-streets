# Bank stabilization proposal (2026-11-04)

**Status: untested draft.** This work is separate from the Supabase schema reconstruction PR and is not safe to deploy publicly.

## Verified pre-existing defects

From `cold_streets_backend/routes/bank.js` on `main`:

- A deposit updated `users` and inserted `time_deposits` through separate `pool.query` calls without a database transaction.
- Multiple concurrent deposit requests could read the same wallet balance and produce inconsistent results.
- `pending_checks` could be marked claimed and payout granted through separate statements, allowing duplicate claims under concurrent requests.
- Adding PostgreSQL `NUMERIC` values in JavaScript may concatenate strings rather than add numbers.
- Deposits did not enforce the existing client's one-active-deposit rule on the server.
- Input type checks relied on coercion, accepting malformed amounts.

## Changes in this draft

- Use a dedicated PostgreSQL connection for each money-changing transaction, with `BEGIN`, `COMMIT`, rollback and client release.
- Lock the user's wallet row with `FOR UPDATE` before evaluating funds.
- Block a second active deposit while the user's row is locked.
- Validate positive integer amounts, IDs and duration indices without truncating or coercing floats.
- Calculate interest with `BigInt` basis points to avoid ordinary floating-point rounding.
- Use a conditional check-status transition and wallet update in the **same** transaction to prevent double-claim payouts.
- Preserve client numeric responses for safe integers and return strings for larger exact balances; Flutter bank view now parses both.

## Major remaining blockers

- **Authentication/authorization:** route handlers still accept a client-supplied `userId`. A user may impersonate another user without verified access tokens. Implement Supabase Auth token verification and server-side ownership checks across the **whole** API before exposing a server to untrusted clients.
- **No automated tests run:** integration tests for concurrent deposits, duplicate check claims, expired checks, large cash values and malformed inputs are essential before merging/deploying.
- **Bank maturation/settlement:** current source does not demonstrate a trusted worker that turns matured deposits into safe, one-time payouts. This draft does not invent one.
- **Cross-route spending:** the same consistent locking and precise money conventions must be adopted by market, casino, property and company routes.
- **Compatibility:** original PostgreSQL column types and constraints are not verified. This draft assumes integer-valued monetary balances (including `.00` string representations).

No database or player data was modified.
