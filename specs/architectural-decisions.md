# Timed — Architectural Decision Records

> 10 ADRs covering every major technical decision. Each includes context, options evaluated, decision, consequences, and reversal cost.

**Last updated:** 2026-04-02

---

## ADR-001: CoreData vs SwiftData vs SQLite for On-Device Persistence

### Context

Timed needs a local persistence layer that handles:
- Complex entity relationships (15+ entity types, M:M joins)
- Background context writes from 4+ concurrent signal agents
- Embedding vector storage (1024-dim float arrays)
- Compound query predicates for memory retrieval scoring
- Model migration as the schema evolves rapidly during v1 development
- macOS 14+ deployment target

### Options

**Option A: CoreData (NSPersistentContainer)**
- Mature, battle-tested on macOS for 20+ years
- Native background contexts with `newBackgroundContext()`
- `Transformable` attributes for custom types (embedding vectors)
- Full migration support (lightweight + heavyweight)
- Verbose boilerplate for managed object subclasses
- Integrated with SwiftUI via `@FetchRequest`

**Option B: SwiftData (@Model)**
- Modern, Swift-native, less boilerplate
- `ModelActor` for background processing
- `#Predicate` macro for type-safe queries
- Limited: no equivalent to `Transformable` for raw `[Float]` vectors
- Limited: `ModelActor` is less proven under heavy concurrent writes
- Limited: migration tooling is still immature (macOS 14 shipped with known migration bugs)
- Limited: complex compound predicates with computed scores are awkward in `#Predicate`

**Option C: SQLite via GRDB or SQLite.swift**
- Full SQL control, optimal for complex scoring queries
- No ORM overhead
- Manual relationship management
- No SwiftUI integration (no `@FetchRequest`)
- Custom migration system needed
- No CloudKit sync path (if ever needed)

### Decision

**CoreData (Option A).**

### Consequences

- Boilerplate: ~40 lines per entity for managed object subclass. Mitigated by code generation.
- All entities defined in `.xcdatamodeld` visual editor + corresponding Swift subclasses in `Sources/Core/Models/`.
- Background contexts used for all Layer 1 writes; view context reserved for UI reads.
- Embedding vectors stored as `Transformable` with `EmbeddingVectorTransformer`.
- Migration: lightweight migration by default; heavyweight only for type changes.

### Reversal Cost: MEDIUM

Switching to SwiftData requires rewriting all managed object subclasses to `@Model`, rewriting all `NSFetchRequest` calls to `#Predicate`, and rebuilding the multi-context concurrency model. The repository pattern (protocols at layer boundaries) limits blast radius — only the `Sources/Core/Models/` and `Sources/Core/Persistence/` directories would change. Estimate: 2–3 days of focused work.

---

## ADR-002: On-Device vs Cloud Voice Processing

### Context

Timed's morning voice session is the primary interaction mode. The executive speaks for ~90 seconds, and the system must:
1. Transcribe speech to text in real-time (for live feedback)
2. Handle Australian-accented English reliably
3. Maintain privacy (voice contains confidential business information)
4. Work offline when traveling

### Options

**Option A: Apple Speech Framework (on-device)**
- Ships with macOS, no external dependency
- Runs entirely on-device — zero network latency, full privacy
- Supports real-time partial results via `SFSpeechAudioBufferRecognitionRequest`
- Accuracy: good for clear English, weaker on domain-specific business terms
- No cost per request
- Already implemented in current codebase (`VoiceCaptureService.swift`)

**Option B: OpenAI Whisper API (cloud)**
- Best-in-class accuracy, especially for accented English
- Handles business terminology well
- Requires network — breaks offline mode
- Privacy concern: raw audio uploaded to OpenAI servers
- Cost: ~$0.006/minute ($0.009 for a 90s session)
- Adds 2–5s latency before transcription begins

**Option C: Whisper.cpp (local model)**
- Whisper accuracy, running on-device via Metal
- ~1GB model download for `medium` or `large-v3`
- Good accuracy, runs at ~1x real-time on M1+
- No live partial results (batch processing only)
- Custom integration work, not maintained by Apple

**Option D: Hybrid — Apple Speech for live, Whisper for post-correction**
- Apple Speech provides real-time feedback during recording
- After recording ends, run Whisper.cpp for higher-accuracy final transcript
- Best UX (live feedback) + best accuracy (Whisper final)
- Increased complexity: two transcription paths, reconciliation logic

### Decision

**Option A: Apple Speech Framework (on-device), with Option D as a Phase 2 upgrade.**

### Consequences

