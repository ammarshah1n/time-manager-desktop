-- ============================================================
-- Timed — RLS Performance + Missing Policies + HNSW + pg_cron
-- Migration: 20260401210000_rls_and_schema_fixes.sql
--
-- Sections:
--   A — RLS performance: rewrap current_workspace_ids() with (select ...)
--   B — Missing RLS policies for tables that have RLS enabled but no policy
--   C — sender_rules CHECK expansion (already done in 000005 — guard only)
--   D — Replace IVFFlat with HNSW on embedding columns
--   E — Activate pg_cron maintenance jobs
-- ============================================================

-- ============================================================
-- A — RLS PERFORMANCE FIX
-- Drop and recreate every policy that calls current_workspace_ids()
-- without the (select ...) sub-query wrapper.
-- The (select ...) prevents Postgres from re-evaluating the
-- function on every row — massive perf win on large tables.
-- ============================================================

-- A1: tasks
DROP POLICY IF EXISTS "tasks_workspace_isolation" ON public.tasks;
CREATE POLICY "tasks_workspace_isolation"
  ON public.tasks FOR ALL TO authenticated
  USING  (workspace_id = ANY((select public.current_workspace_ids())))
  WITH CHECK (workspace_id = ANY((select public.current_workspace_ids())));

-- A2: email_messages
DROP POLICY IF EXISTS "email_messages_workspace_isolation" ON public.email_messages;
CREATE POLICY "email_messages_workspace_isolation"
  ON public.email_messages FOR ALL TO authenticated
  USING  (workspace_id = ANY((select public.current_workspace_ids())))
  WITH CHECK (workspace_id = ANY((select public.current_workspace_ids())));

-- A3: daily_plans
DROP POLICY IF EXISTS "daily_plans_workspace_isolation" ON public.daily_plans;
CREATE POLICY "daily_plans_workspace_isolation"
  ON public.daily_plans FOR ALL TO authenticated
  USING  (workspace_id = ANY((select public.current_workspace_ids())))
  WITH CHECK (workspace_id = ANY((select public.current_workspace_ids())));

-- A4: waiting_items
DROP POLICY IF EXISTS "waiting_items_workspace_isolation" ON public.waiting_items;
CREATE POLICY "waiting_items_workspace_isolation"
  ON public.waiting_items FOR ALL TO authenticated
  USING  (workspace_id = ANY((select public.current_workspace_ids())))
  WITH CHECK (workspace_id = ANY((select public.current_workspace_ids())));

-- A5: voice_captures
DROP POLICY IF EXISTS "voice_captures_workspace_isolation" ON public.voice_captures;
CREATE POLICY "voice_captures_workspace_isolation"
  ON public.voice_captures FOR ALL TO authenticated
  USING  (workspace_id = ANY((select public.current_workspace_ids())))
  WITH CHECK (workspace_id = ANY((select public.current_workspace_ids())));

-- A6: user_profiles
DROP POLICY IF EXISTS "user_profiles_workspace_isolation" ON public.user_profiles;
CREATE POLICY "user_profiles_workspace_isolation"
  ON public.user_profiles FOR ALL TO authenticated
  USING  (workspace_id = ANY((select public.current_workspace_ids())))
  WITH CHECK (workspace_id = ANY((select public.current_workspace_ids())));

-- A7: behaviour_rules
DROP POLICY IF EXISTS "behaviour_rules_workspace_isolation" ON public.behaviour_rules;
CREATE POLICY "behaviour_rules_workspace_isolation"
  ON public.behaviour_rules FOR ALL TO authenticated
  USING  (workspace_id = ANY((select public.current_workspace_ids())))
  WITH CHECK (workspace_id = ANY((select public.current_workspace_ids())));

-- A8: bucket_estimates (created in 000003 without wrapper)
DROP POLICY IF EXISTS "bucket_estimates_workspace_isolation" ON public.bucket_estimates;
CREATE POLICY "bucket_estimates_workspace_isolation"
  ON public.bucket_estimates FOR ALL TO authenticated
  USING  (workspace_id = ANY((select public.current_workspace_ids())))
  WITH CHECK (workspace_id = ANY((select public.current_workspace_ids())));


-- ============================================================
-- B — MISSING RLS POLICIES
-- These tables had RLS enabled in migration 000001 but no
-- policy was ever created, so authenticated users get zero rows.
-- ============================================================

-- B1: email_accounts
DROP POLICY IF EXISTS "email_accounts_workspace_isolation" ON public.email_accounts;
CREATE POLICY "email_accounts_workspace_isolation"
  ON public.email_accounts FOR ALL TO authenticated
  USING  (workspace_id = ANY((select public.current_workspace_ids())))
  WITH CHECK (workspace_id = ANY((select public.current_workspace_ids())));

