# Crew Crime Automation Reconciliation — 2026-11-05

## Scope

This pass replaces the unsafe client-driven crew crime completion model with a server-owned, persisted automation schedule.

It reconciles three generations of recovered data without blending missing values:

1. **Recruits Canvas / Crew Automation Mechanics**
2. **Crimes Database / NPC Automation**
3. the normalized runtime **`crimes_master`** catalog in Supabase

The implementation is intentionally narrower than every row marked `allow_npc=true`. A crime is activated only when the current catalog contains every value required for deterministic server settlement.

## Recovered behavior

The Recruits source defines the core automation behavior:

- assigned NPCs automate a target street crime;
- they receive the mathematical average of the target crime cash range as Dirty Cash;
- a successful loop grants exactly +1 to two random recruit stats, capped at the recruit's max potential;
- the later stat update expands recruit stats to STR, DEF, DEX, SPD, ACU, OPS, PRE and RES;
- required crime tools must be present in the player's inventory;
- NPC automation grants no Crime EXP and no rare/critical loot;
- NPCs can perform only one domain task at a time;
- switching between different street crimes has no transfer cooldown;
- switching between different systems uses a 10-minute transfer cooldown.

The older Recruits generation also describes a fixed 60-second loop and a flat 1% casualty chance.

The later Crimes Database/runtime catalog carries per-crime fields specifically for NPC automation:

- `mechanics_json.allow_npc`
- `mechanics_json.automation_CD`
- `penalties_json.npc_casualty_risk`
- `requirements_json.tool_req`
- `rewards_json.min_cash`
- `rewards_json.max_cash`

Where those later per-crime fields are present and complete, this pass treats them as the more specific recovered rule. Missing later fields are **not** filled from the older 60-second/1% defaults.

## Fail-closed eligibility

A crime is exposed to crew automation only when all of the following are true:

- `allow_npc=true`;
- `automation_CD` is an explicit positive integer;
- `min_cash` and `max_cash` are explicit non-negative integers;
- the mathematical average is positive and integer-denominated;
- `npc_casualty_risk` is explicitly present and between 0 and 1;
- the only requirement keys are `tool_req` and `time_of_day`;
- `time_of_day` is exactly `Any`;
- `tool_req` is either `NONE` or a valid current `items_master.item_id`.

The integer-average requirement is deliberate. Existing economy settlement treats currency as integer-denominated, so an odd min/max sum is not rounded up, rounded down, or converted to fractional cash without a recovered rounding rule.

Day/Night crimes are paused because no canonical NPC automation clock/timezone semantics have been recovered. Crimes with consumables, inventory-item inputs, emails, botnet resources, or other additional requirements are paused rather than silently bypassing or consuming those resources.

Zero-cash specialized crimes are also paused in this pass because their meaningful reward is not represented by the cash average and the Recruits source does not define how their specialized resource output should interact with NPC automation.

## Current enabled catalog subset

The connected development catalog resolves to 13 source-complete rows:

| Crime ID | Crime | Interval | Average Dirty Cash | Casualty risk | Tool |
|---:|---|---:|---:|---:|---|
| 1 | Search Public Trash Cans | 30s | 5 | 1% | None |
| 2 | Check Payphone Coin Returns | 45s | 8 | 1% | None |
| 15 | Swipe Bottles from the Liquor Store | 300s | 85 | 3% | None |
| 16 | Lift Apparel from the Boutique | 450s | 155 | 4% | None |
| 17 | Loot Devices from the Tech Store | 600s | 275 | 6% | None |
| 18 | Snatch Watches from the Jeweler | 900s | 475 | 8% | Wire Cutters (item 371) |
| 19 | Raid the High-End Wine Cellar | 1800s | 850 | 10% | None |
| 25 | Teenager | 180s | 55 | 2% | None |
| 28 | Arguing Couple | 360s | 140 | 4% | None |
| 29 | Foreigner | 420s | 175 | 4% | None |
| 36 | Street Thug | 1080s | 675 | 8% | None |
| 39 | Stressed Shopper | 1800s | 1325 | 12% | None |
| 43 | Delivery Rider | 3000s | 2800 | 20% | None |

The subset is derived at runtime from the catalog predicate; the IDs above are documentation of the current recovered development catalog, not a hard-coded reward allowlist.

## Persistent schedule

