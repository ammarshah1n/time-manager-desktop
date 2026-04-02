# Timed — Comprehensive Test Strategy

## Executive Summary

Timed is a macOS cognitive intelligence layer operating in strict **observation-only mode**, built on Swift 5.9+, CoreData, Supabase, and a three-tier Claude model stack (Haiku/Sonnet/Opus). Because its value proposition compounds over longitudinal time (weeks to months), the test strategy must simultaneously verify functional correctness, ML convergence, privacy invariants, and emergent pattern quality — all without ever relaxing the read-only constraint. This document prescribes testing methodology across all four architectural layers with concrete patterns, coverage targets, tooling, and evidence-backed improvements over naive approaches.

***

## Testing Framework Selection

The starting recommendation is a **hybrid of Swift Testing (WWDC24) and XCTest**, chosen deliberately rather than committing to either alone.[^1]

| Concern | Recommended Framework | Rationale |
|---|---|---|
| Unit tests (logic, ML, CRUD) | Swift Testing | Native async/await, parameterized `@Test`, expressive `#expect`, better failure output[^2] |
| Integration tests (pipelines) | Swift Testing | Structured concurrency aligns with async pipeline stages[^3] |
| Performance benchmarks | XCTest `measure{}` | Apple's performance baseline infrastructure, no Swift Testing equivalent yet[^4][^5] |
| UI observation smoke tests | XCTest / XCUITest | No Swift Testing UI counterpart[^1] |
| Async concurrency edge cases | Both | `XCTestExpectation` for complex multi-task synchronisation; async throws for simple cases[^6][^7] |

Apple has pitched formal interoperability between the two frameworks, making migration incremental. Write new tests in Swift Testing immediately; leave existing XCTest performance harnesses in place. For strict mode (prevent accidental XCTest import in new Swift Testing files), enable strict interop opt-in.[^8]

***

## Layer Architecture and Coverage Targets

```
┌──────────────────────────────────────────┐
│  Layer 4: Delivery / Reflection           │  Target: ≥80% line, ≥75% branch
├──────────────────────────────────────────┤
│  Layer 3: Memory (CoreData + Supabase)   │  Target: ≥95% line, ≥90% branch
├──────────────────────────────────────────┤
│  Layer 2: ML / Pattern Engine            │  Target: ≥85% line, ≥80% branch
├──────────────────────────────────────────┤
│  Layer 1: Signal Ingestion               │  Target: ≥90% line, ≥85% branch
└──────────────────────────────────────────┘
```

Layer 3 carries the highest target because CRUD failures can silently corrupt longitudinal state. Layer 4 carries a lower target because LLM output is non-deterministic and partial coverage is expected there — semantic quality is covered by the LLM-as-judge tier instead.

**Overall target: ≥85% line coverage**, measured via `xcov` or Xcode's built-in coverage report gated in CI.

***

## Unit Testing

### 1. Thompson Sampling Convergence

Thompson Sampling converges asymptotically such that the probability of sampling the optimal arm approaches 1 as trials increase, provided Bayesian regret is sub-linear. Unit testing this requires statistical rather than deterministic assertions.[^9]

**Pattern:**

```swift
@Test("Thompson sampling selects optimal arm at scale")
func thompsonSamplingConvergence() async {
    var sampler = ThompsonSampler(arms: 3, seed: 42) // seeded for reproducibility
    let trueOptimal = 1 // arm index with highest true reward
    let trueRewards = [0.2, 0.8, 0.35]

    for _ in 0..<2000 {
        let chosen = sampler.sample()
        let reward = Double.random(in: 0...1, using: &sampler.rng) < trueRewards[chosen] ? 1.0 : 0.0
        sampler.update(arm: chosen, reward: reward)
    }

    let selectionRate = sampler.selectionRate(for: trueOptimal)
    #expect(selectionRate > 0.80) // optimal arm selected ≥80% after 2000 rounds
}

@Test("Thompson sampling Beta params update correctly")
func betaParamUpdate() {
    var sampler = ThompsonSampler(arms: 2, seed: 0)
    sampler.update(arm: 0, reward: 1.0)
    sampler.update(arm: 0, reward: 0.0)
    #expect(sampler.alpha(for: 0) == 2.0)
    #expect(sampler.beta(for: 0) == 2.0)
}
```

**Key considerations:**
- Use a seeded PRNG (`SystemRandomNumberGenerator` replacement or `SeedableRNG`) to make convergence tests deterministic in CI[^10][^9]
- Assert convergence checkpoints at N=100 (≥50% optimal), N=500 (≥70%), N=2000 (≥80%) — sub-linear regret bounds imply these milestones[^9]
- Separate the update arithmetic test (deterministic) from the convergence test (statistical) — they are different failure modes

### 2. EMA Accuracy

