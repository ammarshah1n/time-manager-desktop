# PLAN.md — Timed
<!-- New session: read this → HANDOFF.md first entry → BUILD_STATE.md top block → verify infra with CLI if unsure. -->

## CURRENT STATE (2026-04-30)
- **Branch:** `unified` is the single active trunk.
- **Core product:** TimedKit + TimedMacApp + TimediOS scaffold are all on one trunk.
- **Microsoft path:** end-to-end verified 2026-04-29 with real Outlook data reaching Tier 0 and the orb context.
- **Gmail path:** additive Gmail + Google Calendar code shipped locally in commit `4e5cf9e`; Microsoft path intentionally untouched.
- **Backend:** Supabase CLI verified 39 active remote Edge Functions on 2026-04-30; local tree has 40 function dirs plus `_shared`.
- **Migrations:** 64 remote migrations applied, including `20260430120000_gmail_provider.sql`.
- **Trigger.dev:** Hobby tier upgraded; Prod deploy `20260429.2` live with 13 detected tasks / 9 schedules.
- **Graphiti:** one-shot `graphiti-backfill` completed in Trigger.dev Prod run `run_cmol21ysj5ohl0unbrlg495f2`; emitted 2 Tier 0 observations.
- **Security hardening:** Edge Function auth/CORS hardening is committed and deployed; unauthenticated cron smoke call returns 401.

## ACTIVE PRIORITY
1. Launch Timed and connect Gmail using the only current Google test user, `5066sim@gmail.com`.
2. Resume Apple Developer enrollment for notarised Mac/iOS delivery.
3. Decide whether optional local-only `deepgram-transcribe` should be deployed or kept parked.

## FILE QUICK REF
- App shell: `Sources/TimedKit/AppEntry/TimedAppShell.swift`
- Mac app entry: `Sources/TimedMacApp/TimedMacAppMain.swift`
- iOS app entry: `Platforms/iOS/TimediOSAppMain.swift`
- Auth: `Sources/TimedKit/Core/Services/AuthService.swift`
- Microsoft: `Sources/TimedKit/Core/Clients/GraphClient.swift`, `Sources/TimedKit/Core/Services/EmailSyncService.swift`, `Sources/TimedKit/Core/Services/CalendarSyncService.swift`
- Gmail: `Sources/TimedKit/Core/Clients/GoogleClient.swift`, `Sources/TimedKit/Core/Clients/GmailClient.swift`, `Sources/TimedKit/Core/Services/GmailSyncService.swift`, `Sources/TimedKit/Core/Services/GmailCalendarSyncService.swift`
- Planning: `Sources/TimedKit/Core/Services/PlanningEngine.swift`
- Supabase functions: `supabase/functions/`
- Trigger tasks: `trigger/src/tasks/`
- Current status: `HANDOFF.md`, `BUILD_STATE.md`

## BLOCKED / WATCH
- Apple Developer enrollment still blocks notarised Mac DMG and iOS TestFlight.
- `deepgram-transcribe` exists locally but was not in the 2026-04-30 remote function list.
- `BUILD_STATE.md` and `HANDOFF.md` are source of truth; older docs under `docs/` can be historical.
