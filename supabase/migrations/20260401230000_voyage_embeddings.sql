-- ============================================================
-- Switch embeddings to 1024-dim (Jina AI jina-embeddings-v3)
-- Fully guarded — only acts on tables/columns that exist.
-- ============================================================

-- 1. Nullify + resize embedding columns (only if they exist)
DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='email_messages' AND column_name='embedding') THEN
    UPDATE public.email_messages SET embedding = NULL WHERE embedding IS NOT NULL;
    ALTER TABLE public.email_messages ALTER COLUMN embedding TYPE vector(1024);
    DROP INDEX IF EXISTS public.email_messages_embedding_idx;
    DROP INDEX IF EXISTS public.email_messages_embedding_hnsw_idx;
    CREATE INDEX email_messages_embedding_hnsw_idx ON public.email_messages USING hnsw (embedding vector_cosine_ops) WITH (m=16, ef_construction=64);
  END IF;

  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='tasks' AND column_name='embedding') THEN
    UPDATE public.tasks SET embedding = NULL WHERE embedding IS NOT NULL;
    ALTER TABLE public.tasks ALTER COLUMN embedding TYPE vector(1024);
    DROP INDEX IF EXISTS public.tasks_embedding_idx;
    DROP INDEX IF EXISTS public.tasks_embedding_hnsw_idx;
    CREATE INDEX tasks_embedding_hnsw_idx ON public.tasks USING hnsw (embedding vector_cosine_ops) WITH (m=16, ef_construction=64);
  END IF;

  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='estimation_history' AND column_name='embedding') THEN
    UPDATE public.estimation_history SET embedding = NULL WHERE embedding IS NOT NULL;
    ALTER TABLE public.estimation_history ALTER COLUMN embedding TYPE vector(1024);
    DROP INDEX IF EXISTS public.estimation_history_embedding_idx;
    DROP INDEX IF EXISTS public.estimation_history_embedding_hnsw_idx;
    CREATE INDEX estimation_history_embedding_hnsw_idx ON public.estimation_history USING hnsw (embedding vector_cosine_ops) WITH (m=16, ef_construction=64);
  END IF;
END $$;

-- 2. Recreate RPC functions with vector(1024) (guarded)
DO $outer$ BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='estimation_history' AND column_name='embedding') THEN
    EXECUTE $fn$
      CREATE OR REPLACE FUNCTION public.match_estimation_history(
        query_embedding vector(1024), match_workspace_id uuid, match_profile_id uuid,
        match_threshold float DEFAULT 0.7, match_count int DEFAULT 5
      )
      RETURNS TABLE (id uuid, actual_minutes integer, bucket_type text, estimate_error real, similarity float)
      LANGUAGE sql STABLE SECURITY DEFINER SET search_path = ''
      AS $body$
        SELECT eh.id, eh.actual_minutes, eh.bucket_type, eh.estimate_error,
               1 - (eh.embedding <=> query_embedding) AS similarity
        FROM public.estimation_history eh
        WHERE eh.workspace_id = match_workspace_id AND eh.profile_id = match_profile_id
          AND eh.actual_minutes IS NOT NULL AND eh.embedding IS NOT NULL
          AND 1 - (eh.embedding <=> query_embedding) > match_threshold
        ORDER BY eh.embedding <=> query_embedding LIMIT match_count;
      $body$;
    $fn$;
  END IF;
END $outer$;

DO $outer$ BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='email_messages' AND column_name='embedding') THEN
    EXECUTE $fn$
      CREATE OR REPLACE FUNCTION public.similar_corrections(
        p_workspace_id uuid, p_embedding vector(1024),
        p_threshold float DEFAULT 0.5, p_limit int DEFAULT 10
      )
      RETURNS TABLE(from_address text, old_bucket text, new_bucket text, subject_snippet text, similarity float)
      LANGUAGE sql STABLE AS $body$
        SELECT etc.from_address, etc.old_bucket, etc.new_bucket, etc.subject_snippet,
               1 - (em.embedding <=> p_embedding) AS similarity
        FROM public.email_triage_corrections etc
        JOIN public.email_messages em ON em.id = etc.email_message_id
        WHERE etc.workspace_id = p_workspace_id AND em.embedding IS NOT NULL
          AND 1 - (em.embedding <=> p_embedding) > p_threshold
        ORDER BY em.embedding <=> p_embedding LIMIT p_limit;
      $body$;
    $fn$;
  END IF;
END $outer$;
