-- Sender social graph
CREATE TABLE IF NOT EXISTS public.sender_social_graph (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id uuid NOT NULL REFERENCES public.workspaces(id) ON DELETE CASCADE,
  profile_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  from_address text NOT NULL,
  avg_reply_latency_min real,
  reply_rate real,
  total_received int NOT NULL DEFAULT 0,
  total_replied int NOT NULL DEFAULT 0,
  importance_score real NOT NULL DEFAULT 0.5,
  last_received_at timestamptz,
  last_replied_at timestamptz,
  sample_size int NOT NULL DEFAULT 0,
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (workspace_id, profile_id, from_address)
);
ALTER TABLE public.sender_social_graph ENABLE ROW LEVEL SECURITY;
CREATE POLICY "sender_graph_ws" ON public.sender_social_graph FOR ALL TO authenticated
  USING (workspace_id = ANY(public.current_workspace_ids()));

-- Thread velocity on email_messages
ALTER TABLE public.email_messages ADD COLUMN IF NOT EXISTS thread_velocity real;
ALTER TABLE public.email_messages ADD COLUMN IF NOT EXISTS sender_importance real DEFAULT 0.5;

-- Task dependency
ALTER TABLE public.tasks ADD COLUMN IF NOT EXISTS depends_on_task_id uuid REFERENCES public.tasks(id) ON DELETE SET NULL;
ALTER TABLE public.tasks ADD COLUMN IF NOT EXISTS is_blocked boolean NOT NULL DEFAULT false;

-- Unblock trigger
CREATE OR REPLACE FUNCTION public.unblock_dependent_tasks()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.status = 'done' AND (OLD.status IS NULL OR OLD.status != 'done') THEN
    UPDATE public.tasks SET is_blocked = false WHERE depends_on_task_id = NEW.id AND workspace_id = NEW.workspace_id;
  END IF;
  RETURN NEW;
END;
$$;
CREATE TRIGGER task_completion_unblock AFTER UPDATE ON public.tasks FOR EACH ROW EXECUTE FUNCTION public.unblock_dependent_tasks();

-- Calendar context on daily_plans
ALTER TABLE public.daily_plans ADD COLUMN IF NOT EXISTS calendar_meeting_minutes integer;
ALTER TABLE public.daily_plans ADD COLUMN IF NOT EXISTS next_free_block_minutes integer;
ALTER TABLE public.daily_plans ADD COLUMN IF NOT EXISTS post_meeting_recovery boolean DEFAULT false;

-- Session interruption event type
ALTER TABLE public.behaviour_events DROP CONSTRAINT IF EXISTS behaviour_events_event_type_check;
ALTER TABLE public.behaviour_events ADD CONSTRAINT behaviour_events_event_type_check CHECK (event_type IN (
  'task_completed','task_deferred','task_deleted','plan_order_override','estimate_override',
  'session_started','triage_correction','task_abandoned','task_unblocked','session_interrupted'
));
