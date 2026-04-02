# Timed — Thread 6: Profile Card & Behaviour Rules Deep Audit

**Repository:** `ammarshah1n/time-manager-desktop` · branch `ui/apple-v1-restore`  
**Commit SHA:** `6e9d497af670811a172850cc7180a5312329ef06`  
**Scope:** `Sources/Features/Prefs/`, `Sources/Core/Models/`, `Sources/Core/Services/InsightsEngine.swift`, `Sources/Core/Services/PlanningEngine.swift`, `Sources/Core/Clients/SupabaseClient.swift`, `Sources/Features/Onboarding/OnboardingFlow.swift`, `Sources/Features/Plan/PlanPane.swift`

***

## Executive Summary

The Timed codebase has a well-designed **scoring kernel** (`PlanningEngine.scoreTask`) that explicitly accepts `behaviouralRules: [BehaviourRule]` and dispatches two live rule types (`ordering`, `timing`). However, the end-to-end pipeline has **three critical breaks** that reduce this sophisticated engine to a dumb static sorter in practice:

1. **The BehaviourRules array is hardcoded to `[]` at every call site.** `PlanPane.generate()` passes `behaviouralRules: []` unconditionally — rules in Supabase are never fetched before planning.
2. **No `UserProfile` model exists.** The concept is split across ephemeral `@AppStorage` keys set in `OnboardingFlow.swift` and never consolidated into a typed struct that the scoring pipeline can read. Critical executive-scheduler fields — work-hour windows, energy curve, meeting-free preferences — are entirely absent.
3. **The feedback loop that learns from overrides is plumbed at the Supabase layer (`insertBehaviourEvent`, `BehaviourEventInsert`) but is never called from any UI action.** Deferrals, re-orderings, and suggestion ignores never increment event counts, so `confidence` values in the `behaviour_rules` table can never evolve.

The combined effect: Timed has all the infrastructure for an A+ executive scheduler but is operating as a B− static sorter. The fixes are contained and do not require architectural changes.

***

## Impact-Ranked Findings

| # | Finding | File(s) | Impact | Effort |
|---|---------|---------|--------|--------|
| F-1 | `behaviouralRules: []` hardcoded in `PlanPane.generate()` — rules never reach scorer | `PlanPane.swift:178` | **High** | Low |
| F-2 | No `UserProfile` struct — onboarding prefs siloed in `@AppStorage`, invisible to PlanningEngine | `OnboardingFlow.swift`, `PlanningEngine.swift` | **High** | Medium |
| F-3 | `insertBehaviourEvent` never called — confidence never updates, learning loop is dead | `SupabaseClient.swift`, all UI panes | **High** | Medium |
| F-4 | Missing work-hour window enforcement — PlanningEngine has no concept of "don't schedule after 18:00" | `PlanningEngine.swift` | **High** | Low |
| F-5 | Profile changes (quiet hours, work hours) are not propagated reactively — require app restart to take effect in `PlanningEngine` | `PlanPane.swift`, `TimedRootView.swift` | **Medium** | Low |
| F-6 | `LearningTab.loadData()` passes hardcoded `UUID()` to `fetchBehaviourRules` — always fetches wrong profile's rules | `PrefsPane.swift:213` | **Medium** | Low |
| F-7 | No energy-curve field — timing rules exist in scorer but no UI to author them and no auto-detection pipeline | `PrefsPane.swift`, `PlanningEngine.swift` | **Medium** | Medium |
| F-8 | No meeting-free window preference — competitor parity gap vs Reclaim, Motion, Clockwise | absent from codebase | **Medium** | Medium |
| F-9 | `LearningTab` shows `BehaviourRuleRow` but no override/dismiss affordance — user cannot manually correct a rule | `PrefsPane.swift` | **Medium** | Low |
| F-10 | `InsightsEngine.suggestedAdjustments` threshold is hardcoded `> 3` minutes — no user-adjustable sensitivity | `InsightsEngine.swift:20` | **Low** | Low |
| F-11 | No ProfileCard surface — learned preferences are buried in `LearningTab` with no executive summary | `PrefsPane.swift` | **Low** | Medium |
| F-12 | `CompletionRecord.wasDeferred` is captured but never used in override weight decay | `CompletionRecord.swift`, `InsightsEngine.swift` | **Low** | Low |

