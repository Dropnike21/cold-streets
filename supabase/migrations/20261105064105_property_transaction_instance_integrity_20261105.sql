-- Property transaction ledger must reference the property instance it records.

ALTER TABLE public.property_transactions
  ADD CONSTRAINT property_transactions_instance_id_fkey
  FOREIGN KEY (instance_id) REFERENCES public.owned_properties(id);

CREATE INDEX IF NOT EXISTS property_transactions_instance_id_idx
  ON public.property_transactions (instance_id);