- Privacy: voice audio never leaves the device. This is critical for C-suite users.
- Accuracy: ~92–95% for clear English. Acceptable for morning sessions where the AI has context to disambiguate.
- Offline: fully functional without network.
- Real-time: partial results update the UI as the user speaks.
- Limitation: occasional misrecognition of business names and acronyms. Mitigated by the AI parsing layer (Sonnet) which has context about the user's contacts and projects.

### Reversal Cost: LOW

`VoiceCaptureService` is already isolated behind the `SignalAgent` protocol. Swapping to Whisper.cpp or a cloud API requires changing only the transcription implementation, not the downstream pipeline.

---

## ADR-003: Nightly vs Continuous Reflection

### Context

The reflection engine is the heart of Timed's intelligence. It must transform raw observations into patterns, semantic knowledge, and procedural rules. The question is *when* to run it.

### Options

**Option A: Continuous real-time reflection**
- Process every signal immediately with Opus
- Immediate intelligence, no delay
- Cost: ~$2–$5/day per user (hundreds of Opus calls)
- Risk: noise — Opus seeing individual signals without daily context
- Risk: rate limits — hundreds of calls per day

**Option B: Nightly batch reflection**
- Accumulate all day's signals, run deep reflection once at night
- Inspired by human sleep-based memory consolidation
- Cost: ~$0.30–$1.50/night (1–3 Opus calls)
- Deep context: Opus sees the full day's patterns, not isolated events
- Delay: insights not available until the next morning
- Aligned with the morning session delivery model

**Option C: Hybrid — real-time lightweight + nightly deep**
- Haiku processes signals in real-time (classification, importance scoring)
- Opus runs deep reflection nightly (pattern extraction, synthesis, rule generation)
- Real-time alerts for high-importance events (Haiku detects, no Opus needed)
- Nightly depth for compounding intelligence
- Cost: ~$0.05–$0.10/day Haiku + $0.30–$1.50/night Opus

**Option D: Event-driven reflection**
- Trigger Opus only when a "significant" event occurs
- Definition of "significant" requires a classifier (which model classifies?)
- Unpredictable cost and timing
- Risk: missing important patterns that emerge from mundane signals

### Decision

**Option C: Hybrid — Haiku real-time classification + Opus nightly deep reflection.**

### Consequences

- Real-time: Haiku classifies every signal (<500ms, ~$0.0001/call). Sets importance scores, triage buckets.
- Nightly: Opus runs recursive 4-pass reflection on all day's unconsolidated memories. Deep, thorough, no cost cap.
- Triggered: Opus can be triggered mid-day for importance > 0.9 signals (rare, ~1–2x/week).
- Morning session: always uses the latest nightly reflection output.
- This maps directly to the brain's wake/sleep cycle: conscious processing (Haiku) during the day, deep consolidation (Opus) at night.

### Reversal Cost: LOW

Each processing mode is behind a protocol. Switching to continuous Opus would mean changing the scheduler, not the reflection engine logic.

---

## ADR-004: Embedding Storage — On-Device vs pgvector vs Hybrid

### Context

Timed uses 1024-dimensional Jina embeddings for memory retrieval (cosine similarity search). The system needs to:
- Store embeddings for every episodic memory (~50–200/day, ~5000/month)
- Search by similarity for retrieval-scored queries
- Keep recent memories fast (<50ms query) and archive old ones cost-effectively

### Options

**Option A: All embeddings in CoreData**
- Stored as `Transformable` `[Float]` (4096 bytes each)
- Similarity search: load all vectors, compute cosine in Swift
- Fast for small collections (<5000 vectors)
- Scales poorly: 10,000 vectors × 4KB = 40MB in memory for search
- No vector indexing (brute-force scan)

**Option B: All embeddings in Supabase pgvector**
- PostgreSQL extension with IVFFlat or HNSW indexing
- Handles millions of vectors efficiently
- Requires network for every query
- Adds 100–500ms latency per search
- Single source of truth, no sync issues

**Option C: Hybrid — recent on-device, archival in pgvector**
- Last 90 days in CoreData (brute-force, fast, <5000 vectors)
- Older than 90 days: migrate embeddings to Supabase pgvector
- Local search for recent memories (<10ms)
- pgvector search for archival retrieval (only when nightly reflection needs deep history)
- Bounded local storage
- Two search paths to maintain

### Decision

**Option C: Hybrid — recent on-device, archival in pgvector.**

### Consequences

