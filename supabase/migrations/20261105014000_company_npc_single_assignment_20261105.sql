-- A crew_id is globally unique in user_crew. One NPC recruit cannot occupy
-- multiple company rosters simultaneously.

CREATE UNIQUE INDEX company_employees_one_npc_company_per_crew_idx
  ON public.company_employees (employee_id)
  WHERE is_npc = true;
