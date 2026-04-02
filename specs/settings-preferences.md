# Settings and User Preferences Spec

> Status: Implementation-ready spec
> Last updated: 2026-04-02
> Applies to: Timed macOS intelligence layer

---

## Design Philosophy

Timed is a system that is mostly invisible. It runs in the menu bar, observes in the background, reflects overnight, and delivers intelligence each morning. The settings panel serves a user who wants to verify, adjust, or understand what the system is doing — not a user who is configuring a productivity tool.

The settings panel has two jobs:
1. Give the executive control over what the system observes and how it delivers intelligence
2. Show the executive what the system has learned (the "About My Model" panel)

Settings are NOT where intelligence is configured. The nightly reflection engine, the four-layer architecture, the memory tiers, and the observation-only constraint are not configurable. They are the product.

---

## What IS Configurable

### 1. Morning Session Time

**Setting:** Hour and minute for the daily morning notification

**Storage:** `@AppStorage("prefs.morningSession.hour")`, `@AppStorage("prefs.morningSession.minute")`

**Default:** 7:30 AM

**Range:** 5:00 AM - 10:00 AM, 15-minute increments

**Implementation:** Reschedules the `UNNotificationRequest` whenever changed. The notification triggers the morning session view.

```swift
func scheduleMorningNotification(hour: Int, minute: Int) {
    let center = UNUserNotificationCenter.current()
    center.removePendingNotificationRequests(withIdentifiers: ["morning-session"])

    let content = UNMutableNotificationContent()
    content.title = "Your morning briefing is ready"
    content.body = "Timed has been thinking about your day."
    content.sound = .default

    var dateComponents = DateComponents()
    dateComponents.hour = hour
    dateComponents.minute = minute
    let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)

    let request = UNNotificationRequest(identifier: "morning-session", content: content, trigger: trigger)
    center.add(request)
}
```

### 2. Alert Frequency

**Setting:** How often Timed surfaces proactive intelligence alerts throughout the day

**Options:**
- **Low:** Max 2 alerts/day. Only critical anomalies (missed deadline risk, major schedule change, relationship going cold with key stakeholder). For the executive who wants Timed to be near-silent.
- **Medium (default):** Max 5 alerts/day. Includes low + pattern observations, energy warnings, attention allocation drift. The recommended setting for most users.
- **High:** Max 10 alerts/day. Includes medium + minor pattern updates, meeting preparation context, communication load warnings. For the first month of use, to see what the system detects.

**Storage:** `@AppStorage("prefs.alerts.frequency")` — values: `"low"`, `"medium"`, `"high"`

**Implementation:** The `DriftDetectorAgent` and `IntelligenceDelivery` layer check this setting before surfacing alerts. The alert budget is tracked daily and resets at midnight.

```swift
struct AlertBudget {
    let maxPerDay: Int
    var alertsToday: Int = 0
    var lastResetDate: Date = .distantPast

    mutating func canAlert() -> Bool {
        let calendar = Calendar.current
        if !calendar.isDateInToday(lastResetDate) {
            alertsToday = 0
            lastResetDate = Date()
        }
        return alertsToday < maxPerDay
    }

    mutating func recordAlert() {
        alertsToday += 1
    }

    static func budget(for frequency: String) -> AlertBudget {
        switch frequency {
        case "low":    return AlertBudget(maxPerDay: 2)
        case "high":   return AlertBudget(maxPerDay: 10)
        default:       return AlertBudget(maxPerDay: 5)
        }
    }
}
```

### 3. Signal Sources (Enabled/Disabled)

Each signal source can be independently toggled:

| Signal Source | Default | Storage Key | Requires |
|--------------|---------|-------------|----------|
| Email observation | ON (if Microsoft connected) | `prefs.signals.email` | Microsoft OAuth |
| Calendar observation | ON (if Microsoft connected) | `prefs.signals.calendar` | Microsoft OAuth |
| Voice sessions | ON (if mic granted) | `prefs.signals.voice` | Microphone permission |
| App focus tracking | OFF | `prefs.signals.appFocus` | Accessibility permission |
| Task behaviour | ON | `prefs.signals.taskBehaviour` | None |
| Completion logging | ON | `prefs.signals.completionLogging` | None |

