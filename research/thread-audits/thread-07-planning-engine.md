# Timed — Research Thread 7: DishMeUp UX, Context Filtering & PlanningEngine Upgrades

> **Scope:** `DishMeUpSheet.swift` · `PlanningEngine.swift`
> **Branch:** `ui/apple-v1-restore`
> **Impact scale:** 🔴 High · 🟡 Medium · 🟢 Low

***

## Executive Summary

DishMeUpSheet is architecturally sound — the four-quadrant layout (time → context → mood → output stack) matches the mental model the PRD targets. The key gaps are: the preset durations miss the most-used ranges (15 min, 45 min, 90 min); context is entirely manual when macOS Network.framework could auto-suggest it; the mood taxonomy maps well to psychology but is missing one high-value category ("admin drain"); PlanningEngine's greedy fill is already strong but leaves value on the floor for N < 50 tasks; the output stack lacks per-task start times; and there is no session tracking or completion flow to capture `CompletionRecord.actualMinutes`. Addressing items 1–4 and 6–7 together will close the user loop that currently ends at "Accept & Start" with no further reinforcement.

***

## 1. "I Have X Minutes" — Preset Duration UX

### Benchmarks

| App | Preset options | Free-form? | Granularity |
|---|---|---|---|
| Focusmate | 25 / 50 / 75 min only | No | Fixed [^1][^2] |
| Forest | Free-form 10–120 min | Yes | 1 min [^3] |
| Sunsama | Variable per task (timeboxing) | Yes | 5 min increments [^4] |
| Timed (current) | 30 / 1h / 2h / 3h | Yes (±15m stepper) | 15 min |

Focusmate's three-option model is deliberately constrained — their session design is built around 25/50/75 as psychological anchors aligned with ultradian rhythm cycles. The fixed presets eliminate the "how long should I work?" decision entirely, which research shows reduces morning decision paralysis by up to 80%. Sunsama takes the opposite approach, treating session length as a by-product of timeboxed tasks rather than a primary input.[^4][^5][^1]

### Analysis

The current presets (30m / 1h / 2h / 3h) skip the two most common "stolen time" windows:
- **15 minutes** — between meetings, waiting contexts, the #1 "I have a gap" use case
- **45 minutes** — the standard deep work block without a full hour commitment
- **90 minutes** — the ultradian rhythm boundary that neuroscience research supports as an optimal sustained focus unit[^6]

The ±15m stepper already provides free-form access, so presets are a discoverability layer, not a constraint. The goal is to surface the right starting points while preserving the escape hatch.

### Recommended Changes — `DishMeUpSheet.swift`

**Replace line ~98 (`presets` definition):**

```swift
// BEFORE (4 presets, missing 15m/45m/90m)
private let presets: [(label: String, mins: Int)] = [("30m", 30), ("1h", 60), ("2h", 120), ("3h", 180)]

// AFTER (6 presets covering stolen-time + standard + deep blocks)
private let presets: [(label: String, mins: Int)] = [
    ("15m", 15), ("30m", 30), ("45m", 45),
    ("1h", 60), ("90m", 90), ("2h", 120)
]
```

**UX change:** Remove "3h" (extremely rare for a DishMeUp session — anyone allocating 3h is doing daily planning, not quick dispatch). Add "15m" as the leftmost option to prime the common mobile/gap use case.

**Stepper fix:** The current `max(15, minutes - 15)` lower bound is correct. Raise the upper bound guidance to 180 min but remove it from presets to reduce visual noise.

**Estimated lines changed:** 1–3 lines in `presets`, plus layout width adjustment (~5 lines). The 6-button row fits comfortably in the 560pt sheet width with `minWidth: 44`.

**Impact:** 🔴 High — addresses the #1 friction point for gap-filling sessions.

***

## 2. Context Filtering — Manual vs Auto-Detection

### How Competitors Handle Context

OmniFocus 3 renamed "contexts" to "tags" in v3, enabling multi-tag assignment per action — a task can carry both a `@phone` and `@home` tag simultaneously. Things 3 uses manually assigned location/context tags with no auto-detection. GTD methodology defines context as the *tool or location required* (e.g., `@computer`, `@phone`, `@errands`), with the user selecting the relevant context filter when choosing what to do next. Critically, **none of the major apps auto-detect context in 2025** — this is an untapped competitive advantage.[^7][^8][^9][^10]

### macOS Sensor APIs Available

**`NWPathMonitor` (Network.framework) — macOS 10.14+, Swift-native:**

```swift
import Network
let monitor = NWPathMonitor()
monitor.pathUpdateHandler = { path in
    let isWifi = path.usesInterfaceType(.wifi)
    let isSatisfied = path.status == .satisfied
    let isAirplaneMode = path.status == .unsatisfied 
                         && path.availableInterfaces.isEmpty
}
monitor.start(queue: .global(qos: .utility))
```

