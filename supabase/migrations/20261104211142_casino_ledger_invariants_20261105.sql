-- Denomination-agnostic casino ledger integrity.
-- Live Casino settlement remains disabled until token/wager/paytable semantics
-- are recovered canonically.

ALTER TABLE public.users
    ADD CONSTRAINT users_casino_tokens_nonnegative_integer_check
    CHECK (casino_tokens >= 0 AND casino_tokens = trunc(casino_tokens));

ALTER TABLE public.casino_jackpots
    ADD CONSTRAINT casino_jackpots_value_nonnegative_integer_check
    CHECK (current_value >= 0 AND current_value = trunc(current_value));

ALTER TABLE public.casino_audit
    ADD CONSTRAINT casino_audit_bet_nonnegative_integer_check
    CHECK (bet_amount >= 0 AND bet_amount = trunc(bet_amount)),
    ADD CONSTRAINT casino_audit_payout_nonnegative_integer_check
    CHECK (payout >= 0 AND payout = trunc(payout));

ALTER TABLE public.hilo_sessions
    ADD CONSTRAINT hilo_sessions_bet_positive_integer_check
    CHECK (bet_amount > 0 AND bet_amount = trunc(bet_amount)),
    ADD CONSTRAINT hilo_sessions_card_value_check
    CHECK (current_card_value BETWEEN 2 AND 14),
    ADD CONSTRAINT hilo_sessions_card_suit_check
    CHECK (current_card_suit IN ('HEARTS', 'DIAMONDS', 'CLUBS', 'SPADES')),
    ADD CONSTRAINT hilo_sessions_multiplier_positive_check
    CHECK (current_multiplier > 0),
    ADD CONSTRAINT hilo_sessions_streak_nonnegative_check
    CHECK (current_streak >= 0);
