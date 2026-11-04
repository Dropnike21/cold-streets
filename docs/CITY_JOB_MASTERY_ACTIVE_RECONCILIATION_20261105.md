# City Job Mastery Active Reconciliation — 2026-11-05

## Scope

This pass implements only City Job **active mastery** settlement that can be reconciled without inventing reward mappings.

It uses the reconstructed `jobs_master.mastery_logic_json` rules as the current rule set for this priority and cross-checks executable targets against the recovered runtime catalog/storage model. Historical design variants are preserved as source conflicts rather than merged into the current rules.

No recovered catalog dump or alternate private item mapping is committed here.

## Source reconciliation outcome

Ten active mastery rules were reviewed.

- **Two are executable in this pass.**
  - One item-backed rule has an exact rule-to-item-catalog identity and quantity relationship.
  - One Heat effect has explicit semantics and a canonical server-owned `users.heat` field.
- **Eight remain fail-closed.**
  - Seven item-backed rules have an item identity/name/tier conflict or no exact catalog target.
  - One non-item resource rule has no canonical player resource storage model.

No conflicting item ID was remapped to a similar-looking catalog item.

### Per-job reconciliation ledger

| City Job | Active mastery result | Reconciliation status |
|---|---|---|
| Armed Forces | The recovered rule resolves to a different supply-pack item than the described Heavy Ordnance Crate. A Heavy Ordnance Crate exists elsewhere in the catalog, but this pass does not remap the rule to it. | **Paused** |
| City Hospital | The recovered reward ID resolves to a different medical consumable than the described Trauma Kit. | **Paused** |
| Local Grocery | The recovered reward ID resolves to a weapon, while the description calls for a case of Energy Drinks. Multiple drink-like catalog items exist, so there is no unambiguous substitute. | **Paused** |
| Grand Casino | The recovered reward ID resolves to an alcohol consumable rather than casino chips. A server-owned casino-token balance exists, but the recovered mastery rule is item-shaped and does not canonically point to that balance. | **Paused** |
| Data Entry | The recovered rule grants an `emails` resource, but the reconstructed player schema has no canonical Emails inventory/resource balance. Account email addresses are not a gameplay resource. | **Paused** |
| Logistics Center | The recovered reward ID resolves to Scrap Metal rather than the described Mystery Cargo Crate. Similar crate/mystery items exist, but none is an exact canonical target for this rule. | **Paused** |
| Municipal Courthouse | The rule explicitly spends Job Incentives and halves current Heat; this matches the active description and the canonical `users.heat` field. | **Enabled** |
| Public Library | The recovered reward ID resolves to a different consumable rather than the described Rare Book/EXP booster, and there is no exact catalog identity to substitute safely. | **Paused** |
| Construction Site | The recovered item identity, quantity, and description all agree on five Graphene Sheets, with canonical inventory storage. | **Enabled** |
| Tech Startup | The recovered reward points to a Tier 1 Hacking Tablet while the description says High-End Hacking Tablet. No exact higher-tier canonical target is established by the recovered rule. | **Paused** |

The older *City Jobs & Career Mastery* canvas contains a different mastery generation from the later recovered `jobs_master` rules. This implementation does not combine those generations. That version conflict remains documented for a later canonical-design decision.

## Activation contract

`POST /jobs/mastery/activate`

Request body:

```json
{
  "job_id": "<mastered City Job id>"
}
```

The route rejects all other body keys. Reward ID, quantity, cost, multiplier, payout, and actor identity are never accepted from the client.

The acting player is derived only from verified authentication. A valid persistent `Idempotency-Key` UUID is required.

## Settlement invariants

The transaction lock order is:

1. authenticated player row;
2. persistent idempotency record;
3. that player's selected `user_job_data` row;
4. catalog/reward rows where applicable.

The selected job must already have `current_rank = 5` and `is_mastered = true`. Requiring both avoids treating a malformed legacy progress row as mastered merely because one flag is set.

The historical City Jobs source says mastery persists after leaving, but also describes retained job incentives as **frozen** after resignation until return. To avoid inventing off-job spending semantics, mastery status remains preserved while active-mastery spending requires the player to be currently employed in that same City Job. A replay of an already completed idempotent request is returned before re-checking current employment.

Costs, quantities, and item IDs are parsed from server-owned mastery data with exact integer handling. PostgreSQL `BIGINT` values are not routed through JavaScript floating-point arithmetic.

The Heat effect is applied in PostgreSQL using exact `NUMERIC` arithmetic. The backend does not round Heat through JavaScript.

## Drift protection

The two enabled rules have reconciliation fingerprints. At activation time the backend reconstructs the fingerprint from the complete server-owned mastery rule text, the active mastery description, and, for item rewards, current item catalog metadata. This means a description change, rule-shape change, or catalog identity change fails closed even if the parsed reward still looks superficially compatible.

If either source or catalog data changes, the route returns `503` and performs no deduction or reward until the rule is re-reconciled.

The legacy reconstructed `mastery_logic_json` column is currently text and may contain pseudo-JSON. The parser first accepts strict JSON; otherwise it recognizes only the narrow recovered active-rule shapes required by this pass. It never evaluates catalog text as JavaScript.

## Remaining conflicts

The following remain intentionally unresolved:

- exact catalog targets for the seven conflicting item-backed active masteries;
- a canonical storage model for the non-item resource mastery;
- whether the older City Jobs mastery generation should replace, coexist with, or be retired in favor of the recovered `jobs_master` generation;
- any future off-job active-mastery spending behavior if the word "frozen" is later defined differently.

The disabled legacy `/jobs/exchange` rank-special path remains disabled and is not reused by this mastery flow.

## Verification boundary

This pass performed source/catalog inspection and code readback only.

Per project instruction, no gameplay test, build test, deployment, or production change was performed.
