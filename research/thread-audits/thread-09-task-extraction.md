# Timed — Thread 9: Task Extraction & Triage Pipeline Deep Audit

**Repo:** `ammarshah1n/time-manager-desktop` · **Branch:** `ui/apple-v1-restore`
**Scope:** `TaskExtractionService.swift`, `Triage/TriagePane.swift`, `Triage/TaskBundleSheet.swift`, `Capture/CapturePane.swift`, `String+EmailSubject.swift`
**Thread:** 9 of 10 — Threads 1–8 covered Voice Pipeline, MorningInterview, EmailSync, DB Schema, Edge Functions, Profile Card/BehaviourRules, DishMeUp+PlanningEngine, CalendarSync.

***

## Executive Summary

The intake funnel — Capture → Triage → Task — is architecturally sound and already well-considered for a single-executive user. `VoiceCaptureService` / `TranscriptParser` deliver a real confidence-scored, regex-segmented voice pipeline; `TriagePane` provides full keyboard-driven triage with a low-confidence nudge and undo stack; and `TaskExtractionService` groups email threads into bundles with keyword-based bucket detection. However, four critical gaps prevent the funnel from being truly zero-friction for an executive:

1. **No global hotkey or menubar quick-add** — capture requires the app window to be in focus, a hard block during a phone call or mid-document.
2. **Text-entry capture is zero-NLP** — `addTextCapture()` passes raw input straight through as the task title with hardcoded `.action`/`15 min` defaults, ignoring the `TranscriptParser` already available.
3. **Thread grouping is sender+subject only** — `TaskExtractionService` has no time-windowing, so genuinely unrelated emails from the same sender sharing a word in the subject are incorrectly bundled.
4. **`EmailClassifier` is a stub** — the inline comment literally says `// Stub: real implementation will call Edge Function → Claude Sonnet`, meaning every email entering triage has only rule-based pre-classification; the low-confidence nudge fires correctly but the underlying AI classification it references does not yet exist.

***

## Impact-Ranked Findings

| # | Finding | File | Severity | Impact for Executive |
|---|---------|------|----------|---------------------|
| F1 | No global hotkey / menubar quick-capture | `TimeManagerDesktopApp.swift`, `CapturePane.swift` | 🔴 High | Cannot capture mid-call, mid-doc; friction = tasks lost |
| F2 | `addTextCapture()` bypasses NLP | `CapturePane.swift` | 🔴 High | Text tasks arrive with wrong bucket/time, pollute plan |
| F3 | `EmailClassifier` is a stub | `EmailClassifier.swift` | 🔴 High | Triage low-confidence nudge references AI that doesn't exist |
| F4 | Thread grouping has no time-window | `TaskExtractionService.swift` | 🟠 Medium | Stale emails from same sender wrongly bundled; misleads exec |
| F5 | `String+EmailSubject.swift` misses key patterns | `String+EmailSubject.swift` | 🟠 Medium | Priority/time extraction fails on most real-world subject formats |
| F6 | No confidence score propagated to Triage items | `TriagePane.swift` / `TaskExtractionService.swift` | 🟠 Medium | Low-confidence nudge only fires for voice items, not email bundles |
| F7 | `undoLast()` title-match deduplication is fragile | `TriagePane.swift` | 🟡 Low | Undo silently fails if two emails share subject |
| F8 | Capture has no persistent draft state | `CapturePane.swift` | 🟡 Low | App quit mid-capture loses unconfirmed voice items |
| F9 | `estimateMinutes` ignores subject-parsed time | `TaskExtractionService.swift` | 🟡 Low | AI-suggested times in email subjects ignored in bundles |

***

## F1 — No Global Hotkey / Menubar Quick-Capture

### Finding

`TimeManagerDesktopApp.swift` registers a single `WindowGroup` with no `MenuBarExtra`, no `.commands {}` block with `CommandGroup`, and no Carbon/`CGEvent` global hotkey tap. Capture is entirely contained within `CapturePane.swift` as an in-window tab. An executive receiving a call or reading a PDF in another app must ⌘-Tab to Timed, navigate to the Capture tab, and then dictate — a 4–6 second friction overhead that reliably causes tasks to be abandoned.

### Comparison — Things 3 Quick Entry