**Implementation:** The `AgentCoordinator` checks these flags before starting each agent. Disabling a signal source stops the corresponding agent immediately and excludes that signal type from future reflection cycles. Existing episodic memories from that source are NOT deleted — they just stop accumulating.

```swift
func isSignalSourceEnabled(_ source: SignalSource) -> Bool {
    switch source {
    case .email:       return UserDefaults.standard.bool(forKey: "prefs.signals.email")
    case .calendar:    return UserDefaults.standard.bool(forKey: "prefs.signals.calendar")
    case .voice:       return UserDefaults.standard.bool(forKey: "prefs.signals.voice")
    case .behaviour:   return UserDefaults.standard.bool(forKey: "prefs.signals.appFocus")
    case .task:        return UserDefaults.standard.bool(forKey: "prefs.signals.taskBehaviour")
    }
}
```

### 4. Data Retention Period

**Setting:** How long episodic memories are retained before archival

**Options:**
- 30 days
- 90 days (default)
- 180 days
- 1 year
- Forever

**Storage:** `@AppStorage("prefs.data.retentionDays")` — values: `30`, `90`, `180`, `365`, `0` (forever)

**What "retention" means:** Episodic memories older than the retention period are archived: their `content` and `rawData` fields are cleared, but the metadata (timestamp, source, category, importanceScore) is preserved. Semantic facts and procedural rules derived from those memories are NEVER deleted — the intelligence is permanent, only the raw evidence expires.

```swift
func archiveExpiredMemories(retentionDays: Int) async throws {
    guard retentionDays > 0 else { return } // "Forever" — skip

    let cutoff = Calendar.current.date(byAdding: .day, value: -retentionDays, to: Date())!
    let context = persistentContainer.newBackgroundContext()

    try await context.perform {
        let fetch = NSFetchRequest<EpisodicMemoryEntity>(entityName: "EpisodicMemoryEntity")
        fetch.predicate = NSPredicate(format: "timestamp < %@ AND isArchived == NO", cutoff as NSDate)

        let expired = try context.fetch(fetch)
        for memory in expired {
            memory.content = "[archived]"
            memory.rawDataJSON = nil
            memory.isArchived = true
            // Keep: id, timestamp, source, category, importanceScore, embedding
        }
        try context.save()
    }
}
```

### 5. Privacy Controls

#### Window Title Opt-In

**Setting:** Whether Timed captures window titles (not just app names) when Accessibility is enabled

**Default:** OFF (even with Accessibility permission granted)

**Storage:** `@AppStorage("prefs.privacy.captureWindowTitles")`

**UI text:** "Include window titles in observation. Window titles may contain document names, email subjects, and other sensitive text. Only enable this if you want Timed to understand which specific documents and emails you focus on."

#### Per-Sender Email Opt-Out

**Setting:** List of email addresses excluded from all Timed processing

**Storage:** CoreData entity `SenderExclusionEntity` (not UserDefaults — can be many entries)

**UI:** Searchable list showing all observed senders with a toggle for each. Also supports manual email entry for pre-emptive exclusion.

```
┌─────────────────────────────────────────────────┐
│  Excluded Senders                               │
│                                                 │
│  Emails from these senders are invisible to     │
│  Timed. They are not classified, not tracked,   │
│  and not included in pattern analysis.          │
│                                                 │
│  [Search senders...              ]              │
│                                                 │
│  lawyer@firm.com          [✓ Excluded]          │
│  therapist@practice.com   [✓ Excluded]          │
│  wife@personal.com        [✓ Excluded]          │
│                                                 │
│  [+ Add email address]                          │
└─────────────────────────────────────────────────┘
```

#### Cloud Sync Toggle

