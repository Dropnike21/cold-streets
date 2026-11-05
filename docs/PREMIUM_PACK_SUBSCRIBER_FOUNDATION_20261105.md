# Premium Packs and Subscriber Foundation — 2026-11-05

## Corrected product model

The project owner clarified that premium monetization is modeled after a donor
pack/subscriber economy, but with Cold Streets-specific benefits.

There are three distinct concepts.

### VIP Pack

- tradable premium asset;
- may be held or sold rather than consumed immediately;
- when consumed, grants a timed benefit entitlement for 30 days;
- known benefit targets currently include:
  - Max Energy target: 200;
  - +20% Nerve benefit;
  - Casino Token daily spend cap: 150.

The exact meaning/application point of the +20% Nerve benefit is not yet
unambiguous, and the owner indicated additional benefits may exist. Therefore
consumption remains paused until the complete benefit contract is finalized.

### Kingpin Pack

- separate tradable premium asset;
- intended to grant a 30-day timed benefit when consumed;
- exact Kingpin benefit set is not yet defined.

Kingpin Pack is not silently treated as VIP Pack.

### Subscriber

Subscriber is an account subscription, not an inventory pack.

While the billing period is active, Subscriber receives the VIP-level benefit
set plus subscriber-only benefits. The owner explicitly defined:

- 1 VIP Pack per month;
- 1 Book per month;
- +20 items to the city NPC market daily allowance.

The base city NPC market limit is 100 items/day, so active Subscriber status
produces an effective limit of 120 items/day.

The Book catalog and book boost semantics are not yet authoritative, so monthly
grant settlement remains paused.

## Do not conflate VIP Pass

The recovered item catalog already contains a separate item named `VIP Pass`.

It is not mapped to `VIP Pack`, and no legacy item ID is reused for the new
premium system.

## Server-owned storage

Migration:

`20261105084920_vip_casino_cap_20261105.sql`

now creates four separate premium-domain tables.

### premium_pack_catalog

Text-keyed catalog for premium packs. Initial rows:

- `vip_pack`;
- `kingpin_pack`.

Both are marked tradable. Both currently have
`activation_available = false` until their full activation semantics are safe.

### user_premium_pack_inventory

Stores unconsumed premium packs separately from ordinary recovered
`items_master` inventory.

It includes `reserved_quantity` for future marketplace escrow.

This avoids inventing numeric item IDs or colliding with the recovered item
catalog.

### user_premium_entitlements

Stores timed benefits independently from pack inventory.

Each row contains:

- player;
- benefit tier;
- start/end timestamps;
- server source type;
- immutable server source reference.

A consumed pack will eventually create a 30-day row here.

### user_subscriptions

Stores the server-owned current Subscriber billing period.

The table records status, current period boundaries and cancellation-at-period
end state. It has no public mutation API.

No client-supplied payment/subscription state is trusted.

## Effective-benefit resolver

`utils/premiumEntitlements.js` derives benefits from database-time state.

Current safe derivations:

- no VIP-level benefit -> Casino daily spend cap 100;
- active VIP Pack entitlement -> Casino daily spend cap 150;
- active Subscriber period -> VIP-level Casino cap 150;
- active Subscriber period -> city NPC market limit 120;
- active VIP-level benefit -> Max Energy target is recorded as 200.

The +20% Nerve value is exposed as known design data but is not applied because
its exact semantic is still unresolved.

Subscriber monthly grant quantities are recorded as:

- VIP Pack: 1;
- Book: 1.

Settlement is not enabled yet.

## Read-only premium API

`GET /premium/status`

returns:

- pack catalog;
- owned pack inventory and reserved quantity;
- active timed entitlements;
- current Subscriber period/status;
- effective Casino/market benefit limits;
- known but unresolved Energy/Nerve targets;
- monthly Subscriber grant quantities;
- explicit blockers.

Internal payment/source references are not returned to the client.

## Mutations intentionally paused

`POST /premium/consume-pack` -> 503

`POST /premium/subscribe` -> 503

They stay closed until:

1. VIP Nerve semantics are exact;
2. the remaining VIP benefit list is final;
3. Kingpin benefits are defined;
4. Pack purchase/payment issuance is authoritative;
5. Subscriber billing activation/renewal/cancellation is connected;
6. the Book catalog and effects are defined;
7. monthly grant settlement has persistent idempotency and a durable worker;
8. pack stacking/extension behavior is defined.

## Subscriber city-market integration

The city NPC market now derives the authenticated player's effective daily limit:

- normal player: 100;
- active Subscriber: 120.

The market request's idempotency check was also moved ahead of daily-cap
evaluation so replaying a successful purchase cannot fail as an over-limit
purchase.

The Player Bazaar remains outside the NPC daily purchase cap.

## Security

All premium-domain tables:

- have RLS enabled;
- revoke direct PUBLIC, anon and authenticated access.

The development database currently has zero users, so replacing the temporary
VIP boolean caused no player-state migration ambiguity.

## Verification boundary

Performed:

- project-owner rule reconciliation;
- existing item-catalog collision review;
- development schema update/readback;
- Supabase security-advisor review;
- static backend readback.

Not performed by instruction:

- premium purchase/consumption runtime tests;
- billing integration tests;
- monthly grant worker tests;
- market concurrency tests;
- Flutter build/analyze tests;
- deployment;
- production changes.
