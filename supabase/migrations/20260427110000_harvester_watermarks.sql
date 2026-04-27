-- Wave 2 Task 24 — persistable watermarks for Trigger.dev harvester tasks.
--
-- The `outcome-harvester` task drains `behaviour_events` every 4 hours, matches
-- them against open `recommendations`, and writes `recommendation_outcomes`.
-- Watermarks are persisted here so consecutive runs resume exactly where the
-- previous run left off, bounded by `last_event_at` + `last_event_id`.
--
-- Service-role-only: Trigger.dev tasks write here with the service key. No
-- end-user surface reads this table. RLS is enabled as defence-in-depth; the
-- only granted role is `service_role` via the `FOR ALL` policy below.

CREATE TABLE IF NOT EXISTS public.harvester_watermarks (
    harvester      TEXT PRIMARY KEY,
    last_event_id  UUID,
    last_event_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.harvester_watermarks ENABLE ROW LEVEL SECURITY;

CREATE POLICY harvester_watermarks_service_all
    ON public.harvester_watermarks
    FOR ALL
    TO service_role
    USING (true)
    WITH CHECK (true);

REVOKE ALL ON public.harvester_watermarks FROM anon, authenticated;

COMMENT ON TABLE public.harvester_watermarks IS
  'Persistent cursor per background harvester (e.g. outcome-harvester). Stores the max(occurred_at, id) of the last successfully processed behaviour_events page so the next run resumes without duplication.';

-- Seed the outcome-harvester row so its first run backfills the last 7 days.
INSERT INTO public.harvester_watermarks (harvester, last_event_at)
VALUES ('outcome-harvester', now() - interval '7 days')
ON CONFLICT (harvester) DO NOTHING;
