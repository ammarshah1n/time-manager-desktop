# Timed — App Focus Observer Spec

**Status:** Implementation-ready
**Last updated:** 2026-04-02
**Layer:** L1 — Signal Ingestion
**Implements:** New file: `AppFocusObserver.swift`, writes to signal queue via `DataStore.swift`
**Dependencies:** `NSWorkspace`, `NSRunningApplication`, `TimedLogger.swift`, `TimedScheduler.swift`

---

## 1. Overview

App focus observation tracks which applications the user is actively using and for how long. This is the only signal source that reveals what the executive actually does between meetings. Context-switch frequency, deep work session duration, and app category distribution feed L2/L3 for cognitive load estimation, chronotype refinement, and productivity pattern detection.

This observer uses only public macOS APIs (`NSWorkspace` notifications, `NSRunningApplication` properties). Window title capture is opt-in and off by default. No keylogging, no screen capture, no content inspection of any kind.

---

## 2. Data Sources

### 2.1 NSWorkspace Notifications

| Notification | Trigger | Data Available |
|-------------|---------|----------------|
| `NSWorkspace.didActivateApplicationNotification` | User switches to a different app | `NSRunningApplication` of the newly active app |
| `NSWorkspace.didDeactivateApplicationNotification` | App loses focus | `NSRunningApplication` of the deactivated app |
| `NSWorkspace.didLaunchApplicationNotification` | App launches | `NSRunningApplication` of the launched app |
| `NSWorkspace.didTerminateApplicationNotification` | App terminates | `NSRunningApplication` of the terminated app |

Primary observation uses `didActivateApplicationNotification` and `didDeactivateApplicationNotification` as a pair to track sessions.

### 2.2 NSRunningApplication Properties

| Property | Type | Captured |
|----------|------|----------|
| `bundleIdentifier` | String? | Yes — primary app identifier |
| `localizedName` | String? | Yes — human-readable app name |
| `isActive` | Bool | Yes — used for validation |
| `activationPolicy` | `.regular`, `.accessory`, `.prohibited` | Yes — filter out background-only apps |
| `processIdentifier` | pid_t | No — not useful for signals |
| `icon` | NSImage? | No — visual only |
| `executableURL` | URL? | No — not needed |

### 2.3 Window Title (Opt-In Only)

When the user explicitly enables window title capture in Settings:

```swift
// Requires Accessibility API permission
// System Preferences > Privacy & Security > Accessibility > Timed.app
func captureWindowTitle(for app: NSRunningApplication) -> String? {
    guard UserDefaults.standard.bool(forKey: "captureWindowTitles") else {
        return nil  // Opt-in not enabled
    }
    
    let appElement = AXUIElementCreateApplication(app.processIdentifier)
    var value: AnyObject?
    let result = AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &value)
    guard result == .success else { return nil }
    
    let windowElement = value as! AXUIElement
    var titleValue: AnyObject?
    let titleResult = AXUIElementCopyAttributeValue(windowElement, kAXTitleAttribute as CFString, &titleValue)
    guard titleResult == .success else { return nil }
    
    return titleValue as? String
}
```

**Default:** OFF. User must explicitly toggle in Settings AND grant Accessibility permission.

**When enabled:** Window titles provide richer signals (e.g., "Q3 Board Deck.xlsx" in Excel vs just "Microsoft Excel"). L3 uses titles for topic extraction.

**When disabled:** Only bundle ID and app name are captured. L3 classifies by app category only.

---

## 3. Session Tracking

### 3.1 Session Model

```swift
struct AppFocusSession: Codable, Identifiable {
    let id: UUID
    let bundleId: String              // e.g., "com.microsoft.Outlook"
    let appName: String               // e.g., "Microsoft Outlook"
    let sessionStart: Date
    var sessionEnd: Date?             // nil while session is active
    var duration: TimeInterval {      // Computed
        (sessionEnd ?? Date()).timeIntervalSince(sessionStart)
    }
    let windowTitle: String?          // nil unless opt-in enabled
    let activationPolicy: AppActivationPolicy
    
    // Metadata
    let capturedAt: Date
    let signalSource: SignalSource    // .appFocus
}
```

### 3.2 Session Lifecycle

```
didActivateApplicationNotification fires
  → Read NSRunningApplication properties
  → Filter: activationPolicy must be .regular (skip menubar-only and background apps)
  → Filter: bundleIdentifier must be non-nil
  → Filter: Skip Timed.app itself (self-observation creates noise)
  → Close the previous active session (set sessionEnd = now)
  → Open a new session (sessionStart = now, sessionEnd = nil)
  → If window title opt-in: capture title via Accessibility API
  → Write closed session to signal queue (if duration >= minimum threshold)

didDeactivateApplicationNotification fires
  → Validate it matches the current active session
  → Close session (sessionEnd = now)
  → Write to signal queue (if duration >= minimum threshold)
```

