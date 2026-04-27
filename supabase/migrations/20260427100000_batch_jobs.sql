-- 20260427100000_batch_jobs.sql
--
-- Timed overnight cognitive OS -- Anthropic Batch API ledger.
--
-- The NREM pipeline (nrem-entity-extraction) submits a batch to Anthropic's
-- Message Batches API every night at 02:00, and a consumer task polls every
-- 5 minutes between 02:00 and 08:59 to drain finished batches. One row here
-- per submitted batch; the row transitions:
--
--   pending  -> consumed    (results successfully streamed + persisted)
--   pending  -> failed      (either the batch expired or the consumer saw a
--                            stuck batch older than 26h)
--
-- Row granularity is one batch, not one request, because the Anthropic batch
-- id is the sole correlation key we can use after submission. Per-request
-- success/failure lands in `agent_traces` via the consume task.

BEGIN;

CREATE TABLE IF NOT EXISTS public.batch_jobs (
  id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  batch_id             text NOT NULL UNIQUE,
  submitted_at         timestamptz NOT NULL DEFAULT now(),
  kind                 text NOT NULL,
  status               text NOT NULL,
  consumed_at          timestamptz,
  source_session_id    uuid,
  observation_count    integer,
  error                text,
  CONSTRAINT batch_jobs_status_chk CHECK (status IN ('pending','ready','consumed','failed'))
);

COMMENT ON TABLE  public.batch_jobs IS
  'Ledger of Anthropic Message Batch submissions (NREM entity extraction, etc).';
COMMENT ON COLUMN public.batch_jobs.batch_id IS
  'Anthropic batch id (msgbatch_...) -- the retrieval key from messages.batches.retrieve().';
COMMENT ON COLUMN public.batch_jobs.kind IS
  'Logical producer, e.g. "nrem-extraction". Used to derive per-task watermarks.';
COMMENT ON COLUMN public.batch_jobs.status IS
  'Lifecycle: pending (submitted, not yet drained) -> consumed or failed.';

CREATE INDEX IF NOT EXISTS batch_jobs_kind_status_submitted_idx
  ON public.batch_jobs (kind, status, submitted_at DESC);

-- ---------------------------------------------------------------------------
-- RLS -- service-role only. Batch metadata is pipeline-internal; not user-facing.
-- Service role bypasses RLS; no additional policies are intentional.
-- ---------------------------------------------------------------------------

ALTER TABLE public.batch_jobs ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON public.batch_jobs FROM anon, authenticated;

COMMIT;
