CREATE TABLE IF NOT EXISTS public.bucket_estimates (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id uuid NOT NULL REFERENCES public.workspaces(id) ON DELETE CASCADE,
    profile_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    bucket_type text NOT NULL,
    mean_minutes double precision NOT NULL,
    sample_count int NOT NULL DEFAULT 0,
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE(workspace_id, profile_id, bucket_type)
);
ALTER TABLE public.bucket_estimates ENABLE ROW LEVEL SECURITY;
CREATE POLICY "bucket_estimates_workspace_isolation"
    ON public.bucket_estimates FOR ALL TO authenticated
    USING (workspace_id = ANY(public.current_workspace_ids()))
    WITH CHECK (workspace_id = ANY(public.current_workspace_ids()));
