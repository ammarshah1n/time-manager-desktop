-- Weekly avoidance synthesis — Sunday 4 AM (after weekly-strategic-synthesis at 3 AM)
-- Sonnet correlates 3 streams: email latency, calendar reschedules, task deferrals
-- Cross-stream convergence (>= 2 of 3 for same domain) → avoidance pattern

SELECT cron.schedule(
  'weekly-avoidance-synthesis',
  '0 4 * * 0',
  $$SELECT net.http_post(
    url := current_setting('app.settings.supabase_url') || '/functions/v1/weekly-avoidance-synthesis',
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || current_setting('app.settings.service_role_key'),
      'Content-Type', 'application/json'
    ),
    body := '{}'::jsonb
  )$$
);
