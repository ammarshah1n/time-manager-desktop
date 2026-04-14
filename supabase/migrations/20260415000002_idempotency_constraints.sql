DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'self_improvement_log_profile_id_log_date_key'
      AND conrelid = 'public.self_improvement_log'::regclass
  ) THEN
    ALTER TABLE public.self_improvement_log
      ADD CONSTRAINT self_improvement_log_profile_id_log_date_key
      UNIQUE (profile_id, log_date);
  END IF;
END $$;

CREATE UNIQUE INDEX IF NOT EXISTS idx_bias_signal_observations_profile_bias_detected_date_unique
  ON public.bias_signal_observations (profile_id, bias_type, (detected_at::date));

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'tier2_behavioural_signatures_profile_id_signature_name_key'
      AND conrelid = 'public.tier2_behavioural_signatures'::regclass
  ) THEN
    ALTER TABLE public.tier2_behavioural_signatures
      ADD CONSTRAINT tier2_behavioural_signatures_profile_id_signature_name_key
      UNIQUE (profile_id, signature_name);
  END IF;
END $$;

CREATE UNIQUE INDEX IF NOT EXISTS idx_burnout_assessments_profile_assessed_date_unique
  ON public.burnout_assessments (profile_id, (assessed_at::date));

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'bias_analysis_runs_profile_id_run_date_key'
      AND conrelid = 'public.bias_analysis_runs'::regclass
  ) THEN
    ALTER TABLE public.bias_analysis_runs
      ADD CONSTRAINT bias_analysis_runs_profile_id_run_date_key
      UNIQUE (profile_id, run_date);
  END IF;
END $$;
