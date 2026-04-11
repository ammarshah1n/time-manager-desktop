CREATE TABLE public.email_observations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    executive_id UUID NOT NULL REFERENCES public.executives(id),
    observed_at TIMESTAMPTZ NOT NULL,
    graph_message_id TEXT,
    sender_address TEXT,
    sender_name TEXT,
    recipient_count INT,
    subject_hash TEXT,
    folder TEXT,
    importance TEXT,
    is_reply BOOL DEFAULT false,
    is_forward BOOL DEFAULT false,
    response_latency_seconds INT,
    thread_depth INT,
    categories JSONB,
    created_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX email_observations_executive_observed_brin_idx
ON public.email_observations
USING brin (executive_id, observed_at);

ALTER TABLE public.email_observations ENABLE ROW LEVEL SECURITY;

CREATE POLICY email_observations_select
ON public.email_observations
FOR SELECT
USING (executive_id = public.get_executive_id(auth.uid()));

CREATE POLICY email_observations_insert
ON public.email_observations
FOR INSERT
WITH CHECK (executive_id = public.get_executive_id(auth.uid()));

CREATE POLICY email_observations_update
ON public.email_observations
FOR UPDATE
USING (executive_id = public.get_executive_id(auth.uid()))
WITH CHECK (executive_id = public.get_executive_id(auth.uid()));

CREATE POLICY email_observations_delete
ON public.email_observations
FOR DELETE
USING (executive_id = public.get_executive_id(auth.uid()));

CREATE TABLE public.calendar_observations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    executive_id UUID NOT NULL REFERENCES public.executives(id),
    observed_at TIMESTAMPTZ NOT NULL,
    event_start TIMESTAMPTZ,
    event_end TIMESTAMPTZ,
    attendee_count INT,
    organiser_is_self BOOL DEFAULT false,
    response_status TEXT,
    was_cancelled BOOL DEFAULT false,
    was_rescheduled BOOL DEFAULT false,
    original_start TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX calendar_observations_executive_observed_brin_idx
ON public.calendar_observations
USING brin (executive_id, observed_at);

ALTER TABLE public.calendar_observations ENABLE ROW LEVEL SECURITY;

CREATE POLICY calendar_observations_select
ON public.calendar_observations
FOR SELECT
USING (executive_id = public.get_executive_id(auth.uid()));

CREATE POLICY calendar_observations_insert
ON public.calendar_observations
FOR INSERT
WITH CHECK (executive_id = public.get_executive_id(auth.uid()));

CREATE POLICY calendar_observations_update
ON public.calendar_observations
FOR UPDATE
USING (executive_id = public.get_executive_id(auth.uid()))
WITH CHECK (executive_id = public.get_executive_id(auth.uid()));

CREATE POLICY calendar_observations_delete
ON public.calendar_observations
FOR DELETE
USING (executive_id = public.get_executive_id(auth.uid()));

CREATE TABLE public.app_usage_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    executive_id UUID NOT NULL REFERENCES public.executives(id),
    observed_at TIMESTAMPTZ NOT NULL,
    bundle_id TEXT,
    window_title_hash TEXT,
    focus_duration INT,
    app_category TEXT,
    created_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX app_usage_events_executive_observed_brin_idx
ON public.app_usage_events
USING brin (executive_id, observed_at);

ALTER TABLE public.app_usage_events ENABLE ROW LEVEL SECURITY;

CREATE POLICY app_usage_events_select
ON public.app_usage_events
FOR SELECT
USING (executive_id = public.get_executive_id(auth.uid()));

CREATE POLICY app_usage_events_insert
ON public.app_usage_events
FOR INSERT
WITH CHECK (executive_id = public.get_executive_id(auth.uid()));

CREATE POLICY app_usage_events_update
ON public.app_usage_events
FOR UPDATE
USING (executive_id = public.get_executive_id(auth.uid()))
WITH CHECK (executive_id = public.get_executive_id(auth.uid()));

CREATE POLICY app_usage_events_delete
ON public.app_usage_events
FOR DELETE
USING (executive_id = public.get_executive_id(auth.uid()));