The EMA formula \(\text{EMA}_t = p_t \times m + \text{EMA}_{t-1} \times (1 - m)\) where \(m = \frac{2}{n+1}\) is fully deterministic. Floating point tolerance is the only source of imprecision.[^11][^12]

```swift
@Test("EMA matches hand-computed reference sequence", arguments: [5, 10, 20])
func emaAccuracy(period: Int) {
    let prices = [10.0, 11.0, 12.0, 11.5, 13.0, 12.5, 14.0, 15.0, 14.5, 16.0]
    let multiplier = 2.0 / Double(period + 1)
    var ema = prices
    for price in prices.dropFirst() {
        ema = price * multiplier + ema * (1 - multiplier)
    }
    let sut = EMACalculator(period: period)
    let result = prices.reduce(into: sut) { $0.update($1) }.currentValue
    #expect(abs(result - ema) < 1e-9)
}

@Test("EMA handles single-element series")
func emaSingleElement() {
    let sut = EMACalculator(period: 5)
    sut.update(42.0)
    #expect(sut.currentValue == 42.0)
}
```

Edge case matrix to cover: single element, all-zero series, negative values (signal deltas), large N (test floating point accumulation), period longer than series length.

### 3. Memory Scoring Validation

Memory scoring blends recency, frequency, and contextual salience into a composite score. Test the scoring function as a pure function with fixtures derived from domain logic.

```swift
@Test("Memory score decays with recency")
func memoryScoringRecencyDecay() {
    let fresh = MemoryScorer.score(
        lastAccessed: Date(),
        accessCount: 1,
        salience: 0.5
    )
    let stale = MemoryScorer.score(
        lastAccessed: Calendar.current.date(byAdding: .day, value: -30, to: Date())!,
        accessCount: 1,
        salience: 0.5
    )
    #expect(fresh > stale)
}

@Test("Memory score increases monotonically with access count")
func memoryScoringFrequencyMonotonicity() {
    let scores = (1...10).map { count in
        MemoryScorer.score(lastAccessed: Date(), accessCount: count, salience: 0.5)
    }
    let isMonotone = zip(scores, scores.dropFirst()).allSatisfy { $0 <= $1 }
    #expect(isMonotone)
}
```

### 4. Memory CRUD with In-Memory CoreData

Use `NSInMemoryStoreType` (or `/dev/null` URL equivalent) to isolate each test from disk state. The pattern from Apple's WWDC18 "Core Data Best Practices" remains the gold standard.[^13][^14][^15]

```swift
final class MemoryCRUDTests: XCTestCase {
    var container: NSPersistentContainer!
    var context: NSManagedObjectContext!

    override func setUpWithError() throws {
        container = NSPersistentContainer(name: "Timed",
            managedObjectModel: timedModel) // explicit bundle pass
        let desc = NSPersistentStoreDescription()
        desc.type = NSInMemoryStoreType
        container.persistentStoreDescriptions = [desc]
        try container.loadPersistentStores { _, error in
            XCTAssertNil(error)
        }
        context = container.viewContext
    }

    override func tearDown() {
        context = nil
        container = nil
    }

    func testCreateMemory() throws {
        let mem = Memory(context: context)
        mem.id = UUID()
        mem.content = "Quarterly review pattern"
        mem.score = 0.85
        try context.save()
        let fetched = try context.fetch(Memory.fetchRequest())
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.content, "Quarterly review pattern")
    }
}
```

> **Recommended improvement:** Use a `CoreDataTestCase` base class with a `uniqueTemporaryDirectory` SQLite store (not in-memory) for tests that validate migration or predicate pushdown — in-memory stores skip some CoreData optimisations. Run the full suite against both store types to catch store-specific issues.[^14]

### 5. Signal Parsing with Mock Graph Responses

Microsoft Graph's SDK supports intercepting HTTP via a custom `URLProtocol` subclass, or the `GraphTestHandler` request/response mapping pattern. The preferred approach for Swift is a **URLProtocol mock** registered before each test, replaying JSON fixtures recorded from live Graph calls.[^16][^17]

```swift
final class GraphSignalParserTests: XCTestCase {
    override func setUp() {
        URLProtocol.registerClass(MockGraphURLProtocol.self)
        MockGraphURLProtocol.responseMap = [
            "https://graph.microsoft.com/v1.0/me/calendarView": .fixture("calendar_view")
        ]
    }

    func testCalendarSignalParsing() async throws {
        let parser = GraphSignalParser(session: .mockSession)
        let signals = try await parser.fetchTodaySignals()
        XCTAssertFalse(signals.isEmpty)
        XCTAssertEqual(signals.first?.type, .meeting)
    }
}
```

**Fixture management:** Store JSON fixtures in a `TestResources/GraphFixtures/` bundle under version control. Refresh fixtures on a scheduled CI job (monthly) to detect API schema drift. For batch request testing, use Dev Proxy's `GraphMockResponsePlugin` which natively supports Graph's `$batch` endpoint.[^18]

