# Company Employment Contract Reconciliation — 2026-11-05

## Scope

This pass reconciles real-player company hiring against the Player-Owned
Companies source requirement that real players receive **negotiated Clean Cash
salaries**.

It does not implement payroll settlement.

No gameplay/build/runtime tests or deployment were performed.

## Source-backed employment model

Recovered company design distinguishes:

- NPC Crew: no salary;
- real players: negotiated Clean Cash salary;
- company positions: source Working Stat requirements and Working Stat gains;
- daily payroll: company Dirty Cash is eventually used to pay real employees
  Clean Cash.

PR #28 recovered the exact position catalog.

Before this pass, accepting an application immediately created:

- position: `Unassigned`;
- salary: `0`.

That bypassed the negotiated-salary requirement.

This pass removes direct hiring by Director acceptance.

## Application flow

`POST /companies/apply` remains the entry point.

A pending application is only an expression of interest.

It is **not employment consent**.

Director rejection remains immediate and idempotent.

Direct `manage-applicant action=accept` now fails closed and instructs the
Director to create a negotiated offer.

## Employment offer schema

Migration:

`20261105012000_company_employment_contracts_20261105.sql`

creates:

`company_employment_offers`

Fields:

- offer ID;
- source application;
- company;
- intended employee;
- offering Director;
- source-normalized position;
- negotiated daily Clean Cash salary;
- status;
- immutable request/source UUID;
- creation/responded timestamps.

Statuses:

- `pending`;
- `accepted`;
- `rejected`;
- `withdrawn`.

Constraints require:

- positive integer Clean Cash salary;
- controlled status values;
- responded timestamp only for terminal responses.

A partial unique index permits at most one pending offer per application.

Director + source UUID is unique for replay identity.

The table is backend-owned:

- RLS enabled;
- direct anon/authenticated access revoked.

## One-company-per-real-player invariant

The same migration adds:

`company_employees_one_real_company_per_player_idx`

on `employee_id` where `is_npc = false`.

This makes the existing server rule durable in PostgreSQL: one real player
cannot simultaneously hold employment rows in multiple companies.

NPC recruit IDs remain outside that invariant.

## Director creates offer

New endpoint:

`POST /company-management/employment-offer`

Director supplies only:

- application ID;
- source position ID;
- proposed daily Clean Cash salary.

Server verifies:

- authenticated owner/Director;
- active company;
- pending application belongs to that company;
- applicant still exists;
- applicant has no City Job;
- applicant is not already employed;
- company still has staff capacity;
- position belongs to the company's type;
- applicant meets both recovered Working Stat thresholds;
- salary is an exact positive integer.

The server does not accept:

- arbitrary target user ID;
- client role strings;
- client requirement values;
- client stat values.

Persistent idempotency is required.

The offer stores the exact negotiated salary but does not move money.

## Applicant consent

New read boundary:

`GET /companies/employment-offers/:user_id`

returns the authenticated player's offers and source role requirements.

The backend also returns whether the offer is currently eligible for acceptance
based on:

- pending state;
- active company;
- no City Job;
- current Working Stats.

New mutation:

`POST /companies/employment-offers/respond`

Client supplies only:

- offer ID;
- `accept` or `reject`.

### Reject

Rejection:

- locks the player's offer;
- marks the offer rejected;
- leaves the original application pending so negotiation can continue;
- pays nothing.

### Accept

Acceptance revalidates everything under transaction locks:

- authenticated player owns the offer;
- company still exists and is active;
- source application still pending;
- player still has no City Job;
- player still has no company employment;
- company still has capacity;
- offered position still belongs to company type;
- player still meets both source Working Stat requirements;
- stored salary remains positive integer.

Only then does the server:

- create the real-player `company_employees` row;
- use the server-stored source `role_key`;
- use the server-stored negotiated salary;
- mark application Accepted;
- mark offer accepted;
- close any other pending offers to the same player as withdrawn;
- write company audit log;
- commit idempotent response.

Other companies' applications are not fabricated into Rejected state.

## Director withdrawal

New endpoint:

`POST /company-management/employment-offer/withdraw`

The current owner/Director can withdraw a pending offer.

The underlying application remains pending.

## Payroll remains paused

An accepted contract stores an agreed daily Clean Cash salary.

It **does not currently pay it**.

The company cash-flow blocker remains because the project still lacks canonical
rules for:

- daily settlement boundary/time zone;
- insufficient Dirty Cash behavior;
- exact interaction with laundering tax;
- ACU tax reduction;
- bankruptcy ordering;
- severance;
- audit settlement across multiple employees.

No scheduled payroll worker is introduced.

## Flutter companion

Draft PR #5 now:

### Director

- applicant dialog no longer has direct ACCEPT;
- Director can REJECT;
- eligible applicants can receive MAKE OFFER;
- role choices come from normalized source positions;
- client filters for recovered stat requirements as UX only;
- server revalidates requirements;
- Director enters proposed daily Clean Cash salary;
- pending offer is shown;
- Director can withdraw it.

### Applicant

City Hall now loads the authenticated player's employment offers.

Pending offers show:

- company;
- source role;
- negotiated Clean Cash salary;
- source stat requirements;
- server `can_accept` status.

Applicant can:

- ACCEPT;
- REJECT.

The client sends only offer ID and action.

### Existing employee display

Company dashboard labels salary as:

**Agreed Salary**

and explicitly states:

**Payroll settlement paused**

### Incorporation correction

City Hall previously still displayed an executable incorporation action while
the backend correctly returned 503 because the recovered supply-chain product
generation conflicts with the legacy 20-row product catalog.

The client now consumes:

- `incorporation_available`;
- `incorporation_blocker`.

Incorporation remains visibly disabled instead of presenting a payable action.

The legacy request-body player ID was also removed from the incorporation call.

## Development state

At readback:

- employment offers: 0;
- company employees: 0;
- RLS enabled on employment offers.

No player/company state required migration.

Supabase security/performance advisor checks are clean.

## Still unresolved

This pass intentionally does not implement:

- payroll;
- salary renegotiation for existing accepted employees;
- employee resignation;
- Director firing/severance;
- training;
- NPC assignment;
- effectiveness weighting;
- Working Stat gain cadence;
- company bankruptcy/severance.

These remain separate settlement/mechanics reconciliations.

## Verification boundary

Performed:

- company design reconciliation;
- source-position integration;
- development migration/readback;
- RLS confirmation;
- static backend/client readback;
- Supabase advisor review.

Not performed by instruction:

- Node runtime tests;
- employment-flow integration tests;
- concurrency tests;
- payroll tests;
- Flutter analyze/build/widget tests;
- deployment;
- production changes.
