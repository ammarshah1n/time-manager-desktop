-- executives.outlook_linked
--
-- Tracks whether the executive has a working Microsoft Graph link (i.e., at
-- least one successful email/calendar delta sync has completed). Without this
-- column, the orb's `readInboxSnapshot` returns `{ unread24h: 0, recentInbox: [] }`
-- when Outlook isn't connected — which the LLM happily summarises as "your inbox
-- is clear", a confidence-destroying lie. With this flag, the orb branches:
-- false → "Outlook has not been linked yet — email context unavailable", true →
-- the snapshot proceeds as before.

ALTER TABLE public.executives
    ADD COLUMN IF NOT EXISTS outlook_linked BOOLEAN NOT NULL DEFAULT false;

COMMENT ON COLUMN public.executives.outlook_linked IS
  'True when at least one successful Microsoft Graph email or calendar sync has completed for this executive. Flipped to true by EmailSyncService / CalendarSyncService on first successful sync. Read by voice-llm-proxy and orb-conversation to gate inbox context blocks.';
