-- Bridge email_messages and calendar_observations into tier0_observations.
--
-- Without this, the nightly engine (nrem-entity-extraction → Graphiti) and the
-- 9am/1pm/5pm ACB refresh both read from tier0_observations and see no inbox
-- or calendar signal at all — even though Graph delta sync is populating
-- email_messages and calendar_observations every minute / five minutes.
--
-- Fired AFTER INSERT only. The realtime importance score (rt_score) is left
-- NULL so score-observation-realtime can pick the row up on its next pass.
-- Updates to email_messages (e.g. classify-email setting triage_bucket) do
-- NOT create new tier0 rows — that would double-count.

-- ============================================================
-- email_messages → tier0_observations
-- ============================================================

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
BEGIN
  v_summary := format(
    'Email from %s: %s',
    COALESCE(NEW.from_name, NEW.from_address),
    v_subject_clean
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
    importance_score
  ) VALUES (
    NEW.workspace_id,                       -- single-tenant: workspace_id == executive_id
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
    0.5
  );

  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  -- Never let an observability bridge break the primary write path. If the
  -- tier0 insert fails (e.g. RLS quirk during a bulk backfill), log and move
  -- on — the email row is still saved and the nightly engine will catch up
  -- on the next sweep through email_messages.
  RAISE WARNING 'email_message_to_tier0 failed for id=%: %', NEW.id, SQLERRM;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS email_message_to_tier0_trg ON public.email_messages;
CREATE TRIGGER email_message_to_tier0_trg
  AFTER INSERT ON public.email_messages
  FOR EACH ROW
  EXECUTE FUNCTION public.email_message_to_tier0();

-- ============================================================
-- calendar_observations → tier0_observations
-- ============================================================

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

  INSERT INTO public.tier0_observations (
    profile_id,
    occurred_at,
    source,
    event_type,
    entity_id,
    entity_type,
    summary,
    raw_data,
    importance_score
  ) VALUES (
    NEW.executive_id,
    COALESCE(NEW.event_start, NEW.observed_at),
    'calendar',
    CASE
      WHEN NEW.was_cancelled  THEN 'meeting_cancelled'
      WHEN NEW.was_rescheduled THEN 'meeting_rescheduled'
      ELSE                          'meeting_observed'
    END,
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
    0.5
  );

  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'calendar_observation_to_tier0 failed for id=%: %', NEW.id, SQLERRM;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS calendar_observation_to_tier0_trg ON public.calendar_observations;
CREATE TRIGGER calendar_observation_to_tier0_trg
  AFTER INSERT ON public.calendar_observations
  FOR EACH ROW
  EXECUTE FUNCTION public.calendar_observation_to_tier0();
