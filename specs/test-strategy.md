# Timed — Test Strategy

**Status:** Implementation-ready
**Last updated:** 2026-04-02
**Applies to:** All four layers — Signal Ingestion (L1), Memory Store (L2), Reflection Engine (L3), Intelligence Delivery (L4)

---

## 1. Testing Philosophy

Timed's value compounds over time. Testing must verify not just correctness today but intelligence quality over simulated weeks and months. Three non-negotiable testing principles:

1. **Observation-only constraint is a test category, not an afterthought.** Every integration test asserts no write/mutation occurred on external systems (Graph API, calendar, email).
2. **LLM outputs are tested structurally and qualitatively.** We cannot assert exact strings, but we can assert JSON schema conformance, required field presence, sentiment bounds, and rubric scores.
3. **Compounding intelligence is tested with longitudinal fixtures.** Synthetic datasets spanning 7, 30, and 90 simulated days validate that reflection quality improves measurably.

---

## 2. Coverage Targets

| Layer | Target | Rationale |
|-------|--------|-----------|
| L1 — Signal Ingestion | 90% line coverage | Deterministic parsing, well-defined I/O. No excuse for gaps. |
| L2 — Memory Store | 85% line coverage | CoreData CRUD, scoring, consolidation. Some edge cases around migration. |
| L3 — Reflection Engine | 60% line + quality metrics | LLM output is non-deterministic. Structure tests (schema, required fields) get to 60%. Quality metrics (rubric scoring) supplement. |
| L4 — Intelligence Delivery | 70% line coverage | SwiftUI view models, delivery formatting, session orchestration. Snapshot tests for layout regression. |

Coverage is measured per-layer, not globally. A global 80% that hides 30% L3 coverage is a failure.

---

## 3. Layer 1 — Signal Ingestion Tests

### 3.1 Unit Tests

#### Email Signal Parsing (`EmailSyncService`, `EmailClassifier`)
- **Graph API response deserialization**: Feed recorded JSON responses (see Section 8: Fixtures). Assert correct extraction of: sender, recipients, subject, thread ID, timestamps, read state, importance, categories, is-reply flag, has-attachments flag, body text.
- **Delta sync token handling**: Verify `@odata.deltaLink` is persisted and reused. Verify full sync triggers when delta token is missing or expired (HTTP 410).
- **Computed field derivation**:
  - `responseLatency`: Given a thread with sent timestamps [T1, T2, T3], assert latency = T2 - T1 for the reply pair.
  - `threadDepth`: Assert correct count of messages in thread chain.
  - `senderFrequency`: Given 50 emails from sender X and 3 from sender Y, assert frequency map is accurate.
- **Privacy filtering**: Assert that when an email contains attachment references, attachment binary data is never captured. Assert body text is captured but image URLs / inline images are stripped.
- **Malformed response handling**: Feed truncated JSON, missing required fields, unexpected `@odata.type` values. Assert graceful degradation with `TimedLogger` error output, no crash.

#### Calendar Signal Parsing (`CalendarSyncService`)
- **Event deserialization**: Recorded JSON → assert extraction of event ID, subject, start/end times, duration, attendees, organiser, location, recurrence pattern, acceptance status, cancellation flag.
- **Computed field derivation**:
  - `meetingDensity`: Given 8 events in an 8-hour window, assert density = 1.0 events/hour.
  - `backToBackDetection`: Events [9:00-10:00, 10:00-11:00, 11:30-12:00] → assert first pair flagged as back-to-back, third is not.
  - `overrunFrequency`: Given historical data where 3 of 10 meetings ran past `end` time, assert overrun rate = 0.3.
  - `acceptanceRate`: 15 accepted / 20 total invitations = 0.75.
  - `freeBusyInference`: Assert correct busy/free/tentative mapping from acceptance status.

#### App Focus Observer (`NSWorkspace` notifications)
- **Session tracking**: Simulate `NSWorkspace.didActivateApplicationNotification` sequence. Assert sessions have correct bundle ID, start time, end time, duration.
- **Context switch logging**: 10 app switches in 5 minutes → assert 10 context switch events recorded with correct timestamps.
- **Window title opt-in**: When opt-in is disabled, assert window title field is nil. When enabled, assert it is populated.
- **Battery constraint**: When `ProcessInfo.processInfo.isLowPowerModeEnabled` returns true, assert observation interval increases to configured throttle value.

