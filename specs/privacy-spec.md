# Privacy and Data Handling Spec

> Status: Implementation-ready spec
> Last updated: 2026-04-02
> Applies to: Timed macOS intelligence layer

---

## Design Philosophy

Timed builds the most intimate digital model of a human being that any software has attempted. It knows their decision patterns, avoidance behaviours, relationship dynamics, cognitive rhythms, and emotional signatures. This data, in the wrong hands, would be devastating.

The privacy architecture must satisfy a specific user: a C-suite executive handling material non-public information (MNPI), board-level personnel decisions, M&A discussions, and confidential commercial negotiations. If the privacy model cannot be explained to a CEO in 60 seconds with zero hand-waving, it is not good enough.

**The promise:** Timed observes everything. It stores intelligence locally. It sends the minimum possible to the cloud, and only with encryption. The user can see everything the system knows about them. The user can delete everything, instantly and completely.

---

## Three-Tier Data Classification

### Tier 1: Device-Only (NEVER leaves the Mac)

Data that is stored exclusively in the local CoreData store (encrypted at rest via FileVault) and is never transmitted to any cloud service, including Supabase and Anthropic.

| Data Type | Why Device-Only |
|-----------|----------------|
| Raw audio from voice sessions | Contains unfiltered executive speech — could contain MNPI, names, deal terms |
| Full email body text | Email content may contain privileged information, legal documents, board materials |
| Window titles (if accessibility enabled) | May contain document names, email subjects, financial figures |
| Full meeting transcripts | Contains what was said in confidential meetings |
| App focus durations per app | Reveals work patterns that could be used for surveillance |
| Keystroke dynamics (if ever collected) | Biometric-adjacent data — never collected, listed for explicit exclusion |
| Raw `SignalEvent` payloads | The unprocessed observation stream — too granular for cloud |
| Episodic memory `rawData` field | Structured signal data with full fidelity |

**Technical enforcement:**
```swift
/// Marker protocol. Types conforming to this MUST NOT be serialised
/// for network transmission. The Supabase sync layer checks at compile
/// time that no DeviceOnlyData conforms to SyncableRecord.
protocol DeviceOnlyData {}

struct RawAudioCapture: DeviceOnlyData { ... }
struct FullEmailBody: DeviceOnlyData { ... }
struct WindowTitleObservation: DeviceOnlyData { ... }
```

The `SupabaseSyncService` generic constraint prevents accidental upload:

```swift
func sync<T: SyncableRecord>(_ records: [T]) async throws {
    // SyncableRecord cannot also conform to DeviceOnlyData
    // Compiler enforces this via protocol exclusion
}
```

### Tier 2: Encrypted Transit (sent to Anthropic API for processing, not stored remotely)

Data that is sent to the Anthropic API (Claude Haiku/Sonnet/Opus) for intelligence processing. It passes through Anthropic's API but is NOT stored by Anthropic (per Anthropic's API data policy: API inputs are not used for training and are deleted after processing).

| Data Type | What Is Sent | What Is NOT Sent |
|-----------|-------------|-----------------|
| Email classification | Sender name, subject line, first 200 chars of body | Full body, attachments, CC/BCC list |
| Voice transcript analysis | Parsed structured commands from voice | Raw audio, full unstructured transcript |
| Nightly reflection input | Episodic memory `content` field (natural language summaries), semantic facts, procedural rules | Raw signal payloads, email bodies, audio |
| Morning briefing generation | Core memory snapshot, recent patterns, rules | Any Tier 1 data |
| Drift detection | Aggregated behavioural statistics | Individual observations |

**Truncation rules for LLM input:**

```swift
struct LLMInputSanitiser {
    /// Email body: max 200 characters, strip signatures, strip forwarded content
    static func sanitiseEmailForClassification(_ email: EmailMessage) -> String {
        let body = email.body
            .replacingOccurrences(of: #"(?m)^>.*$"#, with: "", options: .regularExpression) // Remove quoted replies
            .replacingOccurrences(of: #"(?s)--\s*\n.*"#, with: "", options: .regularExpression) // Remove signatures
        return String(body.prefix(200))
    }

    /// Subject line: max 100 characters
    static func sanitiseSubject(_ subject: String) -> String {
        String(subject.prefix(100))
    }

    /// Window title: NEVER sent. If needed for local processing, hash it.
    static func hashWindowTitle(_ title: String) -> String {
        // SHA256 hash — allows pattern detection without revealing content
        SHA256.hash(data: Data(title.utf8)).compactMap { String(format: "%02x", $0) }.joined()
    }

    /// Voice transcript: only structured parsed output, not raw speech
    static func sanitiseVoiceForAnalysis(_ parsed: ParsedVoiceCommand) -> String {
        // Sends: "User requested to defer task 'Q3 review' to Thursday"
        // Does NOT send: "Uh, yeah, push that bloody Q3 review thing to Thursday, I can't deal with it today"
        parsed.structuredSummary
    }
}
```