This gives a clean three-way split:[^11][^12]

| `NWPath` state | Detected context | Confidence |
|---|---|---|
| Satisfied + WiFi interface | `desk` | High |
| Satisfied + no WiFi (Ethernet/cellular) | `desk` | Medium |
| Unsatisfied + interfaces present | `transit` | Medium |
| Unsatisfied + no interfaces | `flight` | High |

**`CMMotionActivityManager` (CoreMotion) — iOS/iPadOS only, NOT macOS.** Motion activity detection (stationary/walking/automotive) is not available on macOS. Do not attempt to import `CoreMotion` for the macOS target — it will compile but the activity manager returns nil.[^13][^14]

**Conclusion:** On macOS, `NWPathMonitor` is the only signal available. It is sufficient to handle the `desk` ↔ `flight` axis with high confidence, and the `transit` case with medium confidence (the user is likely on a MacBook with no WiFi lock to a hotspot).

### Recommended Changes — `DishMeUpSheet.swift`

**Add a `ContextDetector` service (~30 lines, new file or extension):**

```swift
import Network

final class ContextDetector: ObservableObject {
    @Published var suggestedContext: DishMeUpContext? = nil
    private let monitor = NWPathMonitor()

    func startMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.suggestedContext = Self.infer(path)
            }
        }
        monitor.start(queue: DispatchQueue(label: "timed.context.monitor", qos: .utility))
    }

    private static func infer(_ path: NWPath) -> DishMeUpContext {
        guard path.status == .satisfied else {
            // No connectivity at all — airplane mode
            return .flight
        }
        return path.usesInterfaceType(.wifi) ? .desk : .transit
    }

    func stop() { monitor.cancel() }
}
```

**In `DishMeUpSheet`:**
- Add `@StateObject private var contextDetector = ContextDetector()`
- In `.task {}` block, call `contextDetector.startMonitoring()` and pre-fill `context = contextDetector.suggestedContext ?? .desk`
- Add a subtle "Auto-detected" badge below the selected context pill:

```swift
// Below contextPicker HStack:
if let suggested = contextDetector.suggestedContext, suggested == context {
    HStack(spacing: 4) {
        Image(systemName: "bolt.fill").font(.system(size: 9)).foregroundStyle(.secondary)
        Text("Auto-detected").font(.system(size: 10)).foregroundStyle(.secondary)
    }
    .padding(.horizontal, 2)
}
```

**UX principle:** Auto-detection should *suggest*, never *force*. The user always retains one-tap override. The badge validates their choice without being intrusive.

**Estimated lines changed/added:** ~50 lines (new `ContextDetector` extension + ~10 lines wiring in sheet).

**Impact:** 🟡 Medium-High — differentiating feature, meaningfully reduces friction for flight and desk contexts.

***

## 3. Mood as a Planning Input — Psychology Audit

### Academic Research Alignment

Research on mood and task performance consistently shows that:
- **Positive affect** (enthusiasm, alertness) → increased flexibility and creative thinking, but higher distractibility for routine tasks[^15][^16]
- **Negative affect / low arousal** → facilitates single-task depth and reduces distractibility — this is the neurological basis for deep focus states[^15]
- **Task completion itself** replenishes mental energy, particularly when the reward value of the completed task is perceived as high[^17]

Daniel Pink's *When* research (cited in Todoist's methodology) documents a universal three-stage energy arc: peak → trough → rebound — mapping to analytical, administrative, and creative work respectively. Todoist surfaces this as **Peak / Trough / Rebound** labels tied to task energy requirements.[^18][^19]

### Current Mood Taxonomy Assessment

| Mood | Trigger logic | Academic alignment | Verdict |
|---|---|---|---|
| `easy_wins` | `estimatedMinutes <= 5` (PlanningEngine), `<= 15` (DishMeUp filter) | Matches "trough" state — low-energy task clearance[^20] | ✅ Keep, fix the mismatch |
| `avoidance` | `deferredCount >= 2` | Matches procrastination-breaking interventions[^21] | ✅ Keep |
| `deep_focus` | `action` bucket only, `>= 30` min tasks | Maps to negative-affect deep-work state[^15] | ✅ Keep |
| *(missing)* | Admin drain: replies + calls, moderate energy | Maps to Pink's "trough" for communication tasks[^19] | 🔴 Add |

### The `easy_wins` Inconsistency Bug

There is a mismatch between `DishMeUpSheet` and `PlanningEngine`:
- **DishMeUp filter** (line ~264): `$0.estimatedMinutes <= 15` → filters to "quick" tasks
- **PlanningEngine mood bump** (Score.moodEasyWins): only activates at `estimatedMinutes <= 5`

