-- Establish the recovered 120-product source namespace without mapping it
-- onto the incompatible legacy 20-row company_products_master catalog.

CREATE TABLE public.company_source_products_master (
  source_product_name text PRIMARY KEY,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT company_source_products_name_nonempty
    CHECK (btrim(source_product_name) <> '')
);

CREATE UNIQUE INDEX company_source_products_name_casefold_unique_idx
  ON public.company_source_products_master (lower(source_product_name));

INSERT INTO public.company_source_products_master (source_product_name)
SELECT DISTINCT product_name
  FROM public.company_product_rules_master
 ORDER BY product_name;

ALTER TABLE public.company_product_rules_master
  ADD CONSTRAINT company_product_rules_source_product_fk
  FOREIGN KEY (product_name)
  REFERENCES public.company_source_products_master(source_product_name);

CREATE TABLE public.company_source_inventory (
  company_id bigint NOT NULL
    REFERENCES public.player_companies(company_id) ON DELETE CASCADE,
  source_product_name text NOT NULL
    REFERENCES public.company_source_products_master(source_product_name),
  quantity bigint NOT NULL DEFAULT 0,
  reserved_quantity bigint NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (company_id, source_product_name),
  CONSTRAINT company_source_inventory_quantity_check
    CHECK (quantity >= 0),
  CONSTRAINT company_source_inventory_reserved_check
    CHECK (reserved_quantity >= 0 AND reserved_quantity <= quantity)
);

CREATE INDEX company_source_inventory_product_idx
  ON public.company_source_inventory (source_product_name);

ALTER TABLE public.company_source_products_master ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.company_source_inventory ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE public.company_source_products_master FROM anon, authenticated;
REVOKE ALL ON TABLE public.company_source_inventory FROM anon, authenticated;