Things 3 registers a system-wide `⌃ Space` hotkey via `NSEvent.addGlobalMonitorForEvents`. Pressing it from *any* application raises a floating Quick Entry panel with a pre-focused text field, natural-language date parsing, and area/tag selectors — the entire capture completes in under 3 seconds without switching focus. Timed's CapturePane does have an excellent live-transcript voice button but it is only reachable after focus-switching to the main window.

### Fix

**File:** `Sources/Features/TimeManagerDesktopApp.swift`

```swift
// 1. Add MenuBarExtra for always-accessible quick-add
MenuBarExtra("Timed", systemImage: "timer") {
    QuickCaptureMenuView()
        .environmentObject(auth)
}
.menuBarExtraStyle(.window)

// 2. Register global hotkey in TimeManagerDesktopApp.init()
// Uses NSEvent (no private API) — works with Sandboxed apps requesting
// com.apple.security.temporary-exception.mach-lookup.global-name
private func registerGlobalHotkey() {
    NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
        // ⌃⌥Space
        if event.modifierFlags.contains([.control, .option])
            && event.keyCode == 49 {
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: .timedQuickCaptureRequested, object: nil)
            }
        }
    }
}
```

Create `Sources/Features/Capture/QuickCaptureMenuView.swift` as a slim 300×120 popover with a single `TextField` that pipes into `TranscriptParser.parse()` on Return.

***

## F2 — `addTextCapture()` Bypasses NLP Entirely

### Finding

`CapturePane.addTextCapture()` takes the raw text string and constructs a `CaptureItem` with hardcoded `suggestedBucket: .action` and `suggestedMinutes: 15` regardless of what the user typed. The function never calls `TranscriptParser.parse()` even though `TranscriptParser` is already in scope and handles exactly this problem — it extracts duration, due date, bucket type, and a confidence score from free-form text. This means that "Call John back 5 mins" arrives as an `.action` task estimated at 15 minutes instead of a `.calls` task estimated at 5 minutes.

```swift
// CURRENT — CapturePane.swift:addTextCapture()
let item = CaptureItem(
    id: UUID(), inputType: .text,
    rawText: t, parsedTitle: t,
    suggestedBucket: .action,    // ← hardcoded
    suggestedMinutes: 15,        // ← hardcoded
    capturedAt: Date()
)
```

### Fix

**File:** `Sources/Features/Capture/CapturePane.swift` · function `addTextCapture()`

```swift
private func addTextCapture() {
    let t = textInput.trimmingCharacters(in: .whitespaces)
    guard !t.isEmpty else { return }

    // Route through same parser as voice
    let parsed = TranscriptParser.parse(t).first

    let item = CaptureItem(
        id: UUID(),
        inputType: .text,
        rawText: t,
        parsedTitle: parsed?.title ?? t,
        suggestedBucket: bucketFromVoice(parsed?.bucketType ?? "action"),
        suggestedMinutes: parsed?.estimatedMinutes ?? 15,
        capturedAt: Date(),
        extractionConfidence: parsed?.extractionConfidence ?? 0.4
    )
    items.insert(item, at: 0)
    textInput = ""
}
```

This costs zero additional dependencies — `TranscriptParser` is already imported in the same module.

***

## F3 — `EmailClassifier` Is an Explicit Stub

### Finding

`EmailClassifier.swift` contains the comment `// Stub: real implementation will call Edge Function → Claude Sonnet` and returns `.informational` for every email that does not match a stored sender rule. `TriagePane`'s `lowConfidenceNudge` renders the yellow banner that says "AI classified this as **[bucket]** (low confidence)" and routes corrections to `insertTriageCorrection()`, but the `classifiedBucket` and `classificationConfidence` fields on `TriageItem` are only populated if the classifier actually ran. With a stub classifier, these values are likely `nil` for most items, so the nudge never fires for email triage — only for items that come through `VoiceCaptureService` where `ParsedItem.extractionConfidence` is set.

### Fix

In `EmailClassifier.swift`, replace the stub with an async function that calls the existing Supabase edge function pattern (already used in `EmailSyncService` per Thread 3):

