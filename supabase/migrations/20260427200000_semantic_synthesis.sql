-- 20260427200000_semantic_synthesis.sql
--
-- Timed overnight cognitive OS — semantic synthesis ledger.
--
-- Each run of the `rem-synthesis` Trigger.dev task (T28) writes one row per
-- executive per UTC-day. The body is the final assistant text produced by the
-- Claude Agent SDK loop after it has driven the four canonical REM queries
-- (cross-episode patterns / stated-vs-enacted priority divergence /
-- relationship evolution / disconfirming evidence) through graphiti-mcp and
-- skill-library-mcp tools.
--
-- `evidence_refs` is the JSONB array of episode / fact identifiers the agent
-- actually grounded its synthesis in, scraped from the `tool_result` blocks in
-- the agent_traces ledger — it is the audit trail that lets the morning
-- briefing cite source material deterministically.
--
-- `session_id` is the foreign key back to the `agent_sessions` row opened by
-- trace-tool-results.openAgentSession, so every synthesis is replayable block
-- by block from the trace ledger.
--
-- Upsert key is (exec_id, date) so a manual re-run of the nightly REM pass on
-- the same UTC day overwrites in place without creating a second row.

BEGIN;

CREATE TABLE IF NOT EXISTS public.semantic_synthesis (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  exec_id       uuid NOT NULL REFERENCES public.executives(id) ON DELETE CASCADE,
  date          date NOT NULL,
  content       text NOT NULL,
  evidence_refs jsonb NOT NULL DEFAULT '[]'::jsonb,
  session_id    uuid REFERENCES public.agent_sessions(id) ON DELETE SET NULL,
  updated_at    timestamptz NOT NULL DEFAULT now(),
  created_at    timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT semantic_synthesis_exec_date_unique UNIQUE (exec_id, date)
);

COMMENT ON TABLE  public.semantic_synthesis IS
  'One row per executive per UTC-day — output of the REM (rem-synthesis) Trigger.dev pass.';
COMMENT ON COLUMN public.semantic_synthesis.content IS
  'Final assistant text block produced by the Claude Agent SDK query() loop.';
COMMENT ON COLUMN public.semantic_synthesis.evidence_refs IS
  'JSONB array of episode / fact ids scraped from tool_result blocks — audit trail.';
COMMENT ON COLUMN public.semantic_synthesis.session_id IS
  'agent_sessions row opened by trace-tool-results.openAgentSession for this run.';

CREATE INDEX IF NOT EXISTS semantic_synthesis_exec_date_desc_idx
  ON public.semantic_synthesis (exec_id, date DESC);

-- ---------------------------------------------------------------------------
-- RLS — executives read their own synthesis; service role does everything.
-- ---------------------------------------------------------------------------

ALTER TABLE public.semantic_synthesis ENABLE ROW LEVEL SECURITY;

CREATE POLICY "semantic_synthesis_select_own"
  ON public.semantic_synthesis
  FOR SELECT
  USING (exec_id = public.get_executive_id(auth.uid()));

CREATE POLICY "semantic_synthesis_service_role_all"
  ON public.semantic_synthesis
  FOR ALL
  USING (auth.role() = 'service_role')
  WITH CHECK (auth.role() = 'service_role');

COMMIT;