### 6. Pattern Lifecycle Transitions

Pattern state machines should be tested via **systematic state/event enumeration**. Every valid transition is a test case; every invalid transition (guard violation) is also a test case — it should silently no-op or throw predictably.[^19][^20]

```swift
@Suite("Pattern Lifecycle")
struct PatternLifecycleTests {
    @Test("Emerging pattern transitions to Confirmed on threshold")
    func emergingToConfirmed() {
        var pattern = Pattern(state: .emerging)
        pattern.applyEvent(.observationCountReached(threshold: 5))
        #expect(pattern.state == .confirmed)
    }

    @Test("Confirmed pattern cannot re-enter Emerging")
    func confirmedCannotRegressToEmerging() {
        var pattern = Pattern(state: .confirmed)
        pattern.applyEvent(.observationCountReset)
        // Observation-only: confirmed patterns are never downgraded, only archived
        #expect(pattern.state == .confirmed)
    }

    @Test("Pattern archives after inactivity window", arguments: [7, 30, 90])
    func archivesAfterInactivity(days: Int) {
        var pattern = Pattern(state: .confirmed)
        pattern.applyEvent(.inactiveDays(days))
        let expected: PatternState = days >= 90 ? .archived : .confirmed
        #expect(pattern.state == expected)
    }
}
```

***

## Integration Testing

### 1. Graph API with Recorded Responses

For integration tests, use **cassette-style recorded responses** (similar to VCR in other ecosystems). On the first CI run against a live token, record responses to `TestFixtures/graph_cassette.json`. Subsequently, all integration tests replay from the cassette with no network access.

**Better approach than simple mocking:** Use `URLSession`'s `recordingMode` flag via a custom session delegate that switches between live and playback based on an environment variable (`GRAPH_RECORDING_MODE=playback`). This eliminates manual fixture maintenance and catches real schema changes when recording mode is triggered quarterly.

### 2. Memory Consolidation Pipeline

The pipeline converts raw signals into scored, deduplicated, consolidated memories. Integration tests should assert the entire transformation chain using real CoreData contexts.

```swift
@Test("Consolidation pipeline produces unique memories from duplicate signals")
func consolidationDeduplication() async throws {
    let pipeline = MemoryConsolidationPipeline(context: inMemoryContext)
    let duplicates = [
        Signal(type: .meeting, subject: "Board meeting", timestamp: Date()),
        Signal(type: .meeting, subject: "Board meeting", timestamp: Date().addingTimeInterval(60))
    ]
    try await pipeline.process(signals: duplicates)
    let memories = try inMemoryContext.fetch(Memory.fetchRequest())
    #expect(memories.count == 1) // deduplicated to single memory
    #expect(memories.first?.signalCount == 2)
}
```

Key assertions: deduplication correctness, scoring after consolidation within tolerance, temporal ordering preserved, Supabase sync state flag accurate.

### 3. Reflection Output Structure Validation

Reflection is the highest-value output of Timed — it must be structurally valid and semantically coherent. Use a **two-layer validation approach**:[^21]

**Layer 1 — Deterministic schema validation** (zero cost per run):

```swift
struct ReflectionOutput: Codable {
    let summary: String
    let patterns: [PatternReference]
    let confidence: Double // 0.0–1.0
    let timeframe: DateInterval
    let modelUsed: String // "haiku" | "sonnet" | "opus"
}

@Test("Reflection output conforms to schema")
func reflectionSchemaValidation() throws {
    let raw = try await reflectionEngine.generateReflection(for: testFixture)
    let decoded = try JSONDecoder().decode(ReflectionOutput.self, from: raw)
    #expect(decoded.confidence >= 0.0 && decoded.confidence <= 1.0)
    #expect(!decoded.summary.isEmpty)
    #expect(["haiku", "sonnet", "opus"].contains(decoded.modelUsed))
}
```

**Layer 2 — LLM-as-judge** (sampled in CI, not every run):

Use a separate Claude Haiku call at temperature=0 to evaluate reflection quality against a rubric. Run this on 20% of test fixtures in CI with a pass threshold ≥3/5. To eliminate position bias, run each pairwise comparison twice with swapped positions and flag inconsistent judgements as inconclusive rather than failing.[^22][^23]

```swift
// Only runs in integration suite, not unit suite
@Test("Reflection passes LLM-as-judge quality gate", .tags(.llmJudge))
func reflectionQualityGate() async throws {
    let output = try await reflectionEngine.generateReflection(for: benchmarkFixture)
    let judgment = try await LLMJudge.evaluate(
        output: output,
        criteria: ReflectionRubric.standard,
        model: "claude-haiku-4-5",
        temperature: 0
    )
    #expect(judgment.score >= 3)
}
```