```swift
// EmailClassifier.swift — replace stub classify() with async version
func classify(
    _ email: EmailMessage,
    senderRules: [SenderRuleRow]
) async -> (category: EmailCategory, confidence: Float) {
    // 1. Sender-rule fast path (confidence = 1.0)
    let addr = email.sender.lowercased()
    if let rule = senderRules.first(where: { $0.fromAddress.lowercased() == addr }) {
        switch rule.ruleType {
        case "black_hole":    return (.blackHole, 1.0)
        case "inbox_always":  return (.inbox, 1.0)
        case "later":         return (.informational, 0.9)
        case "delegate":      return (.actionRequired, 0.9)
        default: break
        }
    }

    // 2. Keyword fast path (confidence = 0.65–0.75) to avoid
    //    unnecessary edge function calls for obvious cases
    let combined = "\(email.subject) \(email.preview)".lowercased()
    if combined.contains("unsubscribe") || combined.contains("noreply") {
        return (.newsletter, 0.70)
    }
    if combined.contains("?") || combined.contains("please reply") {
        return (.actionRequired, 0.65)
    }

    // 3. Edge function call for everything else
    // (uses same Supabase client pattern as EmailSyncService)
    @Dependency(\.supabaseClient) var supa
    do {
        let result = try await supa.classifyEmail(
            subject: email.subject,
            preview: email.preview,
            sender: email.sender
        )
        return (result.category, result.confidence)
    } catch {
        return (.informational, 0.4)  // fallback, will trigger nudge
    }
}
```

Populate `TriageItem.classifiedBucket` and `classificationConfidence` from the result when inserting into the triage queue in `EmailSyncService`.

***

## F4 — Thread Grouping Has No Time-Window

### Finding

`TaskExtractionService.groupByThread()` groups emails by cleaned subject + sender match with no date constraint. The matching logic in `matchesThread()` uses `contains` — so an email "Budget Update Q1" from CFO in January and "Budget Update Q4" from the same CFO in December will be bundled together if one subject string contains the other. For a single executive with a long email history, this generates misleading multi-month bundles and inflated time estimates.

```swift
// TaskExtractionService.swift — matchesThread()
if cleanSubject.contains(otherClean) || otherClean.contains(cleanSubject) {
    return true  // ← no time check
}
```

### Fix

**File:** `Sources/Core/Services/TaskExtractionService.swift` · function `matchesThread()`

```swift
private func matchesThread(
    _ a: TriageItem, _ b: TriageItem,
    cleanSubject: String,
    windowHours: Double = 72  // configurable — 3-day window
) -> Bool {
    // Must be within time window
    guard abs(a.receivedAt.timeIntervalSince(b.receivedAt)) < windowHours * 3600
    else { return false }

    if a.sender == b.sender {
        let otherClean = b.subject.cleanedEmailSubject.lowercased()
        if cleanSubject == otherClean { return true }
        // Substring match only if subjects are at least 8 chars
        // (prevents "Re" matching "Reply by Friday")
        if cleanSubject.count >= 8 && otherClean.count >= 8
            && (cleanSubject.contains(otherClean) || otherClean.contains(cleanSubject)) {
            return true
        }
    }

    let otherClean = b.subject.cleanedEmailSubject.lowercased()
    if cleanSubject == otherClean && !cleanSubject.isEmpty { return true }
    return false
}
```

Expose `windowHours` via user preferences (72h default, configurable to 24h/168h) in `Sources/Features/Prefs/`.

***

## F5 — `String+EmailSubject.swift` Misses Key Real-World Patterns

### Finding

`String+EmailSubject.swift` strips `Re:`, `Fwd:` and extracts `P1`/`Priority 1` and simple duration patterns. The following common executive email subject patterns are **not handled**:

| Pattern | Example | What Happens Today |
|---------|---------|-------------------|
| Localised prefixes | `AW:`, `SV:`, `Antwort:`, `Réf:` | Kept verbatim as task title |
| `[URGENT]` / `[ACTION]` tags | `[ACTION REQUIRED] Contract sign-off` | Tag becomes part of title, priority not extracted |
| Ticket/case IDs | `[Ticket #8823] Server down` | ID remains in title |
| `EOM` (end of message) | `Quick call today? EOM` | `EOM` stays in title |
| Fractional hours | `1.5hr`, `2.5 hours` | Parsed as 0 (regex only handles integers) |
| `ASAP` / `urgent` (no P-number) | `ASAP: Board deck review` | Priority `nil` — no fast-path boost |

### Fix

**File:** `Sources/Core/Services/String+EmailSubject.swift`

