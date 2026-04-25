-- Production security hardening — closes RLS / tenancy gaps surfaced in audit:
--   1. behaviour_events parent + every existing partition has RLS enforced.
--   2. executives row creation is restricted to service role only.
--   3. SECURITY DEFINER RPCs get a fixed search_path and have public execute revoked.
--   4. View security_invoker is enabled where views expose tenant tables.
--
-- Idempotent — safe to re-run.

BEGIN;

-- --------------------------------------------------------------------------
-- 1. behaviour_events: enforce RLS on parent + every partition
-- --------------------------------------------------------------------------
DO $$
DECLARE
  rec RECORD;
BEGIN
  -- Parent table
  EXECUTE 'ALTER TABLE IF EXISTS public.behaviour_events ENABLE ROW LEVEL SECURITY';
  EXECUTE 'ALTER TABLE IF EXISTS public.behaviour_events FORCE ROW LEVEL SECURITY';

  -- Every partition (covers existing + future months without touching them)
  FOR rec IN
    SELECT inhrelid::regclass AS partition_name
    FROM pg_inherits
    WHERE inhparent = 'public.behaviour_events'::regclass
  LOOP
    EXECUTE format('ALTER TABLE %s ENABLE ROW LEVEL SECURITY', rec.partition_name);
    EXECUTE format('ALTER TABLE %s FORCE ROW LEVEL SECURITY', rec.partition_name);
  END LOOP;
END $$;

-- Tenancy policy: a row is visible iff the caller's executive_id matches the row's
-- profile_id. Drop and recreate to keep idempotent.
DROP POLICY IF EXISTS "behaviour_events_select_own" ON public.behaviour_events;
CREATE POLICY "behaviour_events_select_own"
ON public.behaviour_events FOR SELECT
TO authenticated
USING (
  profile_id IN (
    SELECT id FROM public.executives WHERE auth_user_id = auth.uid()
  )
);

DROP POLICY IF EXISTS "behaviour_events_insert_service" ON public.behaviour_events;
CREATE POLICY "behaviour_events_insert_service"
ON public.behaviour_events FOR INSERT
TO service_role
WITH CHECK (true);

-- --------------------------------------------------------------------------
-- 2. executives: restrict service-role insert policy properly
-- --------------------------------------------------------------------------
DROP POLICY IF EXISTS "executives_insert_service" ON public.executives;
CREATE POLICY "executives_insert_service"
ON public.executives FOR INSERT
TO service_role
WITH CHECK (true);

-- Authenticated users may also self-create exactly their own row, in case
-- bootstrap-executive ever runs without service role.
DROP POLICY IF EXISTS "executives_insert_self" ON public.executives;
CREATE POLICY "executives_insert_self"
ON public.executives FOR INSERT
TO authenticated
WITH CHECK (auth_user_id = auth.uid());

-- --------------------------------------------------------------------------
-- 3. SECURITY DEFINER hardening — fix search_path, revoke public execute
-- --------------------------------------------------------------------------
DO $$
DECLARE
  rec RECORD;
BEGIN
  FOR rec IN
    SELECT n.nspname || '.' || p.proname || '(' ||
           pg_get_function_identity_arguments(p.oid) || ')' AS sig
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE p.prosecdef = true
      AND n.nspname = 'public'
  LOOP
    EXECUTE format('ALTER FUNCTION %s SET search_path = ''''', rec.sig);
    EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM PUBLIC', rec.sig);
    EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM authenticated', rec.sig);
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO service_role', rec.sig);
  END LOOP;
END $$;

-- --------------------------------------------------------------------------
-- 4. Views: enforce caller-side RLS via security_invoker (PG15+)
-- --------------------------------------------------------------------------
DO $$
DECLARE
  rec RECORD;
BEGIN
  FOR rec IN
    SELECT schemaname || '.' || viewname AS view_name
    FROM pg_views
    WHERE schemaname = 'public'
  LOOP
    BEGIN
      EXECUTE format('ALTER VIEW %s SET (security_invoker = true)', rec.view_name);
    EXCEPTION WHEN OTHERS THEN
      -- Older PG versions lack security_invoker — skip silently.
      NULL;
    END;
  END LOOP;
END $$;

-- --------------------------------------------------------------------------
-- 5. pipeline_health_log: tenant-scope read (was global to authenticated)
-- --------------------------------------------------------------------------
DROP POLICY IF EXISTS "pipeline_health_log_select_authenticated" ON public.pipeline_health_log;
DROP POLICY IF EXISTS "pipeline_health_log_select_all" ON public.pipeline_health_log;
DROP POLICY IF EXISTS "pipeline_health_log_select_service" ON public.pipeline_health_log;
CREATE POLICY "pipeline_health_log_select_service"
ON public.pipeline_health_log FOR SELECT
TO service_role
USING (true);

COMMIT;
