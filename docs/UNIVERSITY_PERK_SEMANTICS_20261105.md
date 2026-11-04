# University Perk Semantics Reconciliation — 2026-11-05

## Scope

This pass continues the source-preserving University work from the earlier stabilization stack.

The canonical runtime entitlement source is the normalized `education_courses_master.rewards_jsonb` catalog. Completed-course ownership comes from `user_completed_courses`.

This pass does **not** create a generic perk interpreter. A perk or unlock is connected to gameplay only when both of the following are true:

1. its behavior is explicit in recovered project sources; and
2. an existing backend mechanic provides a clear integration point without inventing stacking, rounding, scope, or interaction rules.

## Sources reconciled

The following recovered sources were compared:

- the original **University & Education Canvas (V1.0)**;
- the **Cold streets database** education course catalog;
- the current normalized Supabase `education_courses_master.rewards_jsonb`;
- the original **Jail & Heat Canvas (V1.0)**;
- the current stabilized backend routes.

The University canvas establishes permanent course rewards and the one-course-at-a-time progression model, but it does not define a universal numeric-perk stacking formula.

The spreadsheet and normalized runtime catalog agree on the currently recovered perk/unlock keys and values.

## Enabled consumers

### `revive_ally`

Already implemented in the prior stack.

Course 82, **Combat Medic Training**, grants `revive_ally`. The existing Hospital medical-revive action accepts this completed-course entitlement without inventing a numeric modifier.

### `jail_bust_out`

Enabled in this pass.

Course 70, **Juris Doctor (JD)**, grants `jail_bust_out` and its description states that the degree grants the power to bust inmates out of jail.

The Jail source separately defines two distinct actions:

- **Bust Out (Outside-In):** a free player spends Nerve to break an inmate out.
- **Escape (Inside-Out):** an inmate spends their own Nerve to escape.

Accordingly:

- self-escape remains available without a University requirement;
- attempting to break out another inmate requires the authenticated actor to be free;
- attempting to break out another inmate requires the source-backed `jail_bust_out` completed-course entitlement;
- the existing stabilized breakout Nerve cost, RNG, penalties, row locking, and idempotency behavior are otherwise unchanged.

The entitlement is checked from server-owned completed-course/catalog state. The client does not submit a course ID or unlock key.

## Numeric perks deliberately left declarative

The normalized catalog currently contains these numeric perk families:

- `energy_regen_bonus`
- `gym_gains`
- `tax_reduction`
- `bank_interest`
- `hacking_success`
- `company_upgrade_discount`
- `job_payout_boost`
- `bail_discount`
- `medical_boost`
- `inventory_capacity`
- `dump_find_chance`
- `assault_heavy_damage_boost`
- `firearm_accuracy`
- `max_nerve`
- `heat_reduction`
- `stealth_ghost`
- `overdose_immunity`
- `counterfeit_success`
- `crop_yield_boost`

They remain non-executable in this pass.

The recovered data provides values, but does not consistently answer the interaction questions needed for safe settlement, including:

- additive percentage points versus multiplicative scaling;
- whether duplicate perks in the same family add, replace, or take the maximum;
- ordering relative to City Job mastery, property, syndicate, item, or other external modifiers;
- integer/fractional rounding rules;
- whether caps apply before or after University effects;
- which exact payout, success roll, Heat event, inventory limit, healing path, or regeneration cadence is affected.

Examples of unresolved ambiguity include two `bail_discount` courses, two `max_nerve` courses, two `inventory_capacity` courses, and two `heat_reduction` courses. No stacking rule is recovered for those pairs.

## Boolean/facility unlocks not connected in this pass

Other recovered unlocks remain stored as entitlements but are not wired merely because their key exists.

Examples include:

- `city_pharmacy`
- `supplement_store`
- `steroid_tolerance`
- `city_bank`
- `basic_hacking_crimes`
- `advanced_hacking_crimes`
- `jail_visits`
- `use_advanced_meds`
- `black_market_organs`
- `advanced_smuggling`
- `chop_shop`
- `craft_explosives`
- `city_dump_access`
- `military_surplus_store`
- `ammunition_store`
- `electronic_crime_tools`
- `illicit_lab_access`
- `basic_forgery_crimes`
- `indoor_grow_house`

These require an existing mechanic whose access boundary is itself source-unambiguous. Some target systems are still design-only or incomplete. Others conflict with already recovered progression; for example, the broader recovery material includes early-game Bank access while the course catalog also carries a `city_bank` unlock, so this pass does not silently reinterpret that key as a global Bank lock.

Boolean perks such as `view_opponent_hp` and `vehicle_upgrades` likewise remain declarative until their target systems are stabilized.

## Security and settlement boundary

The new jail entitlement consumer preserves the existing hardened transaction:

1. actor identity comes from verified authentication;
2. actor/target player rows are deterministically locked;
3. the persistent idempotency record is resolved;
4. current jail/free state is validated;
5. for an outside-in bust, completed-course entitlement is read from server-owned catalog state;
6. only then is secure RNG consumed and the existing breakout settlement executed.

A replay of a completed idempotent request returns the stored terminal response without rolling again.

## Verification boundary

Source/catalog reconciliation and GitHub code readback only.

Per project instruction, no gameplay test, build test, deployment, or production change was performed.
