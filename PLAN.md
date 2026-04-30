# PLAN.md — Timed
<!-- New session: read this → HANDOFF.md first entry → BUILD_STATE.md top block → verify infra with CLI if unsure. -->

## CURRENT STATE (2026-04-30)
- **Branch:** `unified`, ahead of `origin/unified` by 2 local commits at prime time.
- **Core product:** TimedKit + TimedMacApp + TimediOS scaffold are all on one trunk.
- **Microsoft path:** end-to-end verified 2026-04-29 with real Outlook data reaching Tier 0 and the orb context.
- **Gmail path:** additive Gmail + Google Calendar code shipped locally in commit `4e5cf9e`; Microsoft path intentionally untouched.
- **Backend:** Supabase CLI verified 39 active remote Edge Functions on 2026-04-30; local tree has 40 function dirs plus `_shared`.
- **Migrations:** 63 remote migrations applied; local `20260430120000_gmail_provider.sql` is pending remote apply.
- **Trigger.dev:** Hobby tier upgraded; Prod deploy `20260429.2` live with 13 detected tasks / 9 schedules.
- **Graphiti:** backfill implementation is WIP at `2222bb4`, parked on Voyage billing.
- **Security hardening:** multiple Edge Function hardening edits are dirty and uncommitted; do not mix unrelated work into them.

## ACTIVE PRIORITY
1. Apply `20260430120000_gmail_provider.sql` to `fpmjuufefhtlwbfinxlx`.
2. Redeploy `voice-llm-proxy` so the Gmail inbox OR-gate is live.
3. Launch Timed and connect Gmail using the only current Google test user, `5066sim@gmail.com`.
4. Resolve Voyage billing, then run/monitor `graphiti-backfill`.
5. Finish, review, or explicitly park the security-hardening WIP.

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