***

## F-1 · BehaviourRules Hardcoded to Empty Array

### Diagnosis

In `Sources/Features/Plan/PlanPane.swift` at the `generate()` function (line ~178), the `PlanRequest` is constructed with `behaviouralRules: []`:

```swift
let request = PlanRequest(
    workspaceId: UUID(),   // placeholder until Supabase is wired
    profileId: UUID(),
    availableMinutes: totalAvailable,
    moodContext: nil,
    behaviouralRules: [],   // ← DEAD — rules exist in DB but never fetched
    tasks: planTasks,
    bucketStats: []         // ← also dead
)
```

`PlanningEngine.scoreTask` has complete, working logic for `ordering` and `timing` rule types — it decodes `rule.ruleValueJson`, applies `confidence`-weighted bumps of ±200–300 points, and correctly dispatches Thompson sampling. All of that logic runs on an empty slice every time.

### Fix

Fetch rules once at view init and inject them at generation time. Since `PlanPane` is a pure SwiftUI `View` (not an `ObservableObject`), the cleanest pattern is a `@StateObject` planner coordinator:

```swift
// PlanCoordinator.swift — new file
@MainActor
final class PlanCoordinator: ObservableObject {
    @Dependency(\.supabaseClient) private var supabase
    @Published var behaviouralRules: [BehaviourRule] = []
    @Published var bucketStats: [BucketCompletionStat] = []

    func load(profileId: UUID, workspaceId: UUID) async {
        do {
            let rows = try await supabase.fetchBehaviourRules(profileId)
            behaviouralRules = rows.filter(\.isActive).map { row in
                BehaviourRule(
                    ruleKey: row.ruleKey,
                    ruleType: row.ruleType,
                    ruleValueJson: row.ruleValueJson,
                    confidence: row.confidence
                )
            }
            bucketStats = try await supabase.fetchBucketStats(workspaceId, profileId)
        } catch { }
    }
}
```

Then in `PlanPane`:

```swift
// PlanPane.swift — add to struct
@StateObject private var coordinator = PlanCoordinator()

// In .task { } on the view
.task { await coordinator.load(profileId: auth.profileId ?? UUID(),
                                workspaceId: auth.workspaceId ?? UUID()) }

// In generate()
let request = PlanRequest(
    workspaceId: auth.workspaceId ?? UUID(),
    profileId: auth.profileId ?? UUID(),
    availableMinutes: totalAvailable,
    moodContext: moodFromMorningInterview,
    behaviouralRules: coordinator.behaviouralRules,  // ← live
    tasks: planTasks,
    bucketStats: coordinator.bucketStats             // ← live
)
```

***

## F-2 · Missing UserProfile Struct

### Diagnosis

No `UserProfile.swift` exists anywhere in the repository. Onboarding data is scattered across `@AppStorage` keys in `OnboardingFlow.swift` with a static accessor struct `OnboardingUserPrefs`. The `PlanningEngine` has no type-level knowledge of:

- Work-hour start/end window
- Deep-focus preferred hours (energy curve)
- Meeting-free morning/afternoon preference
- Email cadence (batch reply windows)
- Transit modes (used as `isTransitSafe` signal but not as a scheduling window)

`PlanRequest` carries only `moodContext` and `behaviouralRules` — no profile snapshot.

### Fix

Create `Sources/Core/Models/UserProfile.swift`:

