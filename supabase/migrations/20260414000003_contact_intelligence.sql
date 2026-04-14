-- Contact intelligence cards — 15-field schema from v3-03 research
-- 3-layer progressive disclosure: glance (5-8s), summary (15-30s), detail (60-90s)

CREATE TABLE IF NOT EXISTS public.contact_intelligence (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  profile_id uuid NOT NULL,
  contact_id uuid NOT NULL,
  -- Glance layer
  contact_display_name text,
  health_status text CHECK (health_status IN ('green', 'yellow', 'red', 'grey')),
  health_delta float DEFAULT 0,
  primary_signal_label text,
  -- Summary layer
  reply_latency_delta text,
  meeting_attendance_rate float,
  email_frequency_trend text CHECK (email_frequency_trend IN ('rising', 'stable', 'declining')),
  initiated_ratio_delta text,
  tone_formality_index float,
  interpretation_set jsonb DEFAULT '[]'::jsonb,
  recommended_action text,
  confidence_level text CHECK (confidence_level IN ('high', 'medium', 'low')),
  -- Detail layer
  signal_timeline jsonb DEFAULT '[]'::jsonb,
  -- Meta
  card_generated_at timestamptz NOT NULL DEFAULT now(),
  tokens_used int,
  UNIQUE (profile_id, contact_id)
);

CREATE INDEX IF NOT EXISTS idx_contact_intelligence_profile
  ON public.contact_intelligence (profile_id, health_status);

ALTER TABLE public.contact_intelligence ENABLE ROW LEVEL SECURITY;

CREATE POLICY "contact_intelligence_select_own" ON public.contact_intelligence
  FOR SELECT USING (
    profile_id = public.get_executive_id()
    OR auth.role() = 'service_role'
  );

CREATE POLICY "contact_intelligence_service_role" ON public.contact_intelligence
  FOR ALL USING (auth.role() = 'service_role');
