-- Task 21: recommendations + recommendation_outcomes.
-- Each morning briefing section emits one `recommendations` row (via the
-- generate-morning-briefing Edge Function patch in Task 22). Outcome rows are
-- written by the trigger.dev `outcome-harvester` task (Task 24) and by the
-- Swift client when the user acts on / dismisses a section.

CREATE TABLE IF NOT EXISTS public.recommendations (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    briefing_id  UUID NOT NULL REFERENCES public.briefings(id) ON DELETE CASCADE,
    section_key  TEXT NOT NULL,
    task_ref     TEXT,
    content_hash TEXT NOT NULL,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_recommendations_briefing
    ON public.recommendations (briefing_id, section_key);

CREATE INDEX IF NOT EXISTS idx_recommendations_content_hash
    ON public.recommendations (content_hash);

ALTER TABLE public.recommendations ENABLE ROW LEVEL SECURITY;

CREATE POLICY "recommendations_select_own"
    ON public.recommendations
    FOR SELECT
    USING (
        briefing_id IN (
            SELECT id FROM public.briefings
            WHERE profile_id = public.get_executive_id(auth.uid())
        )
    );

CREATE POLICY "recommendations_service_all"
    ON public.recommendations
    FOR ALL
    TO service_role
    USING (true)
    WITH CHECK (true);

CREATE TABLE IF NOT EXISTS public.recommendation_outcomes (
    recommendation_id UUID NOT NULL REFERENCES public.recommendations(id) ON DELETE CASCADE,
    outcome_type      TEXT NOT NULL CHECK (outcome_type IN (
        'acted_on', 'dismissed', 'ignored', 'superseded', 'partial'
    )),
    observed_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    signal_source     TEXT,
    raw_signal        JSONB,
    PRIMARY KEY (recommendation_id, outcome_type)
);

-- Composite PK already enforces uniqueness on (recommendation_id, outcome_type);
-- the explicit index below aids queries that filter by outcome_type alone.
CREATE INDEX IF NOT EXISTS idx_recommendation_outcomes_observed
    ON public.recommendation_outcomes (observed_at DESC);

CREATE INDEX IF NOT EXISTS idx_recommendation_outcomes_outcome_type
    ON public.recommendation_outcomes (outcome_type);

ALTER TABLE public.recommendation_outcomes ENABLE ROW LEVEL SECURITY;

CREATE POLICY "recommendation_outcomes_select_own"
    ON public.recommendation_outcomes
    FOR SELECT
    USING (
        recommendation_id IN (
            SELECT r.id
            FROM public.recommendations r
            JOIN public.briefings b ON b.id = r.briefing_id
            WHERE b.profile_id = public.get_executive_id(auth.uid())
        )
    );

CREATE POLICY "recommendation_outcomes_service_all"
    ON public.recommendation_outcomes
    FOR ALL
    TO service_role
    USING (true)
    WITH CHECK (true);

COMMENT ON TABLE public.recommendations IS
  'One row per morning-briefing section. Joined with recommendation_outcomes to form the Reflexion feedback signal for the nightly agent loop.';
COMMENT ON TABLE public.recommendation_outcomes IS
  'Observed outcomes for each recommendation. (recommendation_id, outcome_type) is the natural key.';
