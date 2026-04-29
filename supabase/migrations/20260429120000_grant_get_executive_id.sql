-- Grant EXECUTE on get_executive_id() overloads to the authenticated role.
-- Both the zero-arg and (uuid) overloads are SECURITY DEFINER but ship without
-- explicit grants, which makes RLS policies that call them fail with
-- `permission denied for function get_executive_id` for client JWT writes.
-- Service role bypasses RLS so EFs are unaffected; only client-side writes
-- (CalendarSyncService.persistCalendarObservation, EmailSyncService email
-- upserts, etc) trip this.
--
-- Surfaced 2026-04-29 when CalendarSyncService logged
-- `permission denied for function get_executive_id` after a successful
-- Graph fetch of one calendar event for executive 9ea0d114-...

GRANT EXECUTE ON FUNCTION public.get_executive_id() TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_executive_id(uuid) TO authenticated;
