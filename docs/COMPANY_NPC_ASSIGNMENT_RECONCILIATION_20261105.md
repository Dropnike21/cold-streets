# Company NPC Recruit Assignment Reconciliation — 2026-11-05

## Scope

This pass reopens the source-backed subset of assigning Syndicate NPC recruits
to player companies now that PR #28 recovered the exact company position
catalog.

It does not implement company effectiveness, production, training or payroll.

No gameplay/build/runtime tests or deployment were performed.

## Recovered source

Player-Owned Companies establishes:

- NPC Crew can be recalled from crime loops and used as company staff;
- NPC Crew work for **$0 salary**;
- NPCs have a Max Potential stat cap;
- company positions carry Working Stat requirements;
- weighted company effectiveness exists, but the exact role weights/formula are
  not fully normalized.

The company sheet now supplies 179 exact position definitions with:

- ACU/OPS/PRE/RES requirements;
- primary/secondary threshold amounts;
- source gain values.

The existing `user_crew` rows contain current and maximum ACU/OPS/PRE/RES
values.

That is sufficient to authorize roster assignment without inventing
effectiveness.

## Database integrity

Migration:

`20261105013500_company_npc_staffing_integrity_20261105.sql`

changes `company_employees.effectiveness_score`:

- removes the legacy default `100`;
- makes it nullable;
- permits only nonnegative values when present.

This is deliberate: the project does not currently have a canonical
effectiveness formula, so new employees should not silently receive a fake
100% effectiveness score.

It also enforces:

- NPC employees must have `daily_salary = 0`;
- position role must be nonempty.

Migration:

`20261105014000_company_npc_single_assignment_20261105.sql`

adds a partial unique index so one globally unique crew ID cannot appear in
multiple company rosters simultaneously.

## Shared crew-domain cooldown

The reconciled crew scheduler already uses:

- `current_domain`;
- `last_transfer_at`;
- a 10-minute cooldown when switching between different active domains.

That logic was previously local to `routes/syndicate.js`.

This pass extracts it to:

`utils/crewDomain.js`

Both crew-crime scheduling and company staffing now use the same transfer
guard.

Behavior is preserved for crime scheduling.

## Company staffing read boundary

`GET /company-management/:company_id/available-crew/:user_id`

now:

- derives the authenticated actor;
- verifies company ownership;
- reads only the actor's recruits;
- exposes current/max Working Stats;
- reports active crew-crime schedule;
- reports current company assignment;
- returns exact source company positions;
- calculates which source positions each recruit currently qualifies for;
- explicitly reports:
  - NPC salary rule = zero;
  - effectiveness unresolved.

This eligibility is convenience/read state only; the mutation rechecks it.

## NPC assignment mutation

`POST /company-management/assign-crew`

is reopened.

Client supplies only:

- crew ID;
- source position ID.

Server verifies:

- authenticated company owner/Director;
- recruit belongs to actor;
- no active crew-crime schedule;
- recruit is not already on any company roster;
- active company;
- recovered base staff capacity;
- position belongs to company type;
- recruit meets both source Working Stat requirements;
- shared domain-transfer cooldown.

Transaction lock order follows the existing crew scheduler:

1. crew-crime schedule;
2. recruit;
3. owner;
4. persistent idempotency;
5. company;
6. roster/position state.

On success:

- recruit domain becomes `COMPANY`;
- recruit assignment points at the company;
- company employee row is inserted;
- source role key is stored;
- salary is exactly 0;
- effectiveness is NULL/unresolved;
- company log is written;
- response is committed idempotently.

No stat gain or company-effectiveness effect is applied.

## Recall

Existing authoritative recall remains available.

It:

- removes the NPC company employee row;
- clears a stale crew-crime schedule if one exists;
- changes assignment to UNASSIGNED;
- preserves domain history needed by the shared transfer cooldown.

## Legacy Syndicate alias

The old:

`POST /syndicate/assign_company`

remains closed.

There is now one authoritative company staffing mutation:

`POST /company-management/assign-crew`

This avoids two APIs implementing different company ownership and position
checks.

## Flutter companion

Draft PR #5 now:

- fetches source company positions with the actor's recruits;
- shows active crime-automation conflicts;
- shows the recruit's current company role;
- disables assignment if no source role is eligible;
- requires choosing one eligible source position;
- sends only crew ID + position ID;
- displays $0 NPC salary as a source rule;
- keeps recall available.

The client does not calculate or submit effectiveness.

## Still unresolved

This pass does not implement:

- Core/Support/Operational/Sales weight mapping;
- weighted average effectiveness;
- NPC Max Potential -> effectiveness curve;
- company production impact;
- sales impact;
- training-point generation;
- individual NPC training;
- 50%-reduced NPC training gain;
- inactivity decay;
- company specials affecting NPCs.

Those remain separate mechanics work.

## Development state

At readback:

- company employee rows: 0;
- recruit rows: 0.

No development-player roster data required migration.

Supabase security/performance advisor checks are clean.

## Verification boundary

Performed:

- company source reconciliation;
- crew scheduler/cooldown reconciliation;
- development migration/readback;
- backend static readback;
- Flutter static readback;
- Supabase advisor review.

Not performed by instruction:

- Node runtime tests;
- assignment/recall integration tests;
- cooldown concurrency tests;
- Flutter analyze/build/widget tests;
- deployment;
- production changes.