#### Voice Input (`SpeechService`, `VoiceCaptureService`)
- **Transcript extraction**: Feed pre-recorded audio buffer to `SFSpeechRecognizer` (on-device). Assert transcript text matches expected output within Levenshtein distance threshold (< 5% error rate for clear speech).
- **Metadata derivation**: Given transcript "I need to handle the board deck by Friday and call Sarah about the Q3 numbers", assert:
  - `wordCount` = 17
  - `pace` is within expected WPM range (120-180 for natural speech)
  - `topics` extraction identifies "board deck", "Sarah", "Q3 numbers"
- **Session type classification**: Feed transcripts matching each session type (morning interview, ad-hoc, focus debrief, correction). Assert correct type assignment.
- **Raw audio never stored**: After pipeline completion, assert no audio buffer exists in memory or disk beyond the active `AVAudioEngine` session.

### 3.2 Integration Tests (L1)

#### Graph API Integration (Recorded Responses)
All Graph API integration tests use **recorded HTTP responses** stored as JSON fixtures. No live API calls in CI.

Recording mechanism:
```swift
// TestSupport/GraphRecorder.swift
protocol HTTPRecording {
    func record(_ request: URLRequest, response: HTTPURLResponse, data: Data)
    func playback(for request: URLRequest) -> (HTTPURLResponse, Data)?
}
```

Test cases:
- **Full email sync flow**: Initial sync (no delta token) → receives 50 emails → persists delta token → delta sync → receives 3 new emails. Assert all 53 emails in signal queue with correct metadata.
- **Calendar sync flow**: Initial sync → 30 events → delta sync → 2 updated, 1 deleted. Assert final state has 29 events with correct modifications.
- **Token refresh**: Simulate 401 response → assert MSAL token refresh triggered → retry succeeds.
- **Rate limit (HTTP 429)**: Assert exponential backoff with jitter. Assert retry succeeds after `Retry-After` header delay.
- **Observation-only assertion**: After full sync, assert zero POST/PATCH/DELETE requests were made to Graph API. Only GET requests allowed.

---

## 4. Layer 2 — Memory Store Tests

### 4.1 CoreData CRUD

Test target: `DataStore.swift`, CoreData stack

- **Create**: Insert episodic memory (signal event). Assert entity persisted with all fields. Assert `createdAt` timestamp is set.
- **Read**: Query memories by type (episodic, semantic, procedural). Assert correct filtering. Query by date range. Assert boundary conditions (inclusive start, exclusive end).
- **Update**: Update memory `importance` score. Assert old value overwritten. Assert `updatedAt` timestamp changed.
- **Delete**: Soft-delete (mark as archived). Assert memory excluded from active queries but retrievable via archive query. Hard-delete after 90-day retention. Assert entity removed from store.
- **Migration**: Test CoreData lightweight migration from schema v1 → v2 (when applicable). Assert no data loss. Assert new fields have correct default values.
- **Concurrency**: Perform 100 concurrent writes from background contexts. Assert no merge conflicts. Assert `NSManagedObjectContext.mergeChanges` handles notifications correctly.
- **Performance**: Insert 10,000 episodic memories. Assert fetch of most recent 50 completes in < 50ms. Assert batch delete of 5,000 archived records completes in < 500ms.

### 4.2 Memory Scoring

Test target: `PlanningEngine.swift` (Thompson sampling), EMA calculations

#### Thompson Sampling
```
Given:
  - Task A: alpha=10, beta=2 (historically completed on time)
  - Task B: alpha=3, beta=8 (historically missed)

Assert:
  - Over 1000 samples, Task A is ranked first > 85% of the time
  - Score distribution for Task A has mean ~0.83 (alpha / (alpha + beta))
  - Score distribution for Task B has mean ~0.27
```

- **Cold start**: New task with alpha=1, beta=1 (uniform prior). Assert high variance in early samples. Assert score converges as observations accumulate.
- **Prior injection from archetype**: "Operator" archetype → assert pre-loaded priors match archetype definition (e.g., alpha=5, beta=2 for operational tasks).
- **Boundary conditions**: alpha=0 or beta=0 → assert graceful handling (should never occur, but defensive test).

#### EMA (Exponential Moving Average) Time Estimation
```
Given:
  - Category: "Deep Work"
  - Historical durations: [60, 55, 65, 58, 62] minutes
  - Smoothing factor α = 0.3

Assert:
  - EMA after 5 observations ≈ 60.7 minutes (manual calculation)
  - New observation of 120 minutes (outlier) → EMA shifts but doesn't jump to 120
  - After 10 more observations at ~60 min, EMA recovers toward 60
```

