-- Morning briefings table
-- Stores generated intelligence briefings with engagement tracking

CREATE TABLE IF NOT EXISTS briefings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profile_id UUID NOT NULL REFERENCES executives(id) ON DELETE CASCADE,
    date DATE NOT NULL,
    content JSONB NOT NULL DEFAULT '{}'::jsonb,
    generated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    word_count INTEGER NOT NULL DEFAULT 0,
    was_viewed BOOLEAN NOT NULL DEFAULT false,
    first_viewed_at TIMESTAMPTZ,
    engagement_duration_seconds INTEGER,
    sections_interacted JSONB DEFAULT '[]'::jsonb,
    insight_superseded_by JSONB DEFAULT '[]'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (profile_id, date)
);

CREATE INDEX idx_briefings_profile_date ON briefings USING btree (profile_id, date DESC);

ALTER TABLE briefings ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Executives can read own briefings"
    ON briefings FOR SELECT
    USING (profile_id = get_executive_id(auth.uid()));

CREATE POLICY "Executives can update own briefings"
    ON briefings FOR UPDATE
    USING (profile_id = get_executive_id(auth.uid()));

CREATE POLICY "Service role manages briefings"
    ON briefings FOR ALL
    USING (auth.role() = 'service_role');