```swift
// UserProfile.swift
struct UserProfile: Sendable {
    let profileId: UUID
    let workStartHour: Int          // e.g. 8
    let workEndHour: Int            // e.g. 18
    let deepFocusHours: [Int]       // e.g. [9,10,11] — morning peak
    let shallowWorkHours: [Int]     // e.g. [14,15] — afternoon trough
    let meetingFreeBeforeHour: Int? // e.g. 10 — no meetings before 10am
    let emailBatchHours: [Int]      // e.g. [9, 13, 17]
    let transitModes: Set<String>
    let defaultMinutesByBucket: [String: Int]
    let familySurname: String

    static func fromOnboardingPrefs() -> UserProfile {
        UserProfile(
            profileId: UUID(),
            workStartHour: 9,
            workEndHour: OnboardingUserPrefs.workdayHours + 9,
            deepFocusHours: [],     // populated by behaviour_rules timing type
            shallowWorkHours: [],
            meetingFreeBeforeHour: nil,
            emailBatchHours: emailBatchFromCadence(OnboardingUserPrefs.emailCadence),
            transitModes: Set(OnboardingUserPrefs.transitModes),
            defaultMinutesByBucket: [
                "reply": OnboardingUserPrefs.replyMins,
                "action": OnboardingUserPrefs.actionMins,
                "calls": OnboardingUserPrefs.callMins,
                "read": OnboardingUserPrefs.readMins
            ],
            familySurname: OnboardingUserPrefs.familySurname
        )
    }

    private static func emailBatchFromCadence(_ cadence: Int) -> [Int] {
        switch cadence {
        case 0: return [^9]
        case 1: return [9, 16]
        case 2: return [9, 13, 17]
        default: return [9, 11, 14, 17]
        }
    }
}
```

Then add `userProfile: UserProfile` to `PlanRequest` and use it in `PlanningEngine.generatePlan` to gate tasks outside `workStartHour..<workEndHour` into overflow automatically.

***

## F-3 · Feedback Loop Dead — `insertBehaviourEvent` Never Called

### Diagnosis

`SupabaseClientDependency` declares `insertBehaviourEvent: @Sendable (BehaviourEventInsert) async throws -> Void` with a full live implementation that writes to `behaviour_events`. A server-side Edge Function or pg_cron job presumably aggregates these events into `behaviour_rules.confidence` and `sample_size`.

However, searching the entire repository for `insertBehaviourEvent` returns zero results — the function is defined but never invoked. The `BehaviourEventInsert` struct is declared but never instantiated from any UI action. This means:

- Deferrals (`deferredCount` increments in `TimedTask`) do not emit events
- Re-orderings in `PlanPane` do not emit events  
- `LearningTab` accuracy data updates local records but never writes back to `behaviour_events`
- `confidence` values in the DB are permanently frozen at whatever they were seeded with

### Fix

Emit behaviour events at the three key interaction points:

**1. Task deferral** (wherever `isDone = false` and task is moved past today):

```swift
// In TasksPane or wherever deferred state is set
func recordDeferral(task: TimedTask, auth: AuthService) async {
    guard let wsId = auth.workspaceId, let pid = auth.profileId else { return }
    @Dependency(\.supabaseClient) var supa
    let event = BehaviourEventInsert(
        workspaceId: wsId, profileId: pid,
        eventType: "deferred",
        taskId: task.id,
        bucketType: bucketTypeStr(task.bucket),
        hourOfDay: Calendar.current.component(.hour, from: Date()),
        dayOfWeek: Calendar.current.component(.weekday, from: Date()),
        oldValue: nil, newValue: "deferred"
    )
    try? await supa.insertBehaviourEvent(event)
}
```

**2. Plan override** (when user drags a task to a different position in `PlanPane`):

```swift
// Emit "reorder" event with oldValue="\(oldPosition)" newValue="\(newPosition)"
```

**3. Suggestion ignored** (when user regenerates plan without accepting the top suggestion):

```swift
// In PlanPane.generate() — before regenerating, record all current top-3 as "ignored" events
```

The Edge Function that consumes these events should apply Bayesian confidence update:

```
new_confidence = (old_confidence * old_sample_size + outcome) / (old_sample_size + 1)
```

where `outcome = 1.0` for completion, `0.0` for deferral, reducing rule weight over consistent overrides.

