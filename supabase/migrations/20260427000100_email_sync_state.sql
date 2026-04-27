-- Wave 2 B1 — Support tables for server-side Graph sync (T9/T10/T39).
--
-- `email_sync_state` holds per-executive delta pagination tokens for both
-- /messages/delta and /calendarView/delta. The Trigger.dev scheduled tasks
-- read and write these on every tick.
--
-- `graph_subscriptions` tracks the live Microsoft Graph change-notification
-- subscriptions so `graph-webhook-renewal` can PATCH them before they expire.
--
-- Also adds a `graph_event_id` column to calendar_observations so the
-- calendar delta sync can dedupe on the Graph event id without needing a
-- raw_data JSONB column. We keep the column nullable so existing rows
-- (which predate server-side ingestion) are unaffected.

-- 1. email_sync_state -------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.email_sync_state (
    exec_id                  UUID PRIMARY KEY
                                REFERENCES public.executives(id) ON DELETE CASCADE,
    delta_link               TEXT,
    calendar_delta_link      TEXT,
    last_synced_at           TIMESTAMPTZ,
    last_calendar_synced_at  TIMESTAMPTZ,
    created_at               TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at               TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.email_sync_state ENABLE ROW LEVEL SECURITY;

-- Service-role-only: Trigger.dev tasks write here with the service key,
-- no end-user surface ever reads this table.
CREATE POLICY email_sync_state_service_all
    ON public.email_sync_state
    FOR ALL
    TO service_role
    USING (true)
    WITH CHECK (true);

REVOKE ALL ON public.email_sync_state FROM anon, authenticated;

COMMENT ON TABLE public.email_sync_state IS
  'Per-executive delta pagination state for server-side Graph sync. Written only by Trigger.dev tasks under the service role.';

-- 2. graph_subscriptions ----------------------------------------------------
CREATE TABLE IF NOT EXISTS public.graph_subscriptions (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    exec_id          UUID REFERENCES public.executives(id) ON DELETE CASCADE,
    subscription_id  TEXT UNIQUE,
    resource         TEXT NOT NULL,
    expires_at       TIMESTAMPTZ NOT NULL,
    client_state     TEXT,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS graph_subscriptions_exec_idx
    ON public.graph_subscriptions (exec_id);

CREATE INDEX IF NOT EXISTS graph_subscriptions_expires_idx
    ON public.graph_subscriptions (expires_at);

ALTER TABLE public.graph_subscriptions ENABLE ROW LEVEL SECURITY;

CREATE POLICY graph_subscriptions_service_all
    ON public.graph_subscriptions
    FOR ALL
    TO service_role
    USING (true)
    WITH CHECK (true);

REVOKE ALL ON public.graph_subscriptions FROM anon, authenticated;

COMMENT ON TABLE public.graph_subscriptions IS
  'Live Microsoft Graph change-notification subscriptions. Renewed every 2 hours by the graph-webhook-renewal Trigger.dev task.';

-- 3. calendar_observations: Graph event id for dedup ------------------------
-- calendar_observations has no natural key today (no graph_event_id, no
-- ical_uid, no raw_data). Add a nullable column so server-side calendar
-- sync can upsert without re-reading the row, and create a partial unique
-- index keyed by (executive_id, graph_event_id) to enforce one row per
-- (exec, event) when a graph id is present.
ALTER TABLE public.calendar_observations
    ADD COLUMN IF NOT EXISTS graph_event_id TEXT;

CREATE UNIQUE INDEX IF NOT EXISTS calendar_observations_exec_graph_event_uidx
    ON public.calendar_observations (executive_id, graph_event_id)
    WHERE graph_event_id IS NOT NULL;

COMMENT ON COLUMN public.calendar_observations.graph_event_id IS
  'Microsoft Graph event id. Nullable because pre-Wave-2 rows were inserted from the Swift client without it. Used by graph-calendar-delta-sync for ON CONFLICT dedup via calendar_observations_exec_graph_event_uidx.';
