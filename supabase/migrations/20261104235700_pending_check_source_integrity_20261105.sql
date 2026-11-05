-- Pending checks are external deferred-payout instruments.
-- Require each row to identify its issuing source at minimum. A future
-- issuer_type/source_ref/currency contract is still required before claims reopen.

ALTER TABLE public.pending_checks
  ALTER COLUMN source SET NOT NULL;

ALTER TABLE public.pending_checks
  ADD CONSTRAINT pending_checks_source_nonempty
  CHECK (btrim(source) <> '');
