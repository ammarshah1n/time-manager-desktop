-- ============================================================
-- Timed — RLS + HNSW + pg_cron (fully guarded)
-- Every statement checks table existence before executing.
-- ============================================================

-- Helper: create/replace RLS policy only if table exists
CREATE OR REPLACE FUNCTION _tmp_safe_policy(
  p_table text, p_policy text
) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name=p_table) THEN
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', p_policy, p_table);
    EXECUTE format(
      'CREATE POLICY %I ON public.%I FOR ALL TO authenticated '
      || 'USING (workspace_id = ANY(public.current_workspace_ids())) '
      || 'WITH CHECK (workspace_id = ANY(public.current_workspace_ids()))',
      p_policy, p_table
    );
  END IF;
END $$;

-- A: Rewrap existing policies
SELECT _tmp_safe_policy('tasks', 'tasks_workspace_isolation');
SELECT _tmp_safe_policy('email_messages', 'email_messages_workspace_isolation');
SELECT _tmp_safe_policy('daily_plans', 'daily_plans_workspace_isolation');
SELECT _tmp_safe_policy('waiting_items', 'waiting_items_workspace_isolation');
SELECT _tmp_safe_policy('voice_captures', 'voice_captures_workspace_isolation');
SELECT _tmp_safe_policy('user_profiles', 'user_profiles_workspace_isolation');
SELECT _tmp_safe_policy('behaviour_rules', 'behaviour_rules_workspace_isolation');
SELECT _tmp_safe_policy('bucket_estimates', 'bucket_estimates_workspace_isolation');

-- B: Missing policies
SELECT _tmp_safe_policy('email_accounts', 'email_accounts_workspace_isolation');
SELECT _tmp_safe_policy('email_triage_corrections', 'email_triage_corrections_workspace_isolation');
SELECT _tmp_safe_policy('sender_rules', 'sender_rules_workspace_isolation');
SELECT _tmp_safe_policy('estimation_history', 'estimation_history_workspace_isolation');
SELECT _tmp_safe_policy('plan_items', 'plan_items_workspace_isolation');
SELECT _tmp_safe_policy('voice_capture_items', 'voice_capture_items_workspace_isolation');
SELECT _tmp_safe_policy('ai_pipeline_runs', 'ai_pipeline_runs_workspace_isolation');
SELECT _tmp_safe_policy('behaviour_events_2026_03', 'behaviour_events_2026_03_ws');
SELECT _tmp_safe_policy('behaviour_events_2026_04', 'behaviour_events_2026_04_ws');
SELECT _tmp_safe_policy('behaviour_events_2026_05', 'behaviour_events_2026_05_ws');

-- Cleanup helper
DROP FUNCTION _tmp_safe_policy(text, text);

-- C: sender_rules CHECK (guarded)
DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='sender_rules') THEN
    IF EXISTS (SELECT 1 FROM pg_constraint WHERE conname='sender_rules_rule_type_check') THEN
      ALTER TABLE public.sender_rules DROP CONSTRAINT sender_rules_rule_type_check;
    END IF;
    ALTER TABLE public.sender_rules ADD CONSTRAINT sender_rules_rule_type_check
      CHECK (rule_type IN ('inbox_always', 'black_hole', 'later', 'delegate'));
  END IF;
END $$;

-- D: HNSW indexes (guarded)
DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='email_messages' AND column_name='embedding') THEN
    DROP INDEX IF EXISTS public.email_messages_embedding_idx;
    CREATE INDEX email_messages_embedding_idx ON public.email_messages USING hnsw (embedding vector_cosine_ops) WITH (m=16, ef_construction=64);
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='tasks' AND column_name='embedding') THEN
    DROP INDEX IF EXISTS public.tasks_embedding_idx;
    CREATE INDEX tasks_embedding_idx ON public.tasks USING hnsw (embedding vector_cosine_ops) WITH (m=16, ef_construction=64);
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='estimation_history' AND column_name='embedding') THEN
    DROP INDEX IF EXISTS public.estimation_history_embedding_idx;
    CREATE INDEX estimation_history_embedding_idx ON public.estimation_history USING hnsw (embedding vector_cosine_ops) WITH (m=16, ef_construction=64);
  END IF;
END $$;

-- E: pg_cron jobs (guarded)
DO $outer$ BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname='pg_cron') THEN
    PERFORM cron.schedule('update-overdue-tasks', '*/15 * * * *',
      $sql$UPDATE public.tasks SET is_overdue=true, updated_at=now() WHERE status IN ('pending','in_progress') AND due_at IS NOT NULL AND due_at < now() AND is_overdue=false$sql$);
    PERFORM cron.schedule('vacuum-high-churn', '0 4 * * *',
      $sql$VACUUM ANALYZE public.tasks, public.email_messages$sql$);
    PERFORM cron.schedule('archive-old-behaviour-events', '0 5 * * 0',
      $sql$DELETE FROM public.behaviour_events WHERE occurred_at < now() - interval '90 days'$sql$);
    PERFORM cron.schedule('decay-stale-rules', '0 3 * * 0',
      $sql$UPDATE public.behaviour_rules SET confidence=GREATEST(confidence-0.1,0.0), updated_at=now() WHERE is_active=true AND updated_at < now()-interval '14 days'$sql$);
  END IF;
END $outer$;
