-- Generic deferred payout / Bank-check contract.
-- The Bank is the redemption surface. Other authoritative subsystems issue
-- immutable cash obligations using issuer_type + source_ref.
-- No issuer is activated by this migration.

ALTER TABLE public.pending_checks
  ADD COLUMN issuer_type text NOT NULL DEFAULT 'legacy',
  ADD COLUMN source_ref text,
  ADD COLUMN payout_currency text,
  ADD COLUMN metadata_jsonb jsonb NOT NULL DEFAULT '{}'::jsonb,
  ADD COLUMN claimed_at timestamptz;

ALTER TABLE public.pending_checks
  ALTER COLUMN issuer_type DROP DEFAULT;

ALTER TABLE public.pending_checks
  ADD CONSTRAINT pending_checks_issuer_type_nonempty
    CHECK (btrim(issuer_type) <> ''),
  ADD CONSTRAINT pending_checks_source_ref_nonempty
    CHECK (source_ref IS NULL OR btrim(source_ref) <> ''),
  ADD CONSTRAINT pending_checks_currency_check
    CHECK (payout_currency IS NULL OR payout_currency IN ('dirty_cash','clean_cash')),
  ADD CONSTRAINT pending_checks_metadata_object
    CHECK (jsonb_typeof(metadata_jsonb) = 'object'),
  ADD CONSTRAINT pending_checks_status_check
    CHECK (status IN ('pending','claimed','voided')),
  ADD CONSTRAINT pending_checks_claimed_state_check
    CHECK (
      (status = 'claimed' AND claimed_at IS NOT NULL)
      OR
      (status <> 'claimed' AND claimed_at IS NULL)
    );

CREATE UNIQUE INDEX pending_checks_issuer_source_unique_idx
  ON public.pending_checks (issuer_type, source_ref)
  WHERE source_ref IS NOT NULL;

CREATE INDEX pending_checks_user_pending_created_idx
  ON public.pending_checks (user_id, created_at DESC, id DESC)
  WHERE status = 'pending';

-- There are no reconstructed rows, so new server-issued checks must always
-- carry both source_ref and payout_currency. Keep the columns nullable only
-- for compatibility with a future import of unreconciled legacy liabilities.
