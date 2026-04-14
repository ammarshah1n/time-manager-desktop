-- Service-role RLS bypass for pipeline-written tables + match_tier0_observations RPC + pg_cron schedules
-- The nightly pipeline Edge Functions use SUPABASE_SERVICE_ROLE_KEY but RLS UPDATE/INSERT policies
-- are scoped to auth.uid() only. This adds FOR ALL bypass for the service role on all pipeline tables.
-- Tables already covered (baselines, briefings) are skipped.

DO $$ BEGIN

  -- tier0_observations: nightly pipeline UPDATEs importance_score, is_processed
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'tier0_observations') THEN
    CREATE POLICY "service_role_tier0_observations" ON public.tier0_observations
    FOR ALL USING (auth.role() = 'service_role');
  END IF;

  -- tier1_daily_summaries: nightly pipeline INSERTs daily summary
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'tier1_daily_summaries') THEN
    CREATE POLICY "service_role_tier1_daily_summaries" ON public.tier1_daily_summaries
    FOR ALL USING (auth.role() = 'service_role');
  END IF;

  -- tier2_behavioural_signatures: self-improvement loop INSERTs signatures
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'tier2_behavioural_signatures') THEN
    CREATE POLICY "service_role_tier2_behavioural_signatures" ON public.tier2_behavioural_signatures
    FOR ALL USING (auth.role() = 'service_role');
  END IF;

  -- tier3_personality_traits: monthly trait synthesis INSERTs
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'tier3_personality_traits') THEN
    CREATE POLICY "service_role_tier3_personality_traits" ON public.tier3_personality_traits
    FOR ALL USING (auth.role() = 'service_role');
  END IF;

  -- active_context_buffer: ACB generation UPSERTs
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'active_context_buffer') THEN
    CREATE POLICY "service_role_active_context_buffer" ON public.active_context_buffer
    FOR ALL USING (auth.role() = 'service_role');
  END IF;

  -- predictions: prediction tracking INSERTs
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'predictions') THEN
    CREATE POLICY "service_role_predictions" ON public.predictions
    FOR ALL USING (auth.role() = 'service_role');
  END IF;

  -- self_improvement_log: batch submission INSERTs + status UPDATEs
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'self_improvement_log') THEN
    CREATE POLICY "service_role_self_improvement_log" ON public.self_improvement_log
    FOR ALL USING (auth.role() = 'service_role');
  END IF;

  -- pipeline_health_log: all pipeline steps INSERT health records
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'pipeline_health_log') THEN
    CREATE POLICY "service_role_pipeline_health_log" ON public.pipeline_health_log
    FOR ALL USING (auth.role() = 'service_role');
  END IF;

END $$;

-- match_tier0_observations: pgvector cosine similarity search for memory retrieval
-- Follows the pattern from 20260331000003_match_estimation_history_rpc.sql
DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'tier0_observations') THEN
    CREATE OR REPLACE FUNCTION public.match_tier0_observations(
      query_embedding vector(1024),
      match_profile_id uuid,
      match_threshold float DEFAULT 0.5,
      match_count int DEFAULT 30
    ) RETURNS TABLE (
      id uuid,
      summary text,
      source text,
      event_type text,
      occurred_at timestamptz,
      importance_score float,
      similarity float
    ) LANGUAGE plpgsql SECURITY DEFINER AS $fn$
    BEGIN
      RETURN QUERY
      SELECT t.id, t.summary, t.source, t.event_type,
             t.occurred_at, t.importance_score::float,
             (1 - (t.embedding <=> query_embedding))::float AS similarity
      FROM public.tier0_observations t
      WHERE t.profile_id = match_profile_id
        AND t.embedding IS NOT NULL
        AND 1 - (t.embedding <=> query_embedding) > match_threshold
      ORDER BY t.embedding <=> query_embedding
      LIMIT match_count;
    END;
    $fn$;
  END IF;
END $$;

-- pg_cron schedules for split nightly pipeline + batch polling
DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    -- Phase 1: importance scoring + conflict detection at 2:00 AM
    PERFORM cron.schedule('nightly-phase1', '0 2 * * *',
      $$SELECT net.http_post(
        url := current_setting('app.supabase_url') || '/functions/v1/nightly-phase1',
        headers := jsonb_build_object(
          'Authorization', 'Bearer ' || current_setting('app.service_role_key'),
          'Content-Type', 'application/json'
        ),
        body := '{}'::jsonb
      )$$);

    -- Phase 2: daily summary + ACB + self-improvement at 2:05 AM
    PERFORM cron.schedule('nightly-phase2', '5 2 * * *',
      $$SELECT net.http_post(
        url := current_setting('app.supabase_url') || '/functions/v1/nightly-phase2',
        headers := jsonb_build_object(
          'Authorization', 'Bearer ' || current_setting('app.service_role_key'),
          'Content-Type', 'application/json'
        ),
        body := '{}'::jsonb
      )$$);

    -- Batch result polling every 30 minutes
    PERFORM cron.schedule('poll-batch-results', '*/30 * * * *',
      $$SELECT net.http_post(
        url := current_setting('app.supabase_url') || '/functions/v1/poll-batch-results',
        headers := jsonb_build_object(
          'Authorization', 'Bearer ' || current_setting('app.service_role_key'),
          'Content-Type', 'application/json'
        ),
        body := '{}'::jsonb
      )$$);
  END IF;
END $$;