This means a 12-minute task passes the DishMeUp filter but receives zero mood boost in the scoring engine. Fix:

```swift
// PlanningEngine.swift — scoreTask(), mood section:
case .easyWins:
    if task.estimatedMinutes <= 15 {  // was <= 5; align with DishMeUp filter
        moodBump = Score.moodEasyWins
    }
```

Also consider adding `Score.quickWinBump` (150) for tasks ≤ 5 min as a permanent small bonus — the threshold mismatch suggests the original intent was a two-tier quick-win system.

### Add `adminDrain` Mood

```swift
// DishMeUpMood enum:
case adminDrain = "Clear my inbox"

var icon: String {
    // ...
    case .adminDrain: "tray.full.fill"
}
var color: Color {
    // ...
    case .adminDrain: .teal
}
```

```swift
// PlanningEngine — MoodContext enum:
case adminDrain = "admin_drain"

// scoreTask() mood section:
case .adminDrain:
    if task.bucketType == "reply" || task.bucketType == "calls" {
        moodBump = Score.moodEasyWins  // reuse +500
    } else if task.bucketType == "action" || task.bucketType == "read" {
        moodBump = Score.deepFocusKill  // suppress deep work
    }
```

```swift
// DishMeUpSheet generate():
case .adminDrain:
    let comm = filtered.filter { $0.bucket == .reply || $0.bucket == .calls }
    if !comm.isEmpty { filtered = comm }
```

**Should we add "creative"?** The academic case is weaker for a macOS productivity app whose task taxonomy is action/reply/calls/read/transit. "Creative" has no current bucket mapping — it would create an orphan mood with no scoring effect. Defer until a `creative` bucket type is added to the data model.

**Estimated lines changed/added:** ~25 lines (mood enum + generate() + PlanningEngine scoring).

**Impact:** 🟡 Medium — fixes a silent scoring bug and adds the most-requested fourth mood category.

***

## 4. Greedy Knapsack → DP 0-1 Knapsack

### Algorithm Comparison

| Algorithm | Optimality | Time complexity | Space | Best for |
|---|---|---|---|---|
| Greedy (current) | Approximate | O(n log n) | O(n) | Any N, any W |
| First-Fit Decreasing (FFD) | 11/9 × OPT | O(n log n) | O(n) | Bin packing, multiple bins[^22][^23] |
| Best-Fit Decreasing (BFD) | Same as FFD asymptotically | O(n log n) | O(n) | Minimise waste per bin |
| DP 0-1 Knapsack | **Optimal** | O(n × W) | O(n × W) | Single bin, exact solution |
| Branch-and-Bound | Optimal | Exponential worst case | Variable | Small N with tight bounds |

The critical insight: FFD and BFD are **bin packing** algorithms — they minimise the number of bins needed to pack all items. Timed's problem is the inverse: pack the **highest-scoring subset** into a **single bin** (the available time window). This is the 0-1 knapsack problem exactly. The current greedy approach already outperforms FFD/BFD for this variant, but it leaves score-optimality on the floor.[^24][^23]

### Performance Analysis

For n = 50 tasks and W = 480 minutes (maximum reasonable session), the DP table has 50 × 480 = **24,000 cells**. Each cell requires one comparison and one addition. On Apple Silicon, this computes in **< 0.5 ms** — orders of magnitude inside the 100ms latency requirement. Even W = 720 (12h) → 36,000 cells, still < 1ms.[^25]

The current implementation's second-pass fill (smallest-first overflow refill) is already a heuristic approximation of this. The DP replaces both the primary greedy pass and the second-pass fill with a single exact solve.

### Recommended Changes — `PlanningEngine.swift`

Replace steps 4–5 (greedy knapsack + second-pass fill) with a DP solve. The fixed-position tasks (dailyUpdate, familyEmail) remain outside the DP pool as pre-allocated budget deductions — this is correct and should be preserved.

```swift
// PlanningEngine.swift — replace the greedy fill block (~lines 100–150)
// After computing `pool` and `usedMinutes` (fixed-task budget reserved):

let budget = request.availableMinutes - usedMinutes  // remaining after fixed tasks

// Build DP table: dp[i][w] = max total score using first i pool items with w minutes
let n = pool.count
var dp = Array(repeating: Array(repeating: 0, count: budget + 1), count: n + 1)

for i in 1...n {
    let item = pool[i - 1]
    let cost = (request.bucketEstimates[item.task.bucketType].map { Int($0) } 
                ?? item.task.estimatedMinutes) + bufferPerTask
    let value = item.breakdown.totalScore
    for w in 0...budget {
        dp[i][w] = dp[i - 1][w]
        if cost <= w {
            dp[i][w] = max(dp[i][w], dp[i - 1][w - cost] + value)
        }
    }
}

// Backtrack to find selected items
var selected: [(task: PlanTask, breakdown: ScoreBreakdown)] = []
var overflow: [PlanTask] = []
var w = budget
for i in stride(from: n, through: 1, by: -1) {
    let item = pool[i - 1]
    let cost = (request.bucketEstimates[item.task.bucketType].map { Int($0) } 
                ?? item.task.estimatedMinutes) + bufferPerTask
    if cost <= w && dp[i][w] != dp[i - 1][w] {
        selected.append(item)
        w -= cost
    } else {
        overflow.append(item.task)
    }
}
selected.sort { $0.breakdown.totalScore > $1.breakdown.totalScore }
// Overflow: sort by score desc (existing step 8 logic applies)
```

