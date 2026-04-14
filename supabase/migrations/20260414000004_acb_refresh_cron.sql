-- Continuous ACB refresh — 3x daily during business hours (weekdays)
-- Sonnet mid-day updates at 9am, 1pm, 5pm. Opus full rebuild at 2am (existing nightly).
-- Two-call architecture per refresh: generation + adversarial critique.

SELECT cron.schedule(
  'acb-refresh-morning',
  '0 9 * * 1-5',
  $$SELECT net.http_post(
    url := current_setting('app.settings.supabase_url') || '/functions/v1/acb-refresh',
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || current_setting('app.settings.service_role_key'),
      'Content-Type', 'application/json'
    ),
    body := '{}'::jsonb
  )$$
);

SELECT cron.schedule(
  'acb-refresh-midday',
  '0 13 * * 1-5',
  $$SELECT net.http_post(
    url := current_setting('app.settings.supabase_url') || '/functions/v1/acb-refresh',
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || current_setting('app.settings.service_role_key'),
      'Content-Type', 'application/json'
    ),
    body := '{}'::jsonb
  )$$
);

SELECT cron.schedule(
  'acb-refresh-evening',
  '0 17 * * 1-5',
  $$SELECT net.http_post(
    url := current_setting('app.settings.supabase_url') || '/functions/v1/acb-refresh',
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || current_setting('app.settings.service_role_key'),
      'Content-Type', 'application/json'
    ),
    body := '{}'::jsonb
  )$$
);