### 3.3 Minimum Session Duration

Sessions shorter than **2 seconds** are discarded. This filters out:
- Accidental app switches (Cmd+Tab overshoot)
- System dialogs that briefly steal focus
- Spotlight/Alfred/Raycast activations (< 1s for quick launches)

Configurable via `UserDefaults` key `minSessionDurationSeconds` (default: 2).

### 3.4 Idle Detection

If no `didActivateApplicationNotification` fires for **5 minutes**, the current session is suspended:
- Mark session as `idle` (not ended — it may resume).
- If the same app reactivates after idle, extend the existing session but log an idle gap.
- If a different app activates, close the previous session with `sessionEnd = idle start time`.

Idle detection uses `NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .keyDown])` to detect user presence. If no input events for 5 minutes → idle.

```swift
struct IdleGap: Codable {
    let start: Date
    let end: Date
    let duration: TimeInterval
}
```

---

## 4. Context-Switch Logging

Every app transition (session close + session open) constitutes a context switch.

### 4.1 Context Switch Signal

```swift
struct ContextSwitch: Codable {
    let id: UUID
    let fromBundleId: String
    let fromAppName: String
    let toBundleId: String
    let toAppName: String
    let timestamp: Date
    let previousSessionDuration: TimeInterval  // How long they were in the "from" app
}
```

### 4.2 Derived Metrics

```swift
/// Context switches per hour, computed over a rolling window.
func contextSwitchRate(window: DateInterval) -> Double {
    let switches = contextSwitches.filter { window.contains($0.timestamp) }
    let hours = window.duration / 3600
    guard hours > 0 else { return 0 }
    return Double(switches.count) / hours
}

/// A "rapid switch burst" is 5+ context switches within 2 minutes.
/// Indicates scattered attention — high cognitive load signal.
func detectRapidSwitchBursts(window: DateInterval) -> [RapidSwitchBurst] {
    // Sliding 2-minute window over context switches in the period
    // Flag windows with >= 5 switches
}

struct RapidSwitchBurst {
    let start: Date
    let end: Date
    let switchCount: Int
    let apps: [String]  // Bundle IDs involved
}
```

---

## 5. Captured vs Not Captured

### 5.1 Captured

| Data | Source | Stored |
|------|--------|--------|
| Bundle identifier | `NSRunningApplication.bundleIdentifier` | Always |
| App name | `NSRunningApplication.localizedName` | Always |
| Session start time | `didActivateApplicationNotification` timestamp | Always |
| Session end time | `didDeactivateApplicationNotification` timestamp | Always |
| Session duration | Computed from start/end | Always |
| Window title | Accessibility API | Only if opt-in enabled |
| Context switch events | Derived from session transitions | Always |
| Idle gaps within sessions | Input event monitoring | Always |

### 5.2 Not Captured (ever)

| Data | Reason |
|------|--------|
| Keystrokes | Privacy. Not needed for cognitive signal. |
| Screen content | Privacy. Not needed. |
| Mouse position/clicks | Privacy. Not needed. |
| File paths opened | Privacy. Would require FSEvents or Accessibility deep inspection. |
| URLs visited | Privacy. Even with window title opt-in, URL bar content is not specifically targeted. If a browser window title includes a URL, that's incidental to title capture. |
| Clipboard content | Privacy. Never. |
| Other users' activity | Single-user app. |

### 5.3 App Classification

App classification (e.g., "deep work tool", "communication tool", "admin tool") is NOT performed in L1. The focus observer captures raw data only. Classification happens in L2/L3 based on:
- Bundle ID → known app category mapping (maintained in L2)
- Usage patterns (e.g., Terminal used for 90-minute sessions = likely deep work)
- Window titles (if available) for topic extraction
- Cross-signal correlation (e.g., Outlook active during email triage hours)

This separation keeps L1 simple and testable.

---

## 6. Battery and Performance Constraints

### 6.1 CPU Budget

Target: < 1% CPU overhead during normal operation.

`NSWorkspace` notifications are event-driven (not polling). The observer does zero work when the user stays in one app. CPU cost is proportional to context-switch frequency, which is typically 5-15 switches/hour.

### 6.2 Low Power Mode

When `ProcessInfo.processInfo.isLowPowerModeEnabled` returns true:
- **Disable idle detection** (stops global event monitoring, which has non-trivial energy cost).
- **Increase minimum session duration** to 5 seconds (reduce write frequency).
- **Disable window title capture** even if opt-in is enabled (Accessibility API calls have energy cost).
- **Batch writes**: Instead of writing each session immediately, batch into 10-minute groups.

```swift
var isLowPowerMode: Bool {
    ProcessInfo.processInfo.isLowPowerModeEnabled
}

// Subscribe to power state changes
NotificationCenter.default.addObserver(
    forName: NSNotification.Name("NSProcessInfoPowerStateDidChangeNotification"),
    object: nil,
    queue: .main
) { [weak self] _ in
    self?.updatePowerConstraints()
}
```

