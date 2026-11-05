DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM public.users LIMIT 1) THEN
    RAISE EXCEPTION
      'user_item_discoveries requires explicit lifetime backfill adjudication before applying to a populated database';
  END IF;
END
$$;

CREATE TABLE public.user_item_discoveries (
  user_id bigint NOT NULL
    REFERENCES public.users(user_id) ON DELETE CASCADE,
  item_id bigint NOT NULL
    REFERENCES public.items_master(item_id),
  discovered_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, item_id)
);

CREATE INDEX user_item_discoveries_item_idx
  ON public.user_item_discoveries (item_id);

ALTER TABLE public.user_item_discoveries ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.user_item_discoveries FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.record_user_item_discovery()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $$
BEGIN
  IF NEW.quantity > 0 THEN
    INSERT INTO public.user_item_discoveries (user_id, item_id)
    VALUES (NEW.user_id, NEW.item_id)
    ON CONFLICT (user_id, item_id) DO NOTHING;
  END IF;
  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.record_user_item_discovery()
  FROM PUBLIC, anon, authenticated;

CREATE TRIGGER user_inventory_discovery_after_insert
AFTER INSERT ON public.user_inventory
FOR EACH ROW
WHEN (NEW.quantity > 0)
EXECUTE FUNCTION public.record_user_item_discovery();

CREATE TRIGGER user_inventory_discovery_after_quantity_update
AFTER UPDATE OF quantity ON public.user_inventory
FOR EACH ROW
WHEN (NEW.quantity > 0)
EXECUTE FUNCTION public.record_user_item_discovery();
