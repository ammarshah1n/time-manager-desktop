CREATE TABLE tier3_personality_traits (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profile_id UUID NOT NULL REFERENCES executives(id),
  trait_name TEXT NOT NULL,
  trait_type TEXT,
  version INT DEFAULT 1,
  valence_vector JSONB,
  precision FLOAT DEFAULT 0.3,
  valid_from TIMESTAMPTZ DEFAULT now(),
  valid_to TIMESTAMPTZ,
  evidence_chain JSONB,
  contradiction_log JSONB,
  predictions_enabled BOOL DEFAULT false,
  supersedes UUID REFERENCES tier3_personality_traits(id),
  trajectory_narrative TEXT,
  embedding VECTOR(3072),
  created_at TIMESTAMPTZ DEFAULT now()
);
-- NOTE: pgvector caps HNSW/IVFFlat at 2000 dims. VECTOR(3072) indexed via USearch locally.
-- Add pgvector index when dimension limit increases or if data exceeds 100K rows.
CREATE INDEX idx_tier3_personality_traits_active ON tier3_personality_traits (profile_id) WHERE valid_to IS NULL;
ALTER TABLE tier3_personality_traits ENABLE ROW LEVEL SECURITY;
CREATE POLICY tier3_personality_traits_select ON tier3_personality_traits FOR SELECT USING (profile_id = get_executive_id(auth.uid()));
CREATE POLICY tier3_personality_traits_insert ON tier3_personality_traits FOR INSERT WITH CHECK (profile_id = get_executive_id(auth.uid()));
CREATE POLICY tier3_personality_traits_update ON tier3_personality_traits FOR UPDATE USING (profile_id = get_executive_id(auth.uid()));
CREATE POLICY tier3_personality_traits_delete ON tier3_personality_traits FOR DELETE USING (profile_id = get_executive_id(auth.uid()));
