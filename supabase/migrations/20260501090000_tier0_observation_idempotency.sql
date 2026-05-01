-- Add deterministic Tier 0 idempotency for entity-backed observations.
-- This collapses duplicate rows emitted by Swift services and database
-- bridges for the same email/calendar entity while leaving entity-less
-- telemetry append-only.

ALTER TABLE public.tier0_observations
ADD COLUMN IF NOT EXISTS idempotency_key TEXT;

UPDATE public.tier0_observations
SET idempotency_key = concat_ws(
  ':',
  profile_id::text,
  source,
  entity_type,
  entity_id::text
)
WHERE idempotency_key IS NULL
  AND entity_id IS NOT NULL
  AND entity_type IS NOT NULL;

WITH ranked AS (
  SELECT
    id,
    row_number() OVER (
      PARTITION BY idempotency_key
      ORDER BY
        (position('.' in event_type) > 0) DESC,
        created_at DESC,
        id DESC
    ) AS row_number
  FROM public.tier0_observations
  WHERE idempotency_key IS NOT NULL
)
DELETE FROM public.tier0_observations obs
USING ranked
WHERE obs.id = ranked.id
  AND ranked.row_number > 1;

CREATE UNIQUE INDEX IF NOT EXISTS tier0_observations_idempotency_key_idx
ON public.tier0_observations (idempotency_key);

CREATE OR REPLACE FUNCTION public.email_message_to_tier0()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_subject_clean text := LEFT(COALESCE(NEW.subject, '(no subject)'), 120);
  v_snippet_clean text := LEFT(COALESCE(NEW.snippet, ''), 280);
  v_summary text;
  v_idempotency_key text;
BEGIN
  v_summary := format(
    'Email from %s: %s',
    COALESCE(NEW.from_name, NEW.from_address),
    v_subject_clean
  );
  v_idempotency_key := concat_ws(
    ':',
    NEW.workspace_id::text,
    'email',
    'email_message',
    NEW.id::text
  );

  INSERT INTO public.tier0_observations (
    profile_id,
    occurred_at,
    source,
    event_type,
    entity_id,
    entity_type,
    summary,
    raw_data,
    idempotency_key,
    importance_score
  ) VALUES (
    NEW.workspace_id,
    NEW.received_at,
    'email',
    'email_received',
    NEW.id,
    'email_message',
    v_summary,
    jsonb_build_object(
      'email_message_id',  NEW.id,
      'from_address',      NEW.from_address,
      'from_name',         NEW.from_name,
      'subject',           v_subject_clean,
      'snippet',           v_snippet_clean,
      'graph_message_id',  NEW.graph_message_id,
      'graph_thread_id',   NEW.graph_thread_id,
      'is_cc_fyi',         NEW.is_cc_fyi,
      'received_at',       NEW.received_at
    ),
    v_idempotency_key,
    0.5
  )
  ON CONFLICT (idempotency_key) DO NOTHING;

  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'email_message_to_tier0 failed for id=%: %', NEW.id, SQLERRM;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.calendar_observation_to_tier0()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_title text := LEFT(COALESCE(NEW.title, '(untitled meeting)'), 120);
  v_prefix text := '';
  v_summary text;
  v_event_type text;
  v_idempotency_key text;
BEGIN
  IF NEW.was_cancelled THEN
    v_prefix := '[CANCELLED] ';
  ELSIF NEW.was_rescheduled THEN
    v_prefix := '[RESCHEDULED] ';
  END IF;

  v_summary := format(
    '%sCalendar event: %s (attendees=%s)',
    v_prefix,
    v_title,
    COALESCE(NEW.attendee_count, 0)
  );
  v_event_type := CASE
    WHEN NEW.was_cancelled THEN 'meeting_cancelled'
    WHEN NEW.was_rescheduled THEN 'meeting_rescheduled'
    ELSE 'meeting_observed'
  END;
  v_idempotency_key := concat_ws(
    ':',
    NEW.executive_id::text,
    'calendar',
    'calendar_observation',
    NEW.id::text
  );

  INSERT INTO public.tier0_observations (
    profile_id,
    occurred_at,
    source,
    event_type,
    entity_id,
    entity_type,
    summary,
    raw_data,
    idempotency_key,
    importance_score
  ) VALUES (
    NEW.executive_id,
    COALESCE(NEW.event_start, NEW.observed_at),
    'calendar',
    v_event_type,
    NEW.id,
    'calendar_observation',
    v_summary,
    jsonb_build_object(
      'calendar_observation_id', NEW.id,
      'title',                   v_title,
      'description',             LEFT(COALESCE(NEW.description, ''), 500),
      'event_start',             NEW.event_start,
      'event_end',               NEW.event_end,
      'attendee_count',          NEW.attendee_count,
      'organiser_is_self',       NEW.organiser_is_self,
      'response_status',         NEW.response_status,
      'was_cancelled',           NEW.was_cancelled,
      'was_rescheduled',         NEW.was_rescheduled,
      'graph_event_id',          NEW.graph_event_id
    ),
    v_idempotency_key,
    0.5
  )
  ON CONFLICT (idempotency_key) DO NOTHING;

  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'calendar_observation_to_tier0 failed for id=%: %', NEW.id, SQLERRM;
  RETURN NEW;
END;
$$;