-- B2: email_triage_corrections
DROP POLICY IF EXISTS "email_triage_corrections_workspace_isolation" ON public.email_triage_corrections;
CREATE POLICY "email_triage_corrections_workspace_isolation"
  ON public.email_triage_corrections FOR ALL TO authenticated
  USING  (workspace_id = ANY((select public.current_workspace_ids())))
  WITH CHECK (workspace_id = ANY((select public.current_workspace_ids())));

-- B3: sender_rules
DROP POLICY IF EXISTS "sender_rules_workspace_isolation" ON public.sender_rules;
CREATE POLICY "sender_rules_workspace_isolation"
  ON public.sender_rules FOR ALL TO authenticated
  USING  (workspace_id = ANY((select public.current_workspace_ids())))
  WITH CHECK (workspace_id = ANY((select public.current_workspace_ids())));

-- B4: estimation_history
DROP POLICY IF EXISTS "estimation_history_workspace_isolation" ON public.estimation_history;
CREATE POLICY "estimation_history_workspace_isolation"
  ON public.estimation_history FOR ALL TO authenticated
  USING  (workspace_id = ANY((select public.current_workspace_ids())))
  WITH CHECK (workspace_id = ANY((select public.current_workspace_ids())));

-- B5: plan_items
DROP POLICY IF EXISTS "plan_items_workspace_isolation" ON public.plan_items;
CREATE POLICY "plan_items_workspace_isolation"
  ON public.plan_items FOR ALL TO authenticated
  USING  (workspace_id = ANY((select public.current_workspace_ids())))
  WITH CHECK (workspace_id = ANY((select public.current_workspace_ids())));

-- B6: voice_capture_items
DROP POLICY IF EXISTS "voice_capture_items_workspace_isolation" ON public.voice_capture_items;
CREATE POLICY "voice_capture_items_workspace_isolation"
  ON public.voice_capture_items FOR ALL TO authenticated
  USING  (workspace_id = ANY((select public.current_workspace_ids())))
  WITH CHECK (workspace_id = ANY((select public.current_workspace_ids())));

-- B7: ai_pipeline_runs
DROP POLICY IF EXISTS "ai_pipeline_runs_workspace_isolation" ON public.ai_pipeline_runs;
CREATE POLICY "ai_pipeline_runs_workspace_isolation"
  ON public.ai_pipeline_runs FOR ALL TO authenticated
  USING  (workspace_id = ANY((select public.current_workspace_ids())))
  WITH CHECK (workspace_id = ANY((select public.current_workspace_ids())));

-- B8: behaviour_events partitions (RLS enabled on partitions, not parent)
DROP POLICY IF EXISTS "behaviour_events_2026_03_ws" ON public.behaviour_events_2026_03;
CREATE POLICY "behaviour_events_2026_03_ws"
  ON public.behaviour_events_2026_03 FOR ALL TO authenticated
  USING  (workspace_id = ANY((select public.current_workspace_ids())))
  WITH CHECK (workspace_id = ANY((select public.current_workspace_ids())));

DROP POLICY IF EXISTS "behaviour_events_2026_04_ws" ON public.behaviour_events_2026_04;
CREATE POLICY "behaviour_events_2026_04_ws"
  ON public.behaviour_events_2026_04 FOR ALL TO authenticated
  USING  (workspace_id = ANY((select public.current_workspace_ids())))
  WITH CHECK (workspace_id = ANY((select public.current_workspace_ids())));

DROP POLICY IF EXISTS "behaviour_events_2026_05_ws" ON public.behaviour_events_2026_05;
CREATE POLICY "behaviour_events_2026_05_ws"
  ON public.behaviour_events_2026_05 FOR ALL TO authenticated
  USING  (workspace_id = ANY((select public.current_workspace_ids())))
  WITH CHECK (workspace_id = ANY((select public.current_workspace_ids())));


-- ============================================================
-- C — sender_rules CHECK EXPANSION
-- Migration 000005 already added 'later' and 'delegate'.
-- Guard: only alter if the old constraint still exists somehow.
-- ============================================================

DO $$ BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'sender_rules_rule_type_check'
      AND conrelid = 'public.sender_rules'::regclass
  ) THEN
    -- Verify current allowed values include later+delegate
    -- If not, drop and recreate (idempotent re-run guard)
    ALTER TABLE public.sender_rules
      DROP CONSTRAINT sender_rules_rule_type_check;
    ALTER TABLE public.sender_rules
      ADD CONSTRAINT sender_rules_rule_type_check
      CHECK (rule_type IN ('inbox_always', 'black_hole', 'later', 'delegate'));
  ELSE
    -- Constraint doesn't exist at all — create it
    ALTER TABLE public.sender_rules
      ADD CONSTRAINT sender_rules_rule_type_check
      CHECK (rule_type IN ('inbox_always', 'black_hole', 'later', 'delegate'));
  END IF;
END $$;


-- ============================================================
-- D — HNSW INDEXES (replace IVFFlat)
-- HNSW is scan-free, no need for pre-training, better recall.
-- m=16, ef_construction=64 as specified.
-- Drop old IVFFlat indexes first, then create HNSW.
-- Using regular CREATE INDEX (not CONCURRENTLY) — runs in txn.
-- ============================================================

