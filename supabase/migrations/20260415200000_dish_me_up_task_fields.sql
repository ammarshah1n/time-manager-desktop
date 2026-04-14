-- ============================================================
-- Dish Me Up: Task scoring fields
-- Migration: 20260415200000_dish_me_up_task_fields.sql
-- Adds urgency/importance split, energy_required, context,
-- and skip_count to support the composite priority score.
-- ============================================================

-- Urgency (1-5): time-sensitivity, amplified as deadline approaches
ALTER TABLE public.tasks
  ADD COLUMN IF NOT EXISTS urgency integer NOT NULL DEFAULT 3
    CHECK (urgency BETWEEN 1 AND 5);

-- Importance (1-5): strategic/personal value
ALTER TABLE public.tasks
  ADD COLUMN IF NOT EXISTS importance integer NOT NULL DEFAULT 3
    CHECK (importance BETWEEN 1 AND 5);

-- Energy required: cognitive load of task
ALTER TABLE public.tasks
  ADD COLUMN IF NOT EXISTS energy_required text NOT NULL DEFAULT 'medium'
    CHECK (energy_required IN ('high', 'medium', 'low'));

-- Context: where the task can be performed
-- Replaces the boolean is_transit_safe with a richer enum
ALTER TABLE public.tasks
  ADD COLUMN IF NOT EXISTS context text NOT NULL DEFAULT 'anywhere'
    CHECK (context IN ('desk', 'transit', 'anywhere'));

-- Skip count: how many times user skipped this task when it was ranked highly
-- Distinct from deferred_count (manual deferral) — this tracks algorithmic skips
ALTER TABLE public.tasks
  ADD COLUMN IF NOT EXISTS skip_count integer NOT NULL DEFAULT 0;

-- Backfill context from existing is_transit_safe flag
UPDATE public.tasks
SET context = 'transit'
WHERE is_transit_safe = true AND context = 'anywhere';

-- Index for energy-based filtering in the allocator
CREATE INDEX IF NOT EXISTS tasks_energy_context_idx
  ON public.tasks(workspace_id, profile_id, energy_required, context)
  WHERE status = 'pending';
