# Onboarding Flow Spec

> Status: Implementation-ready spec
> Last updated: 2026-04-02
> Applies to: Timed macOS intelligence layer

---

## Context

The existing `OnboardingFlow.swift` is a 9-step wizard designed for the v1 "time allocation engine" framing. It collects email cadence, time defaults, transit modes, and PA configuration. This spec redesigns onboarding for the intelligence layer: the system that builds a compounding cognitive model of how the executive operates.

The current flow collects operational preferences. The new flow establishes trust, grants permissions, bootstraps the intelligence model, and gets to the first useful morning session within 24 hours.

---

## Design Constraints

- **Time target:** Complete onboarding in under 5 minutes
- **First useful session:** Within 24 hours of completing onboarding
- **No feature overwhelm:** The executive sees 3 things: privacy promise, Microsoft sign-in, and archetype selection. Everything else is progressive disclosure.
- **Observation-only framing from step 1:** The executive must understand immediately that Timed watches and reflects — it never acts.

---

## Flow: 8 Steps

### Step 1: Welcome + Privacy Explanation

**Time: 30 seconds**

```
┌──────────────────────────────────────────────────┐
│                                                  │
│          [Timed wordmark / logo]                 │
│                                                  │
│   Timed builds a deep model of how you work.     │
│   It observes. It reflects. It never acts.       │
│                                                  │
│   ┌─────────────────────────────────────────┐    │
│   │  Your data stays on this Mac.           │    │
│   │  Raw emails and voice never leave.      │    │
│   │  You can see everything it learns.      │    │
│   │  You can delete everything instantly.   │    │
│   └─────────────────────────────────────────┘    │
│                                                  │
│   [Learn more about privacy]  [Continue →]       │
│                                                  │
└──────────────────────────────────────────────────┘
```

**"Learn more about privacy"** opens a sheet with the full three-tier data classification from `privacy-spec.md`, written in plain English. Not a legal document — a clear explanation.

**Critical:** This is not a checkbox consent form. It is a trust-establishing moment. The tone is direct and confident. No legalese.

### Step 2: Microsoft OAuth (MSAL)

**Time: 30-60 seconds**

```
┌──────────────────────────────────────────────────┐
│                                                  │
│         [Microsoft icon]                         │
│                                                  │
│   Sign in with your Microsoft account.           │
│                                                  │
│   Timed reads your calendar and email to build   │
│   your intelligence model. It never sends        │
│   emails or modifies your calendar.              │
│                                                  │
│   Permissions requested:                         │
│   ✓ Read email (Mail.Read)                       │
│   ✓ Read calendar (Calendars.Read)               │
│   ✓ Offline access                               │
│                                                  │
│   [your@company.com          ]                   │
│                                                  │
│   [Sign in with Microsoft]                       │
│                                                  │
│   [Skip — run locally only]                      │
│                                                  │
└──────────────────────────────────────────────────┘
```

**Implementation:**
1. User enters email hint (pre-populates MSAL login_hint)
2. Click "Sign in with Microsoft" triggers `AuthService.shared.signInWithMicrosoft()`
3. MSAL opens system browser for OAuth consent
4. On success: Supabase Auth session created, Graph access token stored in Keychain
5. On failure: show inline error, allow retry
6. "Skip" allows fully local operation — the user can connect later in Settings

**What happens on success:**
- `AuthService.isSignedIn = true`
- `workspaceId` and `profileId` bootstrapped in Supabase
- `graphAccessToken` stored for email/calendar sync
- Calendar history import begins immediately in the background (see Step 3 background work)

### Step 3: Calendar History Import (90-Day Bootstrap)

**Time: 15 seconds (user waits while progress shows, then moves to next step)**

```
┌──────────────────────────────────────────────────┐
│                                                  │
│         [Calendar icon, animated]                │
│                                                  │
│   Importing your last 90 days of calendar        │
│   history. This gives Timed a head start on      │
│   understanding your patterns.                   │
│                                                  │
│   ████████████░░░░░░░░  47 of 90 days            │
│                                                  │
│   Found so far:                                  │
│   • 234 meetings                                 │
│   • 12 recurring series                          │
│   • Average 4.2 meetings/day                     │
│                                                  │
│   [Continue →]  (enabled after 30 days loaded)   │
│                                                  │
└──────────────────────────────────────────────────┘
```

**Implementation:**
- Calls `GraphClient.fetchCalendarHistory(days: 90)` via delta sync
- Processes into `CalendarBlock` records
- The "Continue" button enables once at least 30 days are loaded (the remaining 60 days import in background)
- If Microsoft sign-in was skipped, this step is skipped entirely

