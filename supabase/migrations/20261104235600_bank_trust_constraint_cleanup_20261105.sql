-- bank_trust_level is already an INTEGER column; retain only the
-- semantic nonnegative invariant and avoid unnecessary float coercion.

ALTER TABLE public.users
  DROP CONSTRAINT users_bank_trust_nonnegative_integer;

ALTER TABLE public.users
  ADD CONSTRAINT users_bank_trust_nonnegative
  CHECK (bank_trust_level >= 0);
