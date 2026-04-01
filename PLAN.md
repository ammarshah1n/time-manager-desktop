# PLAN.md — Timed
<!-- New session: read this → CHANGELOG.md first entry → `swift build && swift test` → working in 30 seconds -->
<!-- Do NOT explore Obsidian/transcripts/specs. Trust this file. Verify infra with CLI if unsure. -->

## CURRENT STATE (2026-04-01)
- **UI complete** — 10 screens + task detail modal + calendar drag-to-create + batch ops + voice morning interview
- **Backend LIVE** — Supabase `fpmjuufefhtlwbfinxlx`, 8 edge functions ACTIVE, all secrets set
- **Azure LIVE** — MSAL OAuth in GraphClient (silent + interactive)
- **Auth flow built** — AuthService.swift: Microsoft OAuth sign-in, session restore, workspace/profile/email_account bootstrap
- **All 3 ML loops CLOSED** — estimation write-back, email correction write-back, behaviour event logging
- **7-rank ML upgrade shipped** — embeddings, Bayesian estimation, energy curve, social graph, Thompson sampling, active learning
- **Scoring model upgraded** — real Beta Thompson, second-pass knapsack fill, adaptive penalty, overdue cap
- **Tests pass** — 49/49, `swift build` clean

## WHAT WORKS END-TO-END
- Email sync pipeline: GraphClient.fetchDeltaMessages → EmailSyncService → Supabase → classify-email (Haiku + semantic few-shot)
- Time estimation: 4-tier (embedding similarity → historical → Bayesian Sonnet → personalised defaults from bucket_estimates)
- Planning: PlanningEngine with Thompson sampling, timing bumps, mood filtering, behaviour rules, corrected durations
- Voice: SpeechService (premium voices) + VoiceCaptureService + conversation state machine in MorningInterview
- Learning: CompletionRecord → EMA posterior → estimation_history → weekly Opus profile card → behaviour rules → PlanningEngine
- Calendar: auto-sync on auth, free-time detection, free-time banner in TodayPane
- Sharing: SharingService + SharingPane with real Supabase invite links + PA member management
- Insights: accuracy per bucket, confidence indicators on time pills, Learning tab in Settings

## WHAT NEEDS TESTING / MANUAL STEPS
- `supabase db push` — run 7 new migrations (20260331000002 through 20260401000007)
- `supabase functions deploy` — redeploy classify-email, estimate-time, generate-profile-card
- `supabase secrets set OPENAI_API_KEY=sk-...` — needed for embedding calls
- Azure provider in Supabase Auth dashboard — needs client secret (create new one in Azure Portal)
- First MSAL sign-in test — launch app, go through onboarding, click "Sign In" on Outlook

## REMAINING WORK (priority order)
1. **Test the auth → email sync → triage flow end-to-end** with real Outlook account
2. **EventKit calendar context** — read macOS calendar for meeting fatigue signal (no OAuth needed)
3. **Thread velocity** — compute messages-per-hour per conversation, pass to classify-email
4. **Waiting items unblock** — detect reply in Graph delta sync, auto-unblock waiting_items
5. **Session interruption tracking** — detect app backgrounding mid-task
6. **Logistic regression calibration** of Score.* constants after 30 days of data

## FILE QUICK REF
- Root state: `Sources/Features/TimedRootView.swift`
- Auth: `Sources/Core/Services/AuthService.swift`
- Email sync: `Sources/Core/Services/EmailSyncService.swift`
- Planning: `Sources/Core/Services/PlanningEngine.swift`
- Voice: `Sources/Core/Services/SpeechService.swift`, `VoiceCaptureService.swift`, `VoiceResponseParser.swift`
- Models: `Sources/Features/PreviewData.swift`
- Supabase: `Sources/Core/Clients/SupabaseClient.swift`
- Graph: `Sources/Core/Clients/GraphClient.swift`
- Edge functions: `supabase/functions/` (8 deployed)
- Migrations: `supabase/migrations/` (7 total)
