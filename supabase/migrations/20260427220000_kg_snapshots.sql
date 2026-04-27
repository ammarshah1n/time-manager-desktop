-- 20260427220000_kg_snapshots.sql
--
-- Timed overnight cognitive OS — weekly knowledge-graph snapshot ledger.
--
-- T28a. One row per successful `export_snapshot` call made by the weekly
-- `kg-snapshot` Trigger.dev task (Sunday 03:45 UTC). The snapshot itself lives
-- in Supabase Storage (bucket kg-snapshots/<YYYY-WW>/<session_id>.json); this
-- table is the audit + retention ledger used by replay (task 41,
-- --mode=kg-restore) to locate historical dumps.
--
-- Retention: the task deletes all but the 52 most recent rows per executive,
-- so replay always has at least a year of weekly snapshots available.

BEGIN;

CREATE TABLE IF NOT EXISTS public.kg_snapshots (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id   uuid REFERENCES public.agent_sessions(id) ON DELETE SET NULL,
  exec_id      uuid REFERENCES public.executives(id) ON DELETE CASCADE,
  week         text NOT NULL, -- ISO week format YYYY-WW
  storage_path text NOT NULL,
  node_count   integer,
  rel_count    integer,
  size_bytes   bigint,
  created_at   timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE  public.kg_snapshots IS
  'Weekly Neo4j snapshot ledger — one row per successful graphiti-mcp export_snapshot call.';
COMMENT ON COLUMN public.kg_snapshots.week IS
  'ISO 8601 week, YYYY-WW. Matches the week folder in the kg-snapshots storage bucket.';
COMMENT ON COLUMN public.kg_snapshots.storage_path IS
  'Object path within the kg-snapshots Supabase Storage bucket (no bucket prefix).';

CREATE INDEX IF NOT EXISTS kg_snapshots_exec_week_idx
  ON public.kg_snapshots (exec_id, week DESC);

-- ---------------------------------------------------------------------------
-- RLS — service-role only. Snapshot metadata is internal ops data; the
-- graph contents themselves are encrypted at rest in Storage.
-- ---------------------------------------------------------------------------

ALTER TABLE public.kg_snapshots ENABLE ROW LEVEL SECURITY;

CREATE POLICY "kg_snapshots_service_role_all"
  ON public.kg_snapshots
  FOR ALL
  USING (auth.role() = 'service_role')
  WITH CHECK (auth.role() = 'service_role');

REVOKE ALL ON public.kg_snapshots FROM anon, authenticated;

COMMIT;
