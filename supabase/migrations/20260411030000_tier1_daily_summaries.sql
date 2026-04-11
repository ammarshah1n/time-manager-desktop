CREATE TABLE tier1_daily_summaries (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profile_id UUID NOT NULL REFERENCES executives(id),
  summary_date DATE NOT NULL,
  day_narrative TEXT,
  significant_events JSONB,
  anomalies JSONB,
  energy_profile JSONB,
  signals_aggregated INT DEFAULT 0,
  embedding VECTOR(3072),
  generated_by TEXT,
  source_tier0_count INT DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(profile_id, summary_date)
);
-- NOTE: pgvector caps HNSW/IVFFlat at 2000 dims. VECTOR(3072) indexed via USearch locally.
-- Add pgvector index when dimension limit increases or if data exceeds 100K rows.
CREATE INDEX idx_tier1_daily_summaries_profile_date ON tier1_daily_summaries USING brin (profile_id, summary_date);
ALTER TABLE tier1_daily_summaries ENABLE ROW LEVEL SECURITY;
CREATE POLICY tier1_daily_summaries_select ON tier1_daily_summaries FOR SELECT USING (profile_id = get_executive_id(auth.uid()));
CREATE POLICY tier1_daily_summaries_insert ON tier1_daily_summaries FOR INSERT WITH CHECK (profile_id = get_executive_id(auth.uid()));
CREATE POLICY tier1_daily_summaries_update ON tier1_daily_summaries FOR UPDATE USING (profile_id = get_executive_id(auth.uid()));
CREATE POLICY tier1_daily_summaries_delete ON tier1_daily_summaries FOR DELETE USING (profile_id = get_executive_id(auth.uid()));
