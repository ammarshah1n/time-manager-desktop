-- Wave 2 B1 — Adds the driver switch that lets the Swift client and the
-- Trigger.dev `graph-delta-sync` task cooperate without racing each other.
--
-- `client`  -> Swift `EmailSyncService` polls Graph via MSAL delegated auth.
-- `server`  -> Trigger.dev tasks (`graph-delta-sync`, `graph-calendar-delta-sync`)
--              poll Graph via app-only client-credentials and write directly
--              to Supabase. The Swift service gates itself off when it reads
--              this column as `server`.

ALTER TABLE public.executives
    ADD COLUMN IF NOT EXISTS email_sync_driver TEXT NOT NULL DEFAULT 'client'
    CHECK (email_sync_driver IN ('client', 'server'));

COMMENT ON COLUMN public.executives.email_sync_driver IS
  'Driver for Graph email/calendar sync. '
  || '`client` = Swift EmailSyncService polls with delegated MSAL token. '
  || '`server` = Trigger.dev graph-delta-sync polls with app-only token. '
  || 'Flipping to `server` disables Swift-side polling on the next start() call.';