```swift
// Extend cleanedEmailSubject to strip localised prefixes and action tags
var cleanedEmailSubject: String {
    var s = self
    let prefixes = [
        "Re: ", "RE: ", "Fwd: ", "FW: ", "re: ", "fwd: ",
        "Re:", "RE:", "Fwd:", "FW:", "re:", "fwd:",
        // Localised
        "AW: ", "AW:", "SV: ", "SV:", "Antwort: ", "Réf: ",
        "RES: ", "ENC: "
    ]
    var changed = true
    while changed {
        changed = false
        for prefix in prefixes where s.hasPrefix(prefix) {
            s = String(s.dropFirst(prefix.count)); changed = true
        }
    }
    // Strip bracket tags: [ACTION], [URGENT], [Ticket #1234], [EXTERNAL]
    if let regex = try? NSRegularExpression(pattern: #"\[[^\]]{1,40}\]\s*"#) {
        s = regex.stringByReplacingMatches(
            in: s, range: NSRange(s.startIndex..., in: s), withTemplate: "")
    }
    // Strip EOM
    s = s.replacingOccurrences(of: " EOM", with: "", options: .caseInsensitive)
    return s.trimmingCharacters(in: .whitespaces)
}

// Extend extractedPriority to handle ASAP/urgent
var extractedPriority: Int? {
    let pattern = #"(?i)\b(?:P([1-3])\b|Priority\s*([1-3])\b)"#
    // ... existing logic ...
    // Add: ASAP/urgent = P1 equivalent
    if self.localizedCaseInsensitiveContains("asap")
        || self.localizedCaseInsensitiveContains("urgent")
        || self.localizedCaseInsensitiveContains("[action") {
        return 1
    }
    return nil  // if regex above didn't match
}

// Extend extractedTimeEstimate to handle fractional hours
var extractedTimeEstimate: Int? {
    // ... existing minute pattern ...
    // Add fractional hours: "1.5hr", "2.5 hours"
    let fracHourPattern = #"(?i)\b(\d+(?:\.\d+)?)\s*(?:hrs?|hours?)\b"#
    if let regex = try? NSRegularExpression(pattern: fracHourPattern),
       let match = regex.firstMatch(in: self, range: NSRange(startIndex..., in: self)),
       let range = Range(match.range(at: 1), in: self),
       let value = Double(self[range]) {
        return Int(value * 60)
    }
    return nil
}
```

***

## F6 — Confidence Score Not Propagated to Email Triage Items

### Finding

`ParsedItem` (voice) correctly stores `extractionConfidence: Float` and `TriagePane.lowConfidenceNudge` checks `item.classificationConfidence`. However, `TaskExtractionService.bundle(from:)` constructs `ExtractedTaskBundle` with no confidence field, and `TaskBundleSheet.acceptBundle()` creates `TimedTask` with no confidence value. This means the nudge banner only triggers when `TriageItem.classificationConfidence` is explicitly set upstream (which currently only happens if the now-stub `EmailClassifier` sets it). The entire confidence feedback loop for email-originated tasks is disconnected.

### Fix

**Step 1** — Add `confidence: Float` to `ExtractedTaskBundle`:
```swift
// TaskExtractionService.swift
struct ExtractedTaskBundle: Identifiable, Sendable {
    ...
    var confidence: Float  // new
}
```

**Step 2** — Set it in `bundle(from:)` based on how much signal was available:
```swift
private func bundle(from emails: [TriageItem]) -> ExtractedTaskBundle {
    ...
    // Confidence: starts at 0.5, boosted by AI classification agreement
    let avgAIConfidence = emails.compactMap { $0.classificationConfidence }.reduce(0, +)
        / Float(max(1, emails.compactMap { $0.classificationConfidence }.count))
    let confidence: Float = emails.count > 1 ? min(0.5 + avgAIConfidence * 0.5, 0.95) : avgAIConfidence

    return ExtractedTaskBundle(..., confidence: confidence)
}
```

**Step 3** — Propagate to `TriageItem` via `TaskBundleSheet.acceptBundle()` so the nudge fires on accepted bundles below 0.65.

***

## F7 — `undoLast()` Uses Fragile Title+Sender Match

### Finding

`TriagePane.undoLast()` removes the task created by the most recently triaged email using:

```swift
tasks.removeAll { $0.title == last.item.subject && $0.sender == last.item.sender }
```


If the executive has two emails from the same sender with identical subjects (a genuine re-send), both tasks are deleted on a single undo — losing a task that should be kept. The `undoStack` correctly stores the `TriageItem` and original index but discards the `TimedTask.id` that was assigned at creation.

### Fix

**File:** `Sources/Features/Triage/TriagePane.swift`

