-- Development-only integrity for the currently non-settling bounty ledger.
-- This does not add claim semantics. New bounty placement remains fail-closed
-- until a server-authoritative PvP terminal result can prove a valid claim.

ALTER TABLE public.bounties
  ADD CONSTRAINT bounties_reward_cash_positive
  CHECK (reward_cash > 0);

ALTER TABLE public.bounties
  ADD CONSTRAINT bounties_no_self_target
  CHECK (target_user_id <> placed_by_user_id);

CREATE INDEX IF NOT EXISTS bounties_reward_cash_desc_idx
  ON public.bounties (reward_cash DESC, created_at DESC);