### 4. End-to-End Signal-to-Delivery Pipeline

The full pipeline: `Calendar/Email Signal → Ingestion → Parse → Score → Memory → Pattern Match → Reflection → Delivery`.

```swift
@Test("Full signal-to-delivery pipeline completes within latency budget")
func e2ePipelineLatency() async throws {
    let start = ContinuousClock.now
    let delivery = try await TimedPipeline.shared.process(
        signals: testSignalBatch(count: 50),
        context: inMemoryContext
    )
    let elapsed = ContinuousClock.now - start
    #expect(delivery != nil)
    #expect(elapsed < .seconds(5)) // SLA: 5s for 50-signal batch
}
```

Run this test against the full Supabase staging environment (not in-memory) weekly, and against the in-memory stack on every PR.

***

## Testing Compounding Intelligence

### Longitudinal Test Fixtures

Compounding intelligence cannot be validated at a single point in time. The fixture strategy creates **temporal snapshots** of a synthetic C-suite executive's data at defined checkpoints.[^24]

| Fixture | Content | Validation Focus |
|---|---|---|
| `week_1.json` | 5 days of signals, no patterns confirmed | Thompson sampling prior is flat; no reflection generated |
| `month_1.json` | 22 days of signals, 2–3 emerging patterns | Patterns transition to confirmed; EMA decay is active |
| `month_3.json` | 66 days, 8–12 confirmed patterns | Cross-pattern correlation; memory consolidation accuracy |
| `month_6.json` | 132 days, 15+ patterns, 2 archived | Archived pattern exclusion; longitudinal scoring drift |

Each fixture is committed as a deterministic JSON blob. Tests feed the fixture through the pipeline and assert:
- Pattern count ≥ expected floor
- Pattern quality score ≥ rolling baseline (tracked in `test_baselines.json`)
- No regressions on patterns that existed in the prior fixture
- Reflection references only patterns confirmed at that time point (temporal honesty)

### Pattern Quality Metrics

Define **pattern quality** as a measurable composite: support (signal count), coherence (variance of signal similarity scores), and persistence (ratio of windows with ≥1 observation). Assert thresholds in tests:

```swift
@Test("3-month fixture produces high-quality patterns")
func patternQualityAt3Months() async throws {
    let engine = PatternEngine(context: inMemoryContext)
    try await engine.ingest(fixture: .month3)
    let topPatterns = engine.patterns(state: .confirmed).prefix(5)
    for pattern in topPatterns {
        #expect(pattern.quality.support >= 10)
        #expect(pattern.quality.coherence >= 0.6)
        #expect(pattern.quality.persistence >= 0.4)
    }
}
```

### Regression Testing

Maintain a `test_baselines.json` file under version control that stores pattern quality scores from the previous release. On each CI run, compute current scores and fail if any confirmed pattern's quality regresses by more than 10%. This is the primary guard against prompt engineering changes degrading intelligence quality silently.[^25]

```json
{
  "fixture": "month_3",
  "patterns": {
    "morning_deep_work_block": { "quality": 0.82, "support": 18 },
    "pre_board_preparation": { "quality": 0.75, "support": 12 }
  },
  "recorded_at": "2026-03-01T00:00:00Z"
}
```

***

## Observation-Only Constraint Testing

This is the most legally and ethically critical invariant of Timed. Testing must occur at **three independent layers**.

### Layer 1: Static Analysis (Compile-Time)

Write custom SwiftLint rules to flag any call to write-capable APIs that have no business in an observation-only app:[^26][^27][^28]

```yaml
# .swiftlint.yml
custom_rules:
  no_audio_capture:
    name: "No Audio Capture"
    regex: "AVAudioRecorder|AVCaptureDeviceInput.*audio|startRecording"
    message: "Observation-only: audio capture APIs are prohibited"
    severity: error
  no_user_data_write:
    name: "No User Data Write"
    regex: "NSFileManager.default.createFile|FileHandle.*write|OutputStream"
    message: "Observation-only: direct file write operations require review"
    severity: warning
  no_clipboard_write:
    name: "No Clipboard Write"
    regex: "NSPasteboard.*setString|UIPasteboard.*string.*="
    message: "Observation-only: clipboard write prohibited"
    severity: error
```

Run `swiftlint analyze` as a pre-build phase and a CI gate; any `error`-severity violation fails the build.[^29][^28]

### Layer 2: Protocol-Level Enforcement

Define `ObservationProtocol` with only read methods. Every data-accessing component conforms to this protocol. Write operations exist only in `SyncService`, which is excluded from injection into observation pipelines.

```swift
protocol ObservationReadable {
    func fetchSignals(since: Date) async throws -> [Signal]
    func fetchMemories(query: String) async throws -> [Memory]
    // No write methods on this protocol
}
```

