-- Bucket completion statistics for Thompson sampling
CREATE TABLE IF NOT EXISTS public.bucket_completion_stats (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id uuid NOT NULL REFERENCES public.workspaces(id) ON DELETE CASCADE,
  profile_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  bucket_type text NOT NULL,
  hour_range text NOT NULL,  -- '06-12', '12-16', '16-20', '20-06'
  completions int NOT NULL DEFAULT 0,  -- alpha parameter
  deferrals int NOT NULL DEFAULT 0,    -- beta parameter
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (workspace_id, profile_id, bucket_type, hour_range)
);

ALTER TABLE public.bucket_completion_stats ENABLE ROW LEVEL SECURITY;

CREATE POLICY "bucket_stats_workspace_isolation"
  ON public.bucket_completion_stats FOR ALL TO authenticated
  USING (workspace_id = ANY(public.current_workspace_ids()))
  WITH CHECK (workspace_id = ANY(public.current_workspace_ids()));

-- Trigger: increment completions/deferrals from behaviour_events
CREATE OR REPLACE FUNCTION public.update_bucket_stats()
RETURNS TRIGGER AS $$
DECLARE
  _hour_range text;
BEGIN
  -- Map hour to range
  _hour_range := CASE
    WHEN NEW.hour_of_day BETWEEN 6 AND 11 THEN '06-12'
    WHEN NEW.hour_of_day BETWEEN 12 AND 15 THEN '12-16'
    WHEN NEW.hour_of_day BETWEEN 16 AND 19 THEN '16-20'
    ELSE '20-06'
  END;

  IF NEW.event_type = 'task_completed' AND NEW.bucket_type IS NOT NULL THEN
    INSERT INTO public.bucket_completion_stats (workspace_id, profile_id, bucket_type, hour_range, completions)
    VALUES (NEW.workspace_id, NEW.profile_id, NEW.bucket_type, _hour_range, 1)
    ON CONFLICT (workspace_id, profile_id, bucket_type, hour_range)
    DO UPDATE SET completions = bucket_completion_stats.completions + 1, updated_at = now();
  ELSIF NEW.event_type = 'task_deferred' AND NEW.bucket_type IS NOT NULL THEN
    INSERT INTO public.bucket_completion_stats (workspace_id, profile_id, bucket_type, hour_range, deferrals)
    VALUES (NEW.workspace_id, NEW.profile_id, NEW.bucket_type, _hour_range, 1)
    ON CONFLICT (workspace_id, profile_id, bucket_type, hour_range)
    DO UPDATE SET deferrals = bucket_completion_stats.deferrals + 1, updated_at = now();
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Apply to current partitions
CREATE TRIGGER trg_update_bucket_stats
  AFTER INSERT ON public.behaviour_events_2026_03
  FOR EACH ROW EXECUTE FUNCTION public.update_bucket_stats();
CREATE TRIGGER trg_update_bucket_stats
  AFTER INSERT ON public.behaviour_events_2026_04
  FOR EACH ROW EXECUTE FUNCTION public.update_bucket_stats();
CREATE TRIGGER trg_update_bucket_stats
  AFTER INSERT ON public.behaviour_events_2026_05
  FOR EACH ROW EXECUTE FUNCTION public.update_bucket_stats();