**Key preservation notes:**
- The overdue-cap logic (top 3 overdue get full bump) runs *before* the DP pool is built — this remains unchanged.
- Thompson sampling bumps are already baked into `ScoreBreakdown.totalScore` before this stage — no change needed.
- The `fixedFirst`/`fixedSecond` budget deduction from `usedMinutes` remains identical.

**What we lose:** The current second-pass fill was actually performing a useful two-phase heuristic. The DP replaces this with a strictly superior single-pass exact solution, so nothing is lost.

**Memory note:** `dp` array for n=50, W=480 = 50 × 481 × 8 bytes ≈ 192KB. Fine for a synchronous plangeneration call. For pathological inputs (n=200+), consider a 1D rolling-array DP to reduce to O(W) space.

**Estimated lines changed:** Remove ~50 lines (greedy + second-pass), add ~25 lines (DP). Net: -25 lines.

**Impact:** 🔴 High — plan quality improvement for sessions where multiple small tasks could fill a gap that one large task occupies.

***

## 5. Plan Presentation — Output Stack Upgrades

### How Reclaim and Motion Present Plans

Reclaim renders an auto-generated plan as **calendar time blocks** — each task becomes a coloured event block with duration, shown inline in the week/day calendar view. The mental model is "your day, pre-filled." Motion goes further: it presents a **"What to work on now"** prompt — a single current task with a countdown — plus a scrollable daily agenda showing all scheduled blocks with their projected times. Both tools use timeline/schedule views rather than flat task lists.[^26][^27][^28][^29]

The current `outputStack` in `DishMeUpSheet` is a numbered ordered list — closer to the Focusmate model where the user declares their intent in order. This is the right choice for a macOS sheet (a full calendar timeline would be overkill), but two targeted enhancements close the gap:[^30]

### Recommended Changes — `DishMeUpSheet.swift`

**Enhancement 1: Per-task projected start time**

The stack currently shows `task.timeLabel` (estimated duration) but not when each task starts. Add a computed projected start time to each row:

```swift
// Add computed property to DishMeUpSheet:
private func projectedStartTimes() -> [UUID: Date] {
    var result: [UUID: Date] = [:]
    var cursor = Date()
    for task in stack {
        result[task.id] = cursor
        let corrected = bucketEstimates[task.bucket.rawValue].map { Int($0) } ?? task.estimatedMinutes
        cursor = cursor.addingTimeInterval(TimeInterval((corrected + 5) * 60))
    }
    return result
}
```

In the `outputStack` row, replace the duration label with a two-line time display:

```swift
VStack(alignment: .trailing, spacing: 1) {
    Text(startTimes[task.id].map { timeFormatter.string(from: $0) } ?? "")
        .font(.system(size: 10)).foregroundStyle(.secondary).monospacedDigit()
    Text(task.timeLabel)
        .font(.system(size: 12, weight: .semibold)).monospacedDigit()
        .foregroundStyle(task.bucket.color)
}
```

This shows e.g. "9:00\n15m" on the right side — the same pattern Motion uses for agenda items.[^27]

**Enhancement 2: Session confidence indicator**

Below the "YOUR STACK" header, add utilisation context:

```swift
// Existing: "3 tasks · 45m · finish by 9:47 AM"
// Enhanced: "3 tasks · 45m · finish by 9:47 AM  ··  67% of 1h used"
let utilPct = Int(Double(stackTotal) / Double(minutes) * 100)
Text("\\(utilPct)% of \\(formatMins(minutes)) used")
    .font(.system(size: 11))
    .foregroundStyle(utilPct > 90 ? .orange : .secondary)
```

> Research shows ordered task lists with projected times have significantly higher completion rates than unordered lists — the mechanism is *commitment specificity*: when a user can see "I start this at 9:15", they are more likely to honour it. Focusmate operationalises this by requiring users to write each task in the chat at session start as a pre-commitment device.[^31][^30]

**Estimated lines changed/added:** ~30 lines.

**Impact:** 🟡 Medium — meaningfully increases plan credibility and commitment.

***

## 6. Session Tracking — Overtime Alerts

### Toggl and RescueTime Patterns