- **No history**: Assert fallback to user-provided estimate or category default.
- **Single observation**: Assert EMA equals that observation exactly.
- **Category isolation**: Deep Work EMA is independent of Admin EMA. Assert no cross-contamination.

### 4.3 Memory Consolidation

- **Episodic → Semantic**: Given 30 episodic memories about "Monday morning email triage taking 45 minutes", assert consolidation produces a semantic memory: "Email triage is a consistent Monday morning pattern, typically 45 minutes."
- **Semantic → Procedural**: Given semantic memory "User avoids scheduling deep work after 3pm" persisting for 14+ days, assert procedural rule is generated: "Do not suggest deep work blocks after 15:00."
- **Deduplication**: Insert 5 near-identical episodic memories (same signal, ±2 minute timestamps). Assert consolidation merges them into 1 with averaged metadata.
- **Decay**: Memory not reinforced for 30 days → assert importance score decays by configured factor. Assert it remains retrievable but ranks lower.

---

## 5. Layer 3 — Reflection Engine Tests

### 5.1 Structure Tests (deterministic, counted toward 60% target)

Test target: Nightly reflection output, `InsightsEngine.swift`

- **Output schema validation**: Nightly reflection output must conform to `ReflectionOutput` schema:
  ```swift
  struct ReflectionOutput: Codable {
      let date: Date
      let firstOrderPatterns: [Pattern]      // min 1
      let secondOrderSynthesis: [Synthesis]   // min 1
      let semanticModelUpdates: [SemanticUpdate]
      let proceduralRules: [ProceduralRule]
      let confidenceScores: [String: Double]  // 0.0-1.0
      let reasoningTrace: String              // non-empty
  }
  ```
  Assert all required fields present. Assert arrays are non-empty. Assert confidence scores are within [0.0, 1.0].

- **Required reasoning trace**: Assert `reasoningTrace` is non-empty and contains at least 3 distinct reasoning steps (detected by sentence count or step markers).
- **Pattern must reference evidence**: Each `Pattern` must contain at least one `evidenceReference` pointing to a real episodic memory ID. Assert referential integrity.
- **No hallucinated dates**: All dates in output must fall within the observation window. Assert no future dates. Assert no dates before the user's account creation.
- **Observation-only constraint**: Assert reflection output contains no `action` fields, no `execute` commands, no `send_email` or `create_event` directives. Regex scan for forbidden verbs: "send", "create", "delete", "modify", "schedule" (in action context).

### 5.2 Quality Metrics (non-deterministic, supplement coverage target)

Quality is measured by rubric scoring using a separate LLM evaluator (Haiku, not the same model being tested).

#### Rubric: Nightly Reflection Quality
| Dimension | Score 1 (Fail) | Score 3 (Pass) | Score 5 (Excellent) |
|-----------|---------------|-----------------|---------------------|
| **Specificity** | Generic observations ("user was busy") | References specific events ("3 back-to-back meetings Mon AM") | Quantified with comparison ("Mon AM meeting density 1.5x weekly average") |
| **Insight depth** | Restates input data | Identifies pattern across multiple signals | Connects pattern to user's cognitive model ("avoidance of strategic work correlates with high meeting density — consistent with the 'Operator' archetype tendency to fill time with reactive tasks") |
| **Actionability** | No implication for future | Suggests general direction | Specific, testable recommendation with confidence level |
| **Consistency** | Contradicts previous reflections | Neutral | Explicitly references and builds on prior reflections |
| **Observation-only** | Contains action directives | Passive voice but implies action | Purely observational with explicit "the user may wish to consider" framing |

**Pass threshold**: Average score >= 3.0 across all dimensions. No single dimension below 2.0.

#### Longitudinal Quality Test
- Feed 7-day fixture → score reflection quality.
- Feed 30-day fixture (includes the same 7 days + 23 more) → score reflection quality.
- Feed 90-day fixture → score reflection quality.
- **Assert**: 30-day quality score > 7-day quality score (compounding intelligence).
- **Assert**: 90-day quality score > 30-day quality score.
- **Tolerance**: Quality improvement must be statistically significant (p < 0.05 over 10 runs with different random seeds).

### 5.3 LLM Output Testing Framework