Unit tests inject `ObservationReadable` only. If a component attempts a write inside a method called through this protocol, the compiler rejects it.

### Layer 3: Runtime Behavioural Test

```swift
@Test("No audio permission requested during full pipeline run")
func noCapturePermissionRequested() async throws {
    let monitor = PermissionRequestMonitor() // swizzles TCC request APIs
    _ = try await TimedPipeline.shared.process(signals: testBatch, context: inMemoryContext)
    #expect(monitor.capturedRequests.filter { $0.type == .microphone }.isEmpty)
    #expect(monitor.capturedRequests.filter { $0.type == .camera }.isEmpty)
}
```

Use a `PermissionRequestMonitor` that method-swizzles `AVCaptureDevice.requestAccess(for:)` in test builds to intercept any implicit permission requests before they hit the OS.

> **Additional recommendation:** Use Apple's `entitlements` file as a negative test — run `codesign -d --entitlements :- <binary>` in CI and assert that `com.apple.security.device.microphone` and `com.apple.security.device.camera` entitlements are absent. A missing entitlement is a hard architectural guarantee; the permission-monitoring test catches accidental runtime requests even without entitlements.

***

## LLM Output Testing

### JSON Schema Validation in CI

Claude's structured output feature (Sonnet 4.5 and Opus, with the `anthropic-beta: structured-outputs-2025-11-13` header) provides constrained decoding that guarantees schema compliance at the API level. For CI:[^30][^31]

1. **All three models** should be tested against the response schema
2. Haiku 3.5 (current generation) does not support constrained decoding — rely on prompt engineering + `JSONDecoder` validation for Haiku responses[^31]
3. Define all LLM response types as `Codable` Swift structs; decoding failure = schema validation failure

```swift
@Test("Haiku reflection output is valid JSON matching ReflectionOutput schema")
func haikuOutputSchema() async throws {
    let response = try await anthropicClient.message(
        model: "claude-haiku-3-5",
        prompt: ReflectionPrompt.standard(fixture: .week1)
    )
    // No constrained decoding on Haiku — must validate manually
    #expect(throws: Never.self) {
        _ = try JSONDecoder().decode(ReflectionOutput.self, from: response.rawData)
    }
}
```

### Handling Non-Determinism in CI

Non-determinism in LLM outputs creates flaky tests unless explicitly managed:[^22][^25]

| Strategy | When to Use | Implementation |
|---|---|---|
| Structural assertion only | Unit tests | Assert schema validity, not content |
| Seeded sampling with temperature=0 | Regression benchmarks | Claude supports `temperature: 0` for deterministic output |
| Statistical sampling (N=5, majority vote) | Integration tests | Run 5× and assert ≥4/5 pass structural check |
| LLM-as-judge with threshold | Quality gate | Score ≥3/5 with Haiku judge at temperature=0[^22] |
| Snapshot with diff tolerance | Golden file tests | Store reference output; fail if structure changes, not content[^25] |

In the CI pipeline, structural tests run on every PR (fast), LLM-judge tests run nightly (slow), and longitudinal regression runs weekly.[^24]

***

## Performance Testing

### Retrieval Latency at Scale

Use XCTest `measure{}` blocks with `XCTClockMetric` to establish baselines and track regressions. The `measure` block runs 10 iterations and fails if performance degrades beyond 10% of baseline.[^4][^5]

```swift
func testMemoryRetrievalLatency() {
    // Seed with 10,000 memory objects
    seedMemories(count: 10_000, context: persistenceStack.viewContext)

    measure(metrics: [XCTClockMetric(), XCTMemoryMetric()]) {
        let semaphore = DispatchSemaphore(value: 0)
        Task {
            _ = try? await memoryStore.retrieve(query: "quarterly board", limit: 20)
            semaphore.signal()
        }
        semaphore.wait()
    }
    // Set baseline: <50ms p50 for 10k record retrieval
}
```

Target thresholds at different scales:

| Memory Count | P50 Target | P99 Target |
|---|---|---|
| 1,000 | <10ms | <30ms |
| 10,000 | <50ms | <150ms |
| 100,000 | <200ms | <500ms |

### Vector Search Performance