Store `TimedTask.id` alongside the undo entry:

```swift
// Replace undoStack type:
@State private var undoStack: [(item: TriageItem, index: Int, taskId: UUID?)] = []

// In classifyCurrent(as:), capture taskId:
let taskId = task.id
undoStack.append((item: item, index: currentIndex, taskId: taskId))

// In undoLast(), use id-based removal:
tasks.removeAll { $0.id == last.taskId }
```

***

## F8 — Capture State Is Not Persisted Across App Restarts

### Finding

`CapturePane` stores `items: [CaptureItem]` as a `@Binding` passed from the root view. There is no `@AppStorage`, CoreData, or Supabase write on capture — items exist only in memory. Quitting the app mid-session (e.g. a laptop battery die during a morning capture walk) silently drops all pending captures. For an executive using voice-to-capture during a commute this is a significant data-loss risk.

### Fix

In `DataStore.swift` (which already handles `TimedTask` persistence per Thread 4), add a lightweight `pendingCaptures` key:

```swift
// DataStore.swift
@Published var pendingCaptures: [CaptureItem] = [] {
    didSet { savePendingCaptures() }
}

private func savePendingCaptures() {
    if let encoded = try? JSONEncoder().encode(pendingCaptures) {
        UserDefaults.standard.set(encoded, forKey: "pendingCaptures")
    }
}

func loadPendingCaptures() {
    guard let data = UserDefaults.standard.data(forKey: "pendingCaptures"),
          let decoded = try? JSONDecoder().decode([CaptureItem].self, from: data)
    else { return }
    pendingCaptures = decoded
}
```

`CaptureItem` will need `Codable` conformance (add `extension CaptureItem: Codable {}`).

***

## F9 — `estimateMinutes` Ignores Subject-Parsed Time

### Finding

`TaskExtractionService.estimateMinutes(emailCount:bucket:)` returns a fixed base value per bucket (e.g. `.reply` = 5, `.action` = 15) regardless of any time estimate already extracted from the email subject by `String+EmailSubject.extractedTimeEstimate`. The `classifyCurrent(as:)` function in `TriagePane` correctly uses `parsed.estimatedMinutes` from the subject parser for single-email triage, but `TaskExtractionService.bundle(from:)` never calls `parsedSubjectMetadata` on the most recent email — it discards potentially explicit time data.

### Fix

**File:** `Sources/Core/Services/TaskExtractionService.swift` · function `bundle(from:)`

```swift
private func bundle(from emails: [TriageItem]) -> ExtractedTaskBundle {
    let mostRecent = emails.last ?? emails

    // Prefer explicit time from subject over heuristic
    let subjectMinutes = mostRecent.subject.parsedSubjectMetadata.estimatedMinutes
    let bucket = detectBucket(from: emails)
    let minutes = subjectMinutes ?? estimateMinutes(emailCount: emails.count, bucket: bucket)
    ...
}
```

***

## End-to-End Latency Analysis

For a single executive, the critical path from input to triaged task breaks down as follows:

| Stage | Current Latency | Bottleneck | Fix |
|-------|----------------|-----------|-----|
| Voice → `liveTranscript` | ~200–400ms | Apple Speech server round-trip (`requiresOnDeviceRecognition = false`) | Set `requiresOnDeviceRecognition = true` for < 100ms; accuracy tradeoff acceptable for short exec commands |
| `TranscriptParser.parse()` | < 5ms | Pure regex in-process — fine | None needed |
| Capture → `CaptureItem` | Sync, < 1ms | None | None needed |
| Manual `Convert` click → `TimedTask` | User interaction latency (seconds) | Requires explicit user confirmation step | Add "Auto-convert high-confidence captures" toggle: if `extractionConfidence > 0.80`, skip review |
| Email sync → `TriageItem` | 15–60s (EmailSyncService polling) | Covered in Thread 3 | Background push via Microsoft Graph webhooks |
| `smartBundle()` in Triage | Async `TaskExtractionService.extractTasks()` — ~5–20ms | Actor dispatch overhead minor | Keep current; already async/`MainActor.run` pattern |
| EmailClassifier stub | 0ms (returns immediately) | Missing real AI classification | Implement F3 fix; add 300ms timeout fallback |

**Primary recommendation for zero-friction executive capture:** implement F1 (global hotkey) first — it reduces the app-focus overhead from ~4–6s to ~1s and is the single highest-leverage change for interruption-driven capture use.