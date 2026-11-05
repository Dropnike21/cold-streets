-- NPC company staffing integrity and unresolved effectiveness semantics.
-- NPC Crew work for zero salary. Weighted-effectiveness formulas are not yet
-- source-reconciled, so do not assign a fabricated default score.

ALTER TABLE public.company_employees
  ALTER COLUMN effectiveness_score DROP NOT NULL,
  ALTER COLUMN effectiveness_score DROP DEFAULT;

ALTER TABLE public.company_employees
  ADD CONSTRAINT company_employees_effectiveness_nonnegative
    CHECK (effectiveness_score IS NULL OR effectiveness_score >= 0),
  ADD CONSTRAINT company_employees_npc_zero_salary
    CHECK (NOT is_npc OR daily_salary = 0),
  ADD CONSTRAINT company_employees_position_nonempty
    CHECK (btrim(position_role) <> '');
