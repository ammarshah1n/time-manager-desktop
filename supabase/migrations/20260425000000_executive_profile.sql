-- Task 19: executive_profile — persistent setup state sourced from onboarding.
-- Replaces the AppStorage-only source-of-truth. OnboardingFlow upserts this row
-- on completion; AppStorage is retained as a local read-through cache.

CREATE TABLE IF NOT EXISTS public.executive_profile (
    exec_id              UUID PRIMARY KEY REFERENCES public.executives(id) ON DELETE CASCADE,
    display_name         TEXT,
    work_hours_start     TIME,
    work_hours_end       TIME,
    typical_workday_hours NUMERIC(4,2),
    email_cadence_mode   SMALLINT,
    transit_modes        JSONB NOT NULL DEFAULT '[]'::jsonb,
    time_defaults        JSONB NOT NULL DEFAULT '{}'::jsonb,
    pa_email             TEXT,
    pa_enabled           BOOLEAN NOT NULL DEFAULT false,
    updated_at           TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.executive_profile ENABLE ROW LEVEL SECURITY;

CREATE POLICY "executive_profile_select_own"
    ON public.executive_profile
    FOR SELECT
    USING (exec_id = public.get_executive_id(auth.uid()));

CREATE POLICY "executive_profile_upsert_own"
    ON public.executive_profile
    FOR INSERT
    WITH CHECK (exec_id = public.get_executive_id(auth.uid()));

CREATE POLICY "executive_profile_update_own"
    ON public.executive_profile
    FOR UPDATE
    USING (exec_id = public.get_executive_id(auth.uid()));

CREATE POLICY "executive_profile_service_all"
    ON public.executive_profile
    FOR ALL
    TO service_role
    USING (true)
    WITH CHECK (true);

COMMENT ON TABLE public.executive_profile IS
  'Executive setup persisted from onboarding (display name, work hours, email cadence, transit modes, time defaults, PA). Source of truth once present; AppStorage becomes a cache.';
COMMENT ON COLUMN public.executive_profile.email_cadence_mode IS
  'Enum index: 0=Once, 1=Twice, 2=3x daily, 3=4+ times.';
COMMENT ON COLUMN public.executive_profile.transit_modes IS
  'JSON array of string keys from {"chauffeur","train","plane","drive"}.';
COMMENT ON COLUMN public.executive_profile.time_defaults IS
  'Task-type default minutes, e.g. {"reply":5,"action":30,"call":15,"read":20}.';