**What the import enables:**
- Day 1 intelligence: "You typically have 4 meetings on Tuesdays, with a 2-hour gap at 10am"
- Chronotype inference: meeting acceptance patterns reveal preferred work hours
- Meeting density baseline: enables drift detection from day 1
- Recurring meeting map: identifies the executive's regular rhythms

### Step 4: Archetype Selection

**Time: 30 seconds**

```
┌──────────────────────────────────────────────────┐
│                                                  │
│   What best describes your role?                 │
│                                                  │
│   This helps Timed start smart on day one.       │
│   It learns your actual patterns over time.      │
│                                                  │
│   ┌─────────────┐  ┌─────────────┐              │
│   │     CEO     │  │     CFO     │              │
│   │ Strategy +  │  │ Finance +   │              │
│   │ stakeholders│  │ reporting   │              │
│   └─────────────┘  └─────────────┘              │
│   ┌─────────────┐  ┌─────────────┐              │
│   │     CTO     │  │     COO     │              │
│   │ Technical + │  │ Operations +│              │
│   │ product     │  │ execution   │              │
│   └─────────────┘  └─────────────┘              │
│   ┌─────────────────────────────┐               │
│   │         General             │               │
│   │  Senior leadership / other  │               │
│   └─────────────────────────────┘               │
│                                                  │
│                            [Continue →]          │
│                                                  │
└──────────────────────────────────────────────────┘
```

**What archetypes pre-load:**

| Archetype | Pre-loaded Scoring Weights | Assumptions |
|-----------|---------------------------|-------------|
| CEO | Strategic tasks +20%, stakeholder comms +15%, people decisions flagged | High meeting density, relationship-driven, delegation patterns |
| CFO | Reporting deadlines +25%, financial review +20%, compliance +15% | Deadline-driven, precision-focused, regulatory awareness |
| CTO | Technical review +20%, architecture decisions +15%, team 1:1s +10% | Deep work blocks important, context-switching costly |
| COO | Operational tasks +20%, process tasks +15%, cross-functional +10% | Execution-focused, high email volume, coordination-heavy |
| General | Balanced weights, no assumptions | Default starting point, learns from scratch |

**Implementation:**
```swift
struct ArchetypeProfile: Codable {
    let archetype: Archetype
    let scoringWeights: [String: Double]   // bucket -> weight modifier
    let initialProceduralRules: [ProceduralRule] // pre-loaded rules
    let chronotypeAssumptions: ChronotypeProfile // default until learned
    let coldStartHints: [String]            // what to look for first
}

enum Archetype: String, Codable, CaseIterable {
    case ceo, cfo, cto, coo, general
}
```

The archetype is a **prior**, not a constraint. It pre-loads `PlanningEngine` scoring weights and initial `ProceduralRule` records. All of these are overwritten as the system observes actual behaviour. By week 2, the archetype matters less. By month 2, it is irrelevant.

### Step 5: First Voice Session Walkthrough

**Time: 60 seconds**

```
┌──────────────────────────────────────────────────┐
│                                                  │
│         [Waveform animation]                     │
│                                                  │
│   Your morning session is a 90-second            │
│   conversation. Timed asks. You talk. It plans.  │
│                                                  │
│   Here's what it sounds like:                    │
│                                                  │
│   ┌─────────────────────────────────────────┐    │
│   │ "Good morning. Based on your calendar,  │    │
│   │  you have 4 meetings today with a       │    │
│   │  2-hour window at 10am.                 │    │
│   │                                         │    │
│   │  What's the most important thing you    │    │
│   │  need to accomplish today?"             │    │
│   └─────────────────────────────────────────┘    │
│                                                  │
│   You respond naturally. Timed builds your day.  │
│                                                  │
│                            [Continue →]          │
│                                                  │
└──────────────────────────────────────────────────┘
```

This step is informational. It shows the executive what to expect tomorrow morning. No interaction required beyond reading and clicking Continue.

**Key messaging:** The morning session is not a chatbot. It is not Siri. It is a cognitive briefing from a system that has spent the night thinking about you. Set expectations high but accurate.

### Step 6: Microphone Permission

**Time: 15 seconds**

```
┌──────────────────────────────────────────────────┐
│                                                  │
│         [Microphone icon]                        │
│                                                  │
│   Timed needs microphone access for your         │
│   morning voice session.                         │
│                                                  │
│   Audio is processed on-device using Apple       │
│   Speech. Raw audio is never stored or           │
│   transmitted.                                   │
│                                                  │
│   [Grant Microphone Access]                      │
│                                                  │
│   [Skip — I'll type instead]                     │
│                                                  │
└──────────────────────────────────────────────────┘
```

