ALTER TABLE public.trade_listings
  ADD COLUMN asset_namespace text NOT NULL DEFAULT 'item';

ALTER TABLE public.trade_listings
  ADD COLUMN premium_pack_key text
    REFERENCES public.premium_pack_catalog(pack_key);

ALTER TABLE public.trade_listings
  ALTER COLUMN item_id DROP NOT NULL;

ALTER TABLE public.trade_listings
  ADD CONSTRAINT trade_listings_asset_namespace_check
  CHECK (asset_namespace IN ('item', 'premium_pack'));

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

CREATE INDEX trade_listings_premium_pack_idx
  ON public.trade_listings (premium_pack_key)
  WHERE premium_pack_key IS NOT NULL;
