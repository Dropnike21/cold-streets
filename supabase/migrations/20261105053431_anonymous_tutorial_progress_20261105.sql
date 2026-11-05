-- Server-owned Anonymous tutorial progression.
-- Requirements are normalized only for the six recovered guided tutorial steps.
-- Rep 7 remains untouched because reward_text says "None" while rewards_json
-- contains Clean Cash, and the Kevin unlock threshold conflicts with the UI.

DO $$
BEGIN
  IF (
    SELECT COUNT(*)
    FROM public.missions_master
    WHERE contact_name = 'anonymous'
      AND reqs_json = '{}'::jsonb
      AND (
        (id = 3  AND rep_req = 1 AND title = 'GET YOUR BEARINGS') OR
        (id = 4  AND rep_req = 2 AND title = 'KNOW YOUR STASH') OR
        (id = 5  AND rep_req = 3 AND title = 'FIRST BLOOD') OR
        (id = 6  AND rep_req = 4 AND title = 'IRON AND BLOOD') OR
        (id = 9  AND rep_req = 5 AND title = 'FOLLOW THE MONEY') OR
        (id = 10 AND rep_req = 6 AND title = 'INTO THE SHADOWS')
      )
  ) <> 6 THEN
    RAISE EXCEPTION 'Anonymous tutorial source rows no longer match the reconciled catalog';
  END IF;
END
$$;

UPDATE public.missions_master
SET reqs_json = '{"visits":["vitals","assets"]}'::jsonb
WHERE id = 3 AND contact_name = 'anonymous' AND rep_req = 1;

UPDATE public.missions_master
SET reqs_json = '{"visits":["inventory","properties","achievements"]}'::jsonb
WHERE id = 4 AND contact_name = 'anonymous' AND rep_req = 2;

UPDATE public.missions_master
SET reqs_json = '{"visits":["crime_searching","crime_shoplifting","crime_pickpocketing"],"successful_crimes":20}'::jsonb
WHERE id = 5 AND contact_name = 'anonymous' AND rep_req = 3;

UPDATE public.missions_master
SET reqs_json = '{"visits":["gym"],"energy_by_stat":{"str":150,"def":150,"dex":150,"spd":150}}'::jsonb
WHERE id = 6 AND contact_name = 'anonymous' AND rep_req = 4;

UPDATE public.missions_master
SET reqs_json = '{"visits":["bank","real_estate"]}'::jsonb
WHERE id = 9 AND contact_name = 'anonymous' AND rep_req = 5;

UPDATE public.missions_master
SET reqs_json = '{"visits":["credit_broker","casino"]}'::jsonb
WHERE id = 10 AND contact_name = 'anonymous' AND rep_req = 6;

CREATE TABLE public.user_mission_progress (
  user_id bigint NOT NULL REFERENCES public.users(user_id),
  mission_id bigint NOT NULL REFERENCES public.missions_master(id),
  status text NOT NULL DEFAULT 'active',
  progress_jsonb jsonb NOT NULL DEFAULT '{}'::jsonb,
  started_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  completed_at timestamptz,
  PRIMARY KEY (user_id, mission_id),
  CONSTRAINT user_mission_progress_status_check
    CHECK (status IN ('active', 'completed')),
  CONSTRAINT user_mission_progress_json_object_check
    CHECK (jsonb_typeof(progress_jsonb) = 'object'),
  CONSTRAINT user_mission_progress_completion_check
    CHECK (
      (status = 'active' AND completed_at IS NULL) OR
      (status = 'completed' AND completed_at IS NOT NULL)
    )
);

CREATE INDEX user_mission_progress_mission_id_idx
  ON public.user_mission_progress (mission_id);

ALTER TABLE public.user_mission_progress ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.user_mission_progress FROM anon, authenticated;
