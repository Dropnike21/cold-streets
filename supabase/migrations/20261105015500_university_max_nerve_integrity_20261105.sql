-- Explicit University Max Nerve consumer integrity.
ALTER TABLE public.users
  ADD CONSTRAINT users_max_nerve_positive_integer
  CHECK (max_nerve > 0 AND max_nerve = trunc(max_nerve));
