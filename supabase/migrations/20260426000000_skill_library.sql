-- Skill library (Voyager-style) — persistent procedural memory for the
-- reflection pipeline. Every time the REM-synthesis agent identifies a novel
-- analytical procedure it calls `skill-library-mcp.write_skill(...)`, and at
-- retrieval time `retrieve_skills(context_text, top_k)` does k-NN against
-- `skills.embedding` (Voyage voyage-3, 1024-dim).
--
-- Ordering: this migration must run AFTER A1's `agent_traces` migration (which
-- creates `agent_sessions`) so the FK on `creation_session_id` resolves. In
-- this repo's convention both migrations have timestamps in Apr 2026; A1 will
-- ship with a Apr 25 prefix, this uses Apr 26. Migrations run lexically, so
-- dependency order is satisfied by filename.
--
-- Defensive note: the FK is declared via ALTER TABLE after CREATE so the
-- migration does not hard-fail in a scratch DB that has not yet run A1's
-- migration — it will succeed with the FK omitted, and A1's migration is a
-- strict Wave-1 sibling, so production always has both before any task runs.

BEGIN;

-- pgvector is already enabled in this project (see voyage_embeddings
-- migration 20260401230000). We assert it here defensively; CREATE EXTENSION
-- IF NOT EXISTS is idempotent.
CREATE EXTENSION IF NOT EXISTS vector;

CREATE TABLE IF NOT EXISTS public.skills (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name                  TEXT NOT NULL,
  procedure_text        TEXT NOT NULL,
  creation_context      JSONB NOT NULL DEFAULT '{}'::jsonb,
  -- FK is applied below, conditional on agent_sessions existing.
  creation_session_id   UUID,
  embedding             VECTOR(1024),
  usage_count           INT NOT NULL DEFAULT 0,
  success_count         INT NOT NULL DEFAULT 0,
  failure_count         INT NOT NULL DEFAULT 0,
  last_used_at          TIMESTAMPTZ,
  retired_at            TIMESTAMPTZ,
  retire_reason         TEXT,
  created_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at            TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Unique skill name per active skill (retired ones don't block new ones with
-- the same name — they shouldn't exist but if the retire_reason was a name
-- collision you want to be able to re-register under the same name).
CREATE UNIQUE INDEX IF NOT EXISTS skills_name_active_uniq
  ON public.skills (name)
  WHERE retired_at IS NULL;

-- Retirement-filter index (used by retrieve_skills + weekly pruning task).
CREATE INDEX IF NOT EXISTS skills_retired_at_idx
  ON public.skills (retired_at);

-- HNSW index for k-NN retrieval. Cosine distance matches how voyage-3
-- embeddings are scored (unit-normalised). m=16, ef_construction=64 are
-- Supabase/pgvector defaults known to be robust for <1M rows.
CREATE INDEX IF NOT EXISTS skills_embedding_hnsw_idx
  ON public.skills
  USING hnsw (embedding vector_cosine_ops)
  WITH (m = 16, ef_construction = 64);

-- Keep updated_at honest.
CREATE OR REPLACE FUNCTION public.skills_set_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS skills_updated_at_trg ON public.skills;
CREATE TRIGGER skills_updated_at_trg
  BEFORE UPDATE ON public.skills
  FOR EACH ROW
  EXECUTE FUNCTION public.skills_set_updated_at();

-- Attach FK to agent_sessions if and only if the table already exists. This
-- keeps the migration runnable in worktrees that have not yet pulled A1's
-- migration.
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'agent_sessions'
  ) THEN
    -- Drop any existing FK so re-running the migration is idempotent.
    BEGIN
      ALTER TABLE public.skills
        DROP CONSTRAINT IF EXISTS skills_creation_session_id_fkey;
    EXCEPTION WHEN others THEN
      NULL;
    END;
    ALTER TABLE public.skills
      ADD CONSTRAINT skills_creation_session_id_fkey
        FOREIGN KEY (creation_session_id)
        REFERENCES public.agent_sessions (id)
        ON DELETE SET NULL;
  END IF;
END
$$;

-- k-NN retrieval RPC — used by skill-library-mcp's retrieve_skills tool.
-- Cosine distance matches the HNSW index's ops class above.
CREATE OR REPLACE FUNCTION public.retrieve_skills(
  query_embedding VECTOR(1024),
  top_k           INT DEFAULT 5
)
RETURNS TABLE (
  id                  UUID,
  name                TEXT,
  procedure_text      TEXT,
  creation_context    JSONB,
  usage_count         INT,
  success_count       INT,
  failure_count       INT,
  last_used_at        TIMESTAMPTZ,
  similarity          NUMERIC
)
LANGUAGE sql
STABLE
AS $$
  SELECT
    s.id,
    s.name,
    s.procedure_text,
    s.creation_context,
    s.usage_count,
    s.success_count,
    s.failure_count,
    s.last_used_at,
    (1 - (s.embedding <=> query_embedding))::NUMERIC AS similarity
  FROM public.skills s
  WHERE s.retired_at IS NULL
    AND s.embedding IS NOT NULL
  ORDER BY s.embedding <=> query_embedding
  LIMIT GREATEST(1, LEAST(top_k, 50));
$$;

-- Usage bookkeeping RPC — atomic increment + stamp last_used_at.
CREATE OR REPLACE FUNCTION public.record_skill_usage(
  p_skill_id   UUID,
  p_outcome    TEXT,
  p_session_id UUID,
  p_notes      TEXT
)
RETURNS VOID
LANGUAGE plpgsql
AS $$
BEGIN
  IF p_outcome NOT IN ('success', 'failure') THEN
    RAISE EXCEPTION 'outcome must be success or failure, got %', p_outcome;
  END IF;

  UPDATE public.skills
  SET usage_count   = usage_count + 1,
      success_count = success_count + CASE WHEN p_outcome = 'success' THEN 1 ELSE 0 END,
      failure_count = failure_count + CASE WHEN p_outcome = 'failure' THEN 1 ELSE 0 END,
      last_used_at  = now(),
      creation_context = creation_context || jsonb_build_object(
        'last_usage', jsonb_build_object(
          'session_id', p_session_id,
          'outcome',    p_outcome,
          'notes',      p_notes,
          'at',         now()
        )
      )
  WHERE id = p_skill_id;
END;
$$;

-- Row Level Security — service role bypasses RLS (see
-- 20260413000000_service_role_rls_bypass.sql); block anon/authenticated.
ALTER TABLE public.skills ENABLE ROW LEVEL SECURITY;

-- No policies = default-deny. Service role still reads/writes via the
-- existing bypass. That is the only caller we expect for this table.

COMMIT;
