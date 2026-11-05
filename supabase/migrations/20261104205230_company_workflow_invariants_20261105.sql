-- Company workflow invariants that are independent of unresolved production formulas.
-- The connected development company runtime tables are empty at recovery time.

ALTER TABLE public.company_applicants
    ADD CONSTRAINT company_applicants_status_check
    CHECK (status IN ('Pending', 'Accepted', 'Rejected')),
    ADD CONSTRAINT company_applicants_pitch_length_check
    CHECK (pitch_message IS NULL OR char_length(pitch_message) <= 2000);

CREATE UNIQUE INDEX company_applicants_one_pending_per_company_user
    ON public.company_applicants (company_id, user_id)
    WHERE status = 'Pending';

ALTER TABLE public.company_employees
    ADD CONSTRAINT company_employees_salary_nonnegative_integer_check
    CHECK (daily_salary >= 0 AND daily_salary = trunc(daily_salary));

ALTER TABLE public.company_inventory
    ADD CONSTRAINT company_inventory_quantity_nonnegative_check
    CHECK (quantity >= 0),
    ADD CONSTRAINT company_inventory_price_nonnegative_integer_check
    CHECK (price_per_unit >= 0 AND price_per_unit = trunc(price_per_unit)),
    ADD CONSTRAINT company_inventory_daily_volume_nonnegative_check
    CHECK (daily_volume >= 0);

ALTER TABLE public.company_shipments
    ADD CONSTRAINT company_shipments_quantity_positive_check
    CHECK (quantity > 0),
    ADD CONSTRAINT company_shipments_total_cost_nonnegative_integer_check
    CHECK (total_cost >= 0 AND total_cost = trunc(total_cost));

ALTER TABLE public.player_companies
    ADD CONSTRAINT player_companies_bank_clean_integer_check
    CHECK (bank_clean = trunc(bank_clean)),
    ADD CONSTRAINT player_companies_bank_dirty_integer_check
    CHECK (bank_dirty = trunc(bank_dirty)),
    ADD CONSTRAINT player_companies_ad_budget_nonnegative_integer_check
    CHECK (advertising_budget >= 0 AND advertising_budget = trunc(advertising_budget)),
    ADD CONSTRAINT player_companies_upgrade_levels_nonnegative_check
    CHECK (
        size_upgrade_level >= 0
        AND staff_room_level >= 0
        AND warehouse_level >= 0
    );
