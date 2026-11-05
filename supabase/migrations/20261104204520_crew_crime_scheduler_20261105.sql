-- Source-backed persistent scheduler state for NPC crew crime automation.
-- No legacy assignment is backfilled because existing rows have no authoritative
-- assignment-start timestamp and must not receive retroactive payouts.

CREATE TABLE public.crew_crime_assignments (
    crew_id BIGINT PRIMARY KEY
        REFERENCES public.user_crew(crew_id) ON DELETE CASCADE,
    crime_id BIGINT NOT NULL
        REFERENCES public.crimes_master(id) ON DELETE RESTRICT,
    assigned_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    next_tick_at TIMESTAMPTZ NOT NULL,
    last_tick_at TIMESTAMPTZ,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX crew_crime_assignments_due_idx
    ON public.crew_crime_assignments (next_tick_at, crew_id);

ALTER TABLE public.crew_crime_assignments ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE public.crew_crime_assignments FROM anon, authenticated;

COMMENT ON TABLE public.crew_crime_assignments IS
'Server-owned schedule for source-backed NPC crime automation. No direct client writes.';
COMMENT ON COLUMN public.crew_crime_assignments.next_tick_at IS
'Persisted due time. Settlement advances this atomically with payout/stat/casualty state.';