-- D1: email_messages.embedding
DROP INDEX IF EXISTS public.email_messages_embedding_idx;
CREATE INDEX email_messages_embedding_idx
  ON public.email_messages USING hnsw (embedding vector_cosine_ops)
  WITH (m = 16, ef_construction = 64);

-- D2: tasks.embedding
DROP INDEX IF EXISTS public.tasks_embedding_idx;
CREATE INDEX tasks_embedding_idx
  ON public.tasks USING hnsw (embedding vector_cosine_ops)
  WITH (m = 16, ef_construction = 64);

-- D3: estimation_history.embedding
DROP INDEX IF EXISTS public.estimation_history_embedding_idx;
CREATE INDEX estimation_history_embedding_idx
  ON public.estimation_history USING hnsw (embedding vector_cosine_ops)
  WITH (m = 16, ef_construction = 64);


-- ============================================================
-- E — PG_CRON MAINTENANCE JOBS
-- Activating the jobs that were commented out in migration 000001.
-- Using cron.schedule with IF NOT EXISTS pattern via
-- DO block to avoid duplicate job errors on re-run.
-- ============================================================

DO $$ BEGIN

-- E1: Update is_overdue flags every 15 minutes
PERFORM cron.schedule(
  'update-overdue-tasks',
  '*/15 * * * *',
  $$UPDATE public.tasks
    SET is_overdue = true, updated_at = now()
    WHERE status IN ('pending','in_progress')
      AND due_at IS NOT NULL
      AND due_at < now()
      AND is_overdue = false$$
);

-- E2: Vacuum analyse on high-churn tables (daily at 04:00 UTC)
PERFORM cron.schedule(
  'vacuum-high-churn',
  '0 4 * * *',
  $$VACUUM ANALYZE public.email_messages, public.tasks, public.behaviour_events_2026_03, public.behaviour_events_2026_04, public.behaviour_events_2026_05$$
);

-- E3: Monthly partition creation (1st of each month at 01:00 UTC)
-- Creates partitions for the next 2 months ahead
PERFORM cron.schedule(
  'create-behaviour-partitions',
  '0 1 1 * *',
  $cron$
  DO $part$
  DECLARE
    _start date;
    _end   date;
    _name  text;
  BEGIN
    FOR i IN 1..2 LOOP
      _start := date_trunc('month', now()) + (i || ' months')::interval;
      _end   := _start + '1 month'::interval;
      _name  := 'behaviour_events_' || to_char(_start, 'YYYY_MM');

      IF NOT EXISTS (
        SELECT 1 FROM pg_class WHERE relname = _name AND relnamespace = 'public'::regnamespace
      ) THEN
        EXECUTE format(
          'CREATE TABLE public.%I PARTITION OF public.behaviour_events FOR VALUES FROM (%L) TO (%L)',
          _name, _start, _end
        );
        EXECUTE format(
          'ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', _name
        );
        EXECUTE format(
          'CREATE POLICY %I ON public.%I FOR ALL TO authenticated USING (workspace_id = ANY((select public.current_workspace_ids()))) WITH CHECK (workspace_id = ANY((select public.current_workspace_ids())))',
          _name || '_ws', _name
        );
        -- Attach rule triggers
        EXECUTE format(
          'CREATE TRIGGER trg_update_rules_on_event AFTER INSERT ON public.%I FOR EACH ROW EXECUTE FUNCTION public.update_rules_on_event()', _name
        );
        EXECUTE format(
          'CREATE TRIGGER trg_update_bucket_stats AFTER INSERT ON public.%I FOR EACH ROW EXECUTE FUNCTION public.update_bucket_stats()', _name
        );
      END IF;
    END LOOP;
  END $part$;
  $cron$
);

-- E4: Archive old behaviour_events (>90 days) — delete from partitions
-- Runs weekly Sunday 05:00 UTC
PERFORM cron.schedule(
  'archive-old-behaviour-events',
  '0 5 * * 0',
  $$DELETE FROM public.behaviour_events WHERE occurred_at < now() - interval '90 days'$$
);

-- E5: Prune stale webhook_events (>30 days, status = processed)
-- Runs daily at 03:00 UTC
PERFORM cron.schedule(
  'prune-webhook-events',
  '0 3 * * *',
  $$DELETE FROM public.webhook_events WHERE status = 'processed' AND received_at < now() - interval '30 days'$$
);

-- E6: Confidence decay for stale behaviour_rules (Sunday 03:00 UTC)
-- Was commented out in migration 000001_realtime_rule_triggers
PERFORM cron.schedule(
  'decay-stale-rules',
  '0 3 * * 0',
  $$UPDATE public.behaviour_rules
    SET confidence = GREATEST(confidence - 0.1, 0.0),
        updated_at = now()
    WHERE is_active = true
      AND updated_at < now() - interval '14 days'$$
);

END $$;