**TLS enforcement:** All API calls use HTTPS (TLS 1.3). The `URLSession` configuration pins to Anthropic's certificate chain:

```swift
let sessionConfig = URLSessionConfiguration.default
sessionConfig.tlsMinimumSupportedProtocolVersion = .TLSv13
```

### Tier 3: Synced to Supabase (anonymised patterns for backup and cross-device)

Data that is synced to the Supabase Postgres database for durability, cross-device access (future), and reflection engine input (edge functions).

| Data Type | What Is Synced | Anonymisation |
|-----------|---------------|---------------|
| Semantic facts | Full `SemanticFact` records | Names replaced with role identifiers ("CFO", "Direct Report #3") |
| Procedural rules | Full `ProceduralRule` records | Same name anonymisation |
| Core memory snapshot | Roles, priorities, chronotype | Names anonymised |
| Task metadata | Bucket, estimated/actual minutes, completion time | No email content, no subject lines |
| Completion records | Bucket, timing accuracy data | No task titles |
| Behaviour rules | Rule type, confidence, sample size | No identifying data |
| Calendar density metrics | Meetings per day, gap durations | No meeting titles, no attendee names |

**What NEVER syncs to Supabase:**
- Email bodies, subjects, or sender email addresses
- Meeting titles or attendee lists
- Voice transcripts or audio
- Window titles
- App names or usage durations
- Any raw `SignalEvent` data
- Episodic memory `content` or `rawData` fields

**Name anonymisation implementation:**

```swift
actor NameAnonymiser {
    private var mapping: [String: String] = [:]
    private var roleCounters: [String: Int] = [:]

    /// Replace real names with role-based identifiers before Supabase sync
    func anonymise(_ text: String, knownContacts: [Contact]) -> String {
        var result = text
        for contact in knownContacts {
            let anonymousId = mapping[contact.email] ?? generateId(for: contact)
            mapping[contact.email] = anonymousId
            result = result.replacingOccurrences(of: contact.fullName, with: anonymousId)
            result = result.replacingOccurrences(of: contact.email, with: "\(anonymousId)@redacted")
        }
        return result
    }

    private func generateId(for contact: Contact) -> String {
        let role = contact.inferredRole ?? "Contact"
        let count = (roleCounters[role] ?? 0) + 1
        roleCounters[role] = count
        return "\(role) #\(count)" // e.g., "CFO #1", "Direct Report #3"
    }
}
```

---

## Encryption Architecture

### At Rest: FileVault Reliance

Timed does NOT implement its own at-rest encryption for the local CoreData store. Rationale:

1. FileVault encrypts the entire disk with AES-XTS 128-bit. It is always enabled on managed corporate Macs.
2. Rolling custom encryption on top of FileVault adds complexity and performance cost with minimal security benefit.
3. CoreData + SQLite do not natively support per-record encryption without significant wrapper code.
4. The attack surface for local data is physical access to an unlocked Mac — FileVault handles the locked case.

**First-launch check:**

```swift
func verifyFileVaultEnabled() -> Bool {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/fdesetup")
    process.arguments = ["isactive"]
    let pipe = Pipe()
    process.standardOutput = pipe
    try? process.run()
    process.waitUntilExit()
    let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
    return output?.trimmingCharacters(in: .whitespacesAndNewlines) == "true"
}
```

If FileVault is not enabled, show a warning during onboarding: "Your disk is not encrypted. Timed stores sensitive intelligence data locally. We strongly recommend enabling FileVault in System Settings > Privacy & Security."

### In Transit: TLS 1.3

All network communication uses TLS 1.3:
- Supabase REST API: HTTPS with Supabase-managed certificates
- Anthropic API: HTTPS with Anthropic-managed certificates
- Microsoft Graph API: HTTPS with Microsoft-managed certificates