Migration `20261104205500_crew_crime_scheduler_20261105.sql` adds `crew_crime_assignments`.

Each row stores:

- the crew member;
- the server-owned crime ID;
- assignment time;
- the next due settlement time;
- the last successful settlement time.

No legacy `user_crew.assignment` row is backfilled. Existing assignment text has no authoritative start timestamp, so backfilling could create retroactive currency.

The table is server-only: RLS is enabled and direct `anon` / `authenticated` table privileges are revoked.

The additional `crime_id` foreign-key index is added by `20261104210000_crew_crime_scheduler_indexes_20261105.sql`.

## Assignment security

`POST /syndicate/assign_job` now:

1. derives the actor from verified authentication;
2. requires a persistent `Idempotency-Key`;
3. validates exact crew ownership;
4. resolves the crime from the server-owned catalog;
5. rejects any crime outside the fail-closed automation subset;
6. locks and verifies the required inventory tool;
7. applies the recovered 10-minute cross-domain transfer rule;
8. persists the due timestamp and display assignment atomically.

The client may identify the desired catalog crime by ID or by the legacy exact title, but it never supplies payout, timer, casualty probability, stat gain, or tool identity.

Multiple NPCs may automate the same street crime. The former backend behavior that forcibly unassigned another NPC from the same crime had no recovered design basis and was removed.

Switching between two street crimes remains cooldown-free because both are in the `CRIMES` domain.

## Automatic settlement

The worker uses database-persisted schedule state and `FOR UPDATE SKIP LOCKED`, so multiple backend replicas can poll safely without paying the same due row twice.

The settlement lock order is:

`schedule -> crew -> user -> required inventory row`

For a due loop:

- the current catalog rule is resolved again; drift or missing semantics pauses the assignment;
- current assignment/domain state is verified;
- the required tool is checked again;
- if the tool is missing, no payout, stat growth, or casualty roll occurs and a new interval begins;
- casualty is rolled with `crypto.randomInt` against the exact catalog probability;
- a fatal loop permanently deletes the recruit and writes a user event;
- a non-fatal successful loop adds the exact integer average to Dirty Cash;
- exactly two distinct recruit stats are selected with secure RNG and incremented by 1, capped at their matching max values;
- the next due timestamp advances in the same database transaction.

No Crime EXP, crime skill EXP, Influence, rare loot, ordinary loot, Nerve charge, or client-supplied reward is settled by this worker.

### Fatal-loop ordering

The recovered sources say stat growth occurs on a **successful** loop and casualty is a disaster on a loop, but do not explicitly say whether a fatal loop also pays cash.

This implementation takes the conservative economic interpretation: a fatal loop is not successful, so it grants no payout and no stat growth before the recruit is deleted.

This choice prevents over-crediting and is documented rather than hidden.

### No retroactive catch-up

After a successful, blocked, or otherwise processed loop, the next due time is based on the current server time plus the catalog interval.

The worker does not replay every interval missed while the backend was offline. Historical tool possession and other required state are not persisted, so retroactive catch-up would require inventing state history and could mint unsupported cash.

## Client completion endpoint

The old `POST /syndicate/complete_job` path remains non-settling. It now returns HTTP 410 and states that crew payouts are settled automatically by the server.

A client cannot choose when a payout occurs or submit a payout amount.

## Known boundaries

This pass does not define:

- Day/Night NPC automation clock semantics;
- consumable/resource-input automation;
- fractional cash rounding;
- specialized zero-cash resource generation;
- Company or Syndicate Wall assignment settlement;
- offline catch-up;
- any client-side UX changes.

Company assignment remains fail closed in the backend until its canonical position/workflow catalog is reconciled.

## Development database state

The two scheduler migrations were applied to the connected **development** Supabase project only.

Immediately after schema application:

- `crew_crime_assignments` contained zero rows;
- the runtime eligibility predicate resolved exactly 13 current catalog crimes;
- no gameplay settlement was triggered.

Supabase's RLS-no-policy advisory for this table is intentional because it is a server-only table with direct client privileges revoked. The advisor also identified the `crime_id` FK index, which was added in the second migration.

## Verification boundary

Performed:

- source reconciliation;
- catalog/schema inspection;
- migration application to the development database;
- static GitHub readback;
- Supabase security/performance advisory review.

Not performed by project instruction:

- gameplay testing;
- build/runtime testing;
- deployment;
- production changes.
