-- ============================================================
-- Timed — Real-time Rule Updates via Database Triggers
-- Migration: 20260401000001_realtime_rule_triggers.sql
--
-- Three deterministic rule types update on every behaviour event
-- with zero LLM cost: ordering, avoidance, timing.
-- Replaces weekly-only rule updates from generate-profile-card.
-- ============================================================

-- ============================================================
-- 1. TRIGGER FUNCTION — fires AFTER INSERT on behaviour_events
-- ============================================================

CREATE OR REPLACE FUNCTION public.update_rules_on_event()
RETURNS TRIGGER AS $$
DECLARE
  _ws_id   uuid   := NEW.workspace_id;
  _prof_id uuid   := NEW.profile_id;
  _bucket  text   := NEW.bucket_type;
  _defer_count int;
BEGIN

  -- --------------------------------------------------------
  -- Rule 1: ORDERING — bump confidence of matching ordering
  -- rule when a task is completed in a known bucket.
  -- --------------------------------------------------------
  IF NEW.event_type = 'task_completed' AND _bucket IS NOT NULL THEN
    UPDATE public.behaviour_rules
    SET confidence  = LEAST(confidence + 0.05, 1.0),
        sample_size = sample_size + 1,
        updated_at  = now()
    WHERE workspace_id = _ws_id
      AND profile_id   = _prof_id
      AND rule_type    = 'ordering'
      AND rule_value_json->>'bucket_type' = _bucket
      AND is_active    = true;
  END IF;

  -- --------------------------------------------------------
  -- Rule 2: AVOIDANCE — upsert avoidance rule when a task
  -- has been deferred 2+ times (including the current event).
  -- --------------------------------------------------------
  IF NEW.event_type = 'task_deferred' AND NEW.task_id IS NOT NULL THEN
    SELECT COUNT(*) INTO _defer_count
    FROM public.behaviour_events
    WHERE task_id = NEW.task_id
      AND event_type = 'task_deferred';

    IF _defer_count >= 2 THEN
      INSERT INTO public.behaviour_rules
        (workspace_id, profile_id, rule_key, rule_type, rule_value_json,
         confidence, sample_size, evidence)
      VALUES
        (_ws_id, _prof_id,
         'avoidance.' || _bucket,
         'avoidance',
         jsonb_build_object('bucket_type', _bucket, 'deferred_count', _defer_count),
         LEAST(_defer_count::real / 10.0, 1.0),
         _defer_count,
         'Task deferred ' || _defer_count || ' times')
      ON CONFLICT (workspace_id, profile_id, rule_key)
      DO UPDATE SET
        confidence  = LEAST(EXCLUDED.confidence, 1.0),
        sample_size = EXCLUDED.sample_size,
        evidence    = EXCLUDED.evidence,
        updated_at  = now();
    END IF;
  END IF;

  -- --------------------------------------------------------
  -- Rule 3: TIMING — accumulate hour_of_day completions per
  -- bucket. Confidence grows toward 0.9 as sample_size → 20.
  -- --------------------------------------------------------
  IF NEW.event_type = 'task_completed'
     AND NEW.hour_of_day IS NOT NULL
     AND _bucket IS NOT NULL
  THEN
    INSERT INTO public.behaviour_rules
      (workspace_id, profile_id, rule_key, rule_type, rule_value_json,
       confidence, sample_size, evidence)
    VALUES
      (_ws_id, _prof_id,
       'timing.' || _bucket,
       'timing',
       jsonb_build_object(
         'bucket_type', _bucket,
         'hour_counts', jsonb_build_object(NEW.hour_of_day::text, 1)
       ),
       0.1, 1,
       'Auto-tracked from completion')
    ON CONFLICT (workspace_id, profile_id, rule_key)
    DO UPDATE SET
      rule_value_json = jsonb_set(
        behaviour_rules.rule_value_json,
        ARRAY['hour_counts', NEW.hour_of_day::text],
        to_jsonb(
          COALESCE(
            (behaviour_rules.rule_value_json->'hour_counts'->>NEW.hour_of_day::text)::int,
            0
          ) + 1
        )
      ),
      sample_size = behaviour_rules.sample_size + 1,
      confidence  = LEAST((behaviour_rules.sample_size + 1)::real / 20.0, 0.9),
      updated_at  = now();
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;


-- ============================================================
-- 2. ATTACH TRIGGER to each behaviour_events partition
-- ============================================================
-- Postgres requires triggers on individual partitions, not
-- the parent partitioned table.

CREATE TRIGGER trg_update_rules_on_event
  AFTER INSERT ON public.behaviour_events_2026_03
  FOR EACH ROW EXECUTE FUNCTION public.update_rules_on_event();

CREATE TRIGGER trg_update_rules_on_event
  AFTER INSERT ON public.behaviour_events_2026_04
  FOR EACH ROW EXECUTE FUNCTION public.update_rules_on_event();

CREATE TRIGGER trg_update_rules_on_event
  AFTER INSERT ON public.behaviour_events_2026_05
  FOR EACH ROW EXECUTE FUNCTION public.update_rules_on_event();


-- ============================================================
-- 3. CONFIDENCE DECAY — pg_cron weekly job
-- ============================================================
-- Reduces confidence by 0.1 for any active rule not reinforced
-- in the last 14 days. Floors at 0.0 (never goes negative).
-- Scheduled Sunday 03:00 UTC alongside generate-profile-cards.
--
-- Uncomment after pg_cron is enabled on the Supabase project:
--
-- SELECT cron.schedule(
--   'decay-stale-rules',
--   '0 3 * * 0',
--   $$UPDATE public.behaviour_rules
--     SET confidence = GREATEST(confidence - 0.1, 0.0),
--         updated_at = now()
--     WHERE is_active = true
--       AND updated_at < now() - interval '14 days'$$
-- );