- Local: CoreData stores embeddings for memories < 90 days old. Brute-force cosine search in Swift. At ~200 memories/day × 90 days = ~18,000 vectors. 18,000 × 4KB = ~72MB peak. Acceptable on M-series Macs.
- Archival: monthly consolidation job migrates old embeddings to Supabase pgvector. CoreData entity deleted, only the embedding + metadata preserved server-side.
- Search: retrieval queries first search local (fast), then optionally extend to pgvector (for nightly reflection that needs historical context).
- Optimization: local search uses Apple Accelerate framework for vectorized cosine similarity (vDSP).

### Reversal Cost: MEDIUM

Moving to all-pgvector requires making every retrieval query a network call. Moving to all-local requires accepting unbounded CoreData growth. The hybrid approach requires maintaining two code paths but bounds both concerns.

---

## ADR-005: macOS Background Processing Strategy

### Context

Timed must run multiple background agents (email sync, calendar sync, app focus tracking) and a nightly reflection engine. macOS is more permissive than iOS for background processing, but there are still constraints.

### Options

**Option A: NSBackgroundActivityScheduler**
- macOS-native API for scheduling background work
- System-managed: macOS decides optimal timing (respects power state, thermal)
- Good for periodic non-urgent tasks (nightly reflection)
- Tolerance parameter controls how much the system can delay execution
- Does not guarantee execution at exact time

**Option B: Timer-based polling (DispatchSourceTimer / Task.sleep)**
- Full control over timing
- Runs in the app's process — only works while app is running
- Simple to implement
- No system-level power management awareness

**Option C: XPC Service / Login Item**
- Separate process that runs independently of the main app
- Can persist across app restarts
- Heavy implementation (separate binary, IPC protocol)
- Required for true "always-on" monitoring

**Option D: Hybrid — Timer for real-time + NSBackgroundActivityScheduler for nightly**
- Real-time agents use Swift concurrency `Task.sleep` loops (5-min intervals)
- Nightly reflection uses `NSBackgroundActivityScheduler` with `interval = 86400`
- App must be running (menu bar presence ensures this)
- System optimizes nightly work timing around power state

### Decision

**Option D: Hybrid approach.**

### Consequences

- Menu bar presence ensures the app process is always running during work hours.
- Real-time agents: `Task.sleep` with configurable intervals (email: 5min, calendar: 15min, app focus: continuous via NSWorkspace notifications).
- Nightly reflection: `NSBackgroundActivityScheduler` with `interval = 86400`, `tolerance = 3600` (system can shift ±1hr for optimal timing).
- App delegate handles `NSApplication.willTerminate` to gracefully stop all agents.
- Login Items registration ensures Timed launches at system boot.
- Power-aware: `ProcessInfo.processInfo.isLowPowerModeEnabled` checked before heavy operations.

### Reversal Cost: LOW

Each agent is a standalone actor. Changing the scheduling mechanism doesn't affect agent logic.

---

## ADR-006: Observation-Only Enforcement

### Context

The hardest architectural constraint: Timed must NEVER act on the world. It cannot send emails, modify calendars, accept meetings, or perform any external write operation. This must be enforced at the architectural level, not relied on developer discipline.

### Options

**Option A: Convention only ("don't write write-methods")**
- Simplest
- Zero enforcement — one developer mistake exposes the user
- Unacceptable for a system handling C-suite executive data

**Option B: OAuth scope restriction only**
- Request only `Mail.Read` and `Calendars.Read` from Microsoft Graph
- Token physically cannot perform write operations
- Strong: works even if code has bugs
- Weak: doesn't cover other potential write paths (Supabase user-facing writes, system actions)

**Option C: Multi-layer enforcement**
- OAuth scopes: read-only (compile-time guarantee against Graph writes)
- Protocol design: no write methods on external service protocols
- Linter rule: custom SwiftLint rule flagging any HTTP POST/PUT/PATCH/DELETE to Graph endpoints
- Code review rule: any PR adding external write capability is auto-rejected
- Runtime assertion: debug builds crash if a write API is called

### Decision

**Option C: Multi-layer enforcement.**

### Consequences

- OAuth: MSAL configured with `["Mail.Read", "Calendars.Read", "offline_access"]` only. Changing scopes requires a new Azure app registration — deliberate and auditable.
- Protocols: `GraphClient` exposes only `fetchEmails()`, `fetchCalendarEvents()`, `fetchDelta()`. No `sendEmail()`, `createEvent()`, etc.
- Linter: custom SwiftLint rule (`.swiftlint.yml`) flags any `URLRequest` with `httpMethod != "GET"` targeting `graph.microsoft.com`.
- Runtime: `#if DEBUG` assertion in network layer that fires if a non-GET request targets any external API.
- Supabase: Edge Functions are the only write path to Supabase tables. The Swift client uses `select()` queries only for user-facing data.