**Implementation:**
- Calls `AVCaptureDevice.requestAccess(for: .audio)` via the system permission dialog
- If denied, the morning session falls back to text input mode
- "Skip" allows text-only operation — the user can enable mic later in System Settings

### Step 7: Accessibility Permission (Optional)

**Time: 15 seconds**

```
┌──────────────────────────────────────────────────┐
│                                                  │
│         [Eye icon]                               │
│                                                  │
│   Optional: deeper observation                   │
│                                                  │
│   With Accessibility access, Timed can see       │
│   which apps you focus on and for how long.      │
│   This helps it understand your work patterns.   │
│                                                  │
│   What it sees: app names and durations.         │
│   What it NEVER sees: window content, text,      │
│   or screen recordings.                          │
│                                                  │
│   [Open Accessibility Settings]                  │
│                                                  │
│   [Skip — I don't want this]                     │
│                                                  │
└──────────────────────────────────────────────────┘
```

**Implementation:**
- Cannot request Accessibility programmatically — opens System Settings > Privacy & Security > Accessibility
- The app checks `AXIsProcessTrusted()` to detect if access is granted
- Polls every 2 seconds while this step is visible, advances automatically when granted
- "Skip" is a first-class option. Many executives will skip this. The system works fine without it — app focus data enriches the model but is not required.

**Window title opt-in (NOT part of onboarding):**
Even with Accessibility access, window titles are NOT captured by default. This is a separate opt-in in Settings > Privacy > "Include window titles in observation." Reason: window titles can contain email subjects, document names, and financial data. The default must be safe.

### Step 8: Set Morning Session Time

**Time: 15 seconds**

```
┌──────────────────────────────────────────────────┐
│                                                  │
│         [Clock icon]                             │
│                                                  │
│   When do you want your morning session?         │
│                                                  │
│   Timed will notify you at this time with your   │
│   cognitive briefing and day plan.               │
│                                                  │
│   ┌────────────────────────┐                     │
│   │    [  7 ] : [ 30 ] AM │                     │
│   └────────────────────────┘                     │
│                                                  │
│   You can change this anytime in Settings.       │
│                                                  │
│   [Start my first day →]                         │
│                                                  │
└──────────────────────────────────────────────────┘
```

**Default:** 7:30 AM (adjustable in 15-minute increments, range 5:00 AM - 10:00 AM)

**Implementation:**
- Stored as `@AppStorage("prefs.morningSession.hour")` and `@AppStorage("prefs.morningSession.minute")`
- Schedules a `UNUserNotificationContent` daily notification at the selected time
- The notification opens the Morning Session view directly

---

## Post-Onboarding Background Work

When the user clicks "Start my first day", the following runs immediately in the background:

### 1. Calendar History Analysis (if Microsoft connected)

- Complete the 90-day import if not finished during Step 3
- Run Haiku classification on meeting types (1:1, group, external, board, review)
- Extract recurring meeting patterns
- Calculate meeting density baseline (daily, weekly)
- Infer work hour boundaries from meeting placement
- Write initial `SemanticFact` records: estimated chronotype, meeting cadence, regular rhythms

### 2. Email Sync Bootstrap (if Microsoft connected)

