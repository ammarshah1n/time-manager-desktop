# 04 — Integrations Specification

> **Status refreshed 2026-05-01:** Microsoft Graph remains the verified production path. Gmail/Google Calendar is implemented additively for Ammar; the migration and `voice-llm-proxy` redeploy completed on 2026-04-30, with in-app Gmail sign-in still pending. Supabase CLI verified 39 active remote Edge Functions; local tree has 40 function dirs plus `_shared` because `deepgram-transcribe` is local-only.

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

**Status:** ✅ Implemented additively; pending live Gmail sign-in
**Scope:** Gmail read + Calendar read via Google Sign-In for the Ammar account path

- **GoogleClient.swift:** Google Sign-In lifecycle and access-token provider.
- **GmailClient.swift:** Gmail v1 and Calendar v3 HTTP client.
- **GmailSyncService.swift:** history-cursor polling, 30-day bootstrap, upsert into existing `email_messages`, classify-email trigger, Tier 0 emission.
- **GmailCalendarSyncService.swift:** Google Calendar sync alongside Microsoft calendar.
- **Schema:** `20260430120000_gmail_provider.sql` adds `executives.gmail_linked`, `executives.google_email`, and `connected_accounts`; applied remotely on 2026-04-30.

## Supabase

**Status:** ⚠️ Implemented with readiness gaps
**Project:** fpmjuufefhtlwbfinxlx

### Client
- **SupabaseClient.swift:** 764 lines, dependency injection via TCA DependencyKey
- 11 row types, 20+ operations (tasks, emails, plans, behaviour rules,
  sender rules, voice captures, waiting items, pipeline runs, bucket stats)

### Edge Functions (39 active remote — verified `supabase functions list` 2026-04-30)
Legacy triage / pipeline: `classify-email`, `detect-reply`, `estimate-time`, `generate-daily-plan`, `generate-profile-card`, `generate-relationship-card`, `graph-webhook`, `parse-voice-capture`, `renew-graph-subscriptions`, `score-observation-realtime`.

`generate-embedding` remains in the local function tree but is disabled and returns dimension `0`. `deepgram-transcribe` also remains local-only as a parked batch-ASR proxy; live `ConversationView` speech ingress uses `deepgram-token` + Deepgram WSS.

Intelligence engine (per NO-COST-CAP-AUDIT): `acb-refresh`, `bootstrap-executive`, `extract-voice-features`, `generate-morning-briefing`, `monthly-trait-synthesis`, `multi-agent-council`, `nightly-bias-detection`, `nightly-consolidation-full`, `nightly-consolidation-refresh`, `nightly-phase1`, `nightly-phase2`, `pipeline-health-check`, `poll-batch-results`, `thin-slice-inference`, `weekly-avoidance-synthesis`, `weekly-pattern-detection`, `weekly-pruning`, `weekly-strategic-synthesis`.

### Auth
- **AuthService.swift:** Supabase Auth with Microsoft OAuth and additive Google OAuth
- Workspace/profile bootstrap on first sign-in (`bootstrapExecutive` calls EF `bootstrap-executive`)
- Graph token acquisition for API calls (dual token: Supabase JWT + MSAL token)
- Google token acquisition for Gmail/Calendar (`makeGoogleTokenProvider`)

## iOS, Share, Widgets, Live Activities

**Status:** ⚠️ Scaffold / simulator-build only

- TimediOS builds, but primary tabs still render `PlaceholderPane` destinations and the orb sheet passes empty task/calendar state.
- BGTask handlers default to no-op workers; APNs token forwarding has no installed sink; silent push currently returns `.noData`.
- The Share extension appends to `share-queue.jsonl`, but the main app does not yet drain that queue.
- Widget snapshot read/write helpers exist, but the main app does not call `SharedSnapshot.write`.
- Live Activity UI exists, but no main-app ActivityKit coordinator starts, updates, or ends it.

## Apple Speech Framework

**Status:** ✅ Implemented
- **VoiceCaptureService.swift:** SFSpeechRecognizer + AVAudioEngine for live
  transcription. Local, on-device, no cloud processing.
- **SpeechService.swift:** ElevenLabs TTS via `elevenlabs-tts-proxy`; no Apple TTS fallback.

## Embeddings

**Status:** ⚠️ Mixed. Graphiti/skill-library use Voyage embeddings, but the app-facing `generate-embedding` Edge Function is disabled and returns empty embeddings with dimension `0`.

| Tier | Model | Dimensions | Use |
|------|-------|------------|-----|
| Tier 0 (raw observations) | Voyage `voyage-3` | 1024 | High-volume, recency-weighted |
| Tier 1–3 (daily summaries, signatures, traits) | OpenAI `text-embedding-3-large` | 3072 | Narrative + cross-signature discrimination |

- App path: `EmbeddingService` calls `generate-embedding`, so app MemoryStore embeddings are not production-ready until that function is re-enabled or replaced.
- Service path: Graphiti/skill-library still use Voyage-backed embedding flows outside this disabled function.
- API keys: `VOYAGE_API_KEY`, `OPENAI_API_KEY` in Supabase secrets
- HNSW indexes dimensioned per tier (`m=32/48/64`, `ef_construction=200/256/300`)
- **Superseded:** Jina v3 1024-dim was the original choice; replaced per NO-COST-CAP-AUDIT 2026-04-10

## Future Integrations (not started)
- Apple HealthKit (HRV, sleep, activity — with user authorisation)
- NSWorkspace notifications (app usage patterns, screen time)
- Apple EventKit (local calendar — currently Outlook-only)
