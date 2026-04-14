-- Production readiness migration: RLS fixes, constraint expansions, missing indexes
-- Fixes: get_executive_id() zero-arg calls, auth.uid() vs get_executive_id() mismatch,
--         missing RLS on initial tables, CHECK constraint gaps, missing indexes

-- ============================================================
-- 1. Zero-arg overload for get_executive_id()
--    Called as get_executive_id() in 6+ RLS policies that wrote it without auth.uid()
--    Fix: create a zero-arg wrapper that calls auth.uid() internally
-- ============================================================

CREATE OR REPLACE FUNCTION public.get_executive_id()
RETURNS UUID
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
    SELECT id FROM public.executives WHERE auth_user_id = auth.uid() LIMIT 1;
$$;

COMMENT ON FUNCTION public.get_executive_id() IS 'Zero-arg overload: resolves auth.uid() to executives.id for use in RLS policies.';

-- ============================================================
-- 2. Fix ONA tables: auth.uid() -> get_executive_id(auth.uid())
--    ona_nodes, ona_edges, relationships all store executives.id in profile_id
--    but RLS compared against auth.uid() (which is auth.users.id)
-- ============================================================

-- ona_nodes: drop broken policies, recreate with correct function
DROP POLICY IF EXISTS "ona_nodes_select" ON ona_nodes;
DROP POLICY IF EXISTS "ona_nodes_insert" ON ona_nodes;
DROP POLICY IF EXISTS "ona_nodes_update" ON ona_nodes;
DROP POLICY IF EXISTS "ona_nodes_delete" ON ona_nodes;

CREATE POLICY "ona_nodes_select" ON ona_nodes FOR SELECT
  USING (profile_id = public.get_executive_id(auth.uid()) OR auth.role() = 'service_role');
CREATE POLICY "ona_nodes_insert" ON ona_nodes FOR INSERT
  WITH CHECK (profile_id = public.get_executive_id(auth.uid()) OR auth.role() = 'service_role');
CREATE POLICY "ona_nodes_update" ON ona_nodes FOR UPDATE
  USING (profile_id = public.get_executive_id(auth.uid()) OR auth.role() = 'service_role');
CREATE POLICY "ona_nodes_delete" ON ona_nodes FOR DELETE
  USING (profile_id = public.get_executive_id(auth.uid()) OR auth.role() = 'service_role');

-- ona_edges: same fix
DROP POLICY IF EXISTS "ona_edges_select" ON ona_edges;
DROP POLICY IF EXISTS "ona_edges_insert" ON ona_edges;
DROP POLICY IF EXISTS "ona_edges_update" ON ona_edges;
DROP POLICY IF EXISTS "ona_edges_delete" ON ona_edges;

CREATE POLICY "ona_edges_select" ON ona_edges FOR SELECT
  USING (profile_id = public.get_executive_id(auth.uid()) OR auth.role() = 'service_role');
CREATE POLICY "ona_edges_insert" ON ona_edges FOR INSERT
  WITH CHECK (profile_id = public.get_executive_id(auth.uid()) OR auth.role() = 'service_role');
CREATE POLICY "ona_edges_update" ON ona_edges FOR UPDATE
  USING (profile_id = public.get_executive_id(auth.uid()) OR auth.role() = 'service_role');
CREATE POLICY "ona_edges_delete" ON ona_edges FOR DELETE
  USING (profile_id = public.get_executive_id(auth.uid()) OR auth.role() = 'service_role');

-- relationships: same fix
DROP POLICY IF EXISTS "relationships_select" ON relationships;
DROP POLICY IF EXISTS "relationships_insert" ON relationships;
DROP POLICY IF EXISTS "relationships_update" ON relationships;
DROP POLICY IF EXISTS "relationships_delete" ON relationships;

CREATE POLICY "relationships_select" ON relationships FOR SELECT
  USING (profile_id = public.get_executive_id(auth.uid()) OR auth.role() = 'service_role');
