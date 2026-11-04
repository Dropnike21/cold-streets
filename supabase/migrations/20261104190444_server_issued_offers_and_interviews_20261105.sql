-- Applied to isolated Supabase development project as migration
-- 20261104190444 / server_issued_offers_and_interviews_20261105.

CREATE TABLE public.recruitment_offers (
  offer_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id BIGINT NOT NULL REFERENCES public.users(user_id) ON DELETE CASCADE,
  npc_name TEXT NOT NULL,
  tier INTEGER NOT NULL CHECK (tier BETWEEN 1 AND 5),
  price NUMERIC(24,0) NOT NULL CHECK (price >= 0),
  cur_str BIGINT NOT NULL, max_str BIGINT NOT NULL,
  cur_def BIGINT NOT NULL, max_def BIGINT NOT NULL,
  cur_dex BIGINT NOT NULL, max_dex BIGINT NOT NULL,
  cur_spd BIGINT NOT NULL, max_spd BIGINT NOT NULL,
  cur_acu BIGINT NOT NULL, max_acu BIGINT NOT NULL,
  cur_ops BIGINT NOT NULL, max_ops BIGINT NOT NULL,
  cur_pre BIGINT NOT NULL, max_pre BIGINT NOT NULL,
  cur_res BIGINT NOT NULL, max_res BIGINT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  expires_at TIMESTAMPTZ NOT NULL DEFAULT (NOW() + INTERVAL '15 minutes'),
  claimed_at TIMESTAMPTZ,
  CHECK (
    cur_str >= 0 AND max_str >= cur_str AND
    cur_def >= 0 AND max_def >= cur_def AND
    cur_dex >= 0 AND max_dex >= cur_dex AND
    cur_spd >= 0 AND max_spd >= cur_spd AND
    cur_acu >= 0 AND max_acu >= cur_acu AND
    cur_ops >= 0 AND max_ops >= cur_ops AND
    cur_pre >= 0 AND max_pre >= cur_pre AND
    cur_res >= 0 AND max_res >= cur_res
  )
);
CREATE INDEX recruitment_offers_user_active_idx
  ON public.recruitment_offers (user_id, expires_at)
  WHERE claimed_at IS NULL;

CREATE TABLE public.job_interview_sessions (
  interview_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id BIGINT NOT NULL REFERENCES public.users(user_id) ON DELETE CASCADE,
  job_id BIGINT NOT NULL REFERENCES public.jobs_master(job_id),
  question_ids BIGINT[] NOT NULL CHECK (cardinality(question_ids) = 5),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  expires_at TIMESTAMPTZ NOT NULL DEFAULT (NOW() + INTERVAL '15 minutes'),
  consumed_at TIMESTAMPTZ
);
CREATE INDEX job_interview_sessions_user_active_idx
  ON public.job_interview_sessions (user_id, expires_at)
  WHERE consumed_at IS NULL;

ALTER TABLE public.recruitment_offers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.job_interview_sessions ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.recruitment_offers FROM anon, authenticated;
REVOKE ALL ON TABLE public.job_interview_sessions FROM anon, authenticated;