***

## F-4 · No Work-Hour Window Enforcement

### Diagnosis

`PlanningEngine.generatePlan` reads `prefs.quietHours.enabled` and `prefs.quietHours.end` from `UserDefaults` directly, but has no concept of a work-end hour. A task could score highly and be placed in the plan regardless of whether it falls within the user's work window. The `timing` behaviour rule can partially compensate but only if manually authored — no automatic enforcement exists.

This is particularly acute for an executive user who may have a hard stop (e.g., 17:00 for commitments), combined with a late-morning meeting block.

### Fix

Add a `workEndHour` guard in `PlanningEngine.generatePlan`:

```swift
// After quiet hours check, before scoring
let workEnd = UserDefaults.standard.integer(forKey: "onboarding_workEndHour")
if workEnd > 0 && currentHour >= workEnd {
    // After hours — only isDoFirst tasks
    effectiveTasks = request.tasks.filter { $0.isDoFirst }
    TimedLogger.planning.info("After work hours (\(workEnd):00) — Do First only")
}
```

Store `workEndHour` during onboarding (currently `workdayHours` is stored but not converted to an end-of-day timestamp).

***

## F-5 · Profile Changes Not Propagated Reactively

### Diagnosis

Preferences that affect planning (`prefs.quietHours.enabled`, `prefs.quietHours.end`, onboarding work-hour values) are read via `UserDefaults.standard` directly inside `PlanningEngine.generatePlan` at invocation time. This means:

- Changes in `PrefsPane` → `NotificationsTab` take effect immediately on the **next** `generate()` call — this is acceptable.
- But `PlanPane` caches `behaviouralRules` in `@State` (under F-1's proposed fix, in `@StateObject`). If the user modifies rules via `LearningTab`, the cached rules in `PlanCoordinator` go stale until the view is fully torn down and recreated.

### Fix

Since `PlanCoordinator` will be a `@StateObject`, add an `@AppStorage` observer or `NotificationCenter` post when any rule changes:

```swift
// In LearningTab, after toggling a rule's isActive state:
NotificationCenter.default.post(name: .behaviourRulesDidChange, object: nil)

// In PlanCoordinator.init():
NotificationCenter.default.addObserver(self, selector: #selector(reloadRules),
    name: .behaviourRulesDidChange, object: nil)
```

Because `PlanningEngine` is a pure function (no state), quiet-hour and work-hour changes are already reactive — the issue is only with the cached rules array. This is a **one-file fix** in `PlanCoordinator`.

***

## F-6 · `LearningTab.loadData()` Passes Hardcoded `UUID()`

### Diagnosis

In `Sources/Features/Prefs/PrefsPane.swift`, inside `LearningTab.loadData()`:

```swift
rules = try await supabase.fetchBehaviourRules(UUID())  // ← random UUID each call
```

`fetchBehaviourRules` takes a `profileId` but is given a fresh random UUID. This call will return 0 rows every time against a real Supabase database, making the entire `LearningTab` section permanently empty for any user with real data.

### Fix

```swift
// LearningTab — inject or read auth:
@Dependency(\.supabaseClient) private var supabase
private var auth: AuthService { AuthService.shared }

private func loadData() async {
    let profileId = auth.profileId ?? UUID()
    do {
        rules = try await supabase.fetchBehaviourRules(profileId)
    } catch {}
    // ... rest of loadData
}
```

This is a one-line change with zero architectural impact.

***

## F-7 · No Energy Curve UI — Timing Rules Orphaned

### Diagnosis

`PlanningEngine.scoreTask` has complete `timing` rule logic: it reads `bucket_type` and `preferred_hours: [Int]` from `rule.ruleValueJson`, applies `+200 * confidence` in-window and `-100 * confidence` out-of-window. This is exactly the energy-curve mechanism.

However:
- No UI exists to author `timing` rules (neither manually nor via auto-detection)
- `LearningTab` shows existing rules by `ruleType` label but provides no authoring surface
- The `InsightsEngine` only computes time-estimation accuracy — it does not detect completion-rate patterns by hour to generate `timing` rules automatically

Reclaim.ai allows users to set separate Working Hours, Meeting Hours, and Personal Hours with per-day time windows. Motion supports an "Energy Based Scheduling" preference. Clockwise's "Ideal Day" lets users specify preferred focus time windows. Timed has the scoring infrastructure but no comparable input surface.[^1][^2][^3][^4][^5]

### Fix

Add a `PrefsEnergyTab` (or expand `BlocksTab`) with:

```swift
struct EnergyCurveEditor: View {
    // 24 time slots, user drags to mark as "peak", "normal", "low"
    // Saves as AppStorage "prefs.energy.peakHours" = "9,10,11"
    //           AppStorage "prefs.energy.lowHours"  = "14,15"
}
```

On save, synthesize `timing` behaviour rules directly in-app (no Edge Function needed for single-user):

```swift
func upsertTimingRules(peakHours: [Int], lowHours: [Int], profileId: UUID) async {
    for bucket in ["action", "reply", "calls"] {
        let json = try! JSONEncoder().encode(["bucket_type": bucket,
                                              "preferred_hours": peakHours])
        // upsert to behaviour_rules with ruleType="timing", confidence=0.7
    }
}
```

***

## F-8 · Missing Meeting-Free Window Preference

### Diagnosis

No field exists in the codebase to express "no meetings before 10am" or "protect Tuesday mornings". `PlanningEngine` operates only on tasks, not on the calendar blocks binding. The `CalendarSyncService` produces `FreeTimeSlot` objects that flow into `TodayPane` but these are not fed into `PlanRequest` as constraints — a `PlanRequest` has no concept of "this slot is blocked by a meeting."

Reclaim.ai's core value proposition is exactly this: it reschedules flexible meetings to protect focus time and enforces meeting hours. Motion blocks out deep-work time automatically against incoming meeting requests. Clockwise explicitly moves meetings to create focus blocks and offers "Auto-Decline" for focus protection.[^6][^7][^3][^8][^9]

### Fix

Add to onboarding Step 4 or the new `EnergyCurveEditor`:

```swift
@AppStorage("prefs.meetingFree.enabled")     var meetingFreeEnabled = false
@AppStorage("prefs.meetingFree.beforeHour")  var meetingFreeBeforeHour = 10
@AppStorage("prefs.meetingFree.days")        var meetingFreeDays = "2,4"  // Tue,Thu
```

In `PlanRequest`, add `freeSlots: [FreeTimeSlot]` and in `PlanningEngine`, enforce that tasks with `estimatedMinutes > 30` are only placed in slots that don't overlap existing calendar blocks.

***

## F-9 · No Rule Override Affordance in `LearningTab`

### Diagnosis

`LearningTab` displays `BehaviourRuleRow` items with confidence bars and sample counts but provides no UI to:
- Disable a rule (`isActive = false`)
- Delete a rule
- Manually correct a rule's `confidence`
- Provide a "thumbs down" on a specific suggestion

This is the UI surface that would close the feedback loop for F-3. Without it, even if `insertBehaviourEvent` starts firing, the user has no way to directly correct a mislearned pattern.

### Fix

Add a context menu or trailing swipe action to each rule row:

```swift
ForEach(rules) { rule in
    BehaviourRuleRowView(rule: rule)
        .contextMenu {
            Button("Disable rule") {
                Task { try? await disableRule(rule.id) }
            }
            Button("This is wrong — reset confidence") {
                Task { try? await resetRule(rule.id) }
            }
        }
}
```

`disableRule` flips `is_active = false` via a new `updateBehaviourRule` method in `SupabaseClientDependency`. `resetRule` sets `confidence = 0.3, sample_size = 0` to force relearning from scratch.

***

## F-10 · Hardcoded Sensitivity Threshold in `InsightsEngine`

### Diagnosis

`InsightsEngine.suggestedAdjustments` uses a hardcoded `abs(diff) > 3` minutes threshold:

```swift
guard abs(diff) > 3 else { return nil }
```

For a user who has deliberately set tight 5-minute estimates for replies, this means a 3-minute actual deviation (60% error) never generates a suggestion. There is no way to adjust this without recompiling.

### Fix

```swift
// AppStorage key: "prefs.insights.sensitivityMins" default 5
static func suggestedAdjustments(_ records: [CompletionRecord],
                                  sensitivityMins: Int = 5) -> [...] {
    let threshold = Double(sensitivityMins)
    // ...
    guard abs(diff) > threshold else { return nil }
}
```

Expose this as a slider in `LearningTab` under an "Insight sensitivity" section.

***

## F-11 · No ProfileCard Surface

### Diagnosis

There is no ProfileCard or executive summary of the user's current scheduling context. The user must navigate to: Onboarding (to re-run), Settings → Learning Tab (for rules), Settings → Blocks Tab (for duration defaults), and Settings → Notifications (for quiet hours) — four separate locations to understand their own profile configuration.

Competitors surface this prominently: Reclaim shows an "Ideal Day" summary, Motion shows a scheduling dashboard, Clockwise shows a Focus Time summary tile.[^2][^1]

### Fix

Add a `ProfileCardView` at the top of the `LearningTab` (or as a first tab "Profile"):

```swift
struct ProfileCardView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Row: Work hours bar (start → end, meeting-free windows highlighted)
            // Row: Energy curve thumbnail (peak/low hour heat map, 24 segments)
            // Row: Email cadence badge ("3× daily at 9, 13, 17")
            // Row: Learning health ("47 completions · 8 active rules · 82% accuracy")
            // CTA: "Edit profile" → navigates to individual tabs
        }
        .padding(16)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
    }
}
```

***

## F-12 · `wasDeferred` Captured but Not Used in Decay

### Diagnosis

`CompletionRecord.wasDeferred: Bool` is captured but `InsightsEngine` never uses it. A rule that consistently produces deferred tasks should have its `confidence` decayed — a deferral is weak negative feedback, not a null signal.

### Fix

In the Edge Function (or in a local `RuleDecayEngine`), apply:

```swift
// On each deferred completion record:
// new_confidence = max(0.1, current_confidence * 0.95)
// On each completed (not deferred):
// new_confidence = min(1.0, current_confidence * 1.02 + 0.01)
```

This exponential moving average with asymmetric decay means a rule must earn confidence slowly but can lose it quickly on consistent overrides — appropriate for executive user preferences that evolve.

***

## Competitor Feature Gap Analysis

| Feature | Reclaim.ai | Motion | Clockwise | Timed (current) | Timed (with fixes) |
|---------|-----------|--------|-----------|-----------------|-------------------|
| Work/meeting/personal hour types | ✅ Full per-day windows[^3] | ✅ Weekly schedule builder[^10][^5] | ✅ "Ideal Day" + meeting windows[^2] | ⚠️ Single `workdayHours` int | ✅ After F-2, F-4, F-8 |
| Energy-based task scheduling | ⚠️ Via habit scheduling | ✅ "Energy Based Scheduling" toggle[^5] | ✅ Focus Time AM/PM preference[^1] | ⚠️ `timing` rules exist but no UI | ✅ After F-7 |
| Meeting-free window enforcement | ✅ Meeting Hours setting[^8] | ✅ Auto-schedule respects no-meeting blocks[^7] | ✅ Auto-decline + focus blocks[^6] | ❌ Absent | ✅ After F-8 |
| Feedback / override learning | ⚠️ Manual task completion only | ⚠️ Reschedules missed tasks | ❌ No explicit learning | ❌ `insertBehaviourEvent` never called | ✅ After F-3, F-9, F-12 |
| Profile/settings summary card | ✅ Personal Settings page | ✅ Scheduling dashboard | ✅ Focus Time summary tile | ❌ Absent | ✅ After F-11 |
| Per-bucket time defaults | ❌ | ⚠️ Task duration field | ❌ | ✅ Onboarding Step 6 | ✅ |
| Confidence-weighted rule engine | ❌ Rule-based only | ❌ | ❌ | ✅ (if rules are fetched) | ✅ After F-1 |

Timed's **scoring engine is architecturally superior** to all three competitors — the `BehaviourRule` confidence-weighting, Thompson sampling, and mood context system does not exist in Reclaim, Motion, or Clockwise in any comparable form. The gap is entirely in **data wiring and profile completeness**, not in algorithm sophistication.

***

## Recommended Implementation Order

For a single-executive user, implement in this sequence to maximise daily-use impact per hour of engineering:

1. **F-6** (1 hour) — Fix `UUID()` bug in `LearningTab` so rules actually load
2. **F-1** (2 hours) — Wire `behaviouralRules` into `PlanPane.generate()` via `PlanCoordinator`
3. **F-4** (1 hour) — Enforce `workEndHour` in `PlanningEngine`
4. **F-3** (3 hours) — Call `insertBehaviourEvent` on deferral and plan override
5. **F-2** (4 hours) — Create `UserProfile` struct and feed it into `PlanRequest`
6. **F-9** (2 hours) — Add rule disable/reset affordance in `LearningTab`
7. **F-7** (3 hours) — Build `EnergyCurveEditor` and auto-synthesise timing rules
8. **F-5** (1 hour) — Add `NotificationCenter` invalidation for cached rules
9. **F-8**, **F-11**, **F-10**, **F-12** — Schedule as polish sprint

Steps 1–4 alone restore the engine to full function and eliminate the biggest gap versus competitors. The estimated total is **~17 hours** for items 1–6, well within a single focused sprint.

---

## References

1. [Focus Time - Clockwise Knowledge Base](https://support.getclockwise.com/article/189-focus-time) - Clockwise helps you visualize how much time you have for focused work by automatically creating Focu...

2. [5 steps to optimize your time with Clockwise - YouTube](https://www.youtube.com/watch?v=ed0EcvDet6Q) - Clockwise can help reorganize your schedule, reduce fragmented time, and free up more focus time. In...

3. [Set your Working, Meeting, Personal, & Custom Hours](https://help.reclaim.ai/en/articles/3600766-set-your-working-meeting-personal-custom-hours) - Reclaim uses your Hours to know which days and times to schedule your work and personal smart calend...

4. [Set Your Working Hours - AI Calendar App | Reclaim.ai](https://reclaim.ai/features/working-hours) - AI-powered scheduling: set your working, meeting, & personal hours to optimize productivity & work-l...

5. [Step By Step Guide How to Use Motion In 2026 - SuperbCrew](https://www.superbcrew.com/step-by-step-guide-how-to-use-motion-in-2026/) - Set Preferences: Dashboard > Settings (gear) > Schedules. Define work hours (e.g., Mon-Fri, 9-5), br...

6. [How to Remove and Turn Off Focus Time on Calendar | Clockwise](https://www.getclockwise.com/blog/remove-focus-time-calendar-outlook) - In this guide, we'll show you how to remove Focus Calendar events in Outlook and turn off automatic ...

7. [Motion: The AI Powered SuperApp for Work](https://www.usemotion.com) - Motion instantly builds the entire project — tasks with deadlines and assignees, project stages, and...

8. [Overview: How Smart Meetings work, and how to create them](https://help.reclaim.ai/en/articles/5604990-overview-how-smart-meetings-work-and-how-to-create-them) - Reclaim will honor preferences between you and your attendees' meeting hours and only schedule event...

9. [Motion App Review: Features, Pros And Cons - Forbes](https://www.forbes.com/advisor/business/software/motion-app-review/) - However, I did find it easy to assign tasks, add start and due dates, upload attachments, leave comm...

10. [Motion App: Complete Tutorial & Tips - YouTube](https://www.youtube.com/watch?v=fkTvit1RQaE) - ... schedule, prioritize tasks, and boost your productivity with the Motion app. Don't forget to lik...

