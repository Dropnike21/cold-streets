# Flutter / API / Schema / Catalog Closure Audit — 2026-11-05

## Scope

Final static reconciliation among:

- Flutter companion PR #5;
- canonical backend PR #44;
- development Supabase schema;
- recovered gameplay/catalog sources.

No Flutter build/analyze or API runtime test was performed.

## Flutter contract state

The client has already been reconciled so authoritative mutation bodies express
intent only.

Final closeout changes also ensure the client no longer exposes executable
surfaces for newly discovered source conflicts:

- City Job resignation: paused;
- Pickpocket execution: paused;
- recruit generation/hiring: paused;
- crew crime assignment/automation: paused;
- Syndicate establishment legacy numeric thresholds removed.

Crew recall remains available so an existing persisted automation assignment can
be stopped safely.

The Syndicate crew-stat UI no longer uses legacy tier-derived maximum scales; it
uses the persisted recruit's actual max-stat values for presentation.

## Development migration equality

Final readback:

- Git migration files: 41;
- development Supabase migration history: 41;
- version/name mismatches: 0;
- Git-only migrations: 0;
- DB-only migrations: 0.

Migration history has not been manually fabricated.

## Direct database exposure

Final development readback:

- public tables: 74;
- public tables with RLS enabled: 74;
- anon/authenticated table grants: 0;
- client-exposed public sequences: 0;
- client/PUBLIC executable public functions: 0;
- public SECURITY DEFINER functions: 0.

Supabase Security Advisor reports only 74 INFO
`rls_enabled_no_policy` findings, which are expected under the intentional
server-only deny-all Data API model.

## Current catalog row counts

Development readback:

| Catalog | Rows |
| --- | ---: |
| items_master | 711 |
| crimes_master | 273 |
| jobs_master | 10 |
| job_ranks | 50 |
| job_interviews | 140 |
| gyms_master | 80 |
| education_courses_master | 220 |
| properties_master | 25 |
| company_types_master | 120 |
| company_positions_master | 179 |
| company_source_products_master | 120 |
| achievements_master | 400 |
| premium_pack_catalog | 2 |

These counts are inventory facts, not a claim that every row has executable
mechanics.

## Catalog-semantic closure

The project now follows one rule consistently:

**a recovered catalog row may be displayed/read without being executable.**

Mutation availability requires the relevant cost, reward, denomination,
stacking, timing and interaction semantics to be unambiguous.

Examples intentionally remaining read-only/paused despite catalog presence:

- property catalog;
- Credit Broker upgrades;
- premium Kingpin/VIP details that are incomplete;
- company product/supply-chain rules without settlement;
- Trade assets without fill settlement;
- Casino game definitions without authoritative paytables/settlement;
- recruit templates while generation/pricing semantics conflict.

## Recruits Canvas reconciliation

A late source review discovered a material conflict with legacy recruit code.

Recruits Canvas specifies current/max stat ranges:

- Runner: 5–15 / 40–80;
- Hustler: 15–30 / 70–120;
- Enforcer: 25–50 / 100–160;
- Specialist: 30–60 / 120–180;
- Lieutenant: 50–80 / 180–250.

The legacy generator used dramatically larger ranges.

The Canvas also defines a dynamic cost formula but not its stat-value/potential
multipliers.

Therefore the client/backend recruit settlement is paused pending an explicit
canonical decision.

## Database trigger closure

Final public trigger inventory contains four non-internal triggers:

- immutable Casino Token spend ledger: UPDATE blocker;
- immutable Casino Token spend ledger: DELETE blocker;
- item-discovery record on positive inventory INSERT;
- item-discovery record on positive inventory quantity UPDATE.

The two trigger functions are SECURITY INVOKER, use an empty search_path, and
are not directly executable by client roles.

The discovery trigger only inserts the actor/item lifetime pair with
ON CONFLICT DO NOTHING; it does not issue cash/items or infer historical
discoveries.

No hidden database trigger performs regeneration, payouts, market restocking or
other gameplay settlement.

## Result

The current Flutter surface no longer represents unresolved catalog economics
as executable gameplay.

The development database and repository migration history match, and direct
client database access remains closed.

The remaining unresolved items are explicit mechanics decisions rather than
silent client/backend/schema drift.
