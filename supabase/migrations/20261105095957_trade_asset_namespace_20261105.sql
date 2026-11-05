ALTER TABLE public.trade_listings
  ADD COLUMN IF NOT EXISTS asset_namespace text NOT NULL DEFAULT 'item';

ALTER TABLE public.trade_listings
  ADD COLUMN IF NOT EXISTS premium_pack_key text
    REFERENCES public.premium_pack_catalog(pack_key);

ALTER TABLE public.trade_listings
  ALTER COLUMN item_id DROP NOT NULL;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
      FROM pg_constraint
     WHERE conrelid = 'public.trade_listings'::regclass
       AND conname = 'trade_listings_asset_namespace_check'
  ) THEN
    ALTER TABLE public.trade_listings
      ADD CONSTRAINT trade_listings_asset_namespace_check
      CHECK (asset_namespace IN ('item', 'premium_pack'));
  END IF;

  IF NOT EXISTS (
    SELECT 1
      FROM pg_constraint
     WHERE conrelid = 'public.trade_listings'::regclass
       AND conname = 'trade_listings_asset_identity_check'
  ) THEN
    ALTER TABLE public.trade_listings
      ADD CONSTRAINT trade_listings_asset_identity_check
      CHECK (
        (asset_namespace = 'item'
          AND item_id IS NOT NULL
          AND premium_pack_key IS NULL)
        OR
        (asset_namespace = 'premium_pack'
          AND item_id IS NULL
          AND premium_pack_key IS NOT NULL)
      );
  END IF;
END
$$;

CREATE INDEX IF NOT EXISTS trade_listings_premium_pack_idx
  ON public.trade_listings (premium_pack_key)
  WHERE premium_pack_key IS NOT NULL;