### Reversal Cost: HIGH (intentionally)

Adding write capability requires: changing Azure app registration (admin consent), updating MSAL scopes, adding new protocol methods, updating linter rules, removing assertions. This is a 5-step process that cannot happen accidentally.

---

## ADR-007: Memory Tier Boundaries and Promotion Rules

### Context

Timed's three-tier memory system (episodic → semantic → procedural) needs clear rules for when data moves between tiers. Too aggressive promotion creates noise in higher tiers. Too conservative means the system never learns.

### Options

**Option A: Time-based promotion only**
- Episodic → semantic after 7 days if accessed 3+ times
- Semantic → procedural after 30 days if reinforced 5+ times
- Simple, predictable
- Ignores content quality — a frequently accessed but unimportant memory gets promoted

**Option B: Reflection-engine-driven promotion (Opus decides)**
- Opus reviews unconsolidated memories and decides what to promote
- Highest quality decisions — Opus has full context
- Expensive: every promotion requires an Opus call
- Opus could be inconsistent across runs

**Option C: Hybrid — heuristic filtering + Opus final decision**
- Heuristic: only memories with importance > 0.5 AND access count > 2 are candidates
- Opus: reviews candidates during nightly reflection, decides promotions
- Reduces Opus token usage by pre-filtering
- Heuristic prevents noise, Opus ensures quality

### Decision

**Option C: Hybrid heuristic + Opus.**

### Consequences

Promotion rules:

**Episodic → Semantic (nightly):**
- Candidate filter: `importanceScore >= 0.5 AND accessCount >= 2 AND isConsolidated == false`
- Opus reviews candidates in clusters (embedding similarity > 0.75)
- Opus decides: promote to semantic fact, or mark as consolidated without promotion
- Semantic memory created with `confidenceScore = 0.5`

**Semantic → Procedural (weekly):**
- Candidate filter: `confidenceScore >= 0.7 AND reinforcementCount >= 5`
- Opus reviews candidates for actionable if-then structure
- Procedural rule created with `status = .testing`

**Procedural → Active Rule (automatic):**
- After 3 activations without user correction: `status` changes from `.testing` to `.active`
- User correction resets activation count and adds to exception notes

**Core Memory (Opus-managed, nightly):**
- Opus reviews the full core memory buffer each night
- Can add, update, or evict entries based on relevance
- Evicted entries are preserved as semantic memories (never lost)

**Archival (monthly):**
- Episodic memories > 90 days with `accessCount == 0`: archived to pgvector
- Semantic memories with `isActive == false` for 30+ days: archived
- Archived = embedding preserved in Supabase, CoreData entity deleted

### Reversal Cost: LOW

Promotion rules are configurable constants, not hard-coded. Changing thresholds requires updating `MemoryPromotionConfig` and re-running consolidation.

---

## ADR-008: AI Model Routing Strategy

### Context

Timed uses three AI model tiers (Haiku, Sonnet, Opus) for different tasks. The routing decision affects cost, latency, and intelligence quality.

### Options

**Option A: Static routing (hardcoded model per task type)**
- Email classification → Haiku, always
- Time estimation → Sonnet, always
- Reflection → Opus, always
- Simple, predictable cost
- No adaptation to load or availability

**Option B: Dynamic routing (confidence-based escalation)**
- Start with Haiku for every task
- If Haiku confidence < threshold, escalate to Sonnet
- If Sonnet confidence < threshold, escalate to Opus
- Minimizes cost
- Adds latency for escalated tasks (two API calls)
- Risk: over-reliance on cheap models for important tasks

**Option C: Static routing with dynamic fallback**
- Each task type has a preferred model (static)
- If preferred model is unavailable (rate limited, outage), fall back to next tier
- Opus tasks NEVER fall back to cheaper models — they retry or defer
- Non-Opus tasks fall back gracefully

### Decision

**Option C: Static routing with dynamic fallback. Opus tasks never downgrade.**

### Consequences

| Task | Preferred | Fallback | Downgrade to Cheaper? |
|------|-----------|----------|----------------------|
| Email classification | Haiku 3.5 | Heuristic (regex + keyword) | N/A (already cheapest) |
| Email triage bucket | Haiku 3.5 | Default "action" bucket | N/A |
| Task time estimation | Sonnet 4 | EMA estimate from history | Yes (acceptable) |
| Voice transcript parsing | Sonnet 4 | Regex TranscriptParser | Yes (acceptable) |
| Nightly reflection | Opus 4.6 | Retry 3x, then defer to tomorrow | **NEVER** downgrade |
| Morning briefing | Opus 4.6 | Cached yesterday's briefing | **NEVER** downgrade |
| Profile generation | Opus 4.6 | Cached last profile | **NEVER** downgrade |

