-- Executive cognitive bias detection schema
-- Research grounding: v3-01 (cognitive bias detection from passive digital signals)
-- 6 viable biases, 3 experimental, 90-day baseline required

-- Individual signal observations
CREATE TABLE IF NOT EXISTS public.bias_signal_observations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  profile_id uuid NOT NULL,
  bias_type text NOT NULL CHECK (bias_type IN (
    'overconfidence', 'anchoring', 'sunk_cost', 'availability',
    'confirmation', 'status_quo', 'planning_fallacy',
    'escalation_of_commitment', 'recency'
  )),
  signal_type text NOT NULL,
  signal_value float,
  classification text CHECK (classification IN ('strong', 'moderate', 'weak')),
  source_ref uuid,
  context_snapshot jsonb,
  meets_minimum_data boolean DEFAULT false,
  competing_hyp_score float,
  detected_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_bias_signals_profile_type
  ON public.bias_signal_observations (profile_id, bias_type);
CREATE INDEX IF NOT EXISTS idx_bias_signals_detected
  ON public.bias_signal_observations (profile_id, detected_at DESC);

-- Temporal evidence chains
CREATE TABLE IF NOT EXISTS public.bias_evidence_chains (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  profile_id uuid NOT NULL,
  bias_type text NOT NULL CHECK (bias_type IN (
    'overconfidence', 'anchoring', 'sunk_cost', 'availability',
    'confirmation', 'status_quo', 'planning_fallacy',
    'escalation_of_commitment', 'recency'
  )),
  observation_ids uuid[] DEFAULT '{}',
  signal_strength_avg float DEFAULT 0,
  consistency_rate float DEFAULT 0,
  confidence float DEFAULT 0,
  personal_baseline jsonb,
  status text NOT NULL DEFAULT 'accumulating' CHECK (status IN (
    'accumulating', 'tentative', 'active', 'decayed', 'dismissed'
  )),
  insight_card jsonb,
  insight_framing text CHECK (insight_framing IN ('curiosity', 'pattern', 'option')),
  decay_after timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- Only one active chain per bias type per user
CREATE UNIQUE INDEX IF NOT EXISTS idx_bias_chains_active
  ON public.bias_evidence_chains (profile_id, bias_type)
  WHERE status IN ('accumulating', 'tentative', 'active');

-- Analysis run observability
CREATE TABLE IF NOT EXISTS public.bias_analysis_runs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  profile_id uuid NOT NULL,
  run_date date NOT NULL,
  emails_analysed int DEFAULT 0,
  calendar_analysed int DEFAULT 0,
  tasks_analysed int DEFAULT 0,
  signals_extracted int DEFAULT 0,
  chains_updated int DEFAULT 0,
  flags_promoted int DEFAULT 0,
  flags_decayed int DEFAULT 0,
  tokens_used int DEFAULT 0,
  cost_usd float,
  created_at timestamptz NOT NULL DEFAULT now()
);

-- RLS
ALTER TABLE public.bias_signal_observations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.bias_evidence_chains ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.bias_analysis_runs ENABLE ROW LEVEL SECURITY;

CREATE POLICY "bias_signals_select_own" ON public.bias_signal_observations
  FOR SELECT USING (profile_id = public.get_executive_id() OR auth.role() = 'service_role');
CREATE POLICY "bias_signals_service_role" ON public.bias_signal_observations
  FOR ALL USING (auth.role() = 'service_role');

CREATE POLICY "bias_chains_select_own" ON public.bias_evidence_chains
  FOR SELECT USING (profile_id = public.get_executive_id() OR auth.role() = 'service_role');
CREATE POLICY "bias_chains_service_role" ON public.bias_evidence_chains
  FOR ALL USING (auth.role() = 'service_role');

CREATE POLICY "bias_runs_select_own" ON public.bias_analysis_runs
  FOR SELECT USING (profile_id = public.get_executive_id() OR auth.role() = 'service_role');
CREATE POLICY "bias_runs_service_role" ON public.bias_analysis_runs
  FOR ALL USING (auth.role() = 'service_role');

-- Extend behavioral_rules with bias type
ALTER TABLE public.behavioral_rules
  ADD COLUMN IF NOT EXISTS bias_type text,
  ADD COLUMN IF NOT EXISTS bias_chain_id uuid REFERENCES public.bias_evidence_chains(id);

-- Cron schedule (3 AM daily, after nightly phase2)
SELECT cron.schedule(
  'nightly-bias-detection',
  '0 3 * * *',
  $$SELECT net.http_post(
    url := current_setting('app.settings.supabase_url') || '/functions/v1/nightly-bias-detection',
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || current_setting('app.settings.service_role_key'),
      'Content-Type', 'application/json'
    ),
    body := '{}'::jsonb
  )$$
);
