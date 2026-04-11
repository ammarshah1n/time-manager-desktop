CREATE TABLE active_context_buffer (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profile_id UUID NOT NULL REFERENCES executives(id) UNIQUE,
  acb_full JSONB,
  acb_light JSONB,
  acb_version INT DEFAULT 0,
  acb_generated_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);
ALTER TABLE active_context_buffer ENABLE ROW LEVEL SECURITY;
CREATE POLICY active_context_buffer_select ON active_context_buffer FOR SELECT USING (profile_id = get_executive_id(auth.uid()));
CREATE POLICY active_context_buffer_insert ON active_context_buffer FOR INSERT WITH CHECK (profile_id = get_executive_id(auth.uid()));
CREATE POLICY active_context_buffer_update ON active_context_buffer FOR UPDATE USING (profile_id = get_executive_id(auth.uid()));
CREATE POLICY active_context_buffer_delete ON active_context_buffer FOR DELETE USING (profile_id = get_executive_id(auth.uid()));

CREATE OR REPLACE FUNCTION get_acb_full(exec_id UUID) RETURNS JSONB AS $$
  SELECT acb_full FROM active_context_buffer WHERE profile_id = exec_id;
$$ LANGUAGE sql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION get_acb_light(exec_id UUID) RETURNS JSONB AS $$
  SELECT acb_light FROM active_context_buffer WHERE profile_id = exec_id;
$$ LANGUAGE sql SECURITY DEFINER;
