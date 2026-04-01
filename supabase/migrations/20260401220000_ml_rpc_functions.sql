-- ============================================================
-- ML RPC Function Upgrades
-- Migration: 20260401220000_ml_rpc_functions.sql
--
-- 1. match_estimation_history: add estimate_error to return columns
-- 2. similar_corrections: add similarity threshold + score column
-- ============================================================

-- Drop and recreate match_estimation_history with estimate_error in return
CREATE OR REPLACE FUNCTION public.match_estimation_history(
  query_embedding vector(1536),
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

-- Drop and recreate similar_corrections with threshold + similarity score
CREATE OR REPLACE FUNCTION public.similar_corrections(
    p_workspace_id uuid,
    p_embedding vector(1536),
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

-- Create June partition for behaviour_events (forward planning)
CREATE TABLE IF NOT EXISTS public.behaviour_events_2026_06
  PARTITION OF public.behaviour_events
  FOR VALUES FROM ('2026-06-01') TO ('2026-07-01');