The "no cost cap on intelligence" principle means Opus tasks never compromise. If Opus is unavailable, the system waits or uses cached data — it does not substitute Sonnet.

### Reversal Cost: LOW

The `AIRouter` actor encapsulates all routing logic. Changing routing rules is a configuration change, not an architecture change.

---

## ADR-009: Microsoft Graph Sync Strategy

### Context

Timed reads email and calendar data from Microsoft Graph (Outlook). The sync strategy affects data freshness, API quota usage, and reliability.

### Options

**Option A: Polling with delta queries**
- Poll `/me/mailFolders/inbox/messages/delta` every 5 minutes
- Delta queries return only changes since last sync
- Simple, reliable, works behind firewalls
- 5-minute delay on new emails
- Quota: ~288 calls/day (well within Graph limits)

**Option B: Graph webhooks (change notifications)**
- Microsoft pushes a notification when email/calendar changes
- Near-real-time (< 30 seconds)
- Requires a publicly accessible HTTPS endpoint (Supabase Edge Function)
- Webhook subscriptions expire every 3 days — must be renewed
- Complex: webhook delivery is not guaranteed (must poll as fallback)

**Option C: Hybrid — webhooks for speed, delta polling as fallback**
- Webhook → Supabase Edge Function → Supabase Realtime → app
- Delta poll every 15 minutes as catch-up (in case webhook missed)
- Best of both: near-real-time + guaranteed consistency
- Most complex: two sync paths, subscription management

### Decision

**Option A for v1: Polling with delta queries only. Option C planned for v2.**

### Consequences

- Simplicity: one sync path, no webhook infrastructure to maintain during v1 development
- Latency: 5-minute delay on new emails. Acceptable — Timed is not a real-time email client.
- Reliability: delta queries are idempotent and self-healing. If a poll fails, the next poll catches up.
- Implementation: `EmailSignalAgent` runs a `Task.sleep(300)` loop calling `GraphClient.fetchDelta()`
- Calendar: separate delta query on `/me/calendar/events/delta`, polling every 15 minutes
- The `graph-webhook` and `renew-graph-subscriptions` Edge Functions already exist for v2 transition

### Reversal Cost: LOW

Adding webhooks is additive — the delta polling remains as fallback. No existing code needs to change.

---

## ADR-010: Distribution Method — Direct DMG vs Mac App Store

### Context

Timed needs to reach C-suite executives' Macs. The distribution method affects permissions, updates, and first-run experience.

### Options

**Option A: Mac App Store**
- Trusted distribution channel
- Automatic updates
- App Sandbox required — restricts:
  - Background processing (more limited)
  - Accessibility API access (needed for app focus tracking)
  - NSWorkspace notifications (available but sandboxed)
  - File system access (highly restricted)
  - MSAL OAuth (may have redirect URI issues in sandbox)
- 30% revenue share
- App Review delays (1–7 days per submission)
- No direct customer relationship

**Option B: Direct DMG + Sparkle**
- Full system permissions (no sandbox)
- Sparkle framework for auto-updates (industry standard for Mac apps)
- Direct customer relationship (email, license key)
- No revenue share
- No App Review delays — ship when ready
- User must approve "unidentified developer" on first launch (mitigated by Developer ID signing + notarization)

**Option C: TestFlight (during development) → App Store (at launch)**
- TestFlight for beta distribution
- App Store for production
- Gets real-world testing before sandbox constraints bite
- Still hits sandbox limitations at App Store launch

### Decision

**Option B: Direct DMG + Sparkle. Developer ID signed and notarized.**

### Consequences

- Full permissions: Accessibility API for app focus tracking, unrestricted background processing, full file system access for local data storage.
- Sparkle: auto-update framework checks for updates on launch and periodically. Updates are signed with EdDSA.
- Notarization: every build is submitted to Apple for notarization before distribution. Users see "Apple checked it for malicious software" on first launch.
- Distribution: DMG hosted on Timed's website or CDN. Download link sent directly to customers.
- No App Store friction: updates ship the moment they're ready. Critical for a v1 product iterating rapidly.
- Licensing: implement a simple license key system (or initially, direct distribution to known customers only).

### Reversal Cost: HIGH

Moving to the App Store requires sandboxing the entire app, which means:
- Rewriting app focus tracking to work within sandbox
- Potentially losing Accessibility API access
- Reworking file storage paths
- Modifying MSAL OAuth redirect handling
- This would be a 1–2 week effort with risk of feature loss.
