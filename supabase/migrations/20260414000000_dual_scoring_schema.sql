-- Dual-scoring architecture: real-time (Haiku) + batch (Sonnet) importance scoring
-- Research grounding: v3-05 dual-scoring architecture report

-- Ensure zero-arg get_executive_id() exists (needed by RLS policies below)
CREATE OR REPLACE FUNCTION public.get_executive_id()
RETURNS uuid LANGUAGE sql STABLE SECURITY DEFINER AS $$
  SELECT id FROM public.executives WHERE auth_user_id = auth.uid() LIMIT 1
$$;

-- Add RT and batch score columns to tier0_observations
ALTER TABLE public.tier0_observations
  ADD COLUMN IF NOT EXISTS rt_score float,
  ADD COLUMN IF NOT EXISTS rt_scored_at timestamptz,
  ADD COLUMN IF NOT EXISTS rt_model text,
  ADD COLUMN IF NOT EXISTS batch_score float,
  ADD COLUMN IF NOT EXISTS batch_scored_at timestamptz,
  ADD COLUMN IF NOT EXISTS batch_model text;

-- Generated stored column: authoritative score resolves to batch when available, else RT
-- Falls back to legacy importance_score if neither exists
ALTER TABLE public.tier0_observations
  ADD COLUMN IF NOT EXISTS authoritative_score float
  GENERATED ALWAYS AS (COALESCE(batch_score, rt_score, importance_score)) STORED;

-- Score audit log (partitioned by month for efficient pruning)
CREATE TABLE IF NOT EXISTS public.score_audit_log (
  id uuid DEFAULT gen_random_uuid(),
  workspace_id uuid NOT NULL,
  observation_id uuid NOT NULL REFERENCES public.tier0_observations(id),
  event_type text NOT NULL CHECK (event_type IN (
    'realtime_scored', 'batch_scored', 'user_override',
    'conflict_detected', 'alert_fired', 'alert_annotated'
  )),
  rt_score float,
  batch_score float,
  score_delta float,
  conflict_severity text GENERATED ALWAYS AS (
    CASE
      WHEN ABS(COALESCE(score_delta, 0)) >= 0.50 THEN 'critical'
      WHEN ABS(COALESCE(score_delta, 0)) >= 0.30 THEN 'major'
      WHEN ABS(COALESCE(score_delta, 0)) >= 0.15 THEN 'minor'
      ELSE 'negligible'
    END
  ) STORED,
  details jsonb,
  occurred_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (id, occurred_at)
) PARTITION BY RANGE (occurred_at);

-- Create initial partitions (3 months ahead)
CREATE TABLE IF NOT EXISTS public.score_audit_log_2026_04
  PARTITION OF public.score_audit_log
  FOR VALUES FROM ('2026-04-01') TO ('2026-05-01');

CREATE TABLE IF NOT EXISTS public.score_audit_log_2026_05
  PARTITION OF public.score_audit_log
  FOR VALUES FROM ('2026-05-01') TO ('2026-06-01');

CREATE TABLE IF NOT EXISTS public.score_audit_log_2026_06
  PARTITION OF public.score_audit_log
  FOR VALUES FROM ('2026-06-01') TO ('2026-07-01');

-- Index for querying conflicts
CREATE INDEX IF NOT EXISTS idx_score_audit_conflict
  ON public.score_audit_log (conflict_severity, occurred_at DESC)
  WHERE conflict_severity IN ('critical', 'major');

CREATE INDEX IF NOT EXISTS idx_score_audit_observation
  ON public.score_audit_log (workspace_id, observation_id);

-- Alert states lifecycle table
CREATE TABLE IF NOT EXISTS public.alert_states (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  profile_id uuid NOT NULL,
  observation_id uuid NOT NULL REFERENCES public.tier0_observations(id),
  status text NOT NULL DEFAULT 'pending' CHECK (status IN (
    'pending', 'fired', 'confirmed', 'downgraded', 'annotated', 'dismissed'
  )),
  fire_score float,
  fire_model text,
  batch_score float,
  reconciliation_action text,
  annotation_text text,
  user_dismissed_at timestamptz,
  user_action_taken text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- Only one active alert per observation
CREATE UNIQUE INDEX IF NOT EXISTS idx_alert_states_active
  ON public.alert_states (observation_id)
  WHERE status NOT IN ('dismissed');

-- RLS for alert_states
ALTER TABLE public.alert_states ENABLE ROW LEVEL SECURITY;

CREATE POLICY "alert_states_select_own" ON public.alert_states
  FOR SELECT USING (
    profile_id = public.get_executive_id()
    OR auth.role() = 'service_role'
  );

CREATE POLICY "alert_states_service_role" ON public.alert_states
  FOR ALL USING (auth.role() = 'service_role');

-- RLS for score_audit_log
ALTER TABLE public.score_audit_log ENABLE ROW LEVEL SECURITY;

CREATE POLICY "score_audit_log_service_role" ON public.score_audit_log
  FOR ALL USING (auth.role() = 'service_role');

-- Index on tier0_observations for authoritative_score queries
CREATE INDEX IF NOT EXISTS idx_tier0_authoritative_score
  ON public.tier0_observations (profile_id, authoritative_score DESC)
  WHERE authoritative_score IS NOT NULL;
