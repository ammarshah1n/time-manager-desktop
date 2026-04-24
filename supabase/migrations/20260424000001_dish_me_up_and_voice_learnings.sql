-- Dish Me Up + Voice learnings schema additions
--
-- 1. calendar_observations: title + description columns so generate-dish-me-up
--    can reason about cognitive load (Signal 6 in the architecture doc).
-- 2. calendar_events view: architecture-doc-friendly name.
-- 3. voice_session_learnings: persists perceived priorities, hidden context,
--    and rule updates extracted from the ElevenLabs morning check-in.

ALTER TABLE public.calendar_observations
  ADD COLUMN IF NOT EXISTS title       TEXT,
  ADD COLUMN IF NOT EXISTS description TEXT;

-- Signal 7 (task awareness): set by generate-dish-me-up every time a task
-- appears in a plan, so Opus can tell genuinely-new tasks from already-seen ones.
ALTER TABLE public.tasks
  ADD COLUMN IF NOT EXISTS last_viewed_at TIMESTAMPTZ;

CREATE OR REPLACE VIEW public.calendar_events AS
SELECT id,
       executive_id AS user_id,
       title,
       description,
       event_start AS starts_at,
       event_end   AS ends_at,
       attendee_count,
       organiser_is_self,
       was_cancelled,
       was_rescheduled,
       observed_at
FROM public.calendar_observations;

CREATE TABLE IF NOT EXISTS public.voice_session_learnings (
  id                   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  executive_id         UUID NOT NULL REFERENCES public.executives(id) ON DELETE CASCADE,
  session_date         DATE NOT NULL,
  perceived_priorities JSONB NOT NULL DEFAULT '[]'::jsonb,
  hidden_context       TEXT,
  new_tasks_to_create  JSONB NOT NULL DEFAULT '[]'::jsonb,
  acb_delta            TEXT,
  rule_updates         JSONB NOT NULL DEFAULT '[]'::jsonb,
  transcript           TEXT,
  created_at           TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS voice_session_learnings_executive_date_idx
  ON public.voice_session_learnings (executive_id, session_date DESC);

ALTER TABLE public.voice_session_learnings ENABLE ROW LEVEL SECURITY;

CREATE POLICY voice_session_learnings_select
  ON public.voice_session_learnings
  FOR SELECT
  USING (executive_id = public.get_executive_id(auth.uid()));

CREATE POLICY voice_session_learnings_insert
  ON public.voice_session_learnings
  FOR INSERT
  WITH CHECK (executive_id = public.get_executive_id(auth.uid()));

CREATE POLICY voice_session_learnings_service_all
  ON public.voice_session_learnings
  FOR ALL
  TO service_role
  USING (true)
  WITH CHECK (true);

COMMENT ON TABLE  public.voice_session_learnings IS
  'Structured output of the morning check-in. Consumed by generate-dish-me-up on the same day and by weekly-strategic-synthesis at week-end.';
COMMENT ON VIEW   public.calendar_events IS
  'Architecture-doc name for calendar_observations. Exposes title + description for Signal 6 (cognitive load).';
