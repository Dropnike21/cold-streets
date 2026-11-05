-- Bank settlement integrity.
-- Economic terms remain deliberately paused:
-- rates, term durations, trust progression, payout denomination, Dirty->Clean
-- conversion, and pending-check auto-liquidation are not made canonical here.

ALTER TABLE public.time_deposits
  ADD CONSTRAINT time_deposits_dirty_nonnegative_integer
  CHECK (dirty_deposited >= 0 AND dirty_deposited = trunc(dirty_deposited));

ALTER TABLE public.time_deposits
  ADD CONSTRAINT time_deposits_clean_nonnegative_integer
  CHECK (clean_deposited >= 0 AND clean_deposited = trunc(clean_deposited));

ALTER TABLE public.time_deposits
  ADD CONSTRAINT time_deposits_payout_nonnegative_integer
  CHECK (total_payout >= 0 AND total_payout = trunc(total_payout));

ALTER TABLE public.time_deposits
  ADD CONSTRAINT time_deposits_principal_positive
  CHECK ((dirty_deposited + clean_deposited) > 0);

ALTER TABLE public.time_deposits
  ADD CONSTRAINT time_deposits_unlock_after_creation
  CHECK (unlocks_at > created_at);

ALTER TABLE public.pending_checks
  ADD CONSTRAINT pending_checks_amount_positive_integer
  CHECK (amount > 0 AND amount = trunc(amount));

ALTER TABLE public.pending_checks
  ADD CONSTRAINT pending_checks_expiry_after_creation
  CHECK (expires_at > created_at);

ALTER TABLE public.users
  ADD CONSTRAINT users_bank_trust_nonnegative_integer
  CHECK (bank_trust_level >= 0 AND bank_trust_level = trunc(bank_trust_level));

CREATE INDEX IF NOT EXISTS time_deposits_user_created_idx
  ON public.time_deposits (user_id, created_at DESC);