No data is transmitted over plain HTTP under any circumstance. The app does not make any HTTP requests — all URLs are hardcoded as `https://`.

### Secrets: Keychain

All credentials stored in the macOS Keychain, never in UserDefaults, environment variables (for production), or hardcoded:

| Secret | Keychain Service | Keychain Account |
|--------|-----------------|-----------------|
| Supabase access token | `com.timed.supabase` | `access-token` |
| Supabase refresh token | `com.timed.supabase` | `refresh-token` |
| Microsoft Graph access token | `com.timed.graph` | `access-token` |
| Microsoft Graph refresh token | `com.timed.graph` | `refresh-token` |
| Anthropic API key | `com.timed.anthropic` | `api-key` |
| Jina AI API key | `com.timed.jina` | `api-key` |

```swift
actor KeychainManager {
    func store(secret: String, service: String, account: String) throws {
        let data = Data(secret.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess || status == errSecDuplicateItem else {
            throw KeychainError.storeFailed(status)
        }
        if status == errSecDuplicateItem {
            let update: [String: Any] = [kSecValueData as String: data]
            SecItemUpdate(query as CFDictionary, update as CFDictionary)
        }
    }

    func retrieve(service: String, account: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
```

**`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`** ensures secrets are:
- Only accessible when the Mac is unlocked
- Never backed up to iCloud Keychain
- Never migrated to a new device (user must re-authenticate)

---

## Transparent Model Inspection: "About My Model"

The user can see EVERYTHING the system has learned about them. This is not optional — it is a core trust mechanism.

### What the Panel Shows

**Section 1: Semantic Facts (What I Know About You)**
All `SemanticFact` records, grouped by category:
- Chronotype: "Peak analytical performance: 9:30-11:30 (confidence: 87%, 34 observations)"
- Preferences: "Prefers email over Slack for complex topics (confidence: 72%, 18 observations)"
- Relationships: "CFO: high-engagement, avg response time 45s (confidence: 91%, 52 observations)"
- Patterns: "Post-board meeting: 72-hour strategic output reduction (confidence: 78%, 8 observations)"

Each fact shows:
- The fact itself in natural language
- Confidence score (percentage)
- Number of supporting observations
- Date first detected and last updated
- A "This is wrong" button that registers a correction signal

**Section 2: Procedural Rules (How I Operate for You)**
All active `ProceduralRule` records:
- "When: task involves confrontational conversation -> Then: add 6.2-day average deferral warning"
- "When: Thursday afternoon after 2.5hr meetings -> Then: flag people decisions as high revision risk"

Each rule shows:
- Trigger and action in plain English
- How many times it has been activated
- Confidence score
- A "Disable this rule" toggle

