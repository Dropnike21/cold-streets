-- Property lifecycle integrity.
-- Player-market settlement, lease/gift transfer, upkeep collection, and bonus
-- application remain deliberately paused until their source semantics are reconciled.

ALTER TABLE public.properties_master
  ADD CONSTRAINT properties_master_cost_nonnegative_integer
  CHECK (cost >= 0 AND cost = trunc(cost));

ALTER TABLE public.properties_master
  ADD CONSTRAINT properties_master_upkeep_nonnegative_integer
  CHECK (upkeep_val >= 0 AND upkeep_val = trunc(upkeep_val));

ALTER TABLE public.properties_master
  ADD CONSTRAINT properties_master_hp_bonus_nonnegative
  CHECK (hp_bonus >= 0);

ALTER TABLE public.property_transactions
  ADD CONSTRAINT property_transactions_amount_nonnegative_integer
  CHECK (amount >= 0 AND amount = trunc(amount));

ALTER TABLE public.property_transactions
  ADD CONSTRAINT property_transactions_seller_id_fkey
  FOREIGN KEY (seller_id) REFERENCES public.users(user_id);

CREATE UNIQUE INDEX IF NOT EXISTS owned_properties_one_active_residence_per_user_idx
  ON public.owned_properties (user_id)
  WHERE status = 'active_residence';

CREATE INDEX IF NOT EXISTS owned_properties_property_type_id_idx
  ON public.owned_properties (property_type_id);

CREATE INDEX IF NOT EXISTS property_market_instance_id_idx
  ON public.property_market (instance_id);

CREATE INDEX IF NOT EXISTS property_market_seller_id_idx
  ON public.property_market (seller_id);

CREATE INDEX IF NOT EXISTS property_transactions_buyer_id_idx
  ON public.property_transactions (buyer_id);

CREATE INDEX IF NOT EXISTS property_transactions_seller_id_idx
  ON public.property_transactions (seller_id);