**Setting:** Whether anonymised intelligence syncs to Supabase

**Default:** ON (if Supabase connected)

**Storage:** `@AppStorage("prefs.privacy.cloudSync")`

**When OFF:** All data stays on-device. The nightly reflection engine runs locally via the XPC service using Anthropic API calls directly (not via Supabase Edge Functions). Supabase is not contacted at all. The user loses cross-device sync and cloud backup, but gains maximum privacy.

### 6. Voice Language

**Setting:** Language for Apple Speech recognition and voice output

**Storage:** `@AppStorage("prefs.voice.language")`

**Default:** System language, falling back to `en-GB`

**Options:** All languages supported by Apple Speech on macOS. Grouped by region:
- English: en-GB, en-US, en-AU
- Other: languages available on the user's system

**Voice selection:** Reuses the existing `VoiceTab` in `PrefsPane.swift` which shows premium voices grouped by language with preview capability.

### 7. Appearance

**Setting:** Visual theme

**Options:**
- System (follows macOS appearance)
- Dark
- Light

**Storage:** `@AppStorage("prefs.appearance.theme")` — values: `0` (system), `1` (light), `2` (dark)

**Implementation:** Already implemented in `AppearanceTab` in `PrefsPane.swift`. No changes needed.

---

## What Is NOT Configurable

These are architectural decisions, not preferences. They are hard-coded and not exposed in Settings.

### 1. Observation-Only Constraint

Timed never acts on the world. No setting to enable "auto-reply to emails" or "auto-schedule meetings." This boundary is non-negotiable and is enforced at the architecture level (no write permissions on Microsoft Graph, no `Mail.Send` scope).

### 2. Four-Layer Architecture

The signal ingestion -> memory store -> reflection engine -> delivery pipeline is not reconfigurable. The user cannot disable the reflection engine, bypass memory, or add custom processing layers.

### 3. Reflection Engine Cadence

The nightly Opus reflection always runs. The user cannot change it to weekly, disable it, or substitute a cheaper model. The nightly reflection IS the product.

The user CAN control what data feeds into it (via signal source toggles) but not whether it runs or how deeply it analyses.

### 4. Memory Tier Structure

Episodic, semantic, and procedural memory tiers are fixed. The user cannot merge them, add custom tiers, or change the consolidation logic.

### 5. Model Selection

Haiku for real-time classification, Sonnet for daily patterns, Opus at max effort for nightly reflection. Not configurable. Intelligence quality is the product.

---

## How Corrections Feed Back

Every user interaction with Timed's intelligence output generates a signal that feeds back into the learning loop. This is not a settings panel feature — it is the mechanism by which the system improves. But the user should understand that their interactions teach the system.

### Re-Ranking a Task

**User action:** Drags a task from position 3 to position 1 in the day plan.

**Signal generated:** `TaskReRankSignal(taskId, fromPosition: 3, toPosition: 1, timestamp)`

**What the system learns:** The `PlanningEngine`'s Thompson sampling updates its posterior distribution for that task's bucket and attributes. If the user consistently promotes "reply" tasks over "action" tasks on Mondays, the system learns a Monday-specific bucket preference.

**Implementation:** Already partially implemented in `PlanningEngine.swift` via `BucketCompletionStat` and Thompson sampling. The re-rank signal is a new signal type that feeds the same posterior update.

```swift
struct TaskReRankSignal: SignalEvent {
    let taskId: UUID
    let fromPosition: Int
    let toPosition: Int
    let timestamp: Date
    let dayOfWeek: Int
    let timeOfDay: Int // hour
    let currentMood: MoodContext?
}
```

### Dismissing a Pattern

**User action:** In the morning session, the system says "You've been avoiding the head of sales 1:1 for 4 days." The user taps "Dismiss" or says "That's not relevant."

**Signal generated:** `PatternDismissalSignal(patternId, reason: .notRelevant, timestamp)`

