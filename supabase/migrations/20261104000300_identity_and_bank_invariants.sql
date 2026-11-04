-- Cold Streets development: database invariants for banking and identity.
-- Applies only after the reconstructed_game_state_20261104 migration.
-- No player, payment, or authentication data is inserted or modified.
--
-- Enforce at most one active time deposit per player even if multiple
-- server instances attempt to create a deposit simultaneously.
CREATE UNIQUE INDEX time_deposits_one_active_per_user
  ON public.time_deposits (user_id)
  WHERE status = 'active';

-- Each internal player UUID maps only to a real Supabase Auth identity.
-- Existing legacy unmapped users (NULL UUID) remain valid during migration.
ALTER TABLE public.users
  ADD CONSTRAINT users_supabase_auth_uid_fkey
  FOREIGN KEY (supabase_auth_uid)
  REFERENCES auth.users (id)
  ON DELETE SET NULL;