### 6.3 Memory Budget

Active session tracking uses < 1KB per session. Context switch log is bounded: keep last 1,000 switches in memory, older ones are in CoreData only. Daily signal count is typically 50-150 sessions — negligible memory impact.

---

## 7. macOS Permissions

### 7.1 Required Permissions

| Permission | Why | Fallback if Denied |
|-----------|-----|-------------------|
| None by default | `NSWorkspace` notifications require no special permissions | N/A — always available |

### 7.2 Optional Permissions

| Permission | Why | Fallback if Denied |
|-----------|-----|-------------------|
| **Accessibility** (System Preferences > Privacy > Accessibility) | Required for window title capture via `AXUIElement` | Window titles are nil. Bundle ID and app name still captured. Feature gracefully degrades. |

### 7.3 Permission Request Flow

1. On first launch: do NOT request Accessibility permission. Start observing with basic data (bundle ID, app name, times).
2. In Settings, if user toggles "Capture window titles": show explanation ("Window titles help Timed understand what you're working on — e.g., which document in Excel. No keystrokes, screen content, or URLs are captured.") and trigger `AXIsProcessTrustedWithOptions` with prompt.
3. If user grants: start capturing window titles from that point forward.
4. If user denies or later revokes: detect via `AXIsProcessTrusted()` check before each capture attempt. Gracefully degrade to bundle ID only.

---

## 8. Signal Queue Write Path

### 8.1 Write Path

```
NSWorkspace notification fires
  → Filter (activationPolicy, bundleId, self-exclusion)
  → Close previous session (if exists and duration >= threshold)
  → Open new session
  → On session close:
    → Check low power mode → batch or immediate write
    → Write AppFocusSession to CoreData (DataStore.saveAppFocusSession)
    → Write ContextSwitch to CoreData (DataStore.saveContextSwitch)
    → Update in-memory context switch rate cache
```

### 8.2 Startup and Shutdown

**App startup:**
- Register for all four `NSWorkspace` notifications.
- Read current frontmost app via `NSWorkspace.shared.frontmostApplication`.
- Open an initial session.
- Start idle detection (unless low power mode).

**App shutdown / background:**
- Close current active session with `sessionEnd = now`.
- Write final session to signal queue.
- Unregister notification observers.

**App crash recovery:**
- On next launch, check for unclosed sessions (sessionEnd == nil, capturedAt > 1 hour ago).
- Close them with `sessionEnd = capturedAt + reasonable estimate` (median of that app's historical session duration, or 5 minutes if no history).
- Mark as `recoveredFromCrash = true`.

---

## 9. Acceptance Criteria

### 9.1 Functional

- [ ] App activation/deactivation creates correctly timestamped sessions.
- [ ] Sessions have accurate bundle ID and app name.
- [ ] Sessions shorter than minimum threshold (2s) are discarded.
- [ ] Background-only apps (`.accessory`, `.prohibited` activation policy) are excluded.
- [ ] Timed.app itself is excluded from observation.
- [ ] Context switches are logged with from/to app details and timestamp.
- [ ] Context switch rate is computed correctly per hour.
- [ ] Rapid switch bursts (5+ in 2 min) are detected.
- [ ] Idle detection triggers after 5 minutes of no input.
- [ ] Idle gaps are recorded within sessions.
- [ ] Crashed sessions are recovered on next launch.

### 9.2 Window Title (Opt-In)

- [ ] Window titles are nil when opt-in is disabled (default).
- [ ] Enabling opt-in triggers Accessibility permission request.
- [ ] With Accessibility granted, window titles are captured.
- [ ] If Accessibility revoked, capture degrades to bundle ID only (no crash).
- [ ] Window title capture is disabled in low power mode regardless of opt-in.

### 9.3 Battery and Performance

- [ ] CPU overhead < 1% during normal usage (Instruments Energy gauge, 5-min sample).
- [ ] Memory usage < 5MB for observer + in-memory cache.
- [ ] Low power mode disables idle detection, increases session threshold, disables window titles.
- [ ] Low power mode batches writes into 10-minute groups.
- [ ] Power state changes are detected and constraints updated immediately.

### 9.4 Privacy

- [ ] No keystrokes captured.
- [ ] No screen content captured.
- [ ] No mouse position/clicks captured.
- [ ] No file paths captured.
- [ ] No clipboard content captured.
- [ ] Window titles captured only with explicit opt-in AND Accessibility permission.
- [ ] No data captured from other user accounts on the machine.

### 9.5 Classification Boundary

- [ ] L1 observer does NOT classify apps into categories.
- [ ] No "deep work" / "communication" / "admin" labels in L1 output.
- [ ] Raw signals (bundle ID, times, durations) are written to signal queue for L2/L3 consumption.