For semantic memory retrieval backed by Supabase pgvector, use the HNSW index to achieve millisecond-range performance. Benchmark findings from production workloads show pgvector with HNSW achieves sub-10ms single-query latency and maintains consistency under concurrent load (std dev 3.9s vs ChromaDB's 11.2s at 50-concurrent).[^32][^33]

```swift
func testVectorSearchConcurrentLoad() {
    let expectation = expectation(description: "All concurrent queries complete")
    expectation.expectedFulfillmentCount = 20

    measure(metrics: [XCTClockMetric()]) {
        for query in concurrentQueryFixture(count: 20) {
            Task {
                _ = try? await vectorStore.semanticSearch(embedding: query.embedding, k: 10)
                expectation.fulfill()
            }
        }
    }
    wait(for: [expectation], timeout: 10.0)
}
```

### Concurrent Agent Testing

Timed runs multiple observation agents concurrently (calendar, email, document). Test for race conditions and deadlocks using Swift's structured concurrency `TaskGroup`:

```swift
@Test("Concurrent agent execution produces no race conditions")
func concurrentAgentSafety() async throws {
    try await withThrowingTaskGroup(of: [Signal].self) { group in
        for agent in [CalendarAgent(), EmailAgent(), DocumentAgent()] {
            group.addTask { try await agent.observe(window: .last24Hours) }
        }
        var allSignals: [Signal] = []
        for try await signals in group {
            allSignals.append(contentsOf: signals)
        }
        #expect(!allSignals.isEmpty)
    }
}
```

Run under TSAN (Thread Sanitizer) in CI: add `-sanitize=thread` to test scheme build settings.

***

## Privacy Testing

### No Raw Audio Persistence

The privacy guarantee is architectural: no `NSMicrophoneUsageDescription` key in `Info.plist`, no AVAudio capture entitlement. Test this automatically in CI:

```swift
@Test("Info.plist contains no microphone usage description")
func noMicrophoneUsageDescription() throws {
    let bundle = Bundle.main
    let micKey = bundle.object(forInfoDictionaryKey: "NSMicrophoneUsageDescription")
    #expect(micKey == nil, "Microphone key must be absent — observation-only app")
}
```

Additionally, assert at the binary level: CI step runs `codesign -d --entitlements :- build/Timed.app` and `grep`s for audio entitlements, failing the build if found.

### No PII in Logs

Validate at test output level using a `TestLogCapture` helper that inspects `os_log` output during test execution. Assert absence of known PII patterns:[^22]

```swift
@Test("Pipeline logs contain no PII")
func noPIIInLogs() async throws {
    let logCapture = TestLogCapture()
    try await TimedPipeline.shared.process(signals: realSignalFixture, context: inMemoryContext)
    let logs = logCapture.capturedMessages

    let piiPatterns = [
        #/\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b/i, // email
        #/\b\d{3}[-.]?\d{3}[-.]?\d{4}\b/,                // phone
        #/\b(?:first|last)\s+name:\s+\S+/i               // explicit PII labels
    ]
    for pattern in piiPatterns {
        #expect(!logs.contains(where: { $0.contains(pattern) }),
                "PII pattern detected in logs")
    }
}
```

For production audit (beyond CI), integrate Sentry with a PII scrubber configured to strip name, email, and phone patterns before transmission.

***

## Recommended Improvements Over Baseline Approaches

### 1. Property-Based Testing for ML Numerics

Instead of writing individual numeric test cases for Thompson Sampling and EMA, use **property-based testing** (SwiftCheck or a custom `Arbitrary` generator). Define invariants mathematically and let the framework generate hundreds of test inputs:[^1]

- EMA invariant: output is always a convex combination of inputs, bounded by `[min(series), max(series)]`
- Thompson Sampling invariant: posterior alpha+beta always equals prior + observed rewards
- Memory score invariant: score is monotone in recency and frequency independently

### 2. Contract Testing for Graph API

Record/replay cassettes become stale. The better long-term approach is **consumer-driven contract testing** (Pact or equivalent): Timed defines the contract it needs from Graph, and a separate test validates the live Graph API satisfies that contract on a scheduled basis. This catches API deprecations without requiring manual fixture refresh.[^16]

### 3. Snapshot/Golden File Testing for LLM Outputs

Rather than asserting exact content (brittle against model updates), store **golden file outputs** with structural annotations. Diffs flag structural changes (new keys, type changes) as failures while ignoring semantic variations in generated text. This is superior to both exact-match and pure schema validation for iterative LLM prompt development.[^25]

### 4. Chaos Testing for the Consolidation Pipeline

Introduce **fault injection** at the signal ingestion boundary: malformed JSON, truncated signals, out-of-order timestamps, duplicate IDs. The consolidation pipeline must handle all gracefully without corrupting the CoreData store. This is especially important for the observation-only constraint — a malformed calendar event must not trigger any write to user data.[^34]

### 5. Privacy-Differential Testing

Run the full pipeline against two fixture variants:
- `executive_A.json`: real names, email addresses, meeting titles
- `executive_A_redacted.json`: same structure, all PII replaced with tokens

Assert that pattern outputs are structurally identical between variants. If the pattern engine produces different results based on the presence of PII, it's using PII as a signal — a privacy violation requiring remediation.

***

## CI Pipeline Structure

```
PR Merge Request:
├── lint (SwiftLint custom rules, observation-only gate)     ~30s
├── unit tests (Swift Testing, in-memory CoreData)            ~2m
├── schema validation tests (JSON schema, Codable)            ~30s
└── static binary check (no mic entitlement)                  ~10s

Nightly:
├── integration tests (Graph cassette, consolidation pipeline) ~5m
├── LLM-as-judge quality gate (20% fixture sample)            ~10m
├── performance benchmarks (XCTest measure blocks)             ~8m
└── privacy differential tests                                ~3m

Weekly:
├── longitudinal regression (all 4 fixture timepoints)        ~20m
├── Thompson sampling convergence (full 2000-round suite)     ~5m
├── Graph contract test (live API validation)                  ~2m
└── baseline update (if all pass, commit new test_baselines.json) ~1m
```

***

## Coverage Enforcement

Use `xcov` or Xcode's coverage report exported as `xccovreport`. CI enforces minimum thresholds per module:

| Module | Line Target | Branch Target | Enforcement |
|---|---|---|---|
| `SignalIngestion` | 90% | 85% | Hard fail |
| `MLEngine` (TS, EMA, Scoring) | 85% | 80% | Hard fail |
| `MemoryLayer` (CoreData CRUD) | 95% | 90% | Hard fail |
| `ReflectionEngine` (LLM) | 70% | 65% | Warn only (LLM non-determinism) |
| `DeliveryLayer` | 80% | 75% | Hard fail |
| **Overall** | **85%** | **80%** | **Hard fail** |

The `ReflectionEngine` target is intentionally lower because deterministic code coverage of LLM call sites is insufficient signal — quality is measured via LLM-as-judge instead.

---

## References

1. [Swift Testing vs XCTest: when to migrate and how to start.](https://blog.micoach.itj.com/swift-testing-vs-xctest) - Compare Swift Testing and XCTest with clear examples. Learn when to migrate, how to start fast, and ...

2. [Swift Testing vs. XCTest: A Comprehensive Comparison](https://blogs.infosys.com/digital-experience/mobility/swift-testing-vs-xctest-a-comprehensive-comparison.html) - This comprehensive comparison delves into both frameworks, highlighting their strengths, weaknesses,...

3. [Unit testing Swift code that uses async/await](https://www.swiftbysundell.com/articles/unit-testing-code-that-uses-async-await) - Let's take a look at how to call async APIs within our unit tests, and also how async/await can be a...

4. [measureBlock: How Does Performance Testing Work In iOS?](https://developer.squareup.com/blog/measureblock-how-does-performance-testing-work-in-ios/) - measureBlock runs your block 10 times and calculates the average time it takes to run your block. Th...

5. [Performance testing in Swift using the XCTest framework](https://swiftwithmajid.com/2023/03/15/performance-testing-in-swift-using-xctest-framework/) - This API allows you to write tests that measure the execution time of a particular block of code, an...

6. [Asynchronous Tests and Expectations - Apple Developer](https://developer.apple.com/documentation/xctest/asynchronous-tests-and-expectations) - To test Swift code that uses async and await for concurrency, mark your test method async or async t...

7. [Async Unit Testing: The Comprehensive Guide - Jacob's Tech Tavern](https://blog.jacobstechtavern.com/p/async-unit-testing-in-swift-the-comprehensive) - In Swift's XCTest, you need to prefix any test method with test . We're also marking this function a...

8. [[Pitch] Targeted Interoperability between Swift Testing and XCTest](https://forums.swift.org/t/pitch-targeted-interoperability-between-swift-testing-and-xctest/82505) - We think supporting targeted interoperability between the Swift Testing and XCTest frameworks will m...

9. [[PDF] Asymptotic Convergence of Thompson Sampling - arXiv](https://arxiv.org/pdf/2011.03917.pdf) - In this paper, we prove an asymptotic convergence result for Thompson sampling under the assumption ...

10. [Thompson sampling - Wikipedia](https://en.wikipedia.org/wiki/Thompson_sampling) - Thompson sampling, [1] [2] [3] named after William R. Thompson, is a heuristic for choosing actions ...

11. [Exponential Moving Average (EMA) Explained - Strategies and Tips](https://www.earn2trade.com/blog/exponential-moving-average/) - Compared to our base scenario, we'll see that reducing the days improves the accuracy when the price...

12. [[2307.13813] How to Scale Your EMA - arXiv](https://arxiv.org/abs/2307.13813) - In this work, we provide a scaling rule for optimization in the presence of a model EMA and demonstr...

13. [How to Write Unit Tests with XCTest - OneUptime](https://oneuptime.com/blog/post/2026-02-02-swift-xctest-unit-tests/view) - Learn how to write effective unit tests in Swift using XCTest, Apple's native testing framework, wit...

14. [Simplifying Core Data Unit Testing - Brian Coyner](https://briancoyner.github.io/articles/2021-08-28-testing-core-data) - This article looks at a technique for setting up unit tests where each test method executes against ...

15. [Swift Testing Core Data setup/teardown](https://forums.swift.org/t/swift-testing-core-data-setup-teardown/75203) - I'm curious what the best practice should be here for writing Swift Tests. I'm creating my entities ...

16. [As a developer, I want to mock Graph responses to test my ... - GitHub](https://github.com/microsoftgraph/msgraph-sdk-design/issues/26) - As a developer, I want to mock Graph responses to test my integration with the Microsoft Graph clien...

17. [Mocking service for unit testing · Issue #695 - GitHub](https://github.com/microsoftgraph/msgraph-sdk-go/issues/695) - Was scanning the repo for example of unit testing response from the api and was not able to found an...

18. [How to mock Microsoft Graph APIs with Dev Proxy - LinkedIn](https://www.linkedin.com/posts/garry-trinder_working-with-microsoft-graph-apis-introduces-activity-7355912820628094976-jfxx) - DevUI makes it easy to test your agents and workflows written with Microsoft Agent Framework! And if...

19. [design patterns - How to unit test a state machine? - Stack Overflow](https://stackoverflow.com/questions/7797816/how-to-unit-test-a-state-machine) - The state machine will be implemented using the standard State Design Pattern (Gof). How do you usua...

20. [State Machines, part 4: Testing - XP123](https://xp123.com/state-machines-part-4-testing/) - How do you test state machines? We'll look at the challenges in testing both the state machines and ...

21. [Why 93% of AI Teams Struggle with LLM-as-a-Judge and 8 ...](https://galileo.ai/blog/alternative-ai-evaluation-methods-llm-judge) - Output Structure Validation is the strict enforcement of schema constraints. JSON schema validation ...

22. [LLM Evaluation and Testing: How to Build an Eval Pipeline That ...](https://dev.to/pockit_tools/llm-evaluation-and-testing-how-to-build-an-eval-pipeline-that-actually-catches-failures-before-5e3n) - The complete guide to evaluating LLM applications before they break in production. Automated eval fr...

23. [LLM-As-Judge: 7 Best Practices & Evaluation Templates - Monte Carlo](https://www.montecarlodata.com/blog-llm-as-judge/) - A straight-to-the-point guide to key concepts, evaluation templates, challenges, and more.

24. [Regression Testing Defined: Purpose, Types & Best Practices](https://www.augmentcode.com/learn/regression-testing-defined-purpose-types-and-best-practices) - Regression testing validates that software changes don't break existing functionality by re-executin...

25. [[PDF] Automated Regression Testing Framework for Large Language ...](https://www.tdcommons.org/cgi/viewcontent.cgi?article=8812&context=dpubs_series) - The system can aggregate test results and perform various actions such as issuing notifications or i...

26. [GitHub - realm/SwiftLint: A tool to enforce Swift style and conventions.](https://github.com/realm/swiftlint) - SwiftLint enforces the style guide rules that are generally accepted by the Swift community. These r...

27. [Avoid easy to miss errors with Custom SwiftLint Rules - YouTube](https://www.youtube.com/watch?v=F9sucfNWcCs) - ... Packages 08:17 - 7. Custom Rule Example #2: Hashable conformance 09:30 - 8. Creating Custom Swif...

28. [Continuous code inspection with SwiftLint for iOS Apps - Halodoc Blog](https://blogs.halodoc.io/continuous-code-inspection-ios/) - SwiftLint is an open-source tool to enforce Swift style and convention. SwiftLint allows us to enfor...

29. [Introducing, DeepSource for Swift](https://deepsource.com/blog/swift-static-analysis) - Today, I'm excited to announce DeepSource's Swift Analyzer, with support for static analysis, Static...

30. [Get validated JSON results from models - Amazon Bedrock](https://docs.aws.amazon.com/bedrock/latest/userguide/claude-messages-structured-outputs.html) - You can use structured outputs with Claude Sonnet 4.5, Claude Haiku 4.5, Claude Opus 4.5, and Claude...

31. [Claude API Structured Output: Complete Guide to Schema ...](https://thomas-wiegold.com/blog/claude-api-structured-output/) - Claude API structured output uses constrained decoding to guarantee JSON schema compliance. Learn im...

32. [Vector Search Performance: Speed & Scalability Benchmarks](https://www.newtuple.com/post/speed-and-scalability-in-vector-search) - Explore vector search benchmarks on speed and scalability. Learn how Newtuple optimizes latency and ...

33. [Vector Search Benchmarks - Qdrant](https://qdrant.tech/benchmarks/) - The first comparative benchmark and benchmarking framework for vector search engines.

34. [Code scanning: Essential guide for development teams - Sonar](https://www.sonarsource.com/resources/library/code-scanning/) - Code scanning is an automated process that uses static analysis to examine source code without execu...

