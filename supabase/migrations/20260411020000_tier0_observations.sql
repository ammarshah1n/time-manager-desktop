CREATE EXTENSION IF NOT EXISTS vector;

CREATE TABLE public.tier0_observations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profile_id UUID NOT NULL REFERENCES public.executives(id),
    occurred_at TIMESTAMPTZ NOT NULL,
    source TEXT NOT NULL,
    event_type TEXT NOT NULL,
    entity_id UUID,
    entity_type TEXT,
    summary TEXT,
    raw_data JSONB,
    importance_score FLOAT NOT NULL DEFAULT 0.5,
    baseline_deviation FLOAT,
    embedding VECTOR(1024),
    is_processed BOOL NOT NULL DEFAULT false,
    processed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX tier0_observations_profile_occurred_brin_idx
ON public.tier0_observations
USING brin (profile_id, occurred_at);

CREATE INDEX tier0_observations_embedding_hnsw_idx
ON public.tier0_observations
USING hnsw (embedding vector_cosine_ops)
WITH (m = 16, ef_construction = 128);

ALTER TABLE public.tier0_observations ENABLE ROW LEVEL SECURITY;

CREATE POLICY tier0_observations_select
ON public.tier0_observations
FOR SELECT
USING (profile_id = public.get_executive_id(auth.uid()));

CREATE POLICY tier0_observations_insert
ON public.tier0_observations
FOR INSERT
WITH CHECK (profile_id = public.get_executive_id(auth.uid()));

CREATE POLICY tier0_observations_update
ON public.tier0_observations
FOR UPDATE
USING (profile_id = public.get_executive_id(auth.uid()))
WITH CHECK (profile_id = public.get_executive_id(auth.uid()));

CREATE POLICY tier0_observations_delete
ON public.tier0_observations
FOR DELETE
USING (profile_id = public.get_executive_id(auth.uid()));
