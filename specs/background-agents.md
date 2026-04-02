# Background Agent Architecture Spec

> Status: Implementation-ready spec
> Last updated: 2026-04-02
> Applies to: Timed macOS intelligence layer

---

## Context

Timed's intelligence depends on continuous passive observation. The Haiku swarm — lightweight background agents that watch email, calendar, task behaviour, app focus, and meeting signals — must run reliably on macOS without draining the battery or competing with the user's foreground work.

The agents are strictly observation-only. They record `SignalEvent` records to episodic memory. They never modify external systems, never send requests to Outlook/Graph on behalf of the user, and never take action. The reflection engine (nightly Opus) processes what they collect.

---

## macOS Background Execution Options

### Option 1: NSBackgroundActivityScheduler

**What it does:** Schedules periodic non-urgent work. macOS coalesces with other background activity for power efficiency. Respects system conditions (battery, thermal, user activity).

**Pros:**
- Power-efficient — macOS decides when to run based on system state
- Simple API — one scheduler per agent
- Respects App Nap, Low Power Mode, thermal throttling
- Good for periodic batch work (email delta sync every 15min, calendar poll every 10min)

**Cons:**
- Non-deterministic timing — macOS can delay by minutes or hours if system is busy
- Cannot guarantee real-time observation
- Not suitable for continuous monitoring (app focus tracking needs immediate response)

**Verdict:** Use for periodic sync agents (email, calendar). Not for real-time observers.

### Option 2: XPC Services

**What it does:** Separate processes that the main app communicates with via XPC protocol. Each runs in its own sandbox. Managed by launchd.

**Pros:**
- Process isolation — a crash in one agent doesn't crash the main app
- Independent memory budgets — each agent's memory is accounted separately
- Can be started on demand by the main app
- Apple-recommended for long-running background work in sandboxed apps

**Cons:**
- Significant implementation complexity (XPC protocol definitions, connection management, error handling)
- Debugging across process boundaries is harder
- Sharing CoreData context requires NSPersistentCloudKitContainer or file coordination
- Each XPC service is a separate build target

**Verdict:** Worth the complexity for the reflection engine (heavy Opus processing should be isolated). Overkill for lightweight signal observers.

### Option 3: Login Items (SMAppService)

**What it does:** Registers the app to launch at login. Combined with `NSApplication.shared.setActivationPolicy(.accessory)`, the app runs as a background agent with menu bar presence.

**Pros:**
- App starts at login without user intervention
- The app IS the background agent — no separate process needed
- Full access to all app state, CoreData, services
- Simple to implement with `SMAppService.mainApp.register()`