**What the system learns:** The semantic fact's confidence score is reduced. If the same pattern is dismissed 3 times, the system stops surfacing it. The procedural rule associated with it (if any) has its confidence reduced.

```swift
func handlePatternDismissal(_ patternId: UUID) async {
    guard var fact = await memoryStore.semanticFact(for: patternId) else { return }
    fact.confidence = max(0.0, fact.confidence - 0.15) // Reduce by 15% per dismissal

    // If confidence drops below threshold, deactivate associated rules
    if fact.confidence < 0.3 {
        let relatedRules = await memoryStore.rulesLinkedTo(factId: fact.id)
        for var rule in relatedRules {
            rule.isActive = false
            await memoryStore.updateRule(rule)
        }
    }

    await memoryStore.updateFact(fact)

    // Record the dismissal as an episodic memory for the next reflection
    let signal = SignalEvent(
        source: .task,
        eventType: .patternDismissed,
        payload: PatternDismissalPayload(patternId: patternId, reason: "user dismissed as not relevant")
    )
    try? await memoryWriter.record(signal)
}
```

### Extending a Timer

**User action:** Focus timer was set for 30 minutes. User extends to 45 minutes.

**Signal generated:** `TimerExtensionSignal(taskId, originalMinutes: 30, extendedTo: 45, timestamp)`

**What the system learns:** The EMA (exponential moving average) for that task's bucket is updated. The `BucketEstimate` for that bucket type shifts upward. Over multiple extensions, the system learns that this user consistently underestimates this type of task.

**Implementation:** Already partially implemented in `InsightsEngine.swift` accuracy tracking. The extension signal feeds the same EMA update as task completion.

```swift
func handleTimerExtension(taskId: UUID, bucket: TaskBucket, originalMinutes: Int, extendedMinutes: Int) async {
    // Update EMA with the extended time as the "actual" duration
    var estimates = try? await DataStore.shared.loadBucketEstimates()
    if var estimate = estimates?[bucket.rawValue] {
        let alpha: Double = 0.3 // EMA smoothing factor
        estimate.meanMinutes = alpha * Double(extendedMinutes) + (1 - alpha) * estimate.meanMinutes
        estimate.sampleCount += 1
        estimate.lastUpdatedAt = Date()
        estimates?[bucket.rawValue] = estimate
        try? await DataStore.shared.saveBucketEstimates(estimates ?? [:])
    }
}
```

### Dismissing an Alert

**User action:** A proactive alert says "You've been in back-to-back meetings for 3 hours. Consider a break before your strategy session." User dismisses it.

**Signal generated:** `AlertDismissalSignal(alertType, timestamp, context)`

**What the system learns:** The alert calibration model updates. If the user consistently dismisses "meeting fatigue" alerts at the 3-hour mark but engages with them at the 4-hour mark, the threshold shifts to 4 hours for this specific user.

```swift
struct AlertCalibration: Codable {
    let alertType: String
    var dismissalCount: Int = 0
    var engagementCount: Int = 0
    var currentThreshold: Double // e.g., hours of meetings before alerting
    var lastAdjustedAt: Date

    mutating func recordDismissal() {
        dismissalCount += 1
        // If dismissed 3 times at current threshold, increase threshold by 20%
        if dismissalCount >= 3 && dismissalCount > engagementCount * 2 {
            currentThreshold *= 1.2
            dismissalCount = 0
            engagementCount = 0
            lastAdjustedAt = Date()
        }
    }

    mutating func recordEngagement() {
        engagementCount += 1
        // If engaged with 3 times at current threshold, it's well-calibrated
        // Optionally decrease threshold slightly if engagement is high
        if engagementCount >= 5 && dismissalCount < 2 {
            currentThreshold *= 0.95 // Slightly more sensitive
            engagementCount = 0
            dismissalCount = 0
            lastAdjustedAt = Date()
        }
    }
}
```

### Correcting a Fact in "About My Model"

**User action:** In the "About My Model" panel, the user sees "Peak analytical performance: 9:30-11:30" and clicks "This is wrong."

