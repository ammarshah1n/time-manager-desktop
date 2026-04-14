-- Weekly strategic synthesis table
-- Research grounding: v3-02 (effort=max for weekly synthesis)

CREATE TABLE IF NOT EXISTS public.weekly_syntheses (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  profile_id uuid NOT NULL,
  week_start date NOT NULL,
  strategic_analysis text,
  time_allocation jsonb DEFAULT '{}'::jsonb,
  decision_velocity jsonb DEFAULT '{}'::jsonb,
  relationship_focus jsonb DEFAULT '[]'::jsonb,
  energy_map jsonb DEFAULT '{}'::jsonb,
  key_contradictions jsonb DEFAULT '[]'::jsonb,
  emerging_risks jsonb DEFAULT '[]'::jsonb,
  strategic_recommendation text,
  generated_at timestamptz NOT NULL DEFAULT now(),
  tokens_used int,
  UNIQUE (profile_id, week_start)
);

ALTER TABLE public.weekly_syntheses ENABLE ROW LEVEL SECURITY;

CREATE POLICY "weekly_syntheses_select_own" ON public.weekly_syntheses
  FOR SELECT USING (
    profile_id = public.get_executive_id()
    OR auth.role() = 'service_role'
  );

CREATE POLICY "weekly_syntheses_service_role" ON public.weekly_syntheses
  FOR ALL USING (auth.role() = 'service_role');

-- Cron schedule for weekly synthesis (Sunday 3 AM)
SELECT cron.schedule(
  'weekly-strategic-synthesis',
  '0 3 * * 0',
  $$SELECT net.http_post(
    url := current_setting('app.settings.supabase_url') || '/functions/v1/weekly-strategic-synthesis',
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || current_setting('app.settings.service_role_key'),
      'Content-Type', 'application/json'
    ),
    body := '{}'::jsonb
  )$$
);
