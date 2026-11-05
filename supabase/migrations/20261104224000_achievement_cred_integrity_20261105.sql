-- Achievement/Cred integrity after source reconciliation.
-- Achievement rewards are intentionally not defined here: the recovered
-- achievements catalog has no reward column, so the old hardcoded +1 Cred
-- payout is not considered canonical.

ALTER TABLE public.achievements_master
  ADD CONSTRAINT achievements_master_threshold_positive_integer
  CHECK (
    threshold_value > 0
    AND threshold_value = trunc(threshold_value)
  );

ALTER TABLE public.users
  ADD CONSTRAINT users_cred_nonnegative_integer
  CHECK (
    cred >= 0
    AND cred = trunc(cred)
  );

CREATE INDEX IF NOT EXISTS achievements_master_tracker_threshold_idx
  ON public.achievements_master (stat_tracker, threshold_value, achievement_id);

CREATE INDEX IF NOT EXISTS user_achievements_achievement_id_idx
  ON public.user_achievements (achievement_id);