- Run initial `GraphClient.deltaSync()` for the last 7 days of email
- Classify each email via Haiku (sender, subject, truncated body)
- Build initial sender frequency map
- Calculate response time baselines per sender
- Identify "Do First" senders (family surname from executive's email domain)
- Write initial `SemanticFact` records: email volume, top senders, response patterns

### 3. Archetype-Based Pattern Seeding

- Load the selected archetype's `initialProceduralRules` into the procedural memory store
- Pre-populate `BehaviourRule` records in `PlanningEngine` scoring
- Set initial `BucketEstimate` values from archetype defaults
- These are all low-confidence (0.3) — they exist to make day 1 useful, not to persist

### 4. Schedule First Nightly Reflection

- If onboarding completes before 10 PM: schedule the first Opus reflection for tonight at 2 AM
- If onboarding completes after 10 PM: schedule for tomorrow at 2 AM
- The first reflection will have limited data (hours, not days) but will still produce an initial model based on calendar history + archetype priors
- The first morning session will be partially pre-scripted: "This is your first morning with Timed. Here's what I know so far from your calendar..."

### 5. Signal Agents Start

- `EmailSentinelAgent` begins periodic observation
- `CalendarWatcherAgent` begins periodic observation
- `BehaviourObserverAgent` starts (if Accessibility granted)
- `CompletionLoggerAgent` starts (immediate, no permissions needed)
- `DriftDetectorAgent` schedules first run for 2 hours after onboarding

---

## First Morning Session (24 Hours After Onboarding)

The first morning session is special. It has limited intelligence (hours of data, not months) but must still feel valuable.

**What the system knows by morning:**
- 90 days of calendar history (meeting density, recurring patterns, work hours)
- 12-24 hours of email observation (volume, top senders)
- Archetype priors (pre-loaded scoring weights)
- One nightly Opus reflection on the limited dataset

**First morning script structure:**

1. **Greeting + state disclosure:** "Good morning. This is your first session with Timed. I've analysed 90 days of your calendar and your last 24 hours of email."

2. **Calendar pattern (from history):** "You typically have [X] meetings on [day of week], with your largest open block at [time]. Today you have [Y] meetings."

3. **Email state:** "You received [N] emails overnight. [M] are flagged as needing action."

4. **First question:** "What's the most important thing you need to accomplish today?"

5. **Plan delivery:** Standard `PlanningEngine` output with archetype-weighted scoring

6. **Explicit learning signal:** "Timed gets smarter every day. By next week, I'll know your energy patterns. By next month, I'll know your decision patterns. Correct me when I'm wrong — it teaches me faster."

---

## UI Implementation

### Single-Screen Wizard with Progress Indicator

The wizard is a single `NSWindow` (580x560, as in the existing `OnboardingFlow.swift`) with:

- Progress dots at the top (8 dots)
- Animated slide transition between steps (`.move(edge: .trailing)` on enter, `.move(edge: .leading)` on exit)
- "Back" and "Continue" navigation buttons at the bottom
- Dark semi-transparent overlay behind the card

### State Management

```swift
struct OnboardingState {
    var currentStep: Int = 0
    var microsoftConnected: Bool = false
    var calendarImportProgress: Double = 0
    var calendarDaysImported: Int = 0
    var meetingsFound: Int = 0
    var recurringSeriesFound: Int = 0
    var selectedArchetype: Archetype = .general
    var microphoneGranted: Bool = false
    var accessibilityGranted: Bool = false
    var morningSessionHour: Int = 7
    var morningSessionMinute: Int = 30
    var isComplete: Bool = false
}
```

### Persistence

Onboarding completion is stored as `@AppStorage("onboarding.completed")`. If `false` on launch, the onboarding flow presents modally over the root view.

All onboarding choices are stored in `@AppStorage` (existing pattern from `OnboardingUserPrefs`). New keys:

```swift
@AppStorage("onboarding.archetype") var archetype: String = "general"
@AppStorage("onboarding.microsoftConnected") var microsoftConnected: Bool = false
@AppStorage("onboarding.accessibilityGranted") var accessibilityGranted: Bool = false
@AppStorage("onboarding.microphoneGranted") var microphoneGranted: Bool = false
@AppStorage("prefs.morningSession.hour") var morningHour: Int = 7
@AppStorage("prefs.morningSession.minute") var morningMinute: Int = 30
@AppStorage("onboarding.completed") var onboardingCompleted: Bool = false
@AppStorage("onboarding.completedAt") var onboardingCompletedAt: String = ""
```

---

## Migration from Existing Onboarding

The current `OnboardingFlow.swift` has 9 steps that collected operational preferences (work day hours, email cadence, time defaults, transit modes, PA email). These preferences are still useful but are relocated:

| Current Step | New Location |
|-------------|-------------|
| Welcome | Replaced by Step 1 (privacy-first welcome) |
| Accounts | Replaced by Step 2 (Microsoft OAuth) |
| Connect Email | Merged into Step 2 |
| Work Day (hours, start/end) | Moved to Settings > Schedule |
| Email Cadence | Moved to Settings > Email |
| Time Defaults | Removed — ML learns these from completion data |
| Transit | Moved to Settings > Transit |
| PA | Moved to Settings > Sharing |
| Done | Replaced by Step 8 (morning session time) |

**Rationale:** The onboarding should establish the intelligence relationship, not configure a productivity tool. Operational preferences are secondary and can be set later. The executive should feel "this system is about to understand me" — not "I'm configuring another settings panel."

---

## Time Budget

| Step | Action | Time |
|------|--------|------|
| 1 | Read privacy promise, click Continue | 30s |
| 2 | Enter email, click Sign In, complete OAuth | 45s |
| 3 | Watch calendar import progress, click Continue | 15s |
| 4 | Select archetype, click Continue | 15s |
| 5 | Read voice session explanation, click Continue | 30s |
| 6 | Grant microphone permission | 15s |
| 7 | Grant or skip Accessibility | 15s |
| 8 | Set morning time, click Start | 15s |
| **Total** | | **~3 minutes** |

Under the 5-minute target with margin for OAuth delays and reading time.
