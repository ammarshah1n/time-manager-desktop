# 04 — Integrations Specification

> **Status refreshed 2026-04-30:** Microsoft Graph remains the verified production path. Gmail/Google Calendar is now implemented additively for Ammar, but its migration and `voice-llm-proxy` redeploy are still pending. Supabase CLI verified 39 active remote Edge Functions; local tree has 40 function dirs plus `_shared`.

## Microsoft Graph (Outlook Email + Calendar)

**Status:** ✅ Fully implemented
**Scope:** Read-only (Mail.Read, Calendars.Read, offline_access)

### Email Integration
- **GraphClient.swift:** MSAL auth (silent + interactive), delta email sync,
  message move, folder CRUD, webhook registration/renewal
- **EmailSyncService.swift:** Actor-based background poller. Delta sync,
  folder-move detection for sender rule learning, reply latency social graph,
  Edge Function trigger for classification
- **Auth:** Azure App Registration with hardcoded client config + env var overrides

### Calendar Integration
- **CalendarSyncService.swift:** Actor. Fetches Outlook events, converts to
  CalendarBlocks, detects free-time gaps
- **CalendarBlock model:** id, title, start, end, category (focus/meeting/admin/break/transit)

### Webhook Support
- Graph webhook registration for real-time email notifications
- Renewal flow implemented in Edge Function (renew-graph-subscriptions)

## Google (Gmail + Google Calendar)

**Status:** ✅ Implemented additively; pending remote migration + live Gmail sign-in
**Scope:** Gmail read + Calendar read via Google Sign-In for the Ammar account path

- **GoogleClient.swift:** Google Sign-In lifecycle and access-token provider.
- **GmailClient.swift:** Gmail v1 and Calendar v3 HTTP client.
- **GmailSyncService.swift:** history-cursor polling, 30-day bootstrap, upsert into existing `email_messages`, classify-email trigger, Tier 0 emission.
- **GmailCalendarSyncService.swift:** Google Calendar sync alongside Microsoft calendar.
- **Schema:** `20260430120000_gmail_provider.sql` adds `executives.gmail_linked`, `executives.google_email`, and `connected_accounts`; pending remote apply as of 2026-04-30.

## Supabase

**Status:** ✅ Fully implemented
**Project:** fpmjuufefhtlwbfinxlx

### Client
- **SupabaseClient.swift:** 764 lines, dependency injection via TCA DependencyKey
- 11 row types, 20+ operations (tasks, emails, plans, behaviour rules,
  sender rules, voice captures, waiting items, pipeline runs, bucket stats)

### Edge Functions (39 active remote — verified `supabase functions list` 2026-04-30)
Legacy triage / pipeline: `classify-email`, `detect-reply`, `estimate-time`, `generate-daily-plan`, `generate-embedding`, `generate-profile-card`, `generate-relationship-card`, `graph-webhook`, `parse-voice-capture`, `renew-graph-subscriptions`, `score-observation-realtime`.

Intelligence engine (per NO-COST-CAP-AUDIT): `acb-refresh`, `bootstrap-executive`, `extract-voice-features`, `generate-morning-briefing`, `monthly-trait-synthesis`, `multi-agent-council`, `nightly-bias-detection`, `nightly-consolidation-full`, `nightly-consolidation-refresh`, `nightly-phase1`, `nightly-phase2`, `pipeline-health-check`, `poll-batch-results`, `thin-slice-inference`, `weekly-avoidance-synthesis`, `weekly-pattern-detection`, `weekly-pruning`, `weekly-strategic-synthesis`.

### Auth
- **AuthService.swift:** Supabase Auth with Microsoft OAuth and additive Google OAuth
- Workspace/profile bootstrap on first sign-in (`bootstrapExecutive` calls EF `bootstrap-executive`)
- Graph token acquisition for API calls (dual token: Supabase JWT + MSAL token)
- Google token acquisition for Gmail/Calendar (`makeGoogleTokenProvider`)

## Apple Speech Framework

**Status:** ✅ Implemented
- **VoiceCaptureService.swift:** SFSpeechRecognizer + AVAudioEngine for live
  transcription. Local, on-device, no cloud processing.
- **SpeechService.swift:** AVSpeechSynthesizer for TTS. British English voice.

## Embeddings — Dual Provider

**Status:** ✅ Configured in Edge Functions; `generate-embedding` is active remotely as of the 2026-04-30 Supabase CLI check

| Tier | Model | Dimensions | Use |
|------|-------|------------|-----|
| Tier 0 (raw observations) | Voyage `voyage-3` | 1024 | High-volume, recency-weighted |
| Tier 1–3 (daily summaries, signatures, traits) | OpenAI `text-embedding-3-large` | 3072 | Narrative + cross-signature discrimination |

- Used by: `generate-embedding`, plus downstream retrieval in nightly engine functions
- API keys: `VOYAGE_API_KEY`, `OPENAI_API_KEY` in Supabase secrets
- HNSW indexes dimensioned per tier (`m=32/48/64`, `ef_construction=200/256/300`)
- **Superseded:** Jina v3 1024-dim was the original choice; replaced per NO-COST-CAP-AUDIT 2026-04-10

## Future Integrations (not started)
- Apple HealthKit (HRV, sleep, activity — with user authorisation)
- NSWorkspace notifications (app usage patterns, screen time)
- Apple EventKit (local calendar — currently Outlook-only)
