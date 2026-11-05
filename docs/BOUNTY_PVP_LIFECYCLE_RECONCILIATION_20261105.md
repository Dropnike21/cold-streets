# Bounty / PvP Claim Lifecycle Reconciliation — 2026-11-05

## Scope

This pass reconciles the implemented Info Broker bounty placement route with the recovered **Info Broker V1.0**, **PvP Combat & Gear V1.0**, current backend, and reconstructed development schema.

It does not invent a PvP result or bounty-claim API.

## Recovered semantics

The Info Broker source establishes:

- the Hitlist is a public bounty ledger;
- players place cash bounties on rivals;
- a bounty is paid when it is successfully claimed;
- a successful hunter also receives **+5 Influence**;
- bounty placement may be anonymous.

The PvP source defines an interactive turn-based combat system, but the current repository does not contain the authoritative combat lifecycle needed to prove which player defeated which target.

The recovery reference also classifies turn-based PvP as design rather than a completed backend system.

## Security/economy consequence

The existing `POST /info-broker/bounty` route deducted Dirty Cash and inserted an escrow-like bounty row, but no authoritative completion event could ever settle that row.

Adding a claim endpoint that accepts a target, bounty ID, winner, or "kill" assertion from the client would make the reward forgeable.

Therefore new bounty placement is now **fail-closed with HTTP 503** until a server-owned PvP combat result exists.

Existing bounty listings remain readable. At reconciliation time the connected development database contains **0 bounty rows**, so this change does not strand an existing development escrow.

## Required future claim contract

Before bounty placement can reopen, the combat system must persist a server-owned terminal result that unambiguously records at least:

- combat/fight identity;
- attacker and defender identities;
- terminal winner/loser;
- completion timestamp and terminal state;
- replay/idempotency protection;
- enough linkage to prove that the bounty target was actually defeated by the claimant.

A bounty settlement should then, in one transaction:

1. lock the terminal combat result;
2. lock the bounty;
3. prove claimant/winner and target/loser match;
4. mark the bounty claimed exactly once;
5. credit the bounty cash exactly once;
6. credit the recovered **+5 Influence** exactly once;
7. persist the claim/combat linkage for audit and replay.

Whether multiple simultaneous bounties on the same target are all claimable from one defeat, only one is claimable, or require separate fights is **not specified by the recovered sources** and remains unresolved.

Likewise, cancellation/refund, expiry, placer fees, anonymous-broker surcharge amount, and the exact cash denomination of the bounty payout are not sufficiently defined to invent here.

## Development database integrity

Development-only migration `harden_bounty_escrow_20261105` adds:

- `reward_cash > 0`;
- `target_user_id <> placed_by_user_id`;
- an index supporting the current reward-descending Hitlist read.

These constraints are denomination-neutral and do not create claim semantics.

## Verification boundary

Performed:

- original Drive source reconciliation;
- current GitHub route/schema inspection;
- development-database row-count and constraint inspection;
- static code readback.

Not performed by instruction:

- gameplay/runtime/build tests;
- public deployment;
- production database changes.
