# Company Workflow Reconciliation — 2026-11-05

## Scope

This pass reconciles the current backend company routes against the recovered
**Player-Owned Companies** design and the connected development Supabase catalog.

The objective is not to make the whole company system playable from incomplete
data. It is to keep economically sensitive workflows closed unless their
server-authoritative inputs and settlement rules are recoverable.

## Recovered design authority

The company source defines a broad economic system:

- three-tier vertical supply chains and supply contracts;
- staffing slots with weighted Core, Support, Operational and Sales roles;
- NPC Syndicate recruits working for zero salary with Max Potential caps;
- real-player employees using negotiated Clean Cash salaries;
- a daily company loop for salaries, laundering, production and sales;
- inventory/stockpiling;
- a two-day runway bankruptcy fail-safe and employee severance;
- daily training points;
- office, warehouse and facility upgrades;
- contract breach penalties and inactivity decay.

Those rules require relationship catalogs and daily-settlement semantics that
are not present in the reconstructed runtime database.

## Current development catalog state

At reconciliation time the connected development database contains:

| Catalog/runtime object | Rows |
|---|---:|
| `company_types_master` | 120 |
| `company_products_master` | 20 |
| `company_positions_master` | 0 |
| `company_specials_master` | 0 |
| `blueprint_products` | 0 |
| `player_companies` | 0 |

The type table still contains legacy text fields such as `positions_json`,
`products_json`, `specials_json` and `upgrades_json`. These text values
are not treated as a substitute for the missing normalized relationship
catalogs. In particular, the type-level product names and the recovered
20-row product master belong to incomplete/conflicting generations and are not
silently mapped together.

## Explicit fail-closed boundaries

### Incorporation

`POST /companies/incorporate` now returns HTTP 503 unconditionally.

The old route could become active as soon as any `blueprint_products` row was
inserted, even if a company type was only partially reconstructed. That could
charge a setup fee and create a company with an incomplete inventory graph.

Incorporation stays closed until canonical product input/output relationships
are recovered and reviewed.

### Employee contract/position management

`POST /company-management/manage-employee` remains HTTP 503 and its old unsafe
implementation has been removed.

The legacy route accepted:

- an arbitrary client-supplied position string;
- a client-supplied salary parsed with JavaScript `parseInt`;
- a client-selected employee/NPC type;
- a training action that directly incremented effectiveness.

The normalized position catalog currently has zero rows, and the recovered
design does not yet provide a normalized salary-acceptance or training
settlement contract. No role, salary, or training result is invented.

### Directorship transfer

`POST /company-management/change-director` remains HTTP 503.

The source supports multi-company ownership through vertical integration, but
does not establish the target-acceptance and ownership-transfer interaction
rules needed to safely move a company to another player. The old direct
ownership flip is therefore removed from the executable path.

### Liquidation

`POST /company-management/sell-company` remains HTTP 503.

The legacy implementation returned 75% of setup cost plus vault balances.
That 75% liquidation formula is not established by the recovered company
source. The source instead defines bankruptcy, runway and severance behavior,
which is not yet normalized or scheduled.

### Stock ordering

`POST /company-management/order-stock` remains HTTP 503.

The old implementation used a system supplier with a 20% markup. The recovered
design instead centers on supply contracts and vertical integration.
`blueprint_products` is also empty. No system supplier economy is activated
by inference.

### Upgrades

`POST /company-management/buy-upgrade` remains HTTP 503.

The old route trusted a client-supplied upgrade cost. Upgrade definitions are
still legacy text rather than a normalized catalog with authoritative cost,
level cap, upkeep and effect semantics.

### NPC company assignment

Both company NPC assignment entry points remain HTTP 503:

- `POST /company-management/assign-crew`
- `POST /syndicate/assign_company`

The source explicitly allows Syndicate NPCs to work for companies at zero
salary, but there is no normalized company-position catalog to determine what
job they occupy, what requirements apply, or how their effectiveness contributes
to production.

## Enabled workflow: pending player applications

Application submission was already source-neutral and hardened in the earlier
stack. This pass makes the Director review path executable without depending
on unresolved company production formulas.

`POST /company-management/manage-applicant` accepts only:

- `application_id`;
- action `accept` or `reject`;
- persistent `Idempotency-Key`.