CREATE POLICY "relationships_insert" ON relationships FOR INSERT
  WITH CHECK (profile_id = public.get_executive_id(auth.uid()) OR auth.role() = 'service_role');
CREATE POLICY "relationships_update" ON relationships FOR UPDATE
  USING (profile_id = public.get_executive_id(auth.uid()) OR auth.role() = 'service_role');
CREATE POLICY "relationships_delete" ON relationships FOR DELETE
  USING (profile_id = public.get_executive_id(auth.uid()) OR auth.role() = 'service_role');

-- ccr_evaluations: same fix
DROP POLICY IF EXISTS "ccr_select" ON ccr_evaluations;
DROP POLICY IF EXISTS "ccr_insert" ON ccr_evaluations;

CREATE POLICY "ccr_select" ON ccr_evaluations FOR SELECT
  USING (profile_id = public.get_executive_id(auth.uid()) OR auth.role() = 'service_role');
CREATE POLICY "ccr_insert" ON ccr_evaluations FOR INSERT
  WITH CHECK (profile_id = public.get_executive_id(auth.uid()) OR auth.role() = 'service_role');

-- ============================================================
-- 3. Fix alert_states RLS: get_executive_id() was called with zero args
--    Now works because of the overload created in section 1
--    But let's also add service_role + update/delete policies
-- ============================================================

-- Policy already references get_executive_id() which now resolves correctly via overload.
-- No change needed — the zero-arg overload in section 1 fixes this.

-- ============================================================
-- 4. Enable RLS on initial schema tables that were missing it
-- ============================================================

ALTER TABLE public.workspaces ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.workspace_members ENABLE ROW LEVEL SECURITY;

-- workspaces: members can read their own workspaces, owners can update
CREATE POLICY "workspaces_select_member" ON public.workspaces
  FOR SELECT USING (id = ANY(public.current_workspace_ids()) OR auth.role() = 'service_role');
CREATE POLICY "workspaces_insert_service" ON public.workspaces
  FOR INSERT WITH CHECK (auth.role() = 'service_role');
CREATE POLICY "workspaces_update_owner" ON public.workspaces
  FOR UPDATE USING (
    id IN (SELECT workspace_id FROM public.workspace_members WHERE profile_id = auth.uid() AND role = 'owner')
    OR auth.role() = 'service_role'
  );

-- profiles: users can read profiles in shared workspaces, update own only
CREATE POLICY "profiles_select_shared" ON public.profiles
  FOR SELECT USING (
    id = auth.uid()
    OR id IN (
      SELECT wm2.profile_id FROM public.workspace_members wm1
      JOIN public.workspace_members wm2 ON wm1.workspace_id = wm2.workspace_id
      WHERE wm1.profile_id = auth.uid()
    )
    OR auth.role() = 'service_role'
  );
CREATE POLICY "profiles_update_own" ON public.profiles
  FOR UPDATE USING (id = auth.uid() OR auth.role() = 'service_role');
CREATE POLICY "profiles_insert_service" ON public.profiles
  FOR INSERT WITH CHECK (id = auth.uid() OR auth.role() = 'service_role');

-- workspace_members: can read own workspace memberships, service role manages all
CREATE POLICY "workspace_members_select_own" ON public.workspace_members
  FOR SELECT USING (
    workspace_id = ANY(public.current_workspace_ids())
    OR auth.role() = 'service_role'
  );
CREATE POLICY "workspace_members_insert_service" ON public.workspace_members
  FOR INSERT WITH CHECK (auth.role() = 'service_role');
CREATE POLICY "workspace_members_delete_owner" ON public.workspace_members
  FOR DELETE USING (
    workspace_id IN (SELECT workspace_id FROM public.workspace_members WHERE profile_id = auth.uid() AND role = 'owner')
    OR auth.role() = 'service_role'
  );

