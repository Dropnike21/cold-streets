# Kevin / Post-Tutorial Mission Reconciliation — 2026-11-05

## Scope

This pass reconciles the handoff from the six server-authoritative Anonymous tutorial missions into the next contact, Kevin.

The goal is not to invent a Kevin campaign. It is to establish exactly what the recovered sources support, remove unsupported economy/progression mutations, and leave a safe boundary for later mission authoring or recovered data.

No runtime/gameplay/build tests or production deployment were performed.

## Recovered mission source

### Master spreadsheet

The recovered Cold Streets master spreadsheet has no `missions_master` worksheet.

The database recovery specification explicitly flags this:

- DB-15: mission VERIFY and Kevin turn-in historically lacked authoritative completion;
- DB-16: there is no spreadsheet `missions_master` tab, so original campaign rows and exact fixer requirements may only exist in the missing original database.

Therefore the spreadsheet cannot validate Kevin contract objectives, payouts, or reputation changes.

### Development mission catalog

The reconstructed development database contains exactly seven relevant mission rows, all for `anonymous`.

There are **zero Kevin mission rows**.

Recovered Anonymous progression:

1. rep 1 — GET YOUR BEARINGS
2. rep 2 — KNOW YOUR STASH
3. rep 3 — FIRST BLOOD
4. rep 4 — IRON AND BLOOD
5. rep 5 — FOLLOW THE MONEY
6. rep 6 — INTO THE SHADOWS
7. rep 7 — END OF THE LINE

Reps 1–6 are already reconciled and settled through the server-owned `user_mission_progress` ledger.

## Anonymous rep-7 handoff

The recovered rep-7 row is:

- id: 11
- contact: anonymous
- title: `END OF THE LINE`
- objective: `No further objectives. Request a contract from Kevin.`
- reward text: `None`
- requirements: `{}`
- stored rewards payload: `{"clean_cash": 1000}`

That row contains a material reward conflict:

- human-facing reward text says **None**;
- machine reward payload contains **1,000 Clean Cash**.

This pass does not choose either value.

The rep-7 row is treated as a **terminal informational handoff**:

- no VERIFY action;
- no reward payment;
- no reputation increment;
- Kevin contact becomes available.

The backend pins the exact recovered conflict so a future catalog edit cannot silently turn the row into a payable mission without reconciliation.

## Rep 7 vs rep 50 conflict

The historical Flutter contact list revealed Kevin only when:

`Anonymous reputation >= 50`

That is incompatible with the recovered mission catalog.

The only reconciled Anonymous progression advances rep 1 through rep 7. There are no recovered missions for reps 8–49.

The recovered rep-7 row explicitly tells the player to request a contract from Kevin.

Therefore the source-backed handoff is:

**Kevin contact visibility begins at Anonymous rep 7.**

This does not mean Kevin contracts themselves are currently enabled.

The client now:

- displays Anonymous progression against the recovered terminal rep of 7 rather than 50;
- reveals Kevin at rep 7;
- labels Kevin **UNLOCKED • CONTRACTS PAUSED**;
- removes the old Kevin-200 → Uncle John progression gate because that number is not backed by a recovered Kevin progression source.

## Unsupported Kevin contract generator

The old backend dynamically generated Kevin contracts with these rules:

- required crimes: random integer from 3 through 7;
- required Gym progress: 10;
- Dirty Cash payout: random 500–999 multiplied by player level;
- full turn-in reputation: +2;
- abort reputation: -2;
- partial settlement route existed in the client but lacked a canonical rule.

These values are code behavior only.

No recovered Kevin mission rows, spreadsheet rows, or design source found in this pass establish those exact values.

They are therefore not treated as authoritative gameplay rules.

## Removed unsafe behavior

### Contract generation and settlement

Kevin actions are now fail-closed:

- `REQUEST`
- `TURN_IN`
- `PARTIAL`
- `ABORT`

All return 503 and mutate nothing.

No random requirements are created.
No cash payout is generated.
No Kevin reputation is added or removed.
No active contract is cleared.

### Background progress mutation

The previous system silently advanced a Kevin contract from:

- successful Searching;
- successful Shoplifting;
- successful Pickpocketing;
- Gym training.

Those calls have been removed.

This is important because a generated contract structure with unsupported requirements must not become part of authoritative gameplay telemetry simply because the player performs ordinary actions.

The obsolete `utils/missionProgress.js` Kevin progress engine has been deleted from this branch.

## Kevin read boundary

`GET /missions/details/:user_id/kevin` now uses authenticated actor identity.

Before Anonymous rep 7:

- returns locked;
- contract is unavailable.

At rep 7 or higher:

- Kevin is visible;
- status is `paused`;
- `contract_available: false`;
- no generated contract is returned.

If an older account happens to contain an old Kevin `active_contract`, the API reports only:

`legacy_active_contract_present: true`

It does not interpret or settle that contract.

The development project currently has zero users and zero active contracts, so no development player data requires migration.

## Anonymous progression retained

The existing reconciled reps 1–6 remain unchanged:

- authenticated actor;
- server-recorded visit/crime/Gym objective telemetry;
- persistent `user_mission_progress`;
- player row lock;
- idempotency ledger;
- source-backed rewards only;
- atomic reward + reputation + completion settlement.

Rep 7 is deliberately excluded from that settlement path because its reward source is contradictory.

## Mission catalog integrity

Migration:

`20261104234000_mission_contact_progression_integrity_20261105.sql`

adds:

- `contact_name NOT NULL`;
- `rep_req NOT NULL`;
- non-empty contact-name check;
- nonnegative reputation requirement;
- JSON-object checks for `reqs_json` and `rewards_json`;
- unique index on `(lower(contact_name), rep_req)`.

The unique contact/reputation rule matches the mission lookup semantics and prevents ambiguous mission selection.

At migration time:

- no duplicate contact/reputation pairs existed;
- no missing contact names existed;
- no invalid reputation requirements existed.

## Flutter companion

Draft PR #5 now:

- removes the impossible `Anonymous >= 50` Kevin gate;
- treats rep 7 as the terminal Anonymous handoff;
- fetches Kevin status from the backend;
- displays Kevin as unlocked but paused;
- removes Request / Turn In / Partial / Abort controls;
- removes presentation of generated contract payouts and requirements;
- stops sending the client player ID in mission action bodies;
- removes the unsupported Uncle John unlock at Kevin rep 200;
- updates the rep-7 fallback objective to match the recovered handoff wording.

## Still unresolved

A future Kevin implementation requires an authoritative source for at least:

1. contract catalog or generation rules;
2. objective types;
3. requirement ranges;
4. payout currency;
5. payout formula;
6. reputation gain/loss;
7. partial completion semantics, if any;
8. abort semantics;
9. contract cooldown/expiry;
10. Kevin progression cap and the next-contact handoff;
11. whether contracts are repeatable and how repeats are audited.

None of these are invented in this pass.

## Verification boundary

Performed:

- recovered Drive mission references reviewed;
- exact development `missions_master` rows inspected;
- Git mission history reviewed;
- backend contract generator reconciled against sources;
- development migration applied;
- constraint/index readback;
- static backend/client readback;
- Supabase advisor review.

Not performed by instruction:

- Node runtime tests;
- gameplay tests;
- mission settlement tests;
- concurrency tests;
- Flutter analyze/build/widget tests;
- deployment;
- production changes.
