-- Cover company foreign keys used by deletion/join paths.
CREATE INDEX blueprint_products_product_idx
    ON public.blueprint_products (product_id);

CREATE INDEX company_applicants_user_idx
    ON public.company_applicants (user_id);

CREATE INDEX company_inventory_product_idx
    ON public.company_inventory (product_id);

CREATE INDEX company_positions_type_idx
    ON public.company_positions_master (type_id);

CREATE INDEX company_shipments_company_idx
    ON public.company_shipments (company_id);

CREATE INDEX company_shipments_product_idx
    ON public.company_shipments (product_id);

CREATE INDEX company_specials_type_idx
    ON public.company_specials_master (type_id);
