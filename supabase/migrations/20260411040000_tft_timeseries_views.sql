-- TFT-compatible time-series views for future Temporal Fusion Transformer training
-- These views structure existing tier0_observations for ML training data accumulation

-- Email signal time series (hourly buckets)
CREATE OR REPLACE VIEW tft_email_hourly AS
SELECT
    profile_id,
    date_trunc('hour', occurred_at) AS bucket,
    EXTRACT(DOW FROM occurred_at)::int AS day_of_week,
    EXTRACT(MONTH FROM occurred_at)::int AS month,
    COUNT(*) FILTER (WHERE event_type = 'email.received') AS emails_received,
    COUNT(*) FILTER (WHERE event_type = 'email.sent') AS emails_sent,
    COUNT(*) FILTER (WHERE event_type = 'email.response_sent') AS responses_sent,
    AVG((raw_data->>'response_time_sec')::float) FILTER (WHERE event_type = 'email.response_sent') AS avg_response_latency,
    MAX((raw_data->>'thread_depth')::int) AS max_thread_depth
FROM tier0_observations
WHERE source = 'email'
GROUP BY profile_id, date_trunc('hour', occurred_at), EXTRACT(DOW FROM occurred_at), EXTRACT(MONTH FROM occurred_at);

-- Calendar signal time series (daily buckets)
CREATE OR REPLACE VIEW tft_calendar_daily AS
SELECT
    profile_id,
    occurred_at::date AS day,
    EXTRACT(DOW FROM occurred_at)::int AS day_of_week,
    EXTRACT(MONTH FROM occurred_at)::int AS month,
    COUNT(*) AS total_events,
    COUNT(*) FILTER (WHERE event_type = 'calendar.cancelled') AS cancellations,
    COUNT(*) FILTER (WHERE event_type = 'calendar.rescheduled') AS reschedules,
    AVG((raw_data->>'attendee_count')::int) AS avg_attendee_count,
    AVG((raw_data->>'duration_minutes')::int) AS avg_duration_minutes,
    SUM(CASE WHEN (raw_data->>'is_back_to_back')::boolean THEN 1 ELSE 0 END) AS back_to_back_count
FROM tier0_observations
WHERE source = 'calendar'
GROUP BY profile_id, occurred_at::date, EXTRACT(DOW FROM occurred_at), EXTRACT(MONTH FROM occurred_at);

-- App usage time series (hourly buckets)
CREATE OR REPLACE VIEW tft_app_usage_hourly AS
SELECT
    profile_id,
    date_trunc('hour', occurred_at) AS bucket,
    EXTRACT(DOW FROM occurred_at)::int AS day_of_week,
    EXTRACT(MONTH FROM occurred_at)::int AS month,
    COUNT(*) AS app_switches,
    COUNT(DISTINCT raw_data->>'bundle_id') AS unique_apps,
    AVG((raw_data->>'focus_duration_seconds')::float) AS avg_focus_duration,
    COUNT(*) FILTER (WHERE raw_data->>'app_category' = 'communication') AS communication_sessions,
    COUNT(*) FILTER (WHERE raw_data->>'app_category' = 'coding') AS coding_sessions,
    COUNT(*) FILTER (WHERE raw_data->>'app_category' = 'browsing') AS browsing_sessions
FROM tier0_observations
WHERE source = 'app_usage'
GROUP BY profile_id, date_trunc('hour', occurred_at), EXTRACT(DOW FROM occurred_at), EXTRACT(MONTH FROM occurred_at);

-- System idle time series (daily buckets)
CREATE OR REPLACE VIEW tft_system_daily AS
SELECT
    profile_id,
    occurred_at::date AS day,
    EXTRACT(DOW FROM occurred_at)::int AS day_of_week,
    COUNT(*) FILTER (WHERE event_type = 'system.idle_start') AS idle_starts,
    COUNT(*) FILTER (WHERE event_type = 'system.idle_end') AS idle_ends,
    AVG((raw_data->>'idle_duration_seconds')::float) FILTER (WHERE event_type = 'system.idle_start') AS avg_idle_duration
FROM tier0_observations
WHERE source = 'system'
GROUP BY profile_id, occurred_at::date, EXTRACT(DOW FROM occurred_at);