**Signal generated:** `FactCorrectionSignal(factId, correctionType: .incorrect, userNote: "I'm best after lunch", timestamp)`

**What the system learns:** The semantic fact is marked as user-corrected. The nightly reflection engine receives this correction as high-priority input. The next reflection cycle re-evaluates the evidence for this fact, looking specifically for contradictory signals. If the user provides a note ("I'm best after lunch"), it becomes an episodic memory with maximum importance score.

```swift
func handleFactCorrection(factId: UUID, userNote: String?) async {
    // Mark fact as disputed
    guard var fact = await memoryStore.semanticFact(for: factId) else { return }
    fact.confidence = 0.2 // Drop to low confidence — needs re-evaluation
    fact.updatedAt = Date()
    await memoryStore.updateFact(fact)

    // Record correction as high-importance episodic memory
    let signal = SignalEvent(
        source: .task,
        eventType: .userCorrection,
        payload: CorrectionPayload(
            factId: factId,
            originalFact: fact.fact,
            userNote: userNote,
            importanceOverride: 1.0 // Maximum importance
        )
    )
    try? await memoryWriter.record(signal)
}
```

---

## Settings UI Structure

### Tab Layout

The settings window uses a macOS-native `TabView` with the following tabs:

| Tab | Icon | Contents |
|-----|------|----------|
| Schedule | `clock` | Morning session time, work hours (start/end) |
| Signals | `antenna.radiowaves.left.and.right` | Signal source toggles, sync frequency |
| Privacy | `lock.shield` | Window title toggle, sender exclusions, cloud sync toggle, FileVault status |
| Alerts | `bell` | Alert frequency (low/medium/high), quiet hours |
| Voice | `waveform` | Language, voice selection, speaking rate |
| Appearance | `paintbrush` | Theme (system/light/dark), accent colour |
| About My Model | `brain` | Full model inspection panel (see privacy-spec.md) |
| Account | `person.crop.circle` | Microsoft connection status, Supabase status, sign out, delete all data |

### Implementation: Evolution of Existing PrefsPane.swift

The existing `PrefsPane.swift` has 8 tabs (accounts, sync, blocks, notifications, appearance, voice, sharing, learning) with several hidden behind `v1BetaMode = true`. The new structure replaces this:

```swift
struct PrefsPane: View {
    @State private var tab = PrefTab.schedule

    var body: some View {
        TabView(selection: $tab) {
            ScheduleTab()
                .tabItem { Label("Schedule", systemImage: "clock") }
                .tag(PrefTab.schedule)

            SignalsTab()
                .tabItem { Label("Signals", systemImage: "antenna.radiowaves.left.and.right") }
                .tag(PrefTab.signals)

            PrivacyTab()
                .tabItem { Label("Privacy", systemImage: "lock.shield") }
                .tag(PrefTab.privacy)

            AlertsTab()
                .tabItem { Label("Alerts", systemImage: "bell") }
                .tag(PrefTab.alerts)

            VoiceTab() // Existing implementation
                .tabItem { Label("Voice", systemImage: "waveform") }
                .tag(PrefTab.voice)

            AppearanceTab() // Existing implementation
                .tabItem { Label("Appearance", systemImage: "paintbrush") }
                .tag(PrefTab.appearance)

            AboutMyModelView()
                .tabItem { Label("About My Model", systemImage: "brain") }
                .tag(PrefTab.model)

            AccountTab()
                .tabItem { Label("Account", systemImage: "person.crop.circle") }
                .tag(PrefTab.account)
        }
        .padding(20)
        .frame(minWidth: 600, minHeight: 440)
        .navigationTitle("Timed Settings")
    }

    enum PrefTab {
        case schedule, signals, privacy, alerts, voice, appearance, model, account
    }
}
```

### Schedule Tab