**Section 3: Core Memory (What's Always in Context)**
The `CoreMemorySnapshot` — everything that is included in every AI prompt:
- Your name and role
- Current top 5 priorities
- Active projects (up to 10)
- Key relationships (up to 15)
- Chronotype profile
- Current stress indicators

**Section 4: Data Inventory**
- Total episodic memories: X,XXX
- Total semantic facts: XXX
- Total procedural rules: XX
- Oldest memory: [date]
- Last reflection: [date]
- Data stored locally: XXX MB
- Data synced to cloud: XXX MB (anonymised)

### Implementation

```swift
struct AboutMyModelView: View {
    @State private var semanticFacts: [SemanticFact] = []
    @State private var proceduralRules: [ProceduralRule] = []
    @State private var coreMemory: CoreMemorySnapshot?
    @State private var dataInventory: DataInventory?

    var body: some View {
        NavigationSplitView {
            List {
                NavigationLink("What I Know", value: Section.semantic)
                NavigationLink("How I Operate", value: Section.procedural)
                NavigationLink("Core Memory", value: Section.core)
                NavigationLink("Data Inventory", value: Section.inventory)
                NavigationLink("Privacy Controls", value: Section.privacy)

                Section {
                    Button("Export All My Data", role: .none) { exportAllData() }
                    Button("Delete All My Data", role: .destructive) { confirmDeletion() }
                }
            }
        } detail: {
            // Section content
        }
    }
}
```

---

## Complete Data Deletion

When the user requests deletion, ALL data is destroyed:

### Deletion Scope

1. **Local CoreData store:** Drop and recreate the SQLite file
2. **Local DataStore JSON files:** Delete entire `~/Library/Application Support/Timed/` directory
3. **Supabase remote data:** Call `delete-all-user-data` edge function that cascades across all tables for the user's `auth.uid()`
4. **Keychain secrets:** Remove all entries under `com.timed.*`
5. **UserDefaults:** Reset all `@AppStorage` keys
6. **Migration backups:** Delete `~/Library/Application Support/Timed/Backups/`
7. **Voice session audio cache:** Delete any temporary audio files in the app's temp directory

### Implementation

```swift
func deleteAllData() async throws {
    // 1. Remote first (if we lose connection after, local data is still deleted)
    if AuthService.shared.isSignedIn {
        try await supabaseClient.deleteAllUserData()
    }

    // 2. Local CoreData
    let storeURL = persistentContainer.persistentStoreDescriptions.first?.url
    try persistentContainer.persistentStoreCoordinator.destroyPersistentStore(
        at: storeURL!, type: .sqlite
    )

    // 3. JSON files
    try FileManager.default.removeItem(at: timedSupportDir)

    // 4. Keychain
    for service in ["com.timed.supabase", "com.timed.graph", "com.timed.anthropic", "com.timed.jina"] {
        try keychainManager.deleteAll(service: service)
    }

    // 5. UserDefaults
    if let bundleId = Bundle.main.bundleIdentifier {
        UserDefaults.standard.removePersistentDomain(forName: bundleId)
    }

    // 6. Backups
    let backupDir = timedSupportDir.appendingPathComponent("Backups")
    try? FileManager.default.removeItem(at: backupDir)

    // 7. Temp audio
    let tempDir = FileManager.default.temporaryDirectory
    let timedTemp = tempDir.appendingPathComponent("Timed")
    try? FileManager.default.removeItem(at: timedTemp)
}
```

### Deletion Confirmation UI

Two-step confirmation:
1. First click: "Delete all my data? This removes everything Timed has learned about you. This cannot be undone."
2. Second click (after 3-second delay): "Type DELETE to confirm"

After deletion, the app resets to the onboarding screen.

---

## Data Export

The user can export all their data at any time:

### Export Format

JSON archive containing:
- `semantic_facts.json` — all semantic facts with full metadata
- `procedural_rules.json` — all procedural rules
- `core_memory.json` — current core memory snapshot
- `episodic_memories.json` — all episodic memory content (NOT raw payloads)
- `completion_records.json` — task completion history
- `settings.json` — all user preferences
- `metadata.json` — export timestamp, app version, data counts

### What Is NOT Exported
- Raw audio files (too large, and the transcript captures the intelligence)
- Embeddings (can be recomputed)
- Raw `SignalEvent` payloads (too granular, and episodic content captures the intelligence)

---

## GDPR Considerations

Timed processes personal data of EU-resident executives. Relevant GDPR articles:

### Article 6: Lawful Basis

**Lawful basis: Consent (Art. 6(1)(a))**

The user explicitly opts in during onboarding. Each signal source (email, calendar, voice, behaviour tracking) is individually consented to. No signal source is enabled by default — the user must actively enable each one.

### Article 13/14: Right to Information

Satisfied by the "About My Model" panel and the privacy explanation during onboarding. The user knows exactly what is collected, how it is processed, where it is stored, and who has access.

### Article 15: Right of Access

Satisfied by the data export feature. The user can export all their data in machine-readable JSON at any time.

### Article 17: Right to Erasure

Satisfied by the complete data deletion feature. All data — local, remote, cached — is destroyed on request.

### Article 20: Right to Data Portability

Satisfied by JSON export. The data is structured, machine-readable, and in a commonly used format.

### Article 25: Data Protection by Design

- Tier 1 data never leaves the device (minimisation)
- Tier 2 data is truncated before transmission (minimisation)
- Tier 3 data is anonymised before cloud sync (pseudonymisation)
- Default state is maximum privacy (no signal sources enabled until user activates them)

### Article 35: Data Protection Impact Assessment

Required before deployment. The DPIA should cover:
- The sensitive nature of executive behavioural modelling
- Risk of re-identification from anonymised patterns
- Risk of model compromise (what an attacker learns from the semantic model)
- Mitigations: device-only storage, anonymisation, deletion capability

---

## Executive-Specific Privacy Concerns

### Material Non-Public Information (MNPI)

C-suite executives routinely handle MNPI in email and meetings. Timed's privacy architecture addresses this:

1. **Email bodies containing MNPI never leave the device.** Only truncated previews (200 chars) are sent for Haiku classification, and these are processed by Anthropic's API (not stored, not used for training).

2. **Meeting content stays local.** Voice transcripts are device-only. The reflection engine receives structured summaries ("executive discussed Q3 pipeline concerns"), not verbatim quotes.

3. **Calendar event titles are anonymised before cloud sync.** "Board meeting: CEO succession planning" becomes a density metric ("1 meeting, 2 hours, category: board").

4. **The semantic model does not contain MNPI.** It contains behavioural patterns: "tends to delay people decisions" — not "is considering firing the VP of Sales."

### How to Explain This to a CEO Handling MNPI

> "Timed runs on your Mac. Your emails, meetings, and voice sessions never leave your computer in their raw form. When we need AI to classify an email, we send only the sender name and the first line — never the full email. The intelligence model we build about your work patterns is stored locally. What goes to our cloud backup is anonymised: 'CFO' instead of the actual name, meeting counts instead of meeting titles. You can see everything the system knows about you, and you can delete it all with one button."

This is a 30-second explanation that a CEO can repeat to their board or legal counsel.

### Insider Trading Risk Mitigation

Even anonymised patterns could theoretically reveal MNPI if combined with other information (e.g., "executive had 3x normal meetings with 'External Counsel #1' this week" could signal M&A activity). Mitigations:

1. Cloud-synced data uses generic role identifiers, not even the relationship type ("Contact #7", not "External Counsel #1")
2. Calendar density is synced as daily aggregate only, not per-meeting
3. The user can disable cloud sync entirely and run fully local
4. The semantic model uploaded to cloud does NOT include relationship-specific patterns — only personal cognitive patterns

---

## Threat Model

### Attack Surface

| Threat | Likelihood | Impact | Mitigation |
|--------|-----------|--------|------------|
| Physical access to unlocked Mac | Medium | Critical | FileVault, screen lock timeout, Keychain requires unlock |
| Supabase database breach | Low | Medium | Only anonymised Tier 3 data in cloud. No email content, no names. |
| Anthropic API interception | Very Low | Medium | TLS 1.3, certificate pinning. API data not stored by Anthropic. |
| Man-in-the-middle | Very Low | Medium | TLS 1.3 on all connections. |
| Malicious app on same Mac | Low | High | App sandbox (if distributed via DMG, sandbox is not enforced — rely on Gatekeeper + notarisation) |
| Compromised Supabase credentials | Low | Medium | RLS policies scoped to `auth.uid()`. One user cannot access another's data. Refresh tokens rotated. |
| Social engineering of API keys | Low | High | Keys in Keychain, not in code. Supabase anon key is public by design; RLS enforces access control. |

### Containment Architecture

If the Supabase database is fully compromised:
- Attacker gets anonymised behavioural patterns ("peak performance 9:30-11:30", "delays people decisions")
- Attacker does NOT get: email content, meeting details, voice recordings, app usage, names, email addresses
- The intelligence is shallow without the device-only context

If the Mac is physically compromised (unlocked):
- Attacker gets everything — this is the maximum exposure scenario
- Mitigation: encourage screen lock, FileVault, strong password
- Timed could add an optional app-level PIN/biometric lock (Touch ID on supported Macs) as a future feature

---

## Per-Sender Email Opt-Out

The user can exclude specific senders from all Timed processing:

```swift
struct SenderPrivacyRule: Codable {
    let senderEmail: String
    let senderName: String
    let excludeFromClassification: Bool  // Skip Haiku classification
    let excludeFromPatternAnalysis: Bool // Skip reflection engine analysis
    let excludeFromReplyTracking: Bool   // Don't track response latency
    let addedAt: Date
}
```

Use case: The executive's lawyer, therapist, or family members whose emails should be completely invisible to the system.

The `EmailSentinelAgent` checks the exclusion list BEFORE processing:

```swift
func shouldProcess(_ email: EmailMessage, exclusions: [SenderPrivacyRule]) -> Bool {
    !exclusions.contains { $0.senderEmail.lowercased() == email.sender.lowercased() }
}
```

Excluded emails are not recorded as `SignalEvent` records. They are as if they never existed to the system.
