-- =============================================================
-- C4: sender_social_graph RLS missing WITH CHECK
-- =============================================================
DROP POLICY IF EXISTS "sender_graph_ws" ON public.sender_social_graph;
CREATE POLICY "sender_graph_ws" ON public.sender_social_graph FOR ALL TO authenticated
  USING (workspace_id = ANY((select public.current_workspace_ids())))
  WITH CHECK (workspace_id = ANY((select public.current_workspace_ids())));

-- =============================================================
-- Performance: wrap bucket_completion_stats RLS with (select …)
-- (bucket_estimates already uses correct pattern — left as-is)
-- =============================================================
DROP POLICY IF EXISTS "bucket_stats_workspace_isolation" ON public.bucket_completion_stats;
CREATE POLICY "bucket_stats_workspace_isolation" ON public.bucket_completion_stats FOR ALL TO authenticated
  USING (workspace_id = ANY((select public.current_workspace_ids())))
  WITH CHECK (workspace_id = ANY((select public.current_workspace_ids())));

-- =============================================================
-- H8: Missing indexes on FK lookups in newer tables
-- =============================================================
CREATE INDEX IF NOT EXISTS bucket_completion_stats_profile_idx
  ON public.bucket_completion_stats(workspace_id, profile_id);
CREATE INDEX IF NOT EXISTS bucket_estimates_profile_idx
  ON public.bucket_estimates(workspace_id, profile_id);
CREATE INDEX IF NOT EXISTS sender_social_graph_profile_idx
  ON public.sender_social_graph(workspace_id, profile_id);
CREATE INDEX IF NOT EXISTS sender_social_graph_address_idx
  ON public.sender_social_graph(workspace_id, from_address);
