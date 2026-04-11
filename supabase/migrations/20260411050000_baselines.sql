-- Baselines table for per-signal rolling averages (30-day window)
-- Weeks 1-2: baselines NULL (establishment period, no deviations computed)

CREATE TABLE IF NOT EXISTS baselines (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profile_id UUID NOT NULL REFERENCES executives(id) ON DELETE CASCADE,
    signal_type TEXT NOT NULL,
    metric_name TEXT NOT NULL,
    mean DOUBLE PRECISION,
    stddev DOUBLE PRECISION,
    sample_count INTEGER NOT NULL DEFAULT 0,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (profile_id, signal_type, metric_name)
);

CREATE INDEX idx_baselines_profile ON baselines USING btree (profile_id);

ALTER TABLE baselines ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Executives can read own baselines"
    ON baselines FOR SELECT
    USING (profile_id = get_executive_id(auth.uid()));

CREATE POLICY "Service role manages baselines"
    ON baselines FOR ALL
    USING (auth.role() = 'service_role');

-- Function to compute or update baselines from tier0_observations
-- Called after each daily summary generation
CREATE OR REPLACE FUNCTION compute_baselines(exec_id UUID)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    cutoff TIMESTAMPTZ := now() - INTERVAL '30 days';
BEGIN
    -- Email response latency baseline
    INSERT INTO baselines (profile_id, signal_type, metric_name, mean, stddev, sample_count, updated_at)
    SELECT
        exec_id,
        'email',
        'response_latency_seconds',
        AVG((raw_data->>'response_time_sec')::float),
        STDDEV((raw_data->>'response_time_sec')::float),
        COUNT(*),
        now()
    FROM tier0_observations
    WHERE profile_id = exec_id
      AND source = 'email'
      AND event_type = 'email.response_sent'
      AND occurred_at > cutoff
      AND (raw_data->>'response_time_sec') IS NOT NULL
    HAVING COUNT(*) >= 5
    ON CONFLICT (profile_id, signal_type, metric_name)
    DO UPDATE SET
        mean = EXCLUDED.mean,
        stddev = EXCLUDED.stddev,
        sample_count = EXCLUDED.sample_count,
        updated_at = now();

    -- Email volume per day baseline
    INSERT INTO baselines (profile_id, signal_type, metric_name, mean, stddev, sample_count, updated_at)
    SELECT
        exec_id,
        'email',
        'daily_volume',
        AVG(daily_count),
        STDDEV(daily_count),
        COUNT(*),
        now()
    FROM (
        SELECT occurred_at::date AS day, COUNT(*) AS daily_count
        FROM tier0_observations
        WHERE profile_id = exec_id AND source = 'email' AND occurred_at > cutoff
        GROUP BY occurred_at::date
    ) daily
    HAVING COUNT(*) >= 5
    ON CONFLICT (profile_id, signal_type, metric_name)
    DO UPDATE SET
        mean = EXCLUDED.mean,
        stddev = EXCLUDED.stddev,
        sample_count = EXCLUDED.sample_count,
        updated_at = now();

    -- App usage: focus duration baseline
    INSERT INTO baselines (profile_id, signal_type, metric_name, mean, stddev, sample_count, updated_at)
    SELECT
        exec_id,
        'app_usage',
        'focus_duration_seconds',
        AVG((raw_data->>'focus_duration_seconds')::float),
        STDDEV((raw_data->>'focus_duration_seconds')::float),
        COUNT(*),
        now()
    FROM tier0_observations
    WHERE profile_id = exec_id
      AND source = 'app_usage'
      AND occurred_at > cutoff
      AND (raw_data->>'focus_duration_seconds') IS NOT NULL
    HAVING COUNT(*) >= 10
    ON CONFLICT (profile_id, signal_type, metric_name)
    DO UPDATE SET
        mean = EXCLUDED.mean,
        stddev = EXCLUDED.stddev,
        sample_count = EXCLUDED.sample_count,
        updated_at = now();

    -- Calendar: daily meeting count baseline
    INSERT INTO baselines (profile_id, signal_type, metric_name, mean, stddev, sample_count, updated_at)
    SELECT
        exec_id,
        'calendar',
        'daily_meeting_count',
        AVG(daily_count),
        STDDEV(daily_count),
        COUNT(*),
        now()
    FROM (
        SELECT occurred_at::date AS day, COUNT(*) AS daily_count
        FROM tier0_observations
        WHERE profile_id = exec_id AND source = 'calendar' AND occurred_at > cutoff
        GROUP BY occurred_at::date
    ) daily
    HAVING COUNT(*) >= 5
    ON CONFLICT (profile_id, signal_type, metric_name)
    DO UPDATE SET
        mean = EXCLUDED.mean,
        stddev = EXCLUDED.stddev,
        sample_count = EXCLUDED.sample_count,
        updated_at = now();

    -- System: idle duration baseline
    INSERT INTO baselines (profile_id, signal_type, metric_name, mean, stddev, sample_count, updated_at)
    SELECT
        exec_id,
        'system',
        'idle_duration_seconds',
        AVG((raw_data->>'idle_duration_seconds')::float),
        STDDEV((raw_data->>'idle_duration_seconds')::float),
        COUNT(*),
        now()
    FROM tier0_observations
    WHERE profile_id = exec_id
      AND source = 'system'
      AND event_type = 'system.idle_start'
      AND occurred_at > cutoff
      AND (raw_data->>'idle_duration_seconds') IS NOT NULL
    HAVING COUNT(*) >= 5
    ON CONFLICT (profile_id, signal_type, metric_name)
    DO UPDATE SET
        mean = EXCLUDED.mean,
        stddev = EXCLUDED.stddev,
        sample_count = EXCLUDED.sample_count,
        updated_at = now();
END;
$$;