```swift
// TestSupport/LLMTestHarness.swift

struct LLMTestCase {
    let name: String
    let systemPrompt: String
    let userInput: String          // Serialised memory context
    let expectedSchema: Codable.Type
    let qualityRubric: Rubric?
    let forbiddenPatterns: [String] // Regex patterns that must NOT appear
    let requiredPatterns: [String]  // Regex patterns that MUST appear
    let maxLatency: TimeInterval    // seconds
    let maxTokens: Int
}

struct LLMTestResult {
    let passed: Bool
    let schemaValid: Bool
    let qualityScore: Double?       // nil if no rubric
    let forbiddenViolations: [String]
    let missingRequired: [String]
    let latency: TimeInterval
    let tokenCount: Int
}
```

Each nightly reflection test case:
1. Loads fixture data into a mock `UserIntelligenceStore`.
2. Invokes the reflection engine with deterministic temperature (0.0 where supported, else lowest available).
3. Validates output against `LLMTestCase`.
4. Scores quality if rubric provided.
5. Logs full input/output for debugging (never in production logs).

**CI integration**: LLM tests run nightly (not on every PR) due to cost and latency. PR CI runs structure tests only (schema validation, forbidden patterns). Quality metric tests run on `main` nightly and on release branches.

---

## 6. Layer 4 — Intelligence Delivery Tests

### 6.1 View Model Tests

- **Morning briefing assembly**: Given a `ReflectionOutput` with 3 patterns and 2 procedural rules, assert `MorningBriefingViewModel` produces:
  - Exactly 3 pattern cards with correct titles and evidence references.
  - 2 rule explanations with reasoning traces.
  - No action buttons (observation-only).
- **Menu bar state**: Given current task "Board deck review" with 45 min remaining, assert menu bar displays "Board deck — 45m".
- **Command palette results**: Given query "email", assert results include email-related insights, not email-sending actions.

### 6.2 Session Orchestration

- **Morning interview flow**: Simulate voice input → transcript → AI response → follow-up question → final briefing. Assert each step transitions correctly. Assert session completes within 90 seconds of user input (excluding user think time).
- **Ad-hoc capture**: Simulate mid-day voice note. Assert it writes to signal queue as episodic memory. Assert it does not trigger a full reflection cycle.
- **Correction handling**: User says "That's wrong, I actually prefer deep work in the afternoon." Assert correction is captured as a high-priority episodic memory with `type: correction`. Assert next reflection incorporates it.

### 6.3 Snapshot Tests

SwiftUI preview snapshots for:
- Morning briefing (populated state, empty state, error state)
- Menu bar (task active, no task, focus mode)
- Command palette (empty query, results, no results)
- Focus timer (running, paused, complete)

Snapshots generated on macOS 14+ with standard display scaling. Reviewed manually on PR, auto-compared in CI for regression.

---

## 7. Cross-Cutting Test Categories

### 7.1 Observation-Only Constraint Tests

A dedicated test suite (`ObservationOnlyTests`) runs across all layers:

```swift
// Tests/ObservationOnlyTests.swift

final class ObservationOnlyTests {
    // L1: Assert all Graph API calls are GET only
    @Test func emailSync_onlyReadsFromGraph()
    @Test func calendarSync_onlyReadsFromGraph()
    
    // L2: Assert memory store never writes to external systems
    @Test func memoryConsolidation_noExternalWrites()
    
    // L3: Assert reflection output contains no action directives
    @Test func nightlyReflection_noActionDirectives()
    @Test func nightlyReflection_noForbiddenVerbs()
    
    // L4: Assert UI has no "send", "create event", "reply" buttons
    @Test func morningBriefing_noActionButtons()
    @Test func commandPalette_noActionCommands()
}
```

### 7.2 Privacy Tests

- **No raw audio persistence**: After voice session ends, assert no `.wav`, `.m4a`, `.caf` files exist in app sandbox.
- **No attachment content**: After email sync, assert no attachment binary data in CoreData or signal queue.
- **No window titles by default**: Assert `AppFocusObserver` does not capture window titles unless user has explicitly enabled the setting (mock `UserDefaults`).
- **Email body handling**: Assert email body is stored as plain text only. Assert HTML tags are stripped. Assert inline images are removed.
- **Memory encryption at rest**: Assert CoreData store uses `NSPersistentStoreFileProtectionKey: .complete` on macOS.
- **No PII in logs**: Feed an email containing a phone number and SSN-like pattern through the pipeline. Assert `TimedLogger` output does not contain either.

### 7.3 Performance Tests

