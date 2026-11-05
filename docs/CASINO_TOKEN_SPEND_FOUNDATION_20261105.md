# Casino Token Spend Foundation — 2026-11-05

## Scope

This pass establishes the accounting substrate for Category 1 Casino Token
games without reopening any gambling mutation.

The recovered Casino V1.0 explicitly establishes:

- Category 1 NPC-vs-player games use **Casino Tokens**;
- players have a **100 Casino Token base daily spend cap**;
- VIP Status adds **+50** to that cap, for **150/day total**;
- Perya, Syndicate Slots and High-Low are Token Games.

The source does **not** establish token issuance/replenishment semantics,
timezone-specific reset rules, or sufficiently complete paytables to settle the
preserved engines safely.

No runtime/gameplay/build tests or deployment were performed.

## Existing player balance invariant

The development schema already enforces:

- `users.casino_tokens >= 0`;
- Casino Token balances must be exact integers.

No replacement balance constraint was added.

## Immutable spend ledger

Migration:

`20261105084348_casino_token_spend_foundation_20261105.sql`

creates `casino_token_spend_ledger`.

Each spend obligation stores:

- authenticated player;
- server-approved Token game key;
- exact positive integer token amount;
- immutable server source reference;
- server spend timestamp.

Database invariants enforce:

- spend amount from 1 through 100;
- nonempty game key and source reference;
- one immutable source reference per player;
- ledger UPDATE and DELETE are rejected;
- RLS enabled;
- direct PUBLIC / anon / authenticated access revoked.

The source reference gives future game settlement a persistent replay boundary.

## Server accounting helper

`utils/casinoTokenLedger.js` defines:

- base daily spend cap: 100;
- VIP daily bonus: +50;
- maximum effective daily spend cap: 150;
- currently preserved reconciled engine identities:
  - `perya`;
  - `slots`;
  - `high_low`;
- read-only current Token status;
- replay-safe future Token debit/reservation.

The reservation helper is **not connected to a gameplay route in this pass**.

Future callers must run inside one database transaction. The helper:

1. validates the server-selected game key;
2. validates exact integer Token amount;
3. locks the authenticated player;
4. checks the persistent source-reference replay row;
5. sums the player's current database-calendar-day spend;
6. derives the effective cap from server-owned VIP Status (100 base / 150 VIP);
7. refuses spend above that effective daily cap;
8. refuses insufficient Token balance;
9. atomically debits Casino Tokens;
10. records the immutable spend obligation.

A retry with the same source reference may replay only if the game and amount
match the original obligation.

## Read-only status API

`GET /casino/status`

returns:

- current Casino Token balance;
- source-backed base, VIP bonus, and effective daily spend cap;
- Token spend recorded today;
- remaining daily spend capacity;
- database day key;
- explicit database-calendar-day boundary;
- preserved Token engine identities;
- explicit false flags for Token issuance and Casino gameplay;
- unresolved paytable/issuance blockers.

All other `/casino/*` requests continue to return 503.

## Reset boundary

The source says "per day" but does not specify an in-world or player timezone. The later Master Items update also explicitly establishes VIP Status as +50 to the Casino Token daily limit.

The ledger therefore uses PostgreSQL `CURRENT_DATE` only as the deterministic
accounting boundary. This is **not** treated as a design decision that Token
balances refill at midnight.

A daily **spend cap** is not the same thing as a daily Token grant.

No Token issuance, refill, renewal or reset worker is created here.

## Preserved engine blockers

### Perya

The source says one/two/three matching dice pay 1x/2x/3x, but recovered code
historically used a different gross-cash payout shape. Gross payout versus
profit semantics remain unresolved.

### Syndicate Slots

The source establishes that 10% of every lost Token contributes to a global
progressive jackpot, but the complete paytable, jackpot seed/reset value and
atomic jackpot payout contract remain unresolved.

### High-Low

The source establishes a Token-funded let-it-ride game but does not provide a
complete authoritative multiplier/cashout schedule.

The preserved legacy child engines must not be treated as authoritative merely
because their code exists.

## Category 2 boundary

Player-vs-player Casino games use Clean Cash according to the source, but their
escrow, matchmaking, winner settlement, hospitalization interactions and rake
rules are separate systems.

No Category 2 gameplay is enabled by this pass.

## Development readback

At reconciliation:

- users: 0;
- legacy Casino audit rows: 0;
- High-Low session rows: 0;
- users with nonzero Casino Tokens: 0;
- Token-spend ledger rows: 0.

After migration:

- RLS enabled;
- anon SELECT: false;
- authenticated SELECT: false;
- immutable UPDATE trigger present;
- immutable DELETE trigger present;
- no new Supabase security advisor finding;
- no new Supabase performance advisor finding.

## Verification boundary

Performed:

- Casino source reconciliation;
- current schema/constraint inspection;
- development migration application/readback;
- static backend readback;
- Supabase advisor review.

Not performed by instruction:

- Casino gameplay tests;
- Token debit integration tests;
- replay/concurrency tests;
- payout/paytable tests;
- Flutter analyze/build/widget tests;
- deployment;
- production changes.
