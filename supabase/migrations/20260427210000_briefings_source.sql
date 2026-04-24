-- 20260427210000_briefings_source.sql
--
-- Timed overnight cognitive OS — briefings provenance.
--
-- T30. Adds a `source` column to `briefings` so every row is explicitly tagged
-- with the pipeline that produced it. The legacy Edge Function
-- (generate-morning-briefing) is labelled 'legacy'; the Trigger.dev
-- rem-synthesis / morning-briefing pipeline writes 'trigger'. This lets the
-- Swift client A/B the two sources during the cutover and lets replay filter
-- by generator.

BEGIN;

ALTER TABLE public.briefings
  ADD COLUMN IF NOT EXISTS source text NOT NULL DEFAULT 'legacy'
  CHECK (source IN ('legacy','trigger'));

COMMENT ON COLUMN public.briefings.source IS
  'Origin of the briefing: legacy = Edge Function generate-morning-briefing; trigger = Trigger.dev rem-synthesis or later pipeline.';

COMMIT;