Toggl Track uses manual or automatic timer start, with idle detection (prompts if keyboard/mouse inactive for a user-defined period) and Pomodoro mode. RescueTime operates as a passive background observer — it never interrupts the user mid-task, instead surfacing insights in post-session reports. Neither product ships a real-time "you've exceeded your estimate" interrupt during an active session.[^32][^33][^34]

The psychological cost of mid-task interruptions is significant: research at UC Irvine found it takes an average of 23 minutes and 15 seconds to fully regain deep focus after being interrupted. An aggressive overtime alert would therefore trade a small insight gain for a substantial productivity cost.[^35]

### Recommended Design — New `SessionTimerView` or inline `DishMeUpSession`

Rather than interrupting, use a **passive ambient indicator** that becomes visible at the task level when the user returns attention to the app:

**Architecture:** After "Accept & Start" is tapped, pass the ordered `stack` and `startTime = Date()` to a `DishMeUpSessionTracker` singleton:

```swift
// New: Sources/Features/DishMeUp/DishMeUpSessionTracker.swift (~60 lines)
final class DishMeUpSessionTracker: ObservableObject {
    @Published var currentTaskIndex: Int = 0
    @Published var sessionStartedAt: Date = .now
    @Published var taskStartedAt: Date = .now
    var plan: [TimedTask] = []
    var planEstimates: [UUID: Int] = [:]  // taskId -> estimatedMinutes

    var currentTask: TimedTask? { plan[safe: currentTaskIndex] }

    var elapsedOnCurrentTask: Int {
        Int(Date().timeIntervalSince(taskStartedAt) / 60)
    }

    var estimateForCurrent: Int {
        currentTask.flatMap { planEstimates[$0.id] } ?? 0
    }

    var isOverEstimate: Bool {
        elapsedOnCurrentTask > estimateForCurrent + 5  // 5-min grace
    }

    func advanceToNext() {
        // Capture actualMinutes before advancing
        if let task = currentTask {
            CompletionRecord.record(
                taskId: task.id,
                estimatedMinutes: estimateForCurrent,
                actualMinutes: elapsedOnCurrentTask
            )
        }
        currentTaskIndex += 1
        taskStartedAt = .now
    }
}
```

