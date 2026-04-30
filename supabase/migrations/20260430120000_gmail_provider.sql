-- Gmail provider support (parallel to Microsoft's outlook_linked).
--
-- Adds:
--   1. executives.gmail_linked         — flag flipped on first GmailSync success.
--   2. executives.google_email         — the Google account currently linked.
--   3. connected_accounts              — per-provider audit table (future-facing).
--
-- The orb's `readInboxSnapshot` will gate on (outlook_linked OR gmail_linked)
-- so a Gmail-only user gets a real inbox snapshot instead of a confidence-
-- destroying "your inbox is clear" lie.
--
-- Intentionally does NOT add a `provider` column to email_messages: Gmail and
-- Microsoft Graph message ID formats don't collide in practice and unifying
-- under email_messages keeps the orb's existing search_emails tool provider-
-- agnostic without changes.

ALTER TABLE public.executives
    ADD COLUMN IF NOT EXISTS gmail_linked BOOLEAN NOT NULL DEFAULT false;

ALTER TABLE public.executives
    ADD COLUMN IF NOT EXISTS google_email TEXT;

COMMENT ON COLUMN public.executives.gmail_linked IS
  'True when at least one successful Gmail history-sync has completed. Flipped by GmailSyncService on first successful poll. Read by voice-llm-proxy alongside outlook_linked to gate inbox context blocks.';

COMMENT ON COLUMN public.executives.google_email IS
  'Email address of the linked Google account (Gmail + Calendar). May differ from the executive''s primary email if they signed in to a personal Google account distinct from their Microsoft work account.';

-- ============================================================
-- connected_accounts — per-provider linkage audit table.
-- ============================================================

CREATE TABLE IF NOT EXISTS public.connected_accounts (
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    executive_id    uuid NOT NULL REFERENCES public.executives(id) ON DELETE CASCADE,
    provider        text NOT NULL CHECK (provider IN ('microsoft', 'google')),
    account_email   text NOT NULL,
    linked_at       timestamptz NOT NULL DEFAULT now(),
    revoked_at      timestamptz,
    created_at      timestamptz NOT NULL DEFAULT now(),
    UNIQUE (executive_id, provider, account_email)
);

CREATE INDEX IF NOT EXISTS connected_accounts_executive_idx
    ON public.connected_accounts (executive_id, provider);

ALTER TABLE public.connected_accounts ENABLE ROW LEVEL SECURITY;

-- Self-read policy: an authenticated user can see only their own connected
-- accounts. Service role (Edge Functions) bypasses RLS as usual.
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
         WHERE schemaname = 'public'
           AND tablename = 'connected_accounts'
           AND policyname = 'connected_accounts_owner_select'
    ) THEN
        CREATE POLICY connected_accounts_owner_select
            ON public.connected_accounts
            FOR SELECT
            TO authenticated
            USING (executive_id = public.get_executive_id());
    END IF;
END $$;

COMMENT ON TABLE public.connected_accounts IS
  'Audit table tracking each (executive, provider, account_email) link. Future-facing: voice-llm-proxy will eventually query this UNION instead of the per-provider boolean flags. For now the boolean flags on executives remain authoritative.';