-- webhook_events: enable RLS, service role only (pipeline internal table)
DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'webhook_events') THEN
    ALTER TABLE public.webhook_events ENABLE ROW LEVEL SECURITY;
    CREATE POLICY "webhook_events_service_role" ON public.webhook_events
      FOR ALL USING (auth.role() = 'service_role');
  END IF;
END $$;

-- ============================================================
-- 5. Fix behaviour_rules typo in bias detection migration
--    Original migration referenced "behavioral_rules" (American spelling)
--    Actual table is "behaviour_rules" (British spelling)
-- ============================================================

ALTER TABLE public.behaviour_rules
  ADD COLUMN IF NOT EXISTS bias_type text,
  ADD COLUMN IF NOT EXISTS bias_chain_id uuid REFERENCES public.bias_evidence_chains(id);

-- ============================================================
-- 6. Expand pipeline_health_log CHECK constraint
--    5 Edge Functions write values not in the original constraint
-- ============================================================

ALTER TABLE public.pipeline_health_log
  DROP CONSTRAINT IF EXISTS pipeline_health_log_check_type_check;

ALTER TABLE public.pipeline_health_log
  ADD CONSTRAINT pipeline_health_log_check_type_check CHECK (
    check_type IN (
      'tier0_count', 'tier1_gap', 'acb_age', 'backfill_status', 'nightly_pipeline',
      'bias_detection', 'weekly_synthesis', 'batch_polling', 'acb_refresh',
      'weekly_avoidance_synthesis', 'monthly_synthesis', 'morning_briefing',
      'graph_webhook', 'embedding_generation'
    )
  );

-- ============================================================
-- 7. Expand predictions.status CHECK constraint
--    Edge Functions query for 'monitoring' and 'resolved' which aren't allowed
-- ============================================================

ALTER TABLE predictions
  DROP CONSTRAINT IF EXISTS predictions_status_check;

ALTER TABLE predictions
  ADD CONSTRAINT predictions_status_check CHECK (
    status IN ('active', 'confirmed', 'falsified', 'expired', 'monitoring', 'resolved')
  );

-- ============================================================
-- 8. Missing indexes on frequently queried columns
-- ============================================================

-- predictions: queried by (profile_id, status) in nightly-phase2, nightly-consolidation-full
CREATE INDEX IF NOT EXISTS idx_predictions_profile_status
  ON predictions (profile_id, status);

-- burnout_assessments: queried by profile_id in nightly pipeline
CREATE INDEX IF NOT EXISTS idx_burnout_assessments_profile
  ON burnout_assessments (profile_id, assessed_at DESC);

-- avoidance_flags: queried by profile_id
CREATE INDEX IF NOT EXISTS idx_avoidance_flags_profile
  ON avoidance_flags (profile_id, detected_at DESC);

-- decision_tracking: queried by profile_id
CREATE INDEX IF NOT EXISTS idx_decision_tracking_profile
  ON decision_tracking (profile_id, detected_at DESC);

-- tier2_candidates: queried by profile_id
CREATE INDEX IF NOT EXISTS idx_tier2_candidates_profile
  ON tier2_candidates (profile_id, proposed_at DESC);

-- self_improvement_log: queried by (profile_id, log_date)
CREATE INDEX IF NOT EXISTS idx_self_improvement_log_profile_date
  ON self_improvement_log (profile_id, log_date DESC);

-- tier2_behavioural_signatures: queried by (profile_id, status) in multiple nightly functions
CREATE INDEX IF NOT EXISTS idx_tier2_sigs_profile_status
  ON tier2_behavioural_signatures (profile_id, status);

-- relationships: queried by (profile_id, health_trajectory) in morning briefing
CREATE INDEX IF NOT EXISTS idx_relationships_profile_health
  ON relationships (profile_id, health_trajectory);

-- ona_nodes: queried sorted by communication_frequency in morning briefing
CREATE INDEX IF NOT EXISTS idx_ona_nodes_profile_freq
  ON ona_nodes (profile_id, communication_frequency DESC);
