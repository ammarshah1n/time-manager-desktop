-- ============================================================
-- Add embedding column to estimation_history for semantic similarity search
-- Migration: 20260331000002_estimation_history_embedding.sql
-- ============================================================

-- Add embedding column (text-embedding-3-small = 1536 dimensions)
alter table public.estimation_history
  add column embedding vector(1536);

-- IVFFlat cosine index for fast similarity queries
-- lists=100 matches tasks.embedding_idx config (suitable for <1M rows)
create index estimation_history_embedding_idx
  on public.estimation_history using ivfflat (embedding vector_cosine_ops)
  with (lists = 100);
