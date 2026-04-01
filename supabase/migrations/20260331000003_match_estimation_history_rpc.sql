-- ============================================================
-- RPC: match_estimation_history
-- Cosine similarity search on estimation_history embeddings.
-- Called by estimate-time Edge Function for tier-1a embedding lookup.
-- Migration: 20260331000003_match_estimation_history_rpc.sql
-- ============================================================

create or replace function public.match_estimation_history(
  query_embedding vector(1536),
  match_workspace_id uuid,
  match_profile_id uuid,
  match_threshold float default 0.7,
  match_count int default 5
)
returns table (
  id uuid,
  actual_minutes integer,
  bucket_type text,
  similarity float
)
language sql stable
security definer
set search_path = ''
as $$
  select
    eh.id,
    eh.actual_minutes,
    eh.bucket_type,
    1 - (eh.embedding <=> query_embedding) as similarity
  from public.estimation_history eh
  where eh.workspace_id = match_workspace_id
    and eh.profile_id = match_profile_id
    and eh.actual_minutes is not null
    and eh.embedding is not null
    and 1 - (eh.embedding <=> query_embedding) > match_threshold
  order by eh.embedding <=> query_embedding
  limit match_count;
$$;