**In the main task row** (wherever the current active task is shown in the app's primary view), add a small amber pill when `isOverEstimate`:

```swift
if tracker.isOverEstimate {
    HStack(spacing: 3) {
        Image(systemName: "clock.badge.exclamationmark").font(.system(size: 10))
        Text("+\\(tracker.elapsedOnCurrentTask - tracker.estimateForCurrent)m")
            .font(.system(size: 10, weight: .semibold))
    }
    .foregroundStyle(.orange)
    .padding(.horizontal, 6).padding(.vertical, 3)
    .background(Color.orange.opacity(0.1), in: Capsule())
}
```

**No modal interruption.** The indicator is visible when the user glances at the app but does not break focus. The user can dismiss by marking the task done or explicitly skipping.

**Estimated lines added:** ~80 lines (new tracker + UI wire-up).

**Impact:** 🟡 Medium — provides the `actualMinutes` data needed to calibrate `bucketEstimates` over time, but must be implemented without harming flow state.

***

## 7. Completion Flow — Capturing `CompletionRecord.actualMinutes`

### Psychology of Task Completion UX

Dopamine release at task completion is one of the most reliable motivational drivers in UX design. Apps like Forest reward session completion with a virtual tree; Duolingo uses streak animations and XP. ADHD research specifically shows that immediate positive reinforcement after task completion creates a conditioned habit loop — the faster the reward, the stronger the conditioning. The key design constraint is *proportionality*: the celebration should match the weight of the task. A 5-minute email reply warrants a subtle animation; a 90-minute deep work block warrants a fuller moment.[^36][^37][^21][^38]

### Recommended Completion Flow

Implement a `TaskCompletionOverlay` that appears when the user marks a DishMeUp task complete during a session. The flow has three tiers based on session context:

**Tier 1: Quick tasks (≤ 10 min estimated)**

Show a 0.5-second spring animation: the task row's background briefly flashes the bucket colour, then the row slides up and collapses. No modal. Automatically begin `taskStartedAt` timer for the next task. Capture actual minutes silently.

```swift
// In the task list, on complete tap:
withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
    completedTaskIds.insert(task.id)
}
// After 0.5s: tracker.advanceToNext()
DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
    tracker.advanceToNext()
}
```

**Tier 2: Standard tasks (11–30 min estimated)**

Show a non-blocking bottom toast for 2.5 seconds:

```swift
// Toast component (new: ~30 lines)
struct CompletionToast: View {
    let task: TimedTask
    let actualMinutes: Int
    let estimatedMinutes: Int
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green).font(.system(size: 16))
            VStack(alignment: .leading, spacing: 1) {
                Text("Done: \\(task.title)").font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                Text(timeDeltaLabel).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            // "Next: X" label if session has remaining tasks
            if let next = tracker.currentTask {
                Text("Next: \\(next.title)").font(.system(size: 11))
                    .foregroundStyle(.secondary).lineLimit(1)
                    .frame(maxWidth: 100)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .shadow(radius: 8, y: 4)
        .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { onDismiss() } }
    }

    private var timeDeltaLabel: String {
        let delta = actualMinutes - estimatedMinutes
        if delta == 0 { return "Right on estimate ✓" }
        if delta > 0  { return "+\\(delta)m over estimate" }
        return "\\(abs(delta))m under estimate"
    }
}
```

**Tier 3: Long tasks (> 30 min estimated) or session completion**

Show a brief modal (2-second auto-dismiss, dismissable earlier) with:
1. Task name + ✓ checkmark (large, animated)
2. Actual vs estimated time delta
3. "Keep going" button → advances to next task
4. "Take a break" button → pauses session timer
5. Auto-advances to next task after 3 seconds if no input

```swift
// DishMeUpCompletionModal: ~60 lines
// Auto-dismiss timer + explicit actions
// Captures actualMinutes via tracker.advanceToNext()
```

**`CompletionRecord.actualMinutes` capture:**

The `advanceToNext()` call in `DishMeUpSessionTracker` is the single point where `actualMinutes` should be written:

```swift
func advanceToNext() {
    guard let task = currentTask else { return }
    let actual = elapsedOnCurrentTask
    let estimated = estimateForCurrent

    // Write to CompletionRecord
    Task {
        try? await DataStore.shared.recordCompletion(
            taskId: task.id,
            estimatedMinutes: estimated,
            actualMinutes: actual
        )
        // Update bucketEstimates rolling mean
        await BucketEstimateService.shared.ingest(
            bucket: task.bucket,
            actualMinutes: actual
        )
    }

    currentTaskIndex += 1
    taskStartedAt = .now
}
```

This feeds the `bucketEstimates` lookup that `PlanningEngine` already uses — closing the learning loop from session → estimate calibration → future plan accuracy.

**Estimated lines added:** ~150 lines (tracker + toast + modal + DataStore write).

**Impact:** 🔴 High — the only feature that makes the system self-improving. Without it, `bucketEstimates` remain static defaults.

***

## Implementation Priority & Line Estimate

| # | Change | Files | Est. Lines | Impact | Effort |
|---|---|---|---|---|---|
| 7 | Completion flow + actualMinutes capture | New tracker + toast + modal + DataStore | ~150 | 🔴 High | 2–3h |
| 4 | DP 0-1 Knapsack (replace greedy) | `PlanningEngine.swift` | -25 net | 🔴 High | 1h |
| 1 | Preset duration expansion (15/30/45/1h/90m/2h) | `DishMeUpSheet.swift` | 3–5 | 🔴 High | 15min |
| 3 | `adminDrain` mood + easyWins threshold fix | `DishMeUpSheet.swift` + `PlanningEngine.swift` | ~25 | 🟡 Medium | 45min |
| 5 | Per-task start times + utilisation % in stack | `DishMeUpSheet.swift` | ~30 | 🟡 Medium | 45min |
| 6 | Session overtime ambient indicator | New `DishMeUpSessionTracker.swift` | ~80 | 🟡 Medium | 1.5h |
| 2 | `NWPathMonitor` context auto-detection | New `ContextDetector` + sheet wiring | ~50 | 🟡 Medium | 1h |

**Total new/changed lines: ~315**
**Implementation sequence:** Do #1 first (zero-risk, immediate user value) → #4 (self-contained algorithm swap) → #7 (enables data loop) → #3 → #5 → #6 → #2.

***

## Architecture Notes

**`DishMeUpMood` ↔ `MoodContext` alignment:** There is currently a translation step in `toMoodContext()`. Adding `adminDrain` requires adding the case to both enums and the translation switch. This is the correct architecture — keep the UI enum (`DishMeUpMood`) decoupled from the engine enum (`MoodContext`) to allow future UI-only moods that don't affect scoring.

**`bucketEstimates` feedback loop:** The full data flow is: `DishMeUpSessionTracker.advanceToNext()` → `DataStore.recordCompletion()` → `BucketEstimateService.ingest()` → next session's `PlanRequest.bucketEstimates`. This loop already exists structurally (the `.task {}` block in `DishMeUpSheet` loads estimates on sheet open) but is broken at the write end — the `actualMinutes` data is never captured. Fixing item #7 closes the loop without any architectural change.

**CoreMotion non-availability on macOS:** Do not add CoreMotion as a dependency for the macOS target. The `CMMotionActivityManager` APIs exist in the macOS SDK headers but return nil activity managers at runtime on Mac hardware. The `NWPathMonitor` approach is sufficient and ships with zero additional permissions or entitlements.

---

## References

1. [Longer Sessions are Here: 75 Minutes of Focus - Focusmate](https://www.focusmate.com/blog/longer-sessions/) - 75-minute sessions help you stay in the flow for longer so you can tackle several small tasks, or ma...

2. [Improving Writing Accountability With Focusmate - Catherine Pope](https://catherinepope.com/posts/improving-writing-accountability-with-focusmate/) - Yes, it does sound a bit creepy, but it's actually highly effective. You choose a 25-, 50-, or 75-mi...

3. [6 Effective Methods to Reduce ADHD Procrastination [2026] - Saner.AI](https://www.saner.ai/blogs/wasted-so-much-time-reduce-adhd-procrastination) - You set a timer (for example, 25–50 minutes), and Forest locks you into that session. ... Choose you...

4. [Sunsama: 17 Features That Will Make You Switch Productivity Tools](https://organizeyouronlinebiz.com/sunsama-features/) - Users can set session lengths and break times according to their personal productivity rhythms. The ...

5. [What's the best productivity app you discovered that actually kills ...](https://www.reddit.com/r/ProductivityApps/comments/1s4gcrs/whats_the_best_productivity_app_you_discovered/) - Tested it myself—cut my morning paralysis by 80%. Poll below: What's your worst daily decision?A) Wh...

6. [Time Management Mistakes That Kill Productivity - Cool Timer](https://cool-timer.com/blog-pages/time-management-mistakes) - Roy Baumeister's landmark research on decision fatigue reveals that ... Reduces completion rates by ...

7. [Making Productive Use of OmniFocus Tags](https://learnomnifocus.com/tutorial/making-productive-use-of-tags-in-omnifocus-3/) - Learn how to make productive use of tags alongside projects, single action lists, and folders. OmniF...

8. [Struggling with GTD Style Filtering with Context, Energy, and Time](https://discourse.omnigroup.com/t/struggling-with-gtd-style-filtering-with-context-energy-and-time/70018) - I am a GTD'er and one of the fundamental methods to selecting your next actions is the combination o...

9. [How I Use Tags in Things 3 - According to Andrea](https://accordingtoandrea.com/2019/06/26/how-i-use-tags-in-things-3/) - Once assigned to an area, tasks are automatically tagged with their respective area tags. Automatica...

10. [This is NOT a complete review of Things 3 - Curtis McHale](https://curtismchale.ca/2019/02/11/this-is-not-a-complete-review-of-things-3/) - While Things 3 doesn't allow nesting of tasks like OmniFocus does, it does allow you to add a simple...

11. [macOS system events for network status in Swift - Stack Overflow](https://stackoverflow.com/questions/51512071/macos-system-events-for-network-status-in-swift) - This is achievable with the NWPathMonitor API. Using it, we can have a function called each time the...

12. [Optimizing your app for Network Reachability - SwiftLee](https://www.avanderlee.com/swift/optimizing-network-reachability/) - You can run your app on an actual device and switch between WiFi, Cellular, and Airplane mode, but o...

13. [ios - CoreMotionActivityManager returning either Automotive or ...](https://stackoverflow.com/questions/45594747/coremotionactivitymanager-returning-either-automotive-or-automotive-stationary) - I'm trying to detect Automotive ActivtyType, however the problem is if "I go on a drive and then sto...

14. [CMMotionActivity - NSHipster](https://nshipster.com/cmmotionactivity/) - CMMotionActivityManager takes raw sensor data from the device and tells you (to what degree of certa...

15. [[PDF] The Impact of Mood on Multitasking Performance and Adaptation](https://digitalcommons.memphis.edu/cgi/viewcontent.cgi?article=2146&context=etd) - Positive and negative moods, therefore, appear to have somewhat opposite effects on task performance...

16. [[PDF] The Effect of Mood on Task Completion Time](https://digitalcommons.lindenwood.edu/cgi/viewcontent.cgi?article=1308&context=psych_journals) - Previous research on task performance outcomes typically supports the hypothesis that negative mood ...

17. [Deriving Mental Energy From Task Completion - Frontiers](https://www.frontiersin.org/journals/psychology/articles/10.3389/fpsyg.2021.717414/full) - Study 1 provides evidence that mental energy is replenished at task completion when the reward value...

18. [How to Craft the Perfect Daily Schedule (According to Science)](https://www.todoist.com/inspiration/daily-schedule) - Crafting your daily schedule with Todoist · Categorize your tasks with labels · Set up custom filter...

19. [How to Prioritize When There's Always More To Do - Todoist](https://www.todoist.com/inspiration/how-to-prioritize) - Prioritization is the process of embracing the limits of your time and energy, freeing yourself from...

20. [Tackle your To-Do List using the Energy Tagging Method](https://planningwithchloe.substack.com/p/tackle-your-to-do-list) - Managing your energy levels can be the key to conquering your to-do list. By organising your tasks b...

21. [From To-Dos to Ta-Das: Celebrating Progress in Neurodiverse Brains](https://nxt.do/blog/from-to-dos-to-ta-das-celebrating-progress-in-neurodiverse-brains) - ADHD research shows that boosting those tiny wins with structured celebrations can rewire our dopami...

22. [First-fit-decreasing bin packing - Wikipedia](https://en.wikipedia.org/wiki/First-fit-decreasing_bin_packing) - First-fit-decreasing (FFD) is an algorithm for bin packing. Its input is a list of items of differen...

23. [Bin Packing Problem - an overview | ScienceDirect Topics](https://www.sciencedirect.com/topics/computer-science/bin-packing-problem) - Simple heuristics like First-Fit Decreasing (FFD) and Best-Fit Decreasing (BFD) sort items in decrea...

24. [Bin Packing Problem (Minimize number of used Bins) - GeeksforGeeks](https://www.geeksforgeeks.org/dsa/bin-packing-problem-minimize-number-of-used-bins/) - First Fit decreasing produces the best result for the sample input because items are sorted first. F...

25. [[PDF] Performance Comparison of Unbounded Knapsack Problem ...](https://ceur-ws.org/Vol-3403/paper21.pdf) - Abstract. This study investigates various linear discrete formulations of the unbounded knapsack pro...

26. [How Reclaim manages your schedule automatically](https://help.reclaim.ai/en/articles/6207587-how-reclaim-manages-your-schedule-automatically) - Reclaim automatically schedules and reschedules events on your calendar, so you don't have to manual...

27. [Motion AI Review (2026): Pricing, Features & Is the AI Calender ...](https://rimo.app/en/blogs/motion-ai_en-US) - Is Motion calendar worth $19/month? We tested Motion's AI auto-scheduling for 30 days. See real resu...

28. [MOTION AI Tutorial 2025: How I Get Things Done With MOTION App](https://www.youtube.com/watch?v=23HDF8VVnVg) - Start your 7-day FREE trial of MOTION AI today — no credit card required! https://hlth.news/get-moti...

29. [Reclaim AI vs Motion (2025): Features, Pricing & AI Scheduling Tool ...](https://aiappgenie.com/post/reclaim-ai-vs-motion) - Reclaim AI offers a free plan with core scheduling features such as smart time-blocking, habit track...

30. [What happens during a Focusmate session? (Do's & Don'ts)](http://support.focusmate.com/en/articles/4044432-what-happens-during-a-focusmate-session-do-s-don-ts) - During a Focusmate session, you simply meet your accountability partner, declare your intentions, an...

31. [Science | Focusmate](https://www.focusmate.com/science/) - The Behavioral Triggers. The behavioral triggers used by Focusmate have been forged deep within the ...

32. [RescueTime vs Toggl Track Comparison (2026) - Apploye](https://apploye.com/blog/rescuetime-vs-toggl/) - The RescueTime assistant gives you the environment of focus work by blocking disturbing apps and sit...

33. [Toggl vs RescueTime: Which One Should You Use? - Timing App](https://timingapp.com/blog/toggl-vs-rescuetime/) - Toggl is one of the oldest time tracking apps and productivity tracking tools that helps you stay aw...

34. [RescueTime VS Toggl Track Comparison – Which one is Better?](https://www.youtube.com/watch?v=oURHwSuhp9Q) - RescueTime VS Toggl Track Comparison – Which one is Better? ---- - Links ---- ➤ https://rescuetime.c...

35. [Information Overload Statistics 2026: Data Overwhelm, Decision ...](https://speakwiseapp.com/blog/information-overload-statistics) - # Information Overload Statistics 2026: Data Overwhelm, Decision Fatigue, and Cognitive Limits

*The...

36. [Boost task completion with dopamine | by Andrés Zapata - UX Planet](https://uxplanet.org/boost-task-completion-with-dopamine-e022ff708096) - Dopamine is released for several reasons, but two, in particular, are of interest for UX designers: ...

37. [The Dopamine Effect in UX Design: How Brain Chemistry Drives ...](https://www.linkedin.com/pulse/dopamine-effect-ux-design-how-brain-chemistry-drives-user-madhesh-p-epthc) - Badges, points, levels—all these game mechanics give users that sweet dopamine hit for task completi...

38. [Gamified Task Management for ADHD: How It Works - MagicTask](https://magictask.io/blog/gamified-task-management-adhd-focus-productivity/) - Discover how gamified task management helps ADHD minds stay focused, motivated, and productive using...

