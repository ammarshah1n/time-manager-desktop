-- ============================================================
-- ML RPC Functions (guarded — skip if required columns missing)
-- ============================================================

-- match_estimation_history: only create if estimation_history has embedding column
DO $outer$ BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='estimation_history' AND column_name='embedding'
  ) THEN
    EXECUTE $fn$
      CREATE OR REPLACE FUNCTION public.match_estimation_history(
        query_embedding vector,
        match_workspace_id uuid,
        match_profile_id uuid,
        match_threshold float DEFAULT 0.7,
        match_count int DEFAULT 5
      )
      RETURNS TABLE (id uuid, actual_minutes integer, bucket_type text, estimate_error real, similarity float)
      LANGUAGE sql STABLE SECURITY DEFINER SET search_path = ''
      AS $body$
        SELECT eh.id, eh.actual_minutes, eh.bucket_type, eh.estimate_error,
               1 - (eh.embedding <=> query_embedding) AS similarity
        FROM public.estimation_history eh
        WHERE eh.workspace_id = match_workspace_id
          AND eh.profile_id = match_profile_id
          AND eh.actual_minutes IS NOT NULL
          AND eh.embedding IS NOT NULL
          AND 1 - (eh.embedding <=> query_embedding) > match_threshold
        ORDER BY eh.embedding <=> query_embedding
        LIMIT match_count;
      $body$;
    $fn$;
  END IF;
END $outer$;

-- similar_corrections: only create if email_messages has embedding column
DO $outer$ BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='email_messages' AND column_name='embedding'
  ) THEN
    EXECUTE $fn$
      CREATE OR REPLACE FUNCTION public.similar_corrections(
        p_workspace_id uuid,
        p_embedding vector,
        p_threshold float DEFAULT 0.5,
        p_limit int DEFAULT 10
      )
      RETURNS TABLE(from_address text, old_bucket text, new_bucket text, subject_snippet text, similarity float)
      LANGUAGE sql STABLE AS $body$
        SELECT etc.from_address, etc.old_bucket, etc.new_bucket, etc.subject_snippet,
               1 - (em.embedding <=> p_embedding) AS similarity
        FROM public.email_triage_corrections etc
        JOIN public.email_messages em ON em.id = etc.email_message_id
        WHERE etc.workspace_id = p_workspace_id
          AND em.embedding IS NOT NULL
          AND 1 - (em.embedding <=> p_embedding) > p_threshold
        ORDER BY em.embedding <=> p_embedding
        LIMIT p_limit;
      $body$;
    $fn$;
  END IF;
END $outer$;

-- June partition (only if parent exists)
DO $outer$ BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='behaviour_events') THEN
    IF NOT EXISTS (SELECT 1 FROM pg_class WHERE relname='behaviour_events_2026_06' AND relnamespace='public'::regnamespace) THEN
      CREATE TABLE public.behaviour_events_2026_06 PARTITION OF public.behaviour_events
        FOR VALUES FROM ('2026-06-01') TO ('2026-07-01');
    END IF;
  END IF;
END $outer$;
