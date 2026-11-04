# Casino Economy Reconciliation — 2026-11-05

## Scope

This pass reconciles the current Perya, Syndicate Slots and High-Low backend
against the recovered **Cold Streets: Casino & Underground Gambling (V1.0)**
source.

The existing casino engines already have useful security primitives—verified
actor identity, transactions, row locks, persistent idempotency and secure RNG.
Those controls do not make an unresolved paytable economically safe.

This pass therefore preserves the historical child engines for later
reconciliation but removes them from the live API surface until the missing
denomination and settlement rules are canonical.

## Recovered Casino model

The source divides gambling into two economic categories.

### Category 1 — NPC vs. Player

The source explicitly calls these **Token Games (System Banked)**.

- Currency: **Casino Tokens**
- Daily limit: players may spend at most **100 Casino Tokens per day**
- Games include Perya Color Game, Syndicate Slots, High-Low and future
  single-player games.

### Category 2 — Player vs. Player

The source explicitly uses **Clean Cash**.

The later Casino update defines the winning-pot tax as:

- 5% on winning pots under $1,000,000
- 20% on winning pots over $1,000,000

No Category 2 PvP gambling backend is implemented in the current repository,
so this pass does not create one.

## Current backend conflict

The three implemented Category 1 engines currently use a hybrid economy:

1. require and consume exactly one Casino Token;
2. accept an arbitrary Dirty/Clean Cash wager;
3. debit Dirty Cash first and then Clean Cash;
4. pay winnings in Clean Cash.

That hybrid is not defined by Casino V1.0.

The source phrase **Currency: Casino Tokens** cannot safely be reinterpreted as
“one token is an entry fee while cash is the real wager” without an explicit
owner decision.

Conversely, converting the existing cash bet directly into a token wager would
also be an invention because the source does not define:

- how many tokens may be wagered per play;
- whether a token stake is returned on a win;
- whether winnings are paid in tokens, cash or another value;
- how daily *spend* is tracked separately from current token balance;
- whether unused tokens carry over;
- how and when tokens are issued or refreshed.

The connected schema has only `users.casino_tokens`. It has no authoritative
daily token-spend/reset timestamp or ledger.

The Flutter hub's fallback of 100 tokens when the local value is zero is
explicitly a client-side mock and is not a server entitlement.

## Perya Color Game

The source defines:

- three color-coded dice;
- a selected color;
- scaling of **1x / 2x / 3x** based on one, two or three matching dice.

The current backend instead returns a gross cash payout of:

- one match: 2x cash bet;
- two matches: 3x;
- three matches: 4x.

That may have been intended to represent stake return plus 1x/2x/3x profit,
but the source does not say whether its multiplier is gross payout or profit.

This pass does not choose between those interpretations.

## Syndicate Slots

The source defines only one numeric economic rule for the current Slots game:

> 10% of every lost token globally is added to a Server-Wide Progressive
> Jackpot.

The current backend instead:

- treats the jackpot as a cash-valued numeric;
- feeds 10% of the **cash wager** when payout is below the wager;
- resets a hit jackpot to 10,000,000;
- uses a code-only reel weighting;
- uses code-only common/diamond payout multipliers.

Casino V1.0 does not define:

- the jackpot starting/reset value;
- jackpot denomination;
- the reel symbol probabilities;
- the common-symbol paytable;
- Diamond paytable;
- whether a partial return counts as a “lost token” for jackpot feeding.

The recovered development row
`casino_jackpots['slots_progressive'] = 145,777,080` is preserved, but its
presence does not establish a canonical denomination.

## High-Low

The source defines:

- dealer flips a card;
- player guesses whether the next card is higher or lower;
- successful players can “let it ride” for exponential payouts.

It does not define:

- a SAME/DRAW wager;
- the exact multiplier progression;
- +0.3x for High/Low;
- +5.0x for SAME;
- card-rank tie behavior;
- a multiplier cap;
- how token stake and payout are denominated.

Those current constants are therefore code-only balance, not canonical source
rules.

## API boundary

The parent `/casino` router now returns HTTP 503 for every Casino endpoint.

This intentionally blocks both mutations and the existing read endpoints. A
read such as the progressive jackpot currently implies a cash denomination in
the Flutter UI; exposing that value as a live game value would continue the
same unresolved economic interpretation even if wagering were disabled.

The child files remain in the repository unchanged so their transaction,
idempotency, RNG and UI integration work can be reused after the economic
contract is selected.

No casino settlement can currently:

- consume Casino Tokens;
- debit Dirty or Clean Cash;
- mint Clean Cash;
- advance a High-Low session;
- feed or pay the progressive jackpot;
- write a new casino audit row.

## Database state at reconciliation

The connected development database contained:

- 0 players;
- 0 active High-Low sessions;
- 0 casino audit rows;
- one existing progressive jackpot row.

No gameplay row was altered by this pass.

## Denomination-neutral database invariants

Migration
`20261104215000_casino_ledger_invariants_20261105.sql` adds constraints that
are valid regardless of the eventual token/cash denomination:

- Casino Token balances are non-negative integers;
- jackpot value is a non-negative integer;
- casino audit bet and payout values are non-negative integers;
- High-Low session bet is a positive integer;
- card rank is 2 through 14;
- suit is one of HEARTS, DIAMONDS, CLUBS or SPADES;
- multiplier is positive;
- streak is non-negative.

No 100-token balance cap is added. The source specifies a **daily spend cap**,
not necessarily a maximum balance.

Migration
`20261104215500_casino_fk_indexes_20261105.sql` adds the covering
`casino_audit(user_id)` index identified by the Supabase performance advisor.

## RLS advisory

Supabase reports `rls_enabled_no_policy` for the casino tables.

That is intentional in the current backend-authoritative architecture. RLS is
enabled and no direct client table policy is granted; future casino settlement
must continue through authenticated backend transactions.

No permissive RLS policy was added merely to silence the advisory.

## Required decisions before reactivation

At minimum, Category 1 needs canonical answers for:

1. Is Casino Token itself the wager/prize currency, or is it a per-play access
   charge alongside a cash wager?
2. If tokens are the wager, how many can be staked per play and what are prizes
   denominated in?
3. How are the 100 daily spend units issued, tracked and reset?
4. Do unused tokens carry over?
5. Perya: are 1x/2x/3x values gross payouts or profit multipliers?
6. Slots: exact symbol weights, paytable, jackpot denomination/reset and what
   qualifies as a lost token for the 10% feed.
7. High-Low: exact payout progression, tie/SAME behavior and any cap.

Only after those decisions should the existing secure transaction machinery be
reconnected to the parent router.

## Verification boundary

Performed:

- original Casino source reconciliation;
- current backend/client/schema inspection;
- static GitHub readback;
- development-only database invariant migrations;
- Supabase security/performance advisor review.

Not performed by project instruction:

- casino gameplay tests;
- build/runtime tests;
- deployment;
- production changes.
