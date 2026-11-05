# Deferred Payout / Bank Check Contract — 2026-11-05

## Scope

This pass turns `pending_checks` into a generic, server-authoritative deferred-payout instrument that can be issued by other Cold Streets systems and redeemed through the Bank.

Candidate issuers include:

- Casino lottery / large jackpot settlement;
- auctions;
- Trade Network / Player Bazaar settlements;
- competitions or events;
- missions or other server-authoritative rewards.

No issuer is enabled by this pass. The contract exists so later systems can issue obligations without inventing one-off payout logic.

No gameplay/build/runtime tests or deployment were performed.

## Core model

The Bank is the **clearing/redemption surface**.

The originating subsystem is the **issuer**.

A valid new deferred payout is identified by:

- recipient user;
- `issuer_type`;
- immutable `source_ref`;
- human-readable `source`;
- exact positive amount;
- explicit payout denomination;
- expiry timestamp;
- optional JSON metadata.

The first supported denominations are:

- `dirty_cash`;
- `clean_cash`.

This does not decide which currency any particular future issuer should use. The issuer must derive that from its own source-backed settlement rules.

## Immutable issuer identity

Migration:

`20261105003000_deferred_payout_contract_20261105.sql`

adds:

- `issuer_type`;
- `source_ref`;
- `payout_currency`;
- `metadata_jsonb`;
- `claimed_at`.

A partial unique index enforces:

`(issuer_type, source_ref)`

for rows with a source reference.

That means a payout source such as an auction, lottery draw, trade settlement, or event reward cannot issue the same obligation twice under the same canonical source identity.

The recipient is intentionally **not** part of that uniqueness key. A retry that changes the recipient for the same source reference is treated as a conflict, not a new payout.

## Server-only issuance helper

`utils/deferredPayout.js` exposes:

`issueDeferredPayout(client, obligation)`

It is not an HTTP route.

It must be called from the authoritative issuer transaction.

The helper:

- validates recipient identity as an exact integer;
- validates issuer/source identifiers;
- requires an exact positive integer amount;
- requires an allowlisted cash denomination;
- requires a valid expiry timestamp;
- requires JSON-object metadata;
- inserts the obligation once;
- on issuer/source conflict, locks the existing obligation;
- accepts the replay only if recipient, source label, amount, expiry, denomination and metadata all match exactly;
- rejects an issuer/source reference reused with different settlement data.

The helper never reads payout values from the client.

## Bank redemption

`POST /bank/claim-check` is now enabled for **fully contracted, unexpired checks only**.

The client supplies only:

- `check_id`.

The server owns:

- recipient;
- issuer;
- source reference;
- amount;
- currency;
- expiry;
- status.

Settlement flow:

1. authenticate actor;
2. require persistent idempotency key;
3. lock actor row;
4. begin idempotency scope;
5. lock check row;
6. verify ownership;
7. require `status = pending`;
8. require issuer/source/currency contract fields;
9. reject expired checks;
10. parse exact database amount;
11. credit only the row's allowlisted currency;
12. mark the check `claimed` and set `claimed_at`;
13. commit idempotent response in the same transaction.

A network retry with the same idempotency key replays the committed response rather than paying twice.

A second unrelated claim after settlement sees non-pending state and cannot pay again.

## Legacy liabilities

The new contract fields remain nullable for compatibility with a future import of unreconciled legacy check rows.

Rows missing:

- `issuer_type`;
- `source_ref`;
- or `payout_currency`

are visible but cannot be claimed.

This prevents a future restored database from assigning payout semantics to historical obligations merely because the modern schema changed.

## Expiry

The existing table requires:

`expires_at > created_at`.

The new issuer helper therefore requires the issuer to choose an expiry timestamp.

This pass **does not** define a universal expiry duration.

It also does not define what happens after expiry.

An expired check:

- is not redeemed;
- is not auto-converted;
- is not deleted;
- is not automatically returned to the issuer;
- is not automatically moved to another balance.

It remains an unresolved liability until the issuing system's fallback semantics are reconciled.

## Status integrity

The table now accepts:

- `pending`;
- `claimed`;
- `voided`.

Claimed rows must have `claimed_at`.

Non-claimed rows must not have `claimed_at`.

No generic client-facing void route exists in this pass.

Future issuer cancellation/refund semantics must remain issuer-specific.

## Flutter companion

Draft PR #5 now:

- distinguishes time-deposit settlement from deferred-payout redemption;
- keeps time deposits paused;
- displays issuer type;
- source reference;
- payout denomination;
- amount;
- expiry;
- status;
- claimed timestamp;
- enables **CLAIM PAYOUT** only when the backend marks a check claimable;
- updates Dirty/Clean Cash from the authoritative claim response;
- leaves legacy, settled and expired rows read-only.

The client never chooses amount or currency.

## What still needs issuer integration

The contract is infrastructure only.

The next systems can integrate it when their own rules are authoritative:

1. Trade Network seller settlement;
2. auction seller/winner settlement;
3. Casino lottery / large jackpot payout;
4. competition/event rewards;
5. other high-value rewards.

Every issuer still needs to define:

- canonical `issuer_type`;
- canonical `source_ref`;
- payout currency;
- amount derivation;
- expiry;
- void/cancel behavior;
- expired-obligation fallback.

## Verification boundary

Performed:

- existing pending-check schema inspection;
- development migration application;
- constraint/index readback;
- static issuer-helper review;
- static Bank route review;
- Flutter companion update;
- Supabase advisor review.

Not performed by instruction:

- Node runtime tests;
- claim integration tests;
- concurrency tests;
- issuer integration tests;
- Flutter analyze/build/widget tests;
- deployment;
- production changes.