**Cons:**
- The entire app must be running (though as accessory, it's lightweight)
- If the user force-quits, observation stops until next login
- Single process — a hung agent blocks others

**Verdict:** Required for launch-at-login. This is the foundation — the app itself runs continuously as an accessory process.

### Option 4: LaunchAgents (launchd plist)

**What it does:** System-level daemon registration. The agent runs independently of any user session in some configurations.

**Pros:**
- Maximum reliability — launchd restarts if it crashes
- Can run before user logs in
- Independent of the main app process

**Cons:**
- Cannot use App Store distribution (though Timed uses DMG + Sparkle, so this is technically possible)
- More complex installation — needs to install a plist to `~/Library/LaunchAgents/`
- Communication with main app requires IPC
- Security concerns — users may be suspicious of a LaunchAgent

**Verdict:** Not recommended. The Login Item approach gives the same always-running behaviour with simpler implementation and less user suspicion. Reserve LaunchAgents for a future scenario where Timed needs to run without any UI process at all.

---

## Recommended Architecture

### Hybrid: Login Item + In-Process Agents + XPC for Reflection

```
┌──────────────────────────────────────────────────────────┐
│  Main App Process (Login Item, accessory mode)           │
│                                                          │
│  ┌────────────┐ ┌────────────┐ ┌──────────────┐        │
│  │ EmailAgent │ │ CalendarAgt│ │ BehaviourAgt │        │
│  │ (periodic) │ │ (periodic) │ │ (continuous) │        │
│  └─────┬──────┘ └─────┬──────┘ └──────┬───────┘        │
│        │              │               │                  │
│        └──────────────┴───────────────┘                  │
│                       │                                  │
│              ┌────────▼────────┐                         │
│              │  AgentCoordinator│                         │
│              │  (shared actor) │                         │
│              └────────┬────────┘                         │
│                       │                                  │
│              ┌────────▼────────┐                         │
│              │  CoreData Store │                         │
│              │  (background    │                         │
│              │   contexts)     │                         │
│              └─────────────────┘                         │
│                                                          │
│  ┌──────────────────────────────┐                        │
│  │  Menu Bar UI (NSStatusItem) │                        │
│  └──────────────────────────────┘                        │
└────────────────────────┬─────────────────────────────────┘
                         │ XPC
              ┌──────────▼──────────┐
              │  ReflectionXPCService│
              │  (separate process) │
              │  Runs nightly Opus  │
              └─────────────────────┘
```

### Justification

1. **Login Item** ensures the app starts at login and stays running as an invisible accessory process with menu bar presence (already implemented in `MenuBarManager.swift`)

2. **In-process agents** for the Haiku swarm: email, calendar, behaviour, and completion observers run as Swift actors within the main process. They share the CoreData persistent container via background contexts. No IPC overhead, simple debugging, easy state sharing.

3. **XPC service** only for the nightly reflection engine: Opus processing can take 30-120 seconds with high memory usage. Isolating it prevents the main process from being killed by macOS memory pressure. If the reflection XPC crashes, the main app and all signal agents continue running.

---

## Agent Definitions

### 1. EmailSentinelAgent

**Purpose:** Monitor email via Microsoft Graph delta sync. Record new emails, reply latencies, classification signals.

**Cadence:** `NSBackgroundActivityScheduler`, interval 15 minutes, tolerance 5 minutes. Also triggered on app foreground.

**CPU budget:** < 5% during sync. Typical sync processes 0-20 new messages.

**Memory budget:** < 30MB peak (message parsing + classification).

**What it records:**
- New email received (sender, subject, timestamp, truncated body for Haiku classification)
- Reply sent (latency from received to replied)
- Email archived/deleted (engagement signal)
- Email forwarded (delegation signal)
- Thread depth changes (conversation complexity)

**Implementation:**
```swift
actor EmailSentinelAgent: SignalAgent {
    let id = "email-sentinel"
    private let graphClient: GraphClient
    private let classifier: EmailClassifier
    private let memoryWriter: MemoryWriter
    private var deltaToken: String?

    func observe() async throws {
        let (messages, newToken) = try await graphClient.deltaSync(since: deltaToken)
        deltaToken = newToken

        for message in messages {
            // Haiku classification (runs via Supabase edge function)
            let classification = try await classifier.classify(message)

            let signal = SignalEvent(
                source: .email,
                eventType: .emailReceived,
                payload: EmailSignalPayload(
                    sender: message.sender,
                    subject: message.subject.truncatedForPrivacy(maxLength: 100),
                    classification: classification,
                    receivedAt: message.receivedAt,
                    bodyPreview: message.body.prefix(200) // NEVER send full body off device
                )
            )
            try await memoryWriter.record(signal)
        }
    }
}
```

### 2. CalendarWatcherAgent

**Purpose:** Monitor calendar changes. Record meeting additions, cancellations, reschedules, and density patterns.

**Cadence:** `NSBackgroundActivityScheduler`, interval 10 minutes, tolerance 3 minutes. Also triggered on app foreground.

**CPU budget:** < 3% during sync.

**Memory budget:** < 15MB peak.

**What it records:**
- New meeting added (who, when, duration, type inference from title/attendees)
- Meeting cancelled (who cancelled, how close to start time)
- Meeting rescheduled (frequency of rescheduling for this meeting series)
- Calendar density change (meetings-per-day trend)
- Gap creation/destruction (when free time appears or disappears)

### 3. BehaviourObserverAgent

**Purpose:** Track app focus, typing patterns (if accessibility permission granted), and desktop activity.

**Cadence:** Continuous via `NSWorkspace.shared.notificationCenter` observers. NOT polling — event-driven.

**CPU budget:** < 1% sustained. The agent is idle between events.

**Memory budget:** < 10MB.

**What it records:**
- App activated/deactivated (which app, duration of focus)
- Screen locked/unlocked (work session boundaries)
- Do Not Disturb toggled (deep work signal)
- Space/desktop switched (context switching frequency)

**Privacy constraint:** Records app NAME only (e.g., "Microsoft Word"), never window title content unless the user explicitly opts in via Settings. Window titles can contain document names, email subjects, and other sensitive content.

**Implementation:**
```swift
actor BehaviourObserverAgent: SignalAgent {
    let id = "behaviour-observer"
    private let memoryWriter: MemoryWriter
    private var currentApp: String?
    private var focusStart: Date?

    func startObserving() {
        let center = NSWorkspace.shared.notificationCenter

        center.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            Task { await self?.handleAppSwitch(to: app.localizedName ?? "Unknown") }
        }

        center.addObserver(
            forName: NSWorkspace.screensDidSleepNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { await self?.handleSleep() }
        }

        center.addObserver(
            forName: NSWorkspace.screensDidWakeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { await self?.handleWake() }
        }
    }

    private func handleAppSwitch(to appName: String) async {
        let now = Date()
        if let previous = currentApp, let start = focusStart {
            let duration = now.timeIntervalSince(start)
            if duration > 5 { // Ignore sub-5-second glances
                let signal = SignalEvent(
                    source: .behaviour,
                    eventType: .appFocus,
                    payload: AppFocusPayload(
                        appName: previous,
                        durationSeconds: duration,
                        startedAt: start,
                        endedAt: now
                    )
                )
                try? await memoryWriter.record(signal)
            }
        }
        currentApp = appName
        focusStart = now
    }
}
```

### 4. CompletionLoggerAgent

**Purpose:** Track task completions, deferrals, re-rankings, and timer sessions. This feeds the EMA time estimation and Thompson sampling.

**Cadence:** Event-driven — triggers when the user interacts with tasks in the UI.

**CPU budget:** Negligible. Writes one record per event.

**Memory budget:** < 5MB.

**What it records:**
- Task completed (estimated vs actual duration, bucket, time of day)
- Task deferred (which task, how many times, inferred reason if available)
- Task re-ranked by user (from position X to position Y — Thompson sampling signal)
- Focus timer started/stopped/completed (duration, was it completed or abandoned)
- Morning interview completed (duration, number of voice corrections)

### 5. DriftDetectorAgent

**Purpose:** Periodic analysis of recent signals to detect anomalies and behaviour drift. Runs Haiku-tier analysis on accumulated signals.

**Cadence:** `NSBackgroundActivityScheduler`, interval 2 hours, tolerance 30 minutes.

**CPU budget:** < 10% during analysis (Haiku API call + local processing). Runs for 5-15 seconds.

**Memory budget:** < 50MB peak (loads recent signals into memory for analysis).

**What it does:**
- Compares last 24 hours of signals to the established semantic model
- Flags anomalies: "Meeting density is 2.3x above 30-day average"
- Detects absence signals: "No email to CFO in 14 days (usual cadence: 3 days)"
- Triggers proactive alerts if anomaly exceeds threshold
- Does NOT run the full reflection cycle — that's the nightly Opus engine's job

---

## Agent Coordination

### Shared State: CoreData Background Contexts

All agents share the same `NSPersistentContainer` but each creates its own `newBackgroundContext()`. This is CoreData's designed concurrency model:

```swift
actor AgentCoordinator {
    static let shared = AgentCoordinator()

    private let container: NSPersistentContainer
    private var agents: [String: any SignalAgent] = [:]
    private var schedulers: [String: NSBackgroundActivityScheduler] = [:]

    func contextForAgent(_ agentId: String) -> NSManagedObjectContext {
        let context = container.newBackgroundContext()
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        context.name = "agent-\(agentId)"
        return context
    }
}
```

**Why not message passing?** The agents are writers, not collaborators. They don't need to communicate with each other. Each agent writes `SignalEvent` records independently. The reflection engine reads them all. Message passing adds complexity without benefit for a write-heavy, read-later architecture.

### Write Coalescing

To avoid thrashing the SQLite store with individual writes:

1. Each agent buffers `SignalEvent` records in memory (max 50 or 5 minutes, whichever comes first)
2. Flushes to CoreData in a single batch save
3. The `MemoryWriter` actor manages the buffer and flush cadence

```swift
actor MemoryWriter {
    private var buffer: [SignalEvent] = []
    private let flushThreshold = 50
    private let flushInterval: TimeInterval = 300 // 5 minutes
    private var lastFlush = Date()

    func record(_ signal: SignalEvent) async throws {
        buffer.append(signal)
        if buffer.count >= flushThreshold || Date().timeIntervalSince(lastFlush) >= flushInterval {
            try await flush()
        }
    }

    private func flush() async throws {
        guard !buffer.isEmpty else { return }
        let toWrite = buffer
        buffer = []
        lastFlush = Date()

        let context = AgentCoordinator.shared.contextForAgent("memory-writer")
        try await context.perform {
            for signal in toWrite {
                let entity = SignalEventEntity(context: context)
                entity.id = signal.id
                entity.timestamp = signal.timestamp
                entity.source = signal.source.rawValue
                entity.eventType = signal.eventType.rawValue
                entity.payloadJSON = try JSONEncoder().encode(signal.payload)
                entity.processed = false
            }
            try context.save()
        }
    }
}
```

---

## App Nap Management

macOS will App Nap the process if it has no visible windows and no active work. Since Timed runs as an accessory (menu bar only, no dock icon), it is a prime App Nap candidate.

**Solution:** Use `ProcessInfo.processInfo.beginActivity()` to declare ongoing activity:

```swift
final class AppNapManager {
    private var activityToken: NSObjectProtocol?

    func preventAppNap() {
        activityToken = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .idleSystemSleepDisabled],
            reason: "Timed is observing signals for intelligence building"
        )
    }

    func allowAppNap() {
        if let token = activityToken {
            ProcessInfo.processInfo.endActivity(token)
            activityToken = nil
        }
    }
}
```

**When to prevent App Nap:**
- Always, while any agent is actively syncing (email delta, calendar poll)
- During focus timer sessions
- During voice capture
- During reflection engine execution

**When to allow App Nap:**
- Between scheduled agent runs (the `NSBackgroundActivityScheduler` will wake the process when needed)
- When the system is on battery and no active observation is needed in the next 5 minutes

**Battery-aware throttling:**

```swift
func adjustForPowerState() {
    let isOnBattery = !ProcessInfo.processInfo.isLowPowerModeEnabled
        && IOPSCopyPowerSourcesInfo()... // Check AC vs battery

    if isOnBattery {
        // Double all scheduler intervals
        emailScheduler.interval = 30 * 60  // 30min instead of 15
        calendarScheduler.interval = 20 * 60  // 20min instead of 10
        driftScheduler.interval = 4 * 60 * 60  // 4hr instead of 2
    } else {
        // Normal intervals
        emailScheduler.interval = 15 * 60
        calendarScheduler.interval = 10 * 60
        driftScheduler.interval = 2 * 60 * 60
    }
}
```

---

## Sleep/Wake Behaviour

### On System Sleep (`NSWorkspace.screensDidSleepNotification`)

1. BehaviourObserverAgent records the current app focus session end
2. All agents flush their buffers to CoreData
3. All `NSBackgroundActivityScheduler` instances are automatically paused by macOS
4. App Nap prevention token is released
5. Note: DO NOT cancel scheduled work — macOS handles suspension

### On System Wake (`NSWorkspace.screensDidWakeNotification`)

1. App Nap prevention token is re-acquired
2. All periodic agents run immediately (catch up on missed observations)
3. EmailSentinelAgent runs delta sync (emails received during sleep)
4. CalendarWatcherAgent syncs (meetings may have been added/changed)
5. BehaviourObserverAgent starts a new observation session
6. DriftDetectorAgent checks if it missed its scheduled window and runs if so

```swift
func handleWake() async {
    appNapManager.preventAppNap()

    // Run all periodic agents immediately on wake
    async let emailCatchup = emailAgent.observe()
    async let calendarCatchup = calendarAgent.observe()

    // Wait for both before releasing App Nap control
    _ = try? await (emailCatchup, calendarCatchup)

    // Check if drift detection was missed
    if let lastDrift = await driftAgent.lastRunDate,
       Date().timeIntervalSince(lastDrift) > driftAgent.scheduledInterval * 1.5 {
        try? await driftAgent.observe()
    }
}
```

---

## CPU and Memory Budgets

| Agent | CPU (active) | CPU (idle) | Memory | Frequency |
|-------|-------------|------------|--------|-----------|
| EmailSentinel | < 5% | 0% | 30MB | Every 15min |
| CalendarWatcher | < 3% | 0% | 15MB | Every 10min |
| BehaviourObserver | < 1% | ~0% | 10MB | Continuous (event-driven) |
| CompletionLogger | < 1% | 0% | 5MB | Event-driven |
| DriftDetector | < 10% | 0% | 50MB | Every 2hr |
| **Total (idle)** | **~0%** | | **~10MB** | |
| **Total (all active)** | **< 20%** | | **~110MB** | |

### Memory Pressure Handling

Register for `DispatchSource.makeMemoryPressureSource()`:

```swift
let source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical])
source.setEventHandler {
    let event = source.data
    if event.contains(.critical) {
        // Flush all buffers, release caches
        Task { await AgentCoordinator.shared.emergencyFlush() }
    } else if event.contains(.warning) {
        // Reduce buffer sizes
        Task { await AgentCoordinator.shared.reduceMemoryFootprint() }
    }
}
source.resume()
```

---

## Health Monitoring

### Agent Heartbeat

Each agent reports its last successful run timestamp to the `AgentCoordinator`:

```swift
protocol SignalAgent: Actor {
    var id: String { get }
    var lastRunDate: Date? { get }
    var lastError: Error? { get }
    var runCount: Int { get }
    func observe() async throws
}
```

### Health Check

The `AgentCoordinator` runs a health check every 30 minutes:

```swift
func healthCheck() -> [AgentHealthReport] {
    agents.values.map { agent in
        AgentHealthReport(
            agentId: agent.id,
            lastRun: agent.lastRunDate,
            isOverdue: agent.lastRunDate.map { Date().timeIntervalSince($0) > agent.expectedInterval * 2 } ?? true,
            consecutiveFailures: agent.consecutiveFailures,
            status: agent.consecutiveFailures > 3 ? .degraded : .healthy
        )
    }
}
```

If an agent has failed 3 consecutive times:
1. Log a warning via `TimedLogger.agents`
2. Attempt to restart the agent
3. If restart fails, mark as degraded and continue with remaining agents
4. Surface degraded status in the menu bar tooltip (subtle, not alarming)
5. Include in the next morning session: "Email observation was interrupted for 4 hours overnight"

### Agent Lifecycle

```swift
actor AgentCoordinator {
    enum AgentState { case stopped, running, degraded, suspended }

    func startAll() async {
        for agent in agents.values {
            await start(agent)
        }
    }

    func start(_ agent: any SignalAgent) async {
        guard agentStates[agent.id] != .running else { return }
        agentStates[agent.id] = .running

        if let periodic = agent as? PeriodicAgent {
            let scheduler = NSBackgroundActivityScheduler(identifier: "com.timed.\(agent.id)")
            scheduler.interval = periodic.interval
            scheduler.tolerance = periodic.tolerance
            scheduler.qualityOfService = .utility
            scheduler.repeats = true
            scheduler.schedule { [weak self] completion in
                Task {
                    do {
                        try await agent.observe()
                    } catch {
                        await self?.handleAgentError(agent.id, error: error)
                    }
                    completion(.finished)
                }
            }
            schedulers[agent.id] = scheduler
        }

        if let continuous = agent as? ContinuousAgent {
            await continuous.startObserving()
        }
    }

    func stop(_ agentId: String) async {
        schedulers[agentId]?.invalidate()
        schedulers.removeValue(forKey: agentId)
        agentStates[agentId] = .stopped
    }

    func suspendAll() async {
        for id in agents.keys {
            agentStates[id] = .suspended
        }
        // Schedulers are automatically paused on sleep — just update state
    }

    func resumeAll() async {
        for id in agents.keys where agentStates[id] == .suspended {
            agentStates[id] = .running
        }
    }
}
```

---

## XPC Reflection Service

The nightly Opus reflection engine runs in a separate XPC service process:

### XPC Protocol

```swift
@objc protocol ReflectionServiceProtocol {
    func runNightlyReflection(
        since lastReflectionDate: Date,
        completion: @escaping (Data?, Error?) -> Void
    )
    func runDailyPatternExtraction(
        completion: @escaping (Data?, Error?) -> Void
    )
    func healthCheck(completion: @escaping (Bool) -> Void)
}
```

### Why XPC for Reflection Only

- The nightly Opus call can consume 200-500MB during context construction (loading episodic memories, semantic model, procedural rules into a prompt)
- Processing takes 30-120 seconds
- If macOS kills the process due to memory pressure, the main app (and all signal agents) survive
- The XPC service reads from the same CoreData store (file coordination via `NSPersistentStoreCoordinator`)
- Results are written back to CoreData, then the main app picks them up via `NSPersistentStoreRemoteChangeNotification`

### Scheduling the Nightly Run

The main app schedules the reflection via `NSBackgroundActivityScheduler` with a preferred time window:

```swift
let nightlyScheduler = NSBackgroundActivityScheduler(identifier: "com.timed.nightly-reflection")
nightlyScheduler.interval = 24 * 60 * 60 // Once per day
nightlyScheduler.tolerance = 2 * 60 * 60 // 2-hour window
nightlyScheduler.qualityOfService = .background
nightlyScheduler.repeats = true
nightlyScheduler.schedule { completion in
    // Connect to XPC service and trigger reflection
    let connection = NSXPCConnection(serviceName: "com.timed.ReflectionService")
    connection.remoteObjectInterface = NSXPCInterface(with: ReflectionServiceProtocol.self)
    connection.resume()

    let proxy = connection.remoteObjectProxyWithErrorHandler { error in
        TimedLogger.reflection.error("XPC connection failed: \(error)")
        completion(.deferred) // Retry later
    } as! ReflectionServiceProtocol

    proxy.runNightlyReflection(since: lastReflectionDate) { result, error in
        if let error {
            TimedLogger.reflection.error("Nightly reflection failed: \(error)")
            completion(.deferred)
        } else {
            completion(.finished)
        }
        connection.invalidate()
    }
}
```

---

## Testing Strategy

### Unit Tests

- Each agent in isolation with mocked `MemoryWriter`
- Verify signal events are correctly constructed from raw input
- Verify buffer flushing triggers at threshold
- Verify battery-aware interval adjustment

### Integration Tests

- Full `AgentCoordinator` lifecycle: start, run, suspend, resume, stop
- Sleep/wake simulation: verify agents flush and resume correctly
- Memory pressure simulation: verify emergency flush behaviour
- CoreData concurrent writes from multiple agents: verify no corruption

### Performance Tests

- Run all 5 agents simultaneously for 1 hour in a test harness
- Measure actual CPU usage via `mach_task_basic_info`
- Measure memory usage via `task_vm_info`
- Verify CPU < 20% peak, < 2% sustained idle
- Verify memory < 150MB total

---

## Open Questions for Implementation

1. **Accessibility permission UX:** BehaviourObserverAgent can track window titles (richer signal) if the user grants Accessibility permission. How to request this without being creepy? Current plan: make it optional in onboarding, default OFF, explain the exact data collected.

2. **Microsoft Graph rate limits:** EmailSentinelAgent hitting Graph delta sync every 15 minutes. Graph throttling threshold is ~10,000 requests per 10 minutes per app. For a single user this is fine, but verify with production credentials.

3. **Reflection XPC memory ceiling:** Need to profile the actual memory usage of the Opus reflection prompt construction. If it exceeds 500MB, consider streaming the episodic memories to the XPC service rather than loading all at once.
