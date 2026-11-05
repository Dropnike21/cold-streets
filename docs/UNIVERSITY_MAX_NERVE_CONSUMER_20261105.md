# University Explicit Max Nerve Consumer — 2026-11-05

## Scope

This pass implements one explicit University perk consumer:

`max_nerve`

No generic perk interpreter is introduced.

No runtime/gameplay/build tests or deployment were performed.

## Source-backed courses

The normalized education catalog contains exactly two reconciled Max Nerve perks.

### Course 162 — Emotional Intelligence

Recovered description:
minor permanent Max Nerve boost.

`rewards_jsonb` contains:

- +50 RES
- +40 ACU
- `max_nerve = 2`

### Course 170 — Master of Behavioral Science

Recovered description:
massive permanent Max Nerve boost.

`rewards_jsonb` contains:

- +300 RES
- +200 ACU
- `max_nerve = 10`

These are direct permanent pool increases, so they have an unambiguous consumer:
`users.max_nerve`.

## Fail-closed catalog pinning

The graduation route now contains an explicit reconciliation map:

- 162 -> +2 Max Nerve
- 170 -> +10 Max Nerve

Graduation fails closed if:

- either reconciled course no longer has exactly one `max_nerve` perk;
- its value changes;
- another unreconciled course suddenly contains `max_nerve`.

This prevents a catalog edit from silently changing a permanent player stat.

## Atomic graduation

The existing University graduation transaction already:

- authenticates actor;
- locks player;
- uses persistent idempotency;
- verifies course maturity;
- inserts the unique completed-course row;
- applies source Working Stat rewards;
- evaluates course-completion achievements.

This pass adds:

`max_nerve = max_nerve + explicit source reward`

to that same user update.

Course completion, Working Stats, Max Nerve, achievements and idempotent response therefore commit or roll back together.

The current `nerve` value is not increased or refilled by this perk.

## Response

Graduation now returns:

`applied_explicit_perks.max_nerve`

with:

- 0 for courses without an executable Max Nerve perk;
- 2 for course 162;
- 10 for course 170.

All other University perks remain in `recorded_entitlements` only.

## Database integrity

Migration:

`20261105015500_university_max_nerve_integrity_20261105.sql`

requires:

- `users.max_nerve > 0`;
- integer-denominated Max Nerve.

No cap is invented.

## Flutter companion

Draft PR #5:

- removes client actor IDs from enroll/dropout/graduate bodies;
- continues to synchronize the full authoritative user row after graduation;
- therefore receives the updated `max_nerve` automatically;
- displays source `max_nerve` perks as explicit `+N MAX NERVE` reward text;
- other perks remain descriptive source labels rather than client-executed effects.

## Still declarative

This pass does not activate:

- Energy regeneration bonus;
- Gym gains;
- Bank interest;
- bail discounts;
- company upgrade discount;
- job payout boost;
- heat reduction;
- combat/weapon perks;
- overdose immunity;
- vehicle upgrades;
- or any other normalized University perk.

Each still requires its own explicit consumer and interaction rules.

## Verification boundary

Performed:

- University source review;
- exact course 162/170 catalog readback;
- schema readback;
- migration application/readback;
- static backend/client readback;
- Supabase security/performance advisor review.

Not performed by instruction:

- Node runtime tests;
- graduation integration tests;
- idempotency/concurrency tests;
- Flutter analyze/build/widget tests;
- deployment;
- production changes.
