# Jail / Crime State Reconciliation — 2026-11-05

## Scope

This pass reconciles the stabilized manual crime engines, Jail, Hospital, and
Heat state transitions against the recovered **Jail & Heat** and **Crimes
Database** sources.

The sources contain two different design generations. This pass preserves the
generation-specific rules that are explicit and keeps unresolved cross-generation
balance decisions non-executable.

No gameplay/build/runtime tests or deployment were performed.

## Source conflict: Heat generation and decay

The older Jail & Heat source defines:

- successful crime: +0.01 Heat;
- arrest: +60 Heat;
- Heat decay: 1% every 5 minutes while online;
- Heat decay: 2% every 5 minutes while jailed or offline.

The later Crimes Database defines:

- per-crime `penalties_json.heat_gen`;
- Federal Arrest when an illegal action reaches the 100% Heat cap;
- Heat decay: 1% online / 2% offline every 2 minutes.

The recovery reference explicitly identifies the Heat/regen cadence as an
unresolved conflict and instructs the project not to silently merge design
generations.

Accordingly:

- the implemented Searching, Shoplifting and Pickpocketing engines continue to
  use their later-generation per-crime `heat_gen` values from
  `crimes_master.penalties_json`;
- no global +0.01 override is applied to those later-generation engines;
- no authoritative Heat-decay worker is introduced;
- the old optional legacy server timer no longer mutates Heat at all.

The existing optional legacy timer can still restore Energy/Nerve/HP if its
unsafe legacy flag is explicitly enabled, but it cannot choose a Heat cadence.

## Crime penalty catalog is server-authoritative

The three currently implemented manual crime engines now require the current
server-owned crime row to contain valid:

- `penalties_json.heat_gen`;
- positive integer `penalties_json.jail_time`;
- positive integer `penalties_json.hosp_time`.

The earlier code used fallback values such as 60-second Jail/Hospital durations
and hard-coded Heat values. Those fallbacks have been removed.

The connected development catalog currently has complete positive Jail,
Hospital and Heat penalty data for all implemented rows:

- Searching: 12 / 12;
- Shoplifting: 8 / 8;
- Pickpocketing: 30 / 30.

If the required penalty data drifts or becomes malformed, the crime action
fails closed instead of substituting a default.

## Crime tool requirements

The current crime catalog stores implemented tool requirements as item IDs.

Recovered examples include:

- item 368 — Heavy Duty Crowbar;
- item 371 — Wire Cutters;
- item 413 — Handheld Metal Detector.

The old engines compared some numeric catalog IDs against item names or used a
mixed ID/name parser.

Searching and Shoplifting now resolve a required tool strictly as a current
`items_master.item_id`, lock the matching `user_inventory` row, and require
positive quantity. A missing catalog item or missing player tool fails closed.

No client-supplied tool identity is trusted.

## Federal Arrest

The later Crimes source states that reaching 100% Heat causes Automatic Federal
Arrest with:

- all Dirty Cash confiscated;
- 50 Influence lost;
- maximum Jail time.

The stabilized implementation now:

1. compares current Heat + the crime's catalog Heat using PostgreSQL `numeric`,
   not JavaScript floating point;
2. treats reaching/capping at 100 as the Federal Arrest boundary;
3. derives maximum Jail time from the current server-owned
   `crimes_master.penalties_json.jail_time` catalog;
4. confiscates all Dirty Cash;
5. applies an exact 50-Influence deduction only where that deduction is
   currently representable without choosing an unresolved negative-balance
   policy;
6. sets Jail state and clears Hospital state in the same transaction.

At reconciliation time all 273 crime rows have valid positive Jail durations
and the catalog maximum is **1,209,600 seconds (14 days)**.

### Influence floor remains unresolved

The recovery specification explicitly flags whether Influence may become
negative as unresolved.

The old Federal Arrest code used
`GREATEST(0, influence - 50)`, which changes “lose 50 Influence” into “lose up
to 50 Influence.”

This pass does not choose either interpretation.

If the current player has at least 50 Influence, Federal Arrest subtracts
exactly 50.

If the player has less than 50 Influence, the crime transaction fails closed
with HTTP 409 before settlement. The project therefore cannot silently clamp
or create negative Influence until that policy is selected canonically.

## Jail / Hospital single-state enforcement

The Jail & Heat source defines a Single State Rule: a player cannot be in Jail
and Hospital at the same time.

Crime-driven state transitions now enforce that directly:

- crime Hospitalization clears `jail_expires_at` and resets
  `jail_initial_seconds`;
- crime Jail clears `hospital_expires_at`;
- Federal Arrest clears `hospital_expires_at`.

All Jail/Hospital durations are applied through parameterized PostgreSQL
interval arithmetic rather than SQL string interpolation.

This pass does **not** reinterpret every historical row or add a timestamp
CHECK constraint; expired state timestamps are retained by the current schema,
so a simple “both columns cannot be non-null” constraint would be incorrect.

## Ordinary Jail outcomes versus older arrest penalties

The older Jail source also describes arrest as immediately losing all unbanked
Dirty Cash and 50 Influence.

The later Crimes generation separately defines Federal Arrest at 100 Heat and
contains ordinary crime Jail outcomes in `penalties_json`.

This pass does not silently apply the older global arrest-loss rule to every
later-generation critical-fail Jail outcome. That interaction remains a
cross-generation design decision.

Federal Arrest uses the explicit later-generation confiscation/scandal rule.
Ordinary catalog Jail outcomes currently apply their catalog Heat and Jail
duration only.

## Jail actions deliberately paused

### Bail

The recovered source establishes:

- Bail uses Clean Cash;
- price is based on the **initial** sentence, not remaining time;
- bailing another player grants +25 Influence;
- self-bail grants no Influence.

It does **not** define a Clean Cash rate.

The former backend value of **$100 per minute** was code-only. Therefore
`POST /jail/bail` returns HTTP 503 until a canonical rate exists.

### Breakout / Escape

The recovered source establishes:

- outside-in Bust Out is performed by a free player;
- inside-out Escape is performed by the inmate;
- the actor spends Nerve;
- a failed attempt adds +20 Heat and +1 hour to the sentence;
- outside-in Bust Out is gated by the recovered Juris Doctor
  `jail_bust_out` University entitlement.

It does **not** define the Nerve cost or success probability.

The former **5 Nerve / 40%** values were code-only. Therefore
`POST /jail/breakout` returns HTTP 503.

The source-backed JD entitlement implemented earlier remains valid as an access
rule, but the action itself is unavailable at the top of this stack until the
missing balance values are chosen.

### Prison Yard

The source requires:

- Energy spending;
- gains split evenly across STR, DEF, DEX and SPD;
- a drastically lower multiplier than a neighborhood Gym.

It does not define the multiplier or an EXP award.

The former prison-yard multiplier and +5 EXP-per-Energy behavior were code-only.
Therefore `POST /jail/gym/train` returns HTTP 503.

## Medical Revive

Medical Revive has enough recovered data to remain active without inventing a
healing amount.

The current City Hospital catalog explicitly defines:

> Medical Revive Skill: Unlocks the ability to revive others from the hospital.
> Cost: 75 Energy.

Its passive rule also records `ability: revive, energy_cost: 75`.

University course 82, **Combat Medic Training**, grants the normalized
`revive_ally` unlock and describes the ability to revive fallen allies.

The backend treats these as two source-backed entitlements to the same Medical
Revive action. The shared action cost is the recovered City Hospital
**75 Energy** rule; the University course does not define a separate cost
override.

Before settlement, the backend verifies the current City Hospital passive
description/rule. If that passive source changes, Medical Revive fails closed
for review.

The action:

- derives the actor from authentication;
- locks actor and target deterministically;
- requires persistent idempotency;
- requires either rank-5/mastered City Hospital or `revive_ally`;
- requires the target to be actively hospitalized;
- rejects a target simultaneously marked as actively jailed;
- spends exactly 75 Energy;
- clears the target's Hospital timer and state reason.

### No invented HP restoration

The previous implementation forced the target to at least **20 HP**, but no
recovered source defines that value.

This pass removes the 20-HP grant.

Crime-driven Hospital outcomes already place the player at 1 HP, so Medical
Revive can discharge those patients without changing HP.

If a future/legacy patient is at 0 HP, the action fails closed. The GDD says
0 HP implies Hospitalization, but no recovered source specifies the HP amount a
Medical Revive should restore. That value must be selected before zero-HP
combat patients can be revived safely.

## Verification boundary

Performed:

- Jail & Heat / Crimes / University / City Job source reconciliation;
- development catalog and schema inspection;
- static GitHub readback;
- exact City Hospital passive-rule verification against the development
  catalog.

No schema migration was required for this pass.

Not performed by project instruction:

- gameplay testing;
- build/runtime testing;
- deployment;
- production changes.
