-- City NPC market purchase audit and daily-limit support.
-- Source: Master Items Canvas says all city NPC markets have a strict
-- 100-item-per-day purchase limit. Player Bazaar is explicitly unlimited.

ALTER TABLE public.user_purchases
  ADD COLUMN purchase_source text NOT NULL DEFAULT 'city_market';

ALTER TABLE public.user_purchases
  ALTER COLUMN purchase_source DROP DEFAULT;

ALTER TABLE public.user_purchases
  ADD CONSTRAINT user_purchases_quantity_positive
    CHECK (quantity > 0),
  ADD CONSTRAINT user_purchases_source_nonempty
    CHECK (btrim(purchase_source) <> '');

CREATE INDEX user_purchases_user_source_date_idx
  ON public.user_purchases (user_id, purchase_source, purchase_date DESC);
