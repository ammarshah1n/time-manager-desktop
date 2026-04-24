-- Task 23: behaviour_events event_type extension + briefings.sections_interacted.
-- Adds four morning-briefing interaction event types, and ensures the
-- sections_interacted JSONB column exists on briefings (the initial
-- briefings migration already creates it; this ALTER is idempotent).

ALTER TABLE public.briefings
    ADD COLUMN IF NOT EXISTS sections_interacted JSONB DEFAULT '[]'::jsonb;

ALTER TABLE public.behaviour_events
    DROP CONSTRAINT IF EXISTS behaviour_events_event_type_check;

ALTER TABLE public.behaviour_events
    ADD CONSTRAINT behaviour_events_event_type_check CHECK (event_type IN (
        'task_completed',
        'task_deferred',
        'task_deleted',
        'plan_order_override',
        'estimate_override',
        'session_started',
        'triage_correction',
        'task_abandoned',
        'task_unblocked',
        'session_interrupted',
        'recommendation_acted_on',
        'recommendation_dismissed',
        'briefing_section_viewed',
        'briefing_section_interacted'
    ));

COMMENT ON COLUMN public.briefings.sections_interacted IS
  'Append-only log of per-section interactions: [{section_key, event_type, at, ...}]. Written by MorningBriefingPane alongside behaviour_events rows.';