```swift
struct ScheduleTab: View {
    @AppStorage("prefs.morningSession.hour") private var morningHour = 7
    @AppStorage("prefs.morningSession.minute") private var morningMinute = 30
    @AppStorage("onboarding_workStartHour") private var workStart = 9
    @AppStorage("onboarding_workEndHour") private var workEnd = 18

    var body: some View {
        Form {
            Section("Morning Session") {
                HStack {
                    Text("Daily briefing at")
                    Spacer()
                    Picker("Hour", selection: $morningHour) {
                        ForEach(5...10, id: \.self) { Text("\($0)").tag($0) }
                    }
                    .frame(width: 60)
                    Text(":")
                    Picker("Minute", selection: $morningMinute) {
                        ForEach([0, 15, 30, 45], id: \.self) { Text(String(format: "%02d", $0)).tag($0) }
                    }
                    .frame(width: 60)
                }
                .onChange(of: morningHour) { _, _ in rescheduleNotification() }
                .onChange(of: morningMinute) { _, _ in rescheduleNotification() }
            }

            Section("Work Window") {
                Stepper("Work starts at \(workStart):00", value: $workStart, in: 5...12)
                Stepper("Work ends at \(workEnd):00", value: $workEnd, in: 14...23)
                Text("Timed uses these to schedule tasks within your work hours and track after-hours patterns.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
```

### Signals Tab

```swift
struct SignalsTab: View {
    @AppStorage("prefs.signals.email") private var emailEnabled = true
    @AppStorage("prefs.signals.calendar") private var calendarEnabled = true
    @AppStorage("prefs.signals.voice") private var voiceEnabled = true
    @AppStorage("prefs.signals.appFocus") private var appFocusEnabled = false
    @AppStorage("prefs.signals.taskBehaviour") private var taskBehaviourEnabled = true
    @AppStorage("prefs.signals.completionLogging") private var completionEnabled = true

    private var microsoftConnected: Bool { AuthService.shared.isSignedIn }
    private var micGranted: Bool { AVCaptureDevice.authorizationStatus(for: .audio) == .authorized }
    private var accessibilityGranted: Bool { AXIsProcessTrusted() }

    var body: some View {
        Form {
            Section("Signal Sources") {
                SignalRow(
                    label: "Email observation",
                    detail: "Monitors inbox for communication patterns, response times, and sender dynamics",
                    isOn: $emailEnabled,
                    available: microsoftConnected,
                    unavailableReason: "Requires Microsoft sign-in"
                )
                SignalRow(
                    label: "Calendar observation",
                    detail: "Tracks meeting density, cancellations, and schedule patterns",
                    isOn: $calendarEnabled,
                    available: microsoftConnected,
                    unavailableReason: "Requires Microsoft sign-in"
                )
                SignalRow(
                    label: "Voice sessions",
                    detail: "Processes morning sessions for task extraction and cognitive state",
                    isOn: $voiceEnabled,
                    available: micGranted,
                    unavailableReason: "Requires microphone permission"
                )
                SignalRow(
                    label: "App focus tracking",
                    detail: "Tracks which apps you use and for how long. App names only — no window content.",
                    isOn: $appFocusEnabled,
                    available: accessibilityGranted,
                    unavailableReason: "Requires Accessibility permission"
                )
                SignalRow(
                    label: "Task behaviour",
                    detail: "Tracks task deferrals, re-rankings, and priority changes",
                    isOn: $taskBehaviourEnabled,
                    available: true,
                    unavailableReason: ""
                )
                SignalRow(
                    label: "Completion logging",
                    detail: "Records task completion times to improve estimates",
                    isOn: $completionEnabled,
                    available: true,
                    unavailableReason: ""
                )
            }

            Section {
                Text("Disabling a signal source stops future observation for that type. Existing data from that source is preserved — it just stops growing.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
```

### Privacy Tab

