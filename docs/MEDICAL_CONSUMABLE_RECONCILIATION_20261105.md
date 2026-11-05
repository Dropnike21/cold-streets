# Explicit Medical Consumable Reconciliation — 2026-11-05

## Scope

This pass implements the recovered newer-generation medkit mechanic for the
three catalog rows whose effects are exact and complete:

- Small First Aid Kit
- Standard First Aid Kit
- Trauma Kit

No generic consumable-effects interpreter is introduced.

No runtime/gameplay/build tests or deployment were performed.

## Source generation

The Master Items update states that medkits are no longer simple flat-heal
items. They provide:

- percentage HP regain;
- flat Hospital Time Reduction.

The recovered item catalog matches that generation for three exact rows.

### 261 — Small First Aid Kit

`{hp_gain_pct: 10, hosp_reduction_mins: 20}`

Cooldown:

- type: `medical`
- 30 seconds

### 262 — Standard First Aid Kit

`{hp_gain_pct: 20, hosp_reduction_mins: 35}`

Cooldown:

- type: `medical`
- 45 seconds

### 263 — Trauma Kit

`{hp_gain_pct: 30, hosp_reduction_mins: 45}`

Cooldown:

- type: `medical`
- 60 seconds

## Explicit catalog pinning

The inventory route contains an explicit map for IDs 261–263.

For one of those IDs, item use fails closed if:

- effect keys change;
- an extra effect is added;
- HP percentage changes;
- Hospital reduction changes.

This prevents later catalog drift from silently changing the implemented
medical mechanic.

## HP regain

For a reconciled medkit:

`HP += max_hp × hp_gain_pct / 100`

capped by `max_hp`.

The database HP fields are NUMERIC, so the percentage is applied with exact
PostgreSQL numeric arithmetic. No new rounding rule is invented.

## Hospital reduction

If the player currently has Hospital time remaining:

`hospital_expires_at -= recovered minutes`

If that reduction reaches or passes the current time:

- `hospital_expires_at` becomes NULL;
- Hospital `state_reason` is cleared when the player is not concurrently jailed.

If the player is not hospitalized, the Hospital reduction is a no-op while the
HP effect still applies.

The Inventory route is intentionally placed before the state gatekeeper, so an
authenticated hospitalized player can use medical items.

## Transaction authority

The existing inventory-use settlement remains:

- authenticated actor;
- persistent idempotency;
- player row lock;
- inventory row lock;
- server item-catalog lookup;
- cooldown check;
- atomic player-state update;
- conditional one-unit inventory decrement;
- cooldown insertion;
- idempotent response commit.

The client supplies only item ID.

## Mixed-effect items remain fail-closed

This pass does **not** partially execute items whose full mechanics are not
reconciled.

Examples that remain blocked:

- Tactical Field Bandage:
  `instant_heal + bleed_reduction`;
- Medical Grade Morphine:
  `hosp_reduction_mins + drowsy_duration`;
- Morphine Syringe:
  damage mitigation / pain resistance / duration;
- Emergency First Aid Bundle:
  nested fixed contents.

The server refuses those items before inventory is consumed.

This is intentional: executing only one effect from a multi-effect item would
change its intended balance.

## Existing direct-effect subset

The previously reconciled strict subset remains supported only when **every**
effect is one of:

- `instant_heal`;
- `energy_gain`;
- `energy_restore`;
- `nerve_gain`.

Unknown or nested mechanics still fail closed.

## Flutter companion

Draft PR #5 now:

- removes the redundant request-body player ID from item use;
- merges returned authoritative player fields into current user state;
- displays the explicit medical result after use:
  - percentage Max HP regained;
  - Hospital minutes reduced;
- refreshes inventory afterward.

The client does not calculate the effect.

## Verification boundary

Performed:

- Master Items source review;
- exact item 261/262/263 development catalog readback;
- backend static readback;
- Flutter static readback;
- Supabase security/performance advisor review.

Not performed by instruction:

- Node runtime tests;
- item-use integration tests;
- Hospital-state integration tests;
- cooldown/concurrency tests;
- Flutter analyze/build/widget tests;
- deployment;
- production changes.
