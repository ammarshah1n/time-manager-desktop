-- Wave 1 Task 22 (A4): idempotency for briefing -> recommendations emission.
--
-- A3 (Task 21, migration 20260428_recommendation_outcomes.sql) creates the
-- `recommendations` table as (id UUID PK, briefing_id UUID FK, section_key,
-- task_ref, content_hash, created_at) with no natural uniqueness constraint.
--
-- The legacy `generate-morning-briefing` Edge Function is temporarily patched
-- to emit one recommendations row per briefing section. To make retries safe
-- (Edge Function reruns, cron re-invocations), we need ON CONFLICT target for
-- the upsert path in index.ts. This migration adds that constraint.
--
-- IF NOT EXISTS guards so this migration is harmless regardless of whether
-- A3's table migration lands before or after it. The constraint is only
-- created when the table actually exists.

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM information_schema.tables
        WHERE table_schema = 'public'
          AND table_name = 'recommendations'
    ) THEN
        IF NOT EXISTS (
            SELECT 1
            FROM pg_constraint
            WHERE conname = 'recommendations_briefing_section_unique'
        ) THEN
            ALTER TABLE public.recommendations
                ADD CONSTRAINT recommendations_briefing_section_unique
                UNIQUE (briefing_id, section_key);
        END IF;
    END IF;
END $$;
