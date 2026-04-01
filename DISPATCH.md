# DISPATCH.md — Timed Parallel Execution Prompt
> Drag this file into a new Claude Code terminal to execute.

## CONTEXT — Read Before Doing Anything

You are continuing work on the Timed macOS app at `/Users/integrale/time-manager-desktop/`.

**Before writing ANY code:**
1. Read `/Users/integrale/time-manager-desktop/PLAN.md` — current state
2. Read `/Users/integrale/time-manager-desktop/CHANGELOG.md` — first entry only (latest session)
3. Run `swift build` to confirm clean baseline
4. Run `swift test` to confirm 49/49 pass

**Architecture rules (from CLAUDE.md):**
- All Graph API calls through `Sources/Core/Clients/GraphClient.swift` — no exceptions
- All Supabase access through `Sources/Core/Clients/SupabaseClient.swift` — never import Supabase directly
- Only edit files in `Sources/Core/` and `Sources/Features/` — NEVER touch `Sources/Legacy/`
- Swift 6.1, macOS 15+, strict concurrency (`@Sendable`, actors, `Sendable` types)
- All models must be `Codable + Sendable + Equatable`
- Commit after every change, not in batches

**What's already built and working (DO NOT rebuild):**
- All 10 UI screens (Today, Triage, Tasks, Waiting, Capture, Calendar, Focus, DishMeUp, MorningInterview, Settings)
- Local persistence (DataStore actor + JSON in ~/Library/Application Support/Timed/)
- PlanningEngine (knapsack algorithm, quiet hours, mood filtering)
- Voice Morning Interview (SpeechService + VoiceResponseParser + voice mode toggle)
- Subject line parsing (extractedPriority/TimeEstimate in String+EmailSubject)
- Family detection (isFamilyMember wired to TriagePane + EmailSyncService)
- Stale item alerts (per-bucket thresholds, amber banner, snooze)
- Task detail modal, calendar drag-to-create, batch operations
- FocusPane "want another task?" prompt
- CompletionRecord + InsightsEngine + DataStore persistence
- NetworkMonitor (NWPathMonitor, offline indicator)
- DishMeUpSheet mood filtering (easy wins/avoidance/deep focus)
- AuthService.swift (Supabase OAuth with Microsoft provider, session restore, workspace bootstrap)
- EmailSyncService.swift (Graph delta sync → Supabase upsert → classify-email Edge Function)
- CalendarSyncService.swift (Graph calendar events → CalendarBlock + free-time detection)
- GraphClient.swift — REAL MSAL OAuth (silent + interactive), all Graph API methods
- SupabaseClient.swift — REAL queries, real credentials hardcoded
- 8 Edge Functions deployed and ACTIVE on Supabase
- 49 tests passing

**What's NOT wired (THE GAPS — your job):**
- OnboardingFlow "Sign In" buttons set AppStorage flags only, don't trigger real OAuth
- EmailSyncService exists but is commented out in TimedRootView
- TimedRootView loads from DataStore only, never from Supabase
- GraphClient.authenticate() never called from UI
- No Realtime subscriptions
- TriagePane shows local data, not real Outlook emails
- SharingService methods are all stubs
- InsightsEngine results never shown in UI
- No Outlook folder-move learning

---

## EXECUTION PLAN — 3 Rounds

### Round 1 — Parallel (fire all 3 as sub-agents)

**Worker A: Real Sign-In (Tasks 1+4 merged)**
```
Files: Sources/Features/Onboarding/OnboardingFlow.swift, Sources/Core/Services/AuthService.swift, Sources/Features/Prefs/PrefsPane.swift

What to do:
1. Add `@Published var graphAccessToken: String?` to AuthService.swift
2. Add a `signInWithGraph()` method to AuthService that calls GraphClientDependency.authenticate() and stores the token
3. Extend AuthService.bootstrapWorkspace() to also create an email_accounts row in Supabase
4. In OnboardingFlow.swift: the Outlook "Sign In" button (line ~163) currently just sets `outlookConnected = true`. Change it to call AuthService.shared.signInWithGraph() then set the flag on success
5. In OnboardingFlow.swift: the Supabase "Sign In" button (line ~177) should call AuthService.shared.signInWithMicrosoft() then set flag on success
6. In PrefsPane.swift AccountsTab: add real sign-in/sign-out buttons that call AuthService
7. OnboardingFlow needs @EnvironmentObject var auth: AuthService (already in environment from TimeManagerDesktopApp)

Read OnboardingFlow.swift, AuthService.swift, GraphClient.swift (lines 168-238 for authenticate method), PrefsPane.swift BEFORE editing.
Run swift build after changes.
```

