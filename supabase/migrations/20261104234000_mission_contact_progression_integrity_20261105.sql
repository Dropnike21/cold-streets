-- Mission catalog integrity for contact/reputation lookups.
-- Kevin contracts remain disabled because no authoritative Kevin mission rows
-- or spreadsheet source were recovered.

ALTER TABLE public.missions_master
  ALTER COLUMN contact_name SET NOT NULL,
  ALTER COLUMN rep_req SET NOT NULL;

ALTER TABLE public.missions_master
  ADD CONSTRAINT missions_master_contact_nonempty
  CHECK (btrim(contact_name) <> '');

ALTER TABLE public.missions_master
  ADD CONSTRAINT missions_master_rep_nonnegative
  CHECK (rep_req >= 0);

ALTER TABLE public.missions_master
  ADD CONSTRAINT missions_master_requirements_object
  CHECK (reqs_json IS NULL OR jsonb_typeof(reqs_json) = 'object');

ALTER TABLE public.missions_master
  ADD CONSTRAINT missions_master_rewards_object
  CHECK (rewards_json IS NULL OR jsonb_typeof(rewards_json) = 'object');

CREATE UNIQUE INDEX IF NOT EXISTS missions_master_contact_rep_unique_idx
  ON public.missions_master (lower(contact_name), rep_req);
