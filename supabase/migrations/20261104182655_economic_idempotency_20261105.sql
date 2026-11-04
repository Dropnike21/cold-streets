-- Applied to isolated Supabase development project as migration
-- 20261104182655 / economic_idempotency_20261105.
-- Server-only retry ledger for committed economic actions.

CREATE TABLE public.economic_idempotency (
  user_id BIGINT NOT NULL REFERENCES public.users(user_id),
  action_scope TEXT NOT NULL CHECK (action_scope ~ '^[a-z0-9_.:-]{1,80}$'),
  idempotency_key UUID NOT NULL,
  request_hash CHAR(64) NOT NULL CHECK (request_hash ~ '^[0-9a-f]{64}$'),
  response_status SMALLINT,
  response_json JSONB,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  completed_at TIMESTAMPTZ,
  PRIMARY KEY (user_id, action_scope, idempotency_key),
  CHECK (
    (completed_at IS NULL AND response_status IS NULL AND response_json IS NULL)
    OR
    (completed_at IS NOT NULL AND response_status BETWEEN 200 AND 299 AND response_json IS NOT NULL)
  )
);

CREATE INDEX economic_idempotency_created_at_idx
  ON public.economic_idempotency (created_at);

ALTER TABLE public.economic_idempotency ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.economic_idempotency FROM anon, authenticated;
