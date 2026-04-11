-- 0.03: executives table — one row per executive user
-- Depends on: Supabase Auth (Microsoft provider enabled in 0.01)

CREATE TABLE IF NOT EXISTS public.executives (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    auth_user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    display_name TEXT NOT NULL,
    email TEXT NOT NULL,
    timezone TEXT NOT NULL DEFAULT 'UTC',
    onboarded_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT executives_auth_user_id_key UNIQUE (auth_user_id)
);

-- RLS: executives can only read/update their own row
ALTER TABLE public.executives ENABLE ROW LEVEL SECURITY;

CREATE POLICY "executives_select_own" ON public.executives
    FOR SELECT USING (auth.uid() = auth_user_id);

CREATE POLICY "executives_update_own" ON public.executives
    FOR UPDATE USING (auth.uid() = auth_user_id);

-- Service role can insert (used by bootstrap-executive Edge Function)
CREATE POLICY "executives_insert_service" ON public.executives
    FOR INSERT WITH CHECK (true);

-- Helper function: get executive_id from auth.uid() — used by RLS on all other tables
CREATE OR REPLACE FUNCTION public.get_executive_id(user_id UUID)
RETURNS UUID
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
    SELECT id FROM public.executives WHERE auth_user_id = user_id LIMIT 1;
$$;

COMMENT ON TABLE public.executives IS 'One row per executive user. Source of truth for profile_id used across all intelligence tables.';
COMMENT ON FUNCTION public.get_executive_id IS 'Maps auth.uid() to executives.id for RLS policies on tier0_observations and downstream tables.';