| Scenario | Target | Measurement |
|----------|--------|-------------|
| Email delta sync (100 new emails) | < 5 seconds | Wall clock from sync start to all signals queued |
| Calendar delta sync (50 events) | < 3 seconds | Wall clock |
| CoreData fetch (50 most recent from 10,000) | < 50ms | `XCTMeasure` block, 10 iterations |
| CoreData batch insert (1,000 signals) | < 2 seconds | Wall clock |
| Memory consolidation (500 episodic → semantic) | < 10 seconds | Wall clock |
| App focus observer overhead | < 1% CPU | Instruments Energy gauge over 5 minutes |
| Voice transcript pipeline (30s audio) | < 5 seconds end-to-end | Wall clock from audio buffer to signal queue |
| Morning briefing render | < 500ms | Time from view model ready to first frame |
| Nightly reflection (30-day context) | < 120 seconds | Wall clock for full Opus reflection cycle |

All performance tests run on baseline hardware: M1 MacBook Pro, 16GB RAM, macOS 14+.

---

## 8. Fixtures and Test Data

### 8.1 Fixture Directory Structure

```
Tests/
  Fixtures/
    GraphAPI/
      email_initial_sync.json          # 50 emails, no delta token
      email_delta_sync.json            # 3 new emails, delta token
      email_malformed.json             # Missing required fields
      email_rate_limited.json          # 429 response with Retry-After
      calendar_initial_sync.json       # 30 events
      calendar_delta_sync.json         # 2 updated, 1 deleted
      calendar_recurring.json          # Complex recurrence patterns
      token_refresh_401.json           # Expired token response
    Longitudinal/
      7day_executive_profile.json      # 7 days of all signal types
      30day_executive_profile.json     # 30 days, includes the 7-day subset
      90day_executive_profile.json     # 90 days, includes the 30-day subset
    Voice/
      morning_interview_transcript.json
      adhoc_capture_transcript.json
      focus_debrief_transcript.json
      correction_transcript.json
    Reflection/
      expected_schema.json             # ReflectionOutput JSON Schema
      forbidden_patterns.txt           # One regex per line
      quality_rubric.json              # Rubric definition for evaluator
```

### 8.2 Longitudinal Fixture Design

Each longitudinal fixture contains synthetic but realistic data for a C-suite executive persona ("Yasser-like"):

- **Email signals**: 40-80 emails/day, realistic sender distribution (5 frequent, 20 occasional, long tail), threads of depth 2-8, response latencies from 5 minutes to 48 hours.
- **Calendar signals**: 4-8 meetings/day, recurring 1:1s, ad-hoc calls, blocked focus time, occasional cancellations. Meeting density varies by day of week.
- **App focus signals**: 6-12 app switches/hour during work, primary apps (Outlook, Slack, Excel, Safari, Terminal), deep work sessions of 45-90 minutes.
- **Voice signals**: 1 morning interview/day, 0-2 ad-hoc captures, 1 focus debrief on 60% of days.

The 7-day fixture is a strict subset of the 30-day fixture, which is a strict subset of the 90-day fixture. This enables compounding intelligence assertions.

---

## 9. CI Pipeline Integration

### PR Pipeline (every push)
1. `swift build` — compilation check.
2. Unit tests (L1, L2, L4) — fast, deterministic.
3. L3 structure tests only (schema validation, forbidden patterns).
4. Observation-only constraint tests.
5. Privacy tests.
6. Coverage report — fail if any layer below target minus 5% grace.

### Nightly Pipeline (main branch, 02:00 UTC)
1. Full PR pipeline.
2. L3 quality metric tests (LLM evaluator, rubric scoring).
3. Longitudinal compounding intelligence tests.
4. Performance benchmarks — fail if any metric regresses by > 20%.
5. Coverage report — fail if any layer below target.

### Release Pipeline (release branches)
1. Full nightly pipeline.
2. Extended performance tests (2x data volume).
3. Manual snapshot review gate.
4. Quality metric tests run 5x for statistical significance.

---

## 10. Testing Tools and Dependencies

| Tool | Purpose |
|------|---------|
| `swift-testing` | Primary test framework (already in use, 49 tests passing) |
| `XCTest` + `XCTMeasure` | Performance benchmarks |
| `ViewInspector` | SwiftUI view model assertions (if needed beyond snapshot) |
| Custom `GraphRecorder` | HTTP recording/playback for Graph API tests |
| Custom `LLMTestHarness` | Schema + rubric validation for LLM outputs |
| Custom `ObservationOnlyAssert` | Cross-cutting observation constraint validation |

No third-party mocking frameworks. Swift protocols + manual mocks. Keeps the dependency tree clean and avoids macro-heavy test libraries that break on Swift version bumps.