**Worker B: Realtime + Sharing (Tasks 5+7 sequential)**
```
Files: Sources/Core/Clients/SupabaseClient.swift, Sources/Core/Services/SharingService.swift, Sources/Features/Sharing/SharingPane.swift

What to do:
FIRST (Task 5 — Realtime):
1. Add a Realtime channel subscription method to SupabaseClientDependency
2. In SharingService.subscribeToTaskChanges(): implement real Supabase Realtime postgres_changes subscription on tasks table filtered by workspace_id

THEN (Task 7 — Sharing stubs):
1. Add CRUD methods to SupabaseClientDependency for workspace_invites (insert, validate) and workspace_members (fetch, delete)
2. Implement SharingService.generateInviteLink() — insert invite row, return timed://invite/{code} URL
3. Implement SharingService.fetchPAMembers() — query workspace_members where role='pa'
4. Implement SharingService.removeMember() — delete from workspace_members
5. Wire SharingPane to use AuthService.shared.workspaceId instead of UUID()

Read SupabaseClient.swift (full file), SharingService.swift, SharingPane.swift BEFORE editing.
Run swift build after changes.
```

**Worker C: Insights wiring (Task 8)**
```
Files: Sources/Features/Today/TodayPane.swift

What to do:
1. Read TodayPane.swift. Find where the totals strip or header area is.
2. Load CompletionRecord array from DataStore on appear
3. If 10+ records exist, call InsightsEngine.suggestedAdjustments() and show results
4. Display as a collapsible section: "📊 Insights" with each suggestion as a row (e.g., "Action tasks take 25m on average, you estimate 15m")
5. Add a dismiss button that hides insights for 7 days via @AppStorage

Read TodayPane.swift, InsightsEngine.swift, DataStore.swift BEFORE editing.
Run swift build after changes.
```

### Round 2 — Sequential chain (after Round 1 auth is done)

**Task 2: Activate EmailSyncService**
```
Files: Sources/Features/TimedRootView.swift, Sources/Core/Services/AuthService.swift

What to do:
1. Read TimedRootView.swift. Find the commented-out EmailSyncService call (around line 109).
2. Add @EnvironmentObject var auth: AuthService (already in environment)
3. In loadData() or a new .onChange(of: auth.graphAccessToken): when token + workspaceId available, call EmailSyncService.shared.start(accessToken:workspaceId:emailAccountId:)
4. emailAccountId comes from AuthService (add it as a published property after bootstrap)
5. Stop sync on sign-out

Run swift build after changes.
```

**Task 3: Supabase reads in TimedRootView**
```
Files: Sources/Features/TimedRootView.swift, Sources/Features/PreviewData.swift

What to do:
1. Add model mapping extensions in PreviewData.swift:
   - TimedTask.init(from: TaskDBRow) — map all fields
   - TriageItem.init(from: EmailMessageRow) — map sender/subject/preview/receivedAt
   - WOOItem.init(from: WaitingItemRow) — map description/contact/dates
2. Add optional emailMessageId: UUID? to TriageItem (default nil, for Supabase write-back)
3. In TimedRootView.loadData(): after local load, if auth.isSignedIn, fetch from Supabase and merge:
   - tasks = try await supabaseClient.fetchTasks(wsId, profileId, ["pending","in_progress"]).map(TimedTask.init)
   - triageItems = try await supabaseClient.fetchEmailMessages(wsId, "inbox", 100).map(TriageItem.init)
4. In persistenceObserver: when auth.isSignedIn, also write to Supabase (async, fire-and-forget)

Run swift build after changes.
```

**Task 6: TriagePane real emails**
```
Files: Sources/Features/Triage/TriagePane.swift, Sources/Features/PreviewData.swift

What to do:
1. TriageItem now has emailMessageId from Task 3
2. In TriagePane.classifyCurrent(): when emailMessageId != nil, also call supabaseClient.updateEmailBucket() and supabaseClient.insertTriageCorrection()
3. This makes drag-to-train work: user classifies in app → correction saved → classify-email Edge Function uses corrections for few-shot learning

Run swift build after changes.
```

### Round 3 — Polish (after Round 2)

**Task 9: Outlook folder-move learning**
```
Files: Sources/Core/Services/EmailSyncService.swift, Sources/Core/Clients/SupabaseClient.swift

What to do:
1. In EmailSyncService.syncOnce(): when processing delta messages, track parentFolderId changes
2. If a message's folder changed and was not moved by the app: extract sender → create/update sender_rule
3. Add upsertSenderRule method to SupabaseClientDependency
4. This is the SaneBox-style training: user moves email in Outlook → app learns from it

Run swift build after changes.
```

---

## TOKEN PROTOCOL

- Use the Agent tool for Workers A, B, C in Round 1 — fire all 3 in a single message
- For Round 2, execute Tasks 2→3→6 sequentially yourself (they chain)
- For Round 3, fire Task 9 as an agent
- After EVERY round: run `swift build` and `swift test`
- Don't read entire files if you only need a specific section — use offset/limit
- Don't rewrite files — use Edit tool for surgical changes
- Don't add features not listed here

## DOCS TO UPDATE AFTER

After all tasks complete:
1. Update `PLAN.md` — mark gaps as closed
2. Update `CHANGELOG.md` — add session entry
3. Update `CLAUDE.md` File Oracle — add any new files
4. Update `~/Timed-Brain/05 - Dev Log/Week-14-2026.md` — append completion notes

## VERIFICATION

After each round:
1. `swift build` → Build complete!
2. `swift test` → 49/49 pass
3. Round 1: OnboardingFlow "Sign In" triggers real MSAL popup
4. Round 2: TriagePane shows emails from Outlook after sync
5. Round 3: Moving email in Outlook creates sender_rule