The client does **not** supply the target player ID, username, position, salary
or company capacity.

Inside one transaction the backend:

1. derives the Director from verified authentication;
2. resolves the managed company from the authenticated owner/Director boundary;
3. persists/resolves the idempotency record;
4. locks and rechecks the company owner and active state;
5. locks the exact pending application row belonging to that company;
6. takes the target player ID only from that row;
7. on acceptance, locks the target player and rechecks that they have not joined
   a City Job or another company since applying;
8. enforces the recovered base employee cap conservatively;
9. inserts the player as `Unassigned` with salary 0;
10. marks the application Accepted or Rejected and logs the transition.

Acceptance does not assign a company position, negotiate a salary, grant
training, or start a production loop.

The application submission route now uses the database's partial unique index
with `ON CONFLICT ... DO NOTHING`, so two concurrent requests with different
idempotency keys cannot create duplicate pending applications for the same
user/company.

## NPC recall escape hatch

New NPC company assignment remains paused, but `recall-crew` remains available
as a recovery path for any legacy/manually inserted company roster row.

Recall now uses:

- authenticated actor identity;
- exact integer crew ID;
- persistent idempotency;
- deterministic shared-state locking beginning with any crew-crime schedule;
- crew ownership recheck;
- current company ownership recheck;
- exact company/NPC roster-row validation.

It removes any stale crew-crime schedule, removes the company roster row, and
marks the recruit `UNASSIGNED`.

The recruit's `current_domain` is deliberately left as `COMPANY`, not reset
to `IDLE`. Likewise, crew-crime recall now leaves `current_domain=CRIMES`.
In this recovered model the field acts as the last active work domain while the
assignment itself indicates whether the recruit is currently working.

This preserves the existing 10-minute cross-system transfer boundary: briefly
recalling a recruit cannot erase which domain they most recently entered and
bypass the transfer cooldown. Reassigning within the same domain remains
cooldown-free.

## Database invariants

Development migration
`20261104212500_company_workflow_invariants_20261105.sql` adds constraints that
do not depend on unresolved production formulas:

- application status must be Pending, Accepted or Rejected;
- application pitch length is capped at 2000 characters;
- one pending application per company/user;
- employee salary must be a non-negative integer;
- company inventory quantity and daily volume cannot be negative;
- company inventory price must be a non-negative integer;
- shipment quantity must be positive;
- shipment total cost must be a non-negative integer;
- company Clean/Dirty vault balances must remain integer-denominated;
- advertising budget must be a non-negative integer;
- company upgrade-level counters cannot be negative.

These complement the pre-existing non-negative company-vault constraints.

Development migration
`20261104213500_company_fk_indexes_20261105.sql` adds covering indexes for
company foreign keys identified by the Supabase performance advisor:

- blueprint product -> product;
- applicant -> user;
- inventory -> product;
- position -> type;
- shipment -> company;
- shipment -> product;
- special -> type.

## RLS advisory

Supabase reports `rls_enabled_no_policy` for the reconstructed company tables.
This is consistent with the current backend-authoritative model: RLS is enabled
and no direct client policy grants table access. Company reads/writes in this
stack go through the authenticated backend routes.

No permissive RLS policies were added merely to silence the advisor.

## Still unresolved

The following require further source/catalog reconstruction before activation:

- normalized type-to-product input/output blueprints;
- normalized company positions and stat thresholds;
- weighted effectiveness formula;
- daily production/sales settlement;
- negotiated salary acceptance and daily payroll;
- training-point accrual/reset and training gains;
- normalized upgrade costs, caps, upkeep and effects;
- supply contracts and breach settlement;
- bankruptcy and severance ordering;
- special perks;
- NPC company work contribution;
- directorship transfer acceptance;
- liquidation rules;
- advertising spending/effect settlement.

## Development database state

Both company migrations in this pass were applied only to the connected
development Supabase project.

The company runtime tables contained zero player companies, employees,
applications and shipments during this reconciliation, so the migrations
changed schema guarantees only and did not mutate gameplay state.

## Verification boundary

Performed:

- source reconciliation;
- catalog/schema inspection;
- route hardening;
- static GitHub readback;
- development migration application;
- Supabase security/performance advisor review.

Not performed by project instruction:

- gameplay testing;
- build/runtime testing;
- deployment;
- production changes.
