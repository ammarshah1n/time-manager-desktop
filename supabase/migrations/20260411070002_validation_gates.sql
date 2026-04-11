-- Phase 7.02: 4-gate validation protocol support
-- Adds validation tracking columns to tier2_behavioural_signatures

-- Add validation gates tracking
ALTER TABLE tier2_behavioural_signatures
    ADD COLUMN IF NOT EXISTS gate1_effect_size FLOAT,
    ADD COLUMN IF NOT EXISTS gate1_passed BOOLEAN DEFAULT false,
    ADD COLUMN IF NOT EXISTS gate2_test_retest_r FLOAT,
    ADD COLUMN IF NOT EXISTS gate2_weeks_tested INT DEFAULT 0,
    ADD COLUMN IF NOT EXISTS gate2_passed BOOLEAN DEFAULT false,
    ADD COLUMN IF NOT EXISTS gate3_context_conditions INT DEFAULT 0,
    ADD COLUMN IF NOT EXISTS gate3_passed BOOLEAN DEFAULT false,
    ADD COLUMN IF NOT EXISTS gate4_plausibility_score FLOAT,
    ADD COLUMN IF NOT EXISTS gate4_mechanism TEXT,
    ADD COLUMN IF NOT EXISTS gate4_passed BOOLEAN DEFAULT false,
    ADD COLUMN IF NOT EXISTS all_gates_passed BOOLEAN DEFAULT false,
    ADD COLUMN IF NOT EXISTS last_validation_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS next_revalidation_at TIMESTAMPTZ;

-- Function to check if all gates pass and promote to confirmed
CREATE OR REPLACE FUNCTION check_validation_gates(sig_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    sig RECORD;
    result JSONB;
BEGIN
    SELECT * INTO sig FROM tier2_behavioural_signatures WHERE id = sig_id;
    IF NOT FOUND THEN
        RETURN jsonb_build_object('error', 'signature not found');
    END IF;

    -- Check all 4 gates
    result := jsonb_build_object(
        'gate1_effect_size', COALESCE(sig.gate1_passed, false),
        'gate2_test_retest', COALESCE(sig.gate2_passed, false),
        'gate3_replication', COALESCE(sig.gate3_passed, false),
        'gate4_plausibility', COALESCE(sig.gate4_passed, false)
    );

    -- If all pass, promote to confirmed
    IF sig.gate1_passed AND sig.gate2_passed AND sig.gate3_passed AND sig.gate4_passed THEN
        UPDATE tier2_behavioural_signatures
        SET status = 'confirmed',
            all_gates_passed = true,
            last_validation_at = now(),
            next_revalidation_at = now() + INTERVAL '30 days',
            updated_at = now()
        WHERE id = sig_id;

        result := result || jsonb_build_object('promoted', true, 'new_status', 'confirmed');
    ELSE
        -- Schedule recheck in 7 days
        UPDATE tier2_behavioural_signatures
        SET last_validation_at = now(),
            next_revalidation_at = now() + INTERVAL '7 days',
            updated_at = now()
        WHERE id = sig_id;

        result := result || jsonb_build_object('promoted', false, 'recheck_in', '7 days');
    END IF;

    RETURN result;
END;
$$;

-- CCR (7.05) tracking table
CREATE TABLE IF NOT EXISTS ccr_evaluations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profile_id UUID NOT NULL,
    evaluation_date DATE NOT NULL,
    evaluation_type TEXT CHECK (evaluation_type IN ('weekly_lightweight', 'monthly_full')) NOT NULL,
    model_brier_score FLOAT,
    baseline_brier_score FLOAT,
    ccr_ratio FLOAT,
    predictions_evaluated INT DEFAULT 0,
    accuracy_by_type JSONB DEFAULT '{}',
    calibration_bias JSONB DEFAULT '{}',
    flagged BOOLEAN DEFAULT false,
    flag_reason TEXT,
    created_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE ccr_evaluations ENABLE ROW LEVEL SECURITY;

CREATE POLICY "ccr_select" ON ccr_evaluations FOR SELECT USING (profile_id = auth.uid());
CREATE POLICY "ccr_insert" ON ccr_evaluations FOR INSERT WITH CHECK (profile_id = auth.uid());

-- Weekly lightweight CCR check (SQL only, no LLM)
CREATE OR REPLACE FUNCTION compute_weekly_ccr(exec_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    model_brier FLOAT;
    baseline_brier FLOAT;
    ccr FLOAT;
    pred_count INT;
    consecutive_worse INT;
    result JSONB;
BEGIN
    -- Compute model brier score from resolved predictions (last 30 days)
    SELECT AVG(brier_score), COUNT(*)
    INTO model_brier, pred_count
    FROM predictions
    WHERE profile_id = exec_id
      AND status = 'resolved'
      AND resolved_at > now() - INTERVAL '30 days'
      AND brier_score IS NOT NULL;

    IF pred_count < 3 THEN
        RETURN jsonb_build_object('status', 'insufficient_data', 'predictions', pred_count);
    END IF;

    -- Baseline: assume 0.25 brier (random-ish baseline)
    baseline_brier := 0.25;
    ccr := CASE WHEN model_brier > 0 THEN baseline_brier / model_brier ELSE 1.0 END;

    -- Check for consecutive weeks worse than baseline
    SELECT COUNT(*) INTO consecutive_worse
    FROM ccr_evaluations
    WHERE profile_id = exec_id
      AND ccr_ratio < 1.0
      AND evaluation_date > now() - INTERVAL '21 days'
    ORDER BY evaluation_date DESC;

    -- Insert evaluation
    INSERT INTO ccr_evaluations (profile_id, evaluation_date, evaluation_type, model_brier_score, baseline_brier_score, ccr_ratio, predictions_evaluated, flagged, flag_reason)
    VALUES (exec_id, CURRENT_DATE, 'weekly_lightweight', model_brier, baseline_brier, ccr,
            pred_count,
            consecutive_worse >= 2,
            CASE WHEN consecutive_worse >= 2 THEN 'CCR below baseline for 2+ consecutive weeks' ELSE NULL END);

    result := jsonb_build_object(
        'ccr', ccr,
        'model_brier', model_brier,
        'baseline_brier', baseline_brier,
        'predictions_evaluated', pred_count,
        'flagged', consecutive_worse >= 2
    );

    RETURN result;
END;
$$;