```swift
struct PrivacyTab: View {
    @AppStorage("prefs.privacy.captureWindowTitles") private var captureWindowTitles = false
    @AppStorage("prefs.privacy.cloudSync") private var cloudSyncEnabled = true
    @State private var fileVaultEnabled = false
    @State private var showSenderExclusions = false

    var body: some View {
        Form {
            Section("Observation Depth") {
                Toggle("Include window titles in observation", isOn: $captureWindowTitles)
                Text("Window titles may contain document names, email subjects, and financial data. When OFF, only app names are recorded.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Cloud Sync") {
                Toggle("Sync anonymised intelligence to cloud", isOn: $cloudSyncEnabled)
                Text("When ON, anonymised patterns (no names, no email content) sync to Timed's secure backend for backup. When OFF, all data stays on this Mac only.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Sender Exclusions") {
                Button("Manage excluded senders...") {
                    showSenderExclusions = true
                }
                Text("Emails from excluded senders are completely invisible to Timed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Device Security") {
                HStack {
                    Text("FileVault disk encryption")
                    Spacer()
                    if fileVaultEnabled {
                        Label("Enabled", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.callout)
                    } else {
                        Label("Not enabled", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .font(.callout)
                    }
                }
                if !fileVaultEnabled {
                    Text("Your disk is not encrypted. Timed stores sensitive data locally. Enable FileVault in System Settings > Privacy & Security.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            Section("Data") {
                NavigationLink("About My Model") {
                    AboutMyModelView()
                }
                Button("Export all my data...") {
                    // JSON export
                }
                Button("Delete all my data", role: .destructive) {
                    // Two-step deletion confirmation
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { fileVaultEnabled = verifyFileVaultEnabled() }
        .sheet(isPresented: $showSenderExclusions) {
            SenderExclusionSheet()
        }
    }
}
```

### About My Model Panel

The largest and most important settings panel. Full specification in `privacy-spec.md`, section "Transparent Model Inspection."

**Key design decisions:**
- Left sidebar navigation: What I Know, How I Operate, Core Memory, Data Inventory, Privacy Controls
- Each semantic fact shows confidence, evidence count, last updated
- Each procedural rule shows trigger/action in plain English, activation count
- Every learned item has a "This is wrong" button
- Every rule has a "Disable this rule" toggle
- The panel is read-heavy, not write-heavy — it's an inspection tool, not a configuration tool

---

## Settings for a System That's Mostly Invisible

Most settings panels exist because the user needs to configure the software. Timed's settings panel exists because the user needs to TRUST the software.

### What the user will actually visit:

1. **Week 1:** "About My Model" — curiosity about what it learned. Privacy controls — verifying what's tracked.
2. **Month 1:** Alert frequency — adjusting after calibration. Maybe disabling a signal source.
3. **Month 3:** "About My Model" — impressed by depth of patterns. Showing a colleague.
4. **Month 6:** Rarely. The system is calibrated. Settings visits indicate either a problem or a demo.

### Design implications:

- "About My Model" should be the most prominent, most polished tab
- Privacy controls should feel transparent and empowering, not defensive
- Signal source toggles should show what the system GAINS from each source, not just what it collects
- The "Delete all data" button should be visible and accessible — its presence builds trust even if never used
- No settings should require understanding of the underlying ML architecture

---

## Persistence Strategy

| Setting | Storage | Reason |
|---------|---------|--------|
| UI preferences (theme, accent) | `@AppStorage` (UserDefaults) | Lightweight, survives reinstall |
| Morning session time | `@AppStorage` | Needs to be read before CoreData is loaded |
| Signal source toggles | `@AppStorage` | Read at agent startup, before CoreData |
| Alert frequency | `@AppStorage` | Read frequently by delivery layer |
| Privacy controls | `@AppStorage` | Must be respected before any data processing |
| Sender exclusions | CoreData | Can be many entries, needs search |
| About My Model data | CoreData (read-only display) | Already in memory store |
| Alert calibration thresholds | CoreData | Per-alert-type learned values |

**Rule from CLAUDE.md:** "NEVER use UserDefaults for anything beyond UI preferences." The settings here are UI preferences and agent control flags, which qualifies. Learned values (calibration thresholds, correction signals) go to CoreData.
