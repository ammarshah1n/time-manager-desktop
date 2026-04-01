# PLAN.md — Timed
<!-- New session: read this → then CHANGELOG.md last entry → working in 30 seconds -->
<!-- Max 50 lines. Archive overflow to CHANGELOG.md -->

## CURRENT STATE (2026-03-31)
- **UI complete** — 10 screens, task detail modal, calendar drag-to-create, batch ops, voice capture
- **Local persistence** — DataStore actor + JSON, survives restarts
- **Backend LIVE** — Supabase project `fpmjuufefhtlwbfinxlx`, 8 edge functions deployed, all secrets set
- **Azure LIVE** — App registration done, MSAL OAuth in GraphClient works (silent + interactive)
- **Tests pass** — 49/49 via swift-testing
- **Builds clean** — `swift build` → 0 errors

## WHAT ACTUALLY WORKS END-TO-END
- FR-01 Email Triage: classify-email edge function + GraphClient.fetchDeltaMessages — **real code, not stubs**
- FR-02 Action/Read: TriagePane button classification → creates TimedTask per bucket
- FR-04 Time Estimation: estimate-time edge function (historical + Claude Sonnet fallback)
- FR-05 Dish Me Up: PlanningEngine knapsack + DishMeUpSheet UI — **fully working**
- FR-09 Voice Input: Apple Speech + TranscriptParser → tasks — **fully working**
- FR-11 Quick Capture: TodayPane inline add + CapturePane text/voice — **working**

## THE GAP: UI ↔ Backend Bridge
TimedRootView uses local DataStore. SupabaseClient + GraphClient are fully implemented but **not called from UI**.
- **Missing: Supabase Auth** — RLS policies need `auth.uid()`. No sign-in flow exists.
- **Missing: EmailSyncService** — no background loop calling Graph delta sync
- **Missing: Realtime subscriptions** — no live DB → UI updates

## NEXT (sequential chain)
1. Supabase Auth flow (Microsoft provider) + workspace/profile bootstrap
2. Bridge UI state → SupabaseClient (dual-write: DataStore + Supabase)
3. EmailSyncService (background Graph delta → classify → triage)
4. Realtime subscriptions (tasks, email_messages, plan_items, waiting_items)
5. FR-03 Task Extraction — thread bundling + AI extraction from email body
6. FR-06 Calendar — bind Graph events to CalendarPane + free-time detection
7. FR-07 PA Sharing — invite link + Realtime shared view
8. FR-08 Aging alerts — configurable thresholds + stale item review

## FILE QUICK REF
- Root state: `Sources/Features/TimedRootView.swift`
- Local persistence: `Sources/Core/Services/DataStore.swift`
- Supabase client (**real, not stubs**): `Sources/Core/Clients/SupabaseClient.swift`
- Graph client (**real, not stubs**): `Sources/Core/Clients/GraphClient.swift`
- Planning engine: `Sources/Core/Services/PlanningEngine.swift`
- All models: `Sources/Features/PreviewData.swift`
- Edge functions: `supabase/functions/` (8 deployed, all ACTIVE)
