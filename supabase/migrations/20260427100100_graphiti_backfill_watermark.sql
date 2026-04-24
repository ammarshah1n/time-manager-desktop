-- 20260427100100_graphiti_backfill_watermark.sql
--
-- Timed overnight cognitive OS -- idempotent cursor for the one-shot
-- Graphiti backfill task (trigger/src/tasks/graphiti-backfill.ts).
--
-- Purpose:
--   The backfill walks three sources (ona_nodes, ona_edges,
--   tier0_observations) and replays them into Graphiti MCP as synthetic
--   episodes with their original reference_time. Running the task a second
--   time must be a no-op. Two guards:
--     (1) a per-source watermark (this table) so we don't re-scan rows we
--         already emitted,
--     (2) a content_hash-based `episode_exists` check against Graphiti
--         before every add_episode (defence in depth).
--
-- One row per source. `kind` matches the source name exactly
-- ('ona_nodes', 'ona_edges', 'tier0_observations').

BEGIN;

CREATE TABLE IF NOT EXISTS public.backfill_watermark (
  kind            text PRIMARY KEY,
  last_id         uuid,
  last_timestamp  timestamptz,
  updated_at      timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE  public.backfill_watermark IS
  'Per-source cursor for idempotent Graphiti backfill (trigger/src/tasks/graphiti-backfill.ts).';
COMMENT ON COLUMN public.backfill_watermark.kind IS
  'Source name: "ona_nodes" | "ona_edges" | "tier0_observations".';
COMMENT ON COLUMN public.backfill_watermark.last_id IS
  'UUID of the most recently emitted row (tie-breaker when timestamps collide).';
COMMENT ON COLUMN public.backfill_watermark.last_timestamp IS
  'Timestamp of the most recently emitted row (primary cursor).';

-- ---------------------------------------------------------------------------
-- RLS -- service-role only. Watermarks are pipeline-internal.
-- ---------------------------------------------------------------------------

ALTER TABLE public.backfill_watermark ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON public.backfill_watermark FROM anon, authenticated;

COMMIT;
