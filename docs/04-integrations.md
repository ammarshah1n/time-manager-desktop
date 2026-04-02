# 04 — Integrations Specification

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

## Supabase

**Status:** ✅ Fully implemented
**Project:** fpmjuufefhtlwbfinxlx

### Client
- **SupabaseClient.swift:** 764 lines, dependency injection via TCA DependencyKey
- 11 row types, 20+ operations (tasks, emails, plans, behaviour rules,
  sender rules, voice captures, waiting items, pipeline runs, bucket stats)

### Edge Functions (9 deployed)
| Function | Purpose |
|----------|---------|
| classify-email | Claude Haiku email triage classification |
| detect-reply | Reply detection for WOO tracking |
| estimate-time | Claude Sonnet time estimation |
| generate-daily-plan | Plan generation (to be replaced by intelligence engine) |
| generate-profile-card | Claude Opus executive profile card |
| graph-webhook | Microsoft Graph webhook receiver |
| parse-voice-capture | Voice transcript parsing |
| renew-graph-subscriptions | Graph webhook renewal cron |

### Auth
- **AuthService.swift:** Supabase Auth with Microsoft OAuth provider
- Workspace/profile bootstrap on first sign-in
- Graph token acquisition for API calls
- ⚠️ AuthService creates its own SupabaseClient (violates DI — needs refactor)

## Apple Speech Framework

**Status:** ✅ Implemented
- **VoiceCaptureService.swift:** SFSpeechRecognizer + AVAudioEngine for live
  transcription. Local, on-device, no cloud processing.
- **SpeechService.swift:** AVSpeechSynthesizer for TTS. British English voice.

## Jina AI Embeddings

**Status:** ✅ Configured in Edge Functions
- Model: jina-embeddings-v3
- Dimensions: 1024
- Used in: classify-email, estimate-time Edge Functions
- API key stored in Supabase secrets + 1Password

## Future Integrations (not started)
- Apple HealthKit (HRV, sleep, activity — with user authorisation)
- NSWorkspace notifications (app usage patterns, screen time)
- Apple EventKit (local calendar — currently Outlook-only)
