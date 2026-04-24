-- 20260425000000_agent_traces.sql
--
-- Timed overnight cognitive OS -- trace ledger.
--
-- Every Anthropic inference call made from the Trigger.dev pipeline writes
-- one `agent_sessions` row (outer envelope: model routing, token totals,
-- prompt / context hashes for replay) and one `agent_traces` row per
-- returned content block (text / thinking / tool_use / tool_result).
--
-- This ledger is:
--   a) the only mechanism that makes nightly runs deterministically replayable,
--   b) the input to `trigger/scripts/export-training-data.ts` for building the
--      supervised fine-tuning corpus,
--   c) the diagnostic surface for any failed / skipped nightly reflection run.
--
-- Append-only during normal operation. Retention policy is handled separately
-- (not in this migration) so an early production run cannot silently prune
-- its own trace history.

BEGIN;

-- ---------------------------------------------------------------------------
-- Enums
-- ---------------------------------------------------------------------------

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'agent_session_status') THEN
    CREATE TYPE public.agent_session_status AS ENUM (
      'running',
      'completed',
      'failed',
      'cancelled'
    );
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'agent_trace_block_type') THEN
    CREATE TYPE public.agent_trace_block_type AS ENUM (
      'text',
      'thinking',
      'tool_use',
      'tool_result'
    );
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'agent_trace_role') THEN
    CREATE TYPE public.agent_trace_role AS ENUM (
      'user',
      'assistant',
      'tool'
    );
  END IF;
END
$$;

-- ---------------------------------------------------------------------------
-- agent_sessions
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.agent_sessions (
  id                       uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  task_name                text NOT NULL,
  trigger_run_id           text,
  exec_id                  uuid,
  started_at               timestamptz NOT NULL DEFAULT now(),
  completed_at             timestamptz,
  status                   public.agent_session_status NOT NULL DEFAULT 'running',
  prompt_hash              text NOT NULL,
  context_hash             text NOT NULL,
  total_input_tokens       integer,
  total_output_tokens      integer,
  total_cache_read_tokens  integer
);

COMMENT ON TABLE  public.agent_sessions IS
  'Outer envelope for every Anthropic inference call made by the Trigger.dev pipeline.';
COMMENT ON COLUMN public.agent_sessions.task_name IS
  'Logical task (e.g. "nrem-entity-extraction", "hello-claude") -- free text, not FK.';
COMMENT ON COLUMN public.agent_sessions.prompt_hash IS
  'SHA-256 of {model, system, messages, tools, thinking} -- prompt-level replay key.';
COMMENT ON COLUMN public.agent_sessions.context_hash IS
  'SHA-256 of {mcp_servers, external context handles} -- captures non-prompt inputs.';

CREATE INDEX IF NOT EXISTS agent_sessions_task_started_idx
  ON public.agent_sessions (task_name, started_at DESC);

CREATE INDEX IF NOT EXISTS agent_sessions_exec_started_idx
  ON public.agent_sessions (exec_id, started_at DESC)
  WHERE exec_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS agent_sessions_status_idx
  ON public.agent_sessions (status)
  WHERE status IN ('running', 'failed');

CREATE INDEX IF NOT EXISTS agent_sessions_trigger_run_idx
  ON public.agent_sessions (trigger_run_id)
  WHERE trigger_run_id IS NOT NULL;

-- ---------------------------------------------------------------------------
-- agent_traces
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.agent_traces (
  id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id              uuid NOT NULL REFERENCES public.agent_sessions(id) ON DELETE CASCADE,
  step_index              integer NOT NULL,
  role                    public.agent_trace_role NOT NULL,
  model                   text,
  block_type              public.agent_trace_block_type NOT NULL,
  tool_name               text,
  content                 jsonb NOT NULL,
  latency_ms              integer,
  input_tokens            integer,
  output_tokens           integer,
  cache_read_tokens       integer,
  cache_creation_tokens   integer,
  created_at              timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT agent_traces_step_index_nonneg CHECK (step_index >= 0),
  CONSTRAINT agent_traces_latency_nonneg    CHECK (latency_ms IS NULL OR latency_ms >= 0)
);

COMMENT ON TABLE  public.agent_traces IS
  'Per-block record of every content block produced during a Trigger.dev inference call.';
COMMENT ON COLUMN public.agent_traces.step_index IS
  'Order of the block within the Anthropic response content array (0-based).';
COMMENT ON COLUMN public.agent_traces.content IS
  'Raw Anthropic block (text, thinking, tool_use, or tool_result) -- JSONB for full replay.';

-- Required by plan: (session_id, step_index) + (task_name, started_at DESC).
-- The task/started index lives on agent_sessions above; we add the per-session
-- step index here. Unique so replays cannot accidentally double-write the same
-- block position.
CREATE UNIQUE INDEX IF NOT EXISTS agent_traces_session_step_idx
  ON public.agent_traces (session_id, step_index);

CREATE INDEX IF NOT EXISTS agent_traces_block_type_idx
  ON public.agent_traces (block_type);

CREATE INDEX IF NOT EXISTS agent_traces_tool_name_idx
  ON public.agent_traces (tool_name)
  WHERE tool_name IS NOT NULL;

-- ---------------------------------------------------------------------------
-- RLS -- service-role only. Traces are internal diagnostic data, never
-- surfaced to authenticated users. Service role bypasses RLS; no other
-- policies are intentional.
-- ---------------------------------------------------------------------------

ALTER TABLE public.agent_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.agent_traces   ENABLE ROW LEVEL SECURITY;

-- Revoke all authenticated access; service role still writes because it
-- bypasses RLS. If a UI ever needs to read traces, add an explicit policy
-- here rather than loosening default behaviour.
REVOKE ALL ON public.agent_sessions FROM anon, authenticated;
REVOKE ALL ON public.agent_traces   FROM anon, authenticated;

COMMIT;
