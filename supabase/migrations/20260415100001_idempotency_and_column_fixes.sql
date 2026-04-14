-- score_audit_log: rename workspace_id → profile_id
-- Edge functions now write profile_id but column is workspace_id
-- Note: idempotency constraints handled in 20260415000002_idempotency_constraints.sql

ALTER TABLE public.score_audit_log
  RENAME COLUMN workspace_id TO profile_id;

-- Update the existing index to use new column name
DROP INDEX IF EXISTS idx_score_audit_observation;
CREATE INDEX IF NOT EXISTS idx_score_audit_observation
  ON public.score_audit_log (profile_id, observation_id);
