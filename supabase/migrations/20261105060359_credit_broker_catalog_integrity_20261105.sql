-- Credit Broker catalog integrity.
-- Purchase pricing and upgrade effect application remain deliberately disabled
-- until conflicting source semantics are reconciled.

ALTER TABLE public.credit_upgrades_master
  ADD CONSTRAINT credit_upgrades_master_max_level_positive
  CHECK (max_level > 0);

ALTER TABLE public.credit_upgrades_master
  ADD CONSTRAINT credit_upgrades_master_value_nonnegative
  CHECK (val_per_level >= 0);

ALTER TABLE public.user_credit_upgrades
  ADD CONSTRAINT user_credit_upgrades_level_nonnegative
  CHECK (current_level >= 0);

CREATE INDEX IF NOT EXISTS user_credit_upgrades_upgrade_id_idx
  ON public.user_credit_upgrades (upgrade_id);
