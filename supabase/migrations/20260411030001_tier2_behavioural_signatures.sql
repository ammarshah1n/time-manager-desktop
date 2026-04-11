CREATE TABLE tier2_behavioural_signatures (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profile_id UUID NOT NULL REFERENCES executives(id),
  signature_name TEXT NOT NULL,
  pattern_type TEXT,
  description TEXT,
  cross_domain_correlations JSONB,
  supporting_tier1_ids UUID[],
  observation_count INT DEFAULT 0,
  confidence FLOAT DEFAULT 0.3,
  validation_gates JSONB,
  status TEXT NOT NULL DEFAULT 'emerging' CHECK (status IN ('emerging','developing','confirmed','fading','retired')),
  last_reinforced TIMESTAMPTZ,
  next_revalidation TIMESTAMPTZ,
  embedding VECTOR(3072),
  created_at TIMESTAMPTZ DEFAULT now()
);
-- NOTE: pgvector caps HNSW/IVFFlat at 2000 dims. VECTOR(3072) indexed via USearch locally.
-- Add pgvector index when dimension limit increases or if data exceeds 100K rows.
CREATE INDEX idx_tier2_behavioural_signatures_tier1_ids ON tier2_behavioural_signatures USING gin (supporting_tier1_ids);
ALTER TABLE tier2_behavioural_signatures ENABLE ROW LEVEL SECURITY;
CREATE POLICY tier2_behavioural_signatures_select ON tier2_behavioural_signatures FOR SELECT USING (profile_id = get_executive_id(auth.uid()));
CREATE POLICY tier2_behavioural_signatures_insert ON tier2_behavioural_signatures FOR INSERT WITH CHECK (profile_id = get_executive_id(auth.uid()));
CREATE POLICY tier2_behavioural_signatures_update ON tier2_behavioural_signatures FOR UPDATE USING (profile_id = get_executive_id(auth.uid()));
CREATE POLICY tier2_behavioural_signatures_delete ON tier2_behavioural_signatures FOR DELETE USING (profile_id = get_executive_id(auth.uid()));
