-- Trade Network read-path support.
-- Settlement tables are intentionally not created while P2P currency,
-- fee, expiry, partial-fill, and escrow semantics remain unresolved.

CREATE INDEX IF NOT EXISTS user_inventory_item_id_idx
  ON public.user_inventory (item_id);
