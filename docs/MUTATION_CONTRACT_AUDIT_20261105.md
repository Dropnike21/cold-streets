# Active Mutation Contract Audit — 2026-11-05

## Scope

This pass audits every POST endpoint in the canonical backend integration branch
and turns the mutation surface into an explicit fail-closed contract.

No Node startup, API/gameplay tests, concurrency tests, Flutter build/analyze,
deployment, or production change was performed.

## Route inventory

Static route inventory:

- total POST endpoints: 72;
- registered active/read-preflight POST contracts: 39;
- explicitly paused/legacy POST endpoints: 33;
- unclassified POST endpoints: 0;
- PUT/PATCH/DELETE gameplay handlers found in the current route stack: 0.

All future POST/PUT/PATCH/DELETE paths now fail closed unless they are added to
the central mutation contract or explicitly classified as paused.

## Central mutation registry

Added:

`middleware/mutationContract.js`

For every active POST route the registry defines the exact allowed top-level JSON
fields.

Examples:

- `/crimes/execute` -> `crime_id`;
- `/market/buy-bulk` -> `cart`;
- `/gym/train` -> `stat_type, energy_spent, gym_id`;
- `/company-management/funds` -> `company_id, amount`;
- `/syndicate/assign_job` -> `crew_id, crime_id`;
- `/trade-network/listing-preflight` -> canonical asset identity + quantity.

Active mutation routes reject:

- non-object JSON bodies;
- unrecognized top-level fields;
- all query-string fields.

Unknown mutation paths are rejected before reaching gameplay handlers.

Paused routes are allowed to reach their explicit 410/503 fail-closed response;
their body shape cannot settle gameplay state.

## Actor identity

The contract does not include client actor identifiers.

Authenticated actor identity continues to come only from the verified Supabase
bearer session and `req.player.userId`.

Resource identifiers such as:

- company_id;
- target_id;
- crew_id;
- course_id;
- item_id;
- crime_id

remain client intent and are re-authorized/re-resolved by the server.

## Nested payload contracts

### City Market

Each `cart` element now accepts only:

- `item_id`;
- `quantity`.

Extra nested fields are rejected before cost/stock settlement.

Catalog price and source remain server-derived.

### City Job interview

Each answer now accepts only:

- `question_id`;
- `selected_index`.

The persisted interview session still defines which five questions may be
answered and the server owns the correct answers.

### Trade preflight

The existing Trade normalization already allowed only:

- asset_namespace;
- item_id or pack_key;
- quantity.

Settlement remains disabled.

## Client-selected economy semantics removed

### Company funding

The old request supplied:

- action_type;
- currency_type;
- amount.

Only owner Dirty Cash -> company Dirty Cash is source-reconciled.

The route now represents that operation intrinsically. The client sends only:

- company_id authorization context;
- amount.

It can no longer request withdrawal, Clean Cash transfer, or a different
denomination through request fields.

Flutter was updated accordingly.

## Catalog aliases removed

### Syndicate crew crime

The old route accepted either:

- crime_id; or
- client-provided crime_title.

The title fallback is removed.

Crew assignment now requires canonical `crime_id`, then resolves title,
automation interval, payout, tool requirement, and casualty rate from the
server catalog.

Flutter now submits the board's canonical crime ID.

## Pickpocket authority defect closed

The legacy Pickpocket implementation let Flutter supply `activity_name`.

That activity changes the success modifier, so a modified client could select
the most favorable activity regardless of the target it displayed locally.

The master crime route now accepts only `crime_id`.

Pickpocket execution returns 503 until target/activity state is:

- issued by the server;
- persisted;
- bound to the authenticated actor;
- replay-safe.

The Flutter Pickpocket screen no longer generates executable local target
activity/modifier state. It renders a paused explanation instead.

Searching and Shoplifting remain active because their execution does not depend
on a client-selected probability modifier.

## Persistent idempotency classification

Replay-sensitive authoritative mutations retain persistent idempotency,
including:

- Bank check claim;
- level-up;
- company application/funding/profile/staff/employment changes;
- crime execution;
- Gym purchase/activation/training;
- Hospital revive;
- classifieds;
- inventory use/equip;
- City Job interview/daily pay/promotion/quit/mastery;
- City Market purchase;
- Anonymous verification;
- property move-in;
- Syndicate assignment/board/hire;
- University enrollment/dropout/graduation.

POST surfaces without the economic idempotency ledger are intentionally
non-additive/read-like:

- `/auth/session`: unique Auth UID/profile constraints + one transaction;
- incorporation preflight: read-only;
- event mark-read: monotonic false -> true state setting;
- tutorial visit: monotonic allowlisted observation;
- Trade listing preflight: read-only inventory/catalog snapshot.

## Exact-value review

Economic/resource values continue to use exact integer parsing and PostgreSQL
integer/NUMERIC arithmetic where required.

This pass also removed a recruit-price JSON conversion through `Number`;
Syndicate recruitment prices now use exact JSON integer serialization.

Remaining JavaScript `Number` use in active mutation code is limited to
bounded values such as:

- rank numbers;
- stat requirement comparisons;
- cooldown seconds already checked as safe integers;
- Gym Energy capped to the accepted small request range;
- intentional fractional Gym stat-growth math.

No active cash/balance/Job Point/market quantity/client price settlement relies
on floating-point arithmetic.

## Result

Every currently defined backend POST route is now either:

1. registered with an explicit request contract; or
2. explicitly fail-closed.

There is no unclassified mutation route in the current canonical route stack.
