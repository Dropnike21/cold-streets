# Flutter ↔ Backend Contract Reconciliation — 2026-11-05

## Scope

This pass reconciles the long-lived Flutter companion branch against the
canonical backend integration branch / draft PR #44.

No Flutter build, analyze, widget test, API runtime test, gameplay test, or
deployment was performed.

## Identity boundary

All active Flutter mutation requests now send only action intent.

Removed redundant client-supplied `user_id` fields from authenticated mutation
bodies including:

- Gym purchase/activation/training;
- City Job claim/interview/promote/quit;
- Hospital revive;
- Info Broker classifieds;
- company applications;
- crime execution;
- level-up;
- Syndicate board/hire/unassign/crew crime assignment.

The backend continues to derive the actor from the verified Supabase bearer
session.

GET routes that still contain a player ID in the URL are protected by the
backend's owned-player parameter middleware and are not treated as
authentication claims.

## Casino

The old Flutter Casino hub contained client mock state and linked directly to
legacy Perya, Slots, and High-Low settlement routes.

The hub now reads only:

`GET /casino/status`

It displays authoritative:

- Casino Token balance;
- spent/remaining daily Token allowance;
- effective daily cap;
- VIP-level status;
- Subscriber status.

Casino gameplay remains visibly paused.

The three historical game screens still preserve their class interfaces for
router compatibility, but they contain no HTTP calls, no RNG, no wager math,
and no local settlement behavior. They render a fail-closed paused notice.

## Jail

The previous Jail screen showed code-only mechanics:

- $100/minute bail calculations;
- 5-Nerve breakout labels;
- clickable prison-yard training.

Those values/actions are removed.

The UI now displays:

- BAIL PAUSED;
- BREAKOUT PAUSED;
- YARD PAUSED.

No dormant Jail mutation helper remains.

A missing arrest reason is rendered as "Reason unavailable" rather than an
invented narrative.

## City Jobs

The legacy Job Point `/exchange` client flow is disabled and no longer makes an
HTTP request.

Non-passive legacy specials are displayed as "Active paused".

### Resignation preview

Flutter previously computed Final Heist payout locally as:

`current rank × 10,000`

The backend now provides `resignation_preview` for the current City Job:

- `clean_exit_retention_percent`;
- `heist_payout_dirty_cash`;
- `heist_heat`;
- `heist_ban_days`.

The resignation dialog renders those server values. It does not calculate the
payout formula.

If the authoritative heist preview is missing, the heist button fails closed.

## Info Broker

Classified ads remain active and server-priced.

Bounty placement is visibly paused. The former bounty dialog no longer contains
a settlement HTTP call, preventing a later UI reconnection from accidentally
reopening the fail-closed bounty path.

## Companies

Directorship transfer is visibly paused and its button is disabled.

The remaining active management mutation surfaced by the client is the
source-safe company profile update, plus the previously reconciled server-owned
funding/staff/employment flows in their dedicated controls.

The old stock-order screen no longer invents a $2,500 unit-price fallback.
Missing unit-price provenance is shown as `UNRESOLVED`.

## Syndicate

Recruit hire no longer uses a local wallet subtraction fallback.

The backend hire response now includes:

`recruitment_cooldown_seconds`

Flutter uses the returned authoritative:

- Dirty Cash balance;
- recruitment cooldown duration.

It no longer hardcodes a two-minute cooldown in the successful hire path.

## City NPC Market

Flutter previously defaulted the NPC daily cap to 100 before status loaded.

That is unsafe now that Subscriber can have a 120-item cap.

The client now initializes daily-limit state at zero and remains fail-closed
until `GET /market/status` supplies the authenticated player's effective
limit.

## Real Estate

The existing agency-purchase method remains in the source for future contract
compatibility, but the button is gated by the server-provided
`ownership_purchase_available` flag.

The canonical backend currently returns that flag as false, so agency purchase
remains inaccessible.

## Static endpoint result

The final contract scan found no active/dormant Flutter references to the
following paused settlement endpoints:

- Casino Perya/Slots/High-Low mutations;
- Jail bail/breakout/yard training;
- legacy Job exchange;
- bounty placement;
- Trade list/buy/cancel;
- company directorship/liquidation/pricing/stock/advertising/upgrade mutations;
- legacy Syndicate company assignment or client-triggered completion.

The only retained paused mutation URL is Real Estate agency purchase, guarded by
the authoritative availability flag described above.

## Verification boundary

Performed:

- Flutter route/HTTP inventory;
- backend route inventory;
- request-body/response-shape comparison;
- static paused-endpoint scan;
- static client-authority/fallback scan;
- source readback after edits.

Not performed:

- Flutter analyze/build;
- runtime HTTP calls;
- widget tests;
- gameplay tests;
- concurrency tests;
- deployment.


## Mutation-contract hardening follow-up

The canonical backend now maintains a fail-closed registry for every POST route.
Flutter active mutations must therefore send only the exact documented action
fields.

Additional companion changes in this pass:

- company owner funding sends only `amount` plus the existing company resource
  context; the client no longer selects transfer direction or denomination;
- Syndicate crew crime assignment sends canonical `crime_id`, not a title
  alias;
- Pickpocket execution is fully paused in Flutter because the old screen
  generated target activity/modifier state locally and that value changed
  authoritative success probability;
- Searching and Shoplifting remain active because their execution payload is the
  server catalog `crime_id` only.

The Pickpocket screen is now a static paused surface and contains no executable
HTTP/RNG target flow.

The backend also rejects unexpected top-level mutation fields and query-string
fields, so future Flutter additions must update the reviewed server contract
rather than silently passing new authority-bearing values.
