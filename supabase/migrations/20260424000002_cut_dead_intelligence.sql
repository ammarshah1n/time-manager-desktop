-- Cut dead intelligence — per Dish-Me-Up Ship-It.md
--
-- Each cron below produces signal that Dish Me Up's Opus system prompt does not
-- currently consume. Unschedule them until a consumer is wired. The cron jobs
-- are no-longer-firing, but the underlying SQL and Edge Functions remain
-- deployable — re-enable with cron.schedule() when you wire a reader.

DO $$
BEGIN
  -- Skip silently if the cron is not currently scheduled (fresh-db idempotency).
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'nightly-bias-detection')   THEN PERFORM cron.unschedule('nightly-bias-detection');   END IF;
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'acb-refresh-morning')      THEN PERFORM cron.unschedule('acb-refresh-morning');      END IF;
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'acb-refresh-midday')       THEN PERFORM cron.unschedule('acb-refresh-midday');       END IF;
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'weekly-avoidance-synthesis') THEN PERFORM cron.unschedule('weekly-avoidance-synthesis'); END IF;
END $$;

-- Keep: weekly-strategic-synthesis (Sunday 3am Opus) — feeds Dish Me Up ACB
-- summary system prompt. Keep: acb-refresh-evening (single nightly Sonnet pass).

COMMENT ON SCHEMA public IS
  'Cron inventory as of 20260424: keep weekly-strategic-synthesis + acb-refresh-evening. Rest disabled until a Dish Me Up consumer reads them.';
