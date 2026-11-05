ALTER TABLE public.users
  ADD COLUMN vip_status_active boolean NOT NULL DEFAULT false;

ALTER TABLE public.casino_token_spend_ledger
  DROP CONSTRAINT casino_token_spend_amount_check;

ALTER TABLE public.casino_token_spend_ledger
  ADD CONSTRAINT casino_token_spend_amount_check
  CHECK (token_amount >= 1 AND token_amount <= 150);
