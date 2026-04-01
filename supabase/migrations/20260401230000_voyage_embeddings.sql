-- ============================================================
-- Migration: 20260401230000_voyage_embeddings.sql
-- Switch embedding columns from 1536 (OpenAI text-embedding-3-small)
-- to 1024 (Jina AI jina-embeddings-v3).
--
-- NOTE: This truncates existing embeddings. All emails/tasks must be
-- re-embedded after deploy. Run a backfill job or let natural traffic
-- regenerate them.
-- ============================================================

-- 1. Nullify existing embeddings (1536-dim vectors can't fit in 1024-dim columns)
UPDATE public.email_messages SET embedding = NULL WHERE embedding IS NOT NULL;
UPDATE public.tasks SET embedding = NULL WHERE embedding IS NOT NULL;
UPDATE public.estimation_history SET embedding = NULL WHERE embedding IS NOT NULL;

-- 2. Change embedding columns from vector(1536) to vector(1024)
ALTER TABLE public.email_messages ALTER COLUMN embedding TYPE vector(1024);
ALTER TABLE public.tasks ALTER COLUMN embedding TYPE vector(1024);
ALTER TABLE public.estimation_history ALTER COLUMN embedding TYPE vector(1024);

-- 3. Recreate HNSW indexes for new dimensions
DROP INDEX IF EXISTS public.email_messages_embedding_idx;
CREATE INDEX email_messages_embedding_idx
  ON public.email_messages USING hnsw (embedding vector_cosine_ops)
  WITH (m = 16, ef_construction = 64);

DROP INDEX IF EXISTS public.tasks_embedding_idx;
CREATE INDEX tasks_embedding_idx
  ON public.tasks USING hnsw (embedding vector_cosine_ops)
  WITH (m = 16, ef_construction = 64);

DROP INDEX IF EXISTS public.estimation_history_embedding_idx;
CREATE INDEX estimation_history_embedding_idx
  ON public.estimation_history USING hnsw (embedding vector_cosine_ops)
  WITH (m = 16, ef_construction = 64);

-- 4. Recreate RPC functions with vector(1024) parameter type

CREATE OR REPLACE FUNCTION public.match_estimation_history(
  query_embedding vector(1024),
  match_workspace_id uuid,
  match_profile_id uuid,
  match_threshold float DEFAULT 0.7,
  match_count int DEFAULT 5
)
RETURNS TABLE (
  id uuid,
  actual_minutes integer,
  bucket_type text,
  estimate_error real,
  similarity float
)
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT
    eh.id,
    eh.actual_minutes,
    eh.bucket_type,
    eh.estimate_error,
    1 - (eh.embedding <=> query_embedding) AS similarity
  FROM public.estimation_history eh
  WHERE eh.workspace_id = match_workspace_id
    AND eh.profile_id = match_profile_id
    AND eh.actual_minutes IS NOT NULL
    AND eh.embedding IS NOT NULL
    AND 1 - (eh.embedding <=> query_embedding) > match_threshold
  ORDER BY eh.embedding <=> query_embedding
  LIMIT match_count;
$$;

CREATE OR REPLACE FUNCTION public.similar_corrections(
    p_workspace_id uuid,
    p_embedding vector(1024),
    p_threshold float DEFAULT 0.5,
    p_limit int DEFAULT 10
)
RETURNS TABLE(from_address text, old_bucket text, new_bucket text, subject_snippet text, similarity float)
LANGUAGE sql STABLE AS $$
    SELECT
        etc.from_address,
        etc.old_bucket,
        etc.new_bucket,
        etc.subject_snippet,
        1 - (em.embedding <=> p_embedding) AS similarity
    FROM public.email_triage_corrections etc
    JOIN public.email_messages em ON em.id = etc.email_message_id
    WHERE etc.workspace_id = p_workspace_id
      AND em.embedding IS NOT NULL
      AND 1 - (em.embedding <=> p_embedding) > p_threshold
    ORDER BY em.embedding <=> p_embedding
    LIMIT p_limit;
$$;
