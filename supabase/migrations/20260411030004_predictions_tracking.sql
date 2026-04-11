-- predictions table
CREATE TABLE predictions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profile_id UUID NOT NULL REFERENCES executives(id),
  prediction_type TEXT NOT NULL,
  predicted_behaviour TEXT NOT NULL,
  time_window JSONB,
  confidence FLOAT NOT NULL,
  grounding_trait_ids UUID[],
  falsification_criteria TEXT,
  status TEXT DEFAULT 'active' CHECK (status IN ('active','confirmed','falsified','expired')),
  brier_score FLOAT,
  created_at TIMESTAMPTZ DEFAULT now(),
  resolved_at TIMESTAMPTZ
);

-- burnout_assessments table
CREATE TABLE burnout_assessments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profile_id UUID NOT NULL REFERENCES executives(id),
  assessed_at TIMESTAMPTZ DEFAULT now(),
  exhaustion_score FLOAT,
  depersonalisation_score FLOAT,
  reduced_accomplishment_score FLOAT,
  overall_risk TEXT CHECK (overall_risk IN ('low','moderate','high','critical')),
  contributing_signals JSONB,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- avoidance_flags table
CREATE TABLE avoidance_flags (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profile_id UUID NOT NULL REFERENCES executives(id),
  detected_at TIMESTAMPTZ DEFAULT now(),
  domain TEXT,
  avoidance_type TEXT,
  confidence FLOAT,
  evidence JSONB,
  resolved_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- decision_tracking table
CREATE TABLE decision_tracking (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profile_id UUID NOT NULL REFERENCES executives(id),
  detected_at TIMESTAMPTZ DEFAULT now(),
  decision_state TEXT CHECK (decision_state IN ('committed','consolidating','wavering','reversing')),
  context JSONB,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- tier2_candidates table
CREATE TABLE tier2_candidates (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profile_id UUID NOT NULL REFERENCES executives(id),
  signature_name TEXT,
  pattern_type TEXT,
  description TEXT,
  bocpd_probability FLOAT,
  session_count INT,
  proposed_at TIMESTAMPTZ DEFAULT now(),
  reviewed_at TIMESTAMPTZ,
  review_decision TEXT,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- self_improvement_log table
CREATE TABLE self_improvement_log (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profile_id UUID NOT NULL REFERENCES executives(id),
  log_date DATE NOT NULL,
  proposed_changes JSONB,
  accepted_changes JSONB,
  rejected_reasons JSONB,
  validation_results JSONB,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- RLS for all 6 tables in file 5
ALTER TABLE predictions ENABLE ROW LEVEL SECURITY;
CREATE POLICY predictions_select ON predictions FOR SELECT USING (profile_id = get_executive_id(auth.uid()));
CREATE POLICY predictions_insert ON predictions FOR INSERT WITH CHECK (profile_id = get_executive_id(auth.uid()));
CREATE POLICY predictions_update ON predictions FOR UPDATE USING (profile_id = get_executive_id(auth.uid()));
CREATE POLICY predictions_delete ON predictions FOR DELETE USING (profile_id = get_executive_id(auth.uid()));

ALTER TABLE burnout_assessments ENABLE ROW LEVEL SECURITY;
CREATE POLICY burnout_assessments_select ON burnout_assessments FOR SELECT USING (profile_id = get_executive_id(auth.uid()));
CREATE POLICY burnout_assessments_insert ON burnout_assessments FOR INSERT WITH CHECK (profile_id = get_executive_id(auth.uid()));
CREATE POLICY burnout_assessments_update ON burnout_assessments FOR UPDATE USING (profile_id = get_executive_id(auth.uid()));
CREATE POLICY burnout_assessments_delete ON burnout_assessments FOR DELETE USING (profile_id = get_executive_id(auth.uid()));

ALTER TABLE avoidance_flags ENABLE ROW LEVEL SECURITY;
CREATE POLICY avoidance_flags_select ON avoidance_flags FOR SELECT USING (profile_id = get_executive_id(auth.uid()));
CREATE POLICY avoidance_flags_insert ON avoidance_flags FOR INSERT WITH CHECK (profile_id = get_executive_id(auth.uid()));
CREATE POLICY avoidance_flags_update ON avoidance_flags FOR UPDATE USING (profile_id = get_executive_id(auth.uid()));
CREATE POLICY avoidance_flags_delete ON avoidance_flags FOR DELETE USING (profile_id = get_executive_id(auth.uid()));

ALTER TABLE decision_tracking ENABLE ROW LEVEL SECURITY;
CREATE POLICY decision_tracking_select ON decision_tracking FOR SELECT USING (profile_id = get_executive_id(auth.uid()));
CREATE POLICY decision_tracking_insert ON decision_tracking FOR INSERT WITH CHECK (profile_id = get_executive_id(auth.uid()));
CREATE POLICY decision_tracking_update ON decision_tracking FOR UPDATE USING (profile_id = get_executive_id(auth.uid()));
CREATE POLICY decision_tracking_delete ON decision_tracking FOR DELETE USING (profile_id = get_executive_id(auth.uid()));

ALTER TABLE tier2_candidates ENABLE ROW LEVEL SECURITY;
CREATE POLICY tier2_candidates_select ON tier2_candidates FOR SELECT USING (profile_id = get_executive_id(auth.uid()));
CREATE POLICY tier2_candidates_insert ON tier2_candidates FOR INSERT WITH CHECK (profile_id = get_executive_id(auth.uid()));
CREATE POLICY tier2_candidates_update ON tier2_candidates FOR UPDATE USING (profile_id = get_executive_id(auth.uid()));
CREATE POLICY tier2_candidates_delete ON tier2_candidates FOR DELETE USING (profile_id = get_executive_id(auth.uid()));

ALTER TABLE self_improvement_log ENABLE ROW LEVEL SECURITY;
CREATE POLICY self_improvement_log_select ON self_improvement_log FOR SELECT USING (profile_id = get_executive_id(auth.uid()));
CREATE POLICY self_improvement_log_insert ON self_improvement_log FOR INSERT WITH CHECK (profile_id = get_executive_id(auth.uid()));
CREATE POLICY self_improvement_log_update ON self_improvement_log FOR UPDATE USING (profile_id = get_executive_id(auth.uid()));
CREATE POLICY self_improvement_log_delete ON self_improvement_log FOR DELETE USING (profile_id = get_executive_id(auth.uid()));
