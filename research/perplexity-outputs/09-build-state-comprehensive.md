# Timed — BUILD_STATE.md

> **Cognitive intelligence layer for C-suite executives.** Observation only. Never acts.
> Stack: Swift 5.9+, SwiftUI, CoreData, Supabase/pgvector, Jina embeddings, MSAL OAuth, Claude Haiku/Sonnet/Opus tiers.

***

## Legend

| Symbol | Meaning |
|--------|---------|
| ✅ DONE | Shipped and functional |
| 🔲 NOT STARTED | No code exists yet |
| S / M / L / XL | Complexity: Small (~1–3 days) / Medium (~1 week) / Large (~2–3 weeks) / Extra Large (1+ month) |

***

## Layer 1 — Signal Ingestion

Responsible for capturing real-world signals from the executive's digital environment without taking any action. The layer must operate passively and entirely on-device where possible.

### 1.1 Voice & Audio Agents

| Component | Status | Complexity | Prerequisites | Phase |
|-----------|--------|-----------|---------------|-------|
| Voice morning session (record + transcribe) | ✅ DONE | M | SFSpeechRecognizer, microphone entitlement | P1 |
| Real-time ambient meeting capture | 🔲 NOT STARTED | L | ScreenCaptureKit audio tap or CoreAudio passthrough | P2 |
| Speaker diarization (who said what) | 🔲 NOT STARTED | XL | On-device ML model or external diarization API | P3 |
| Post-session transcript storage + chunking | 🔲 NOT STARTED | M | Voice session (✅), CoreData or Supabase write | P2 |
| SpeechAnalyzer migration (macOS 26) | 🔲 NOT STARTED | S | macOS 26 (Tahoe) SDK deployment target | P2 |

**Note:** Apple's new `SpeechAnalyzer` API (macOS 26 / iOS 26) supersedes `SFSpeechRecognizer`. It is faster, works fully offline, requires no model downloads, and powers Notes, Voice Memos, and Call Summarization on-device. The upgrade is a low-complexity, high-value migration once you adopt the macOS 26 deployment target.[^1][^2][^3]

### 1.2 Email Signal Agent

| Component | Status | Complexity | Prerequisites | Phase |
|-----------|--------|-----------|---------------|-------|
| Email triage (fetch + classify) | ✅ DONE | M | MSAL OAuth, Microsoft Graph API | P1 |
| MSAL OAuth token refresh + silent acquisition | 🔲 NOT STARTED | M | MSAL CocoaPods/SPM, entitlements | P1 |
| Email threading + conversation graph builder | 🔲 NOT STARTED | L | Email triage (✅), CoreData schema | P2 |
| Attachment metadata extraction | 🔲 NOT STARTED | M | Email triage (✅), file type detection | P2 |
| Sender relationship graph (who is important) | 🔲 NOT STARTED | L | Email threading, Thompson scoring (✅) | P3 |
| Gmail OAuth agent (non-Microsoft) | 🔲 NOT STARTED | M | Google Sign-In SDK, additional MSAL work | P3 |

**Sandbox Warning:** Apple tightened app sandbox restrictions on Mail and file access progressively since 2022. CVE-2025-31191 triggered additional restrictions on security-scoped bookmarks. Distributing Timed **outside the Mac App Store** (direct download with Notarization) bypasses the most severe sandbox constraints while still passing Gatekeeper — the recommended architecture for a tool requiring AX API + Mail access.[^4][^5][^6]

### 1.3 Calendar Signal Agent

| Component | Status | Complexity | Prerequisites | Phase |
|-----------|--------|-----------|---------------|-------|
| Calendar event fetch + allocator | ✅ DONE | M | EventKit, `com.apple.security.personal-information.calendars` entitlement | P1 |
| EventKit full-access permission flow (macOS 14+) | 🔲 NOT STARTED | S | `requestFullAccessToEvents()` replaces deprecated API[^7] | P1 |
| Recurring pattern detection | 🔲 NOT STARTED | M | Calendar fetch (✅), basic ML or rule engine | P2 |
| Meeting load heatmap computation | 🔲 NOT STARTED | S | Calendar fetch (✅), EMA estimator (✅) | P2 |
| Calendar write-back guard (ensure read-only) | 🔲 NOT STARTED | S | Calendar fetch (✅) | P1 |

### 1.4 Screen & App Context Agent

| Component | Status | Complexity | Prerequisites | Phase |
|-----------|--------|-----------|---------------|-------|
| Active app + window title observer (AXObserver) | 🔲 NOT STARTED | M | Accessibility entitlement, non-sandboxed app | P2 |
| Context-window content snapshot (ScreenCaptureKit) | 🔲 NOT STARTED | L | ScreenCaptureKit (macOS 12.3+), privacy permissions | P3 |
| Focus app category classifier | 🔲 NOT STARTED | M | AX observer, NaturalLanguage classifier | P2 |
| App switch frequency tracker | 🔲 NOT STARTED | S | AX observer | P2 |
| Deep work vs. shallow work classifier | 🔲 NOT STARTED | M | App category classifier, focus timer (✅) | P2 |

The macOS Accessibility API (`AXObserver`/`AXUIElement`) enables passive window and UI observation. It requires the `com.apple.security.accessibility` entitlement and user grant in System Settings → Accessibility. Note: sandbox must be disabled or this entitlement explicitly set. `ScreenCaptureKit` introduced in macOS 12.3 provides high-performance frame capture with built-in privacy safeguards.[^8][^9][^10]

### 1.5 Communication Pattern Agent

| Component | Status | Complexity | Prerequisites | Phase |
|-----------|--------|-----------|---------------|-------|
| Slack/Teams API poller (read-only) | 🔲 NOT STARTED | L | OAuth for Slack/Teams, rate-limit handling | P3 |
| Message urgency scorer | 🔲 NOT STARTED | M | Slack/Teams poller, NL sentiment (on-device) | P3 |
| Contact importance ranker | 🔲 NOT STARTED | L | Email graph, calendar signal, Thompson scoring (✅) | P3 |

***

## Layer 2 — Memory Store

Provides episodic, semantic, and working memory for the reflection engine. Splits across on-device (CoreData, fast) and cloud (Supabase/pgvector, persistent).

### 2.1 Local Episodic Buffer (CoreData)

| Component | Status | Complexity | Prerequisites | Phase |
|-----------|--------|-----------|---------------|-------|
| CoreData schema: Event, Signal, Session entities | 🔲 NOT STARTED | M | — | P1 |
| TTL-based eviction policy (rolling 7-day local window) | 🔲 NOT STARTED | S | CoreData schema | P2 |
| In-memory working context store (NSCache / actor) | 🔲 NOT STARTED | S | CoreData schema | P1 |
| CoreData ↔ Supabase sync coordinator | 🔲 NOT STARTED | L | CoreData schema, Supabase client | P2 |
| Conflict resolution (offline-first, last-write-wins) | 🔲 NOT STARTED | M | Sync coordinator | P2 |

### 2.2 Semantic Memory (Supabase + pgvector)

| Component | Status | Complexity | Prerequisites | Phase |
|-----------|--------|-----------|---------------|-------|
| Supabase project setup (pgvector extension enabled) | 🔲 NOT STARTED | S | Supabase account | P1 |
| Signal embedding pipeline (Jina API → pgvector) | 🔲 NOT STARTED | M | Jina API key, Supabase schema | P1 |
| `match_documents` cosine similarity RPC | 🔲 NOT STARTED | S | pgvector table, embedding pipeline | P1 |
| Hybrid search (semantic + metadata filter) | 🔲 NOT STARTED | M | `match_documents`, relational join | P2 |
| Embedding batch job (background Swift actor) | 🔲 NOT STARTED | M | Jina embedding pipeline, CoreData | P2 |
| Embedding cache (avoid re-embedding unchanged text) | 🔲 NOT STARTED | S | Embedding pipeline | P2 |

Supabase's pgvector extension supports cosine similarity search with full relational joins, enabling hybrid retrieval of semantic matches filtered by date, source, or person. Jina Embeddings v4 is a 3.8B-parameter multimodal model supporting text and image in a unified vector space, available as a managed REST API with 10 million free tokens. Using Jina's REST API from Swift is straightforward — no native SDK required; `URLSession` + `Codable` suffices.[^11][^12][^13][^14]

### 2.3 Long-Term Knowledge Graph

| Component | Status | Complexity | Prerequisites | Phase |
|-----------|--------|-----------|---------------|-------|
| Entity extraction (people, orgs, topics) | 🔲 NOT STARTED | L | NaturalLanguage framework, signal store | P2 |
| Entity deduplication + merging | 🔲 NOT STARTED | M | Entity extraction | P3 |
| Relationship edge table (Supabase) | 🔲 NOT STARTED | M | Entity extraction, Supabase schema | P3 |
| Graph traversal query helpers | 🔲 NOT STARTED | M | Relationship edge table | P3 |
| Knowledge graph pruning + archival | 🔲 NOT STARTED | M | Graph traversal | P3 |

### 2.4 User Profile & Preference Store

| Component | Status | Complexity | Prerequisites | Phase |
|-----------|--------|-----------|---------------|-------|
| Baseline behavioral model (initial survey) | 🔲 NOT STARTED | S | — | P1 |
| Dynamic preference updates from feedback | 🔲 NOT STARTED | M | Thompson sampling (✅), feedback signal | P2 |
| Work style fingerprint (deep work windows, comm style) | 🔲 NOT STARTED | M | Calendar allocator (✅), app context agent | P2 |
| Role-specific vocabulary + org-context dictionary | 🔲 NOT STARTED | M | Entity extraction | P3 |

***

## Layer 3 — Reflection Engine

The analytical core. Processes stored signals to generate patterns, summaries, predictions, and decision-relevant insights. All inference must be non-prescriptive — the engine observes and surfaces, never directs.

### 3.1 Scoring & ML Models

| Component | Status | Complexity | Prerequisites | Phase |
|-----------|--------|-----------|---------------|-------|
| Thompson sampling email/task scorer | ✅ DONE | M | — | P1 |
| EMA time estimation model | ✅ DONE | M | — | P1 |
| Variance-adaptive Thompson sampling upgrade | 🔲 NOT STARTED | M | Thompson sampling (✅) | P2 |
| On-device sentiment classifier (NLTagger) | 🔲 NOT STARTED | S | NaturalLanguage framework | P2 |
| Named entity recognition (NLTagger) | 🔲 NOT STARTED | S | NaturalLanguage framework | P2 |
| Task complexity classifier (Haiku tier) | 🔲 NOT STARTED | M | Signal ingestion, Haiku API | P2 |
| Meeting energy drain predictor | 🔲 NOT STARTED | L | Calendar signal (✅), EMA model (✅), history | P3 |
| Decision fatigue estimator (time × cognitive load) | 🔲 NOT STARTED | L | App context agent, calendar signal, meeting history | P3 |

Apple's NaturalLanguage framework provides on-device sentiment scoring from -1.0 to +1.0 via `NLTagger` with millisecond latency — appropriate for email and message tone analysis without any API cost. For Thompson sampling, Apple Research published a variance-adaptive extension that achieves lower regret for tasks with heterogeneous reward variance — directly applicable to upgrading the shipped scorer.[^15][^16][^17]

### 3.2 Daily Reflection Stages

| Component | Status | Complexity | Prerequisites | Phase |
|-----------|--------|-----------|---------------|-------|
| Morning session synthesis (goals → structure) | ✅ DONE | M | Voice session (✅), Sonnet | P1 |
| Mid-day signal pulse (calendar + email digest) | 🔲 NOT STARTED | M | Calendar agent (✅), email triage (✅), Haiku | P2 |
| Evening retrospective generator | 🔲 NOT STARTED | M | Signal store, EMA model (✅), Sonnet | P2 |
| Weekly pattern summary | 🔲 NOT STARTED | M | Evening retrospective, entity extraction, Sonnet | P3 |
| Anomaly detection (deviation from baseline) | 🔲 NOT STARTED | L | User profile, rolling stats, Supabase | P3 |
| Trend surfacing (30/60/90-day) | 🔲 NOT STARTED | L | Anomaly detection, knowledge graph | P3 |

### 3.3 AI Tier Routing Engine

| Component | Status | Complexity | Prerequisites | Phase |
|-----------|--------|-----------|---------------|-------|
| Model router (Haiku / Sonnet / Opus dispatch) | 🔲 NOT STARTED | M | Claude API keys | P1 |
| Task complexity pre-classifier | 🔲 NOT STARTED | M | Model router | P1 |
| Token usage tracker + cost guardrail | 🔲 NOT STARTED | S | Model router | P1 |
| Prompt caching for repeated context | 🔲 NOT STARTED | M | Model router, Anthropic prompt cache API | P2 |
| Retry + escalation logic (Haiku fail → Sonnet) | 🔲 NOT STARTED | S | Model router | P1 |

The recommended routing strategy: Haiku (classification, extraction, quick pulse — 60–70% of tasks), Sonnet (morning synthesis, retrospectives, analysis — ~25% of tasks), Opus (complex multi-system reasoning — <10%). At current pricing — Haiku at $1/$5 per million tokens, Sonnet at $3/$15, Opus at $15/$75 — smart routing cuts LLM costs by 60–70% versus defaulting to Sonnet. This is a critical Phase 1 component to build before scaling inference volume.[^18][^19][^20][^21]

### 3.4 Context Window Manager

| Component | Status | Complexity | Prerequisites | Phase |
|-----------|--------|-----------|---------------|-------|
| Sliding context builder (relevant memory retrieval) | 🔲 NOT STARTED | M | Semantic memory, pgvector RPC | P2 |
| Context compressor (summarise old turns) | 🔲 NOT STARTED | M | Sonnet summarization, CoreData | P2 |
| Prompt template registry | 🔲 NOT STARTED | S | Model router | P1 |
| System prompt personalization (user profile injection) | 🔲 NOT STARTED | M | User profile store, prompt templates | P2 |

***

## Layer 4 — Intelligence Delivery

Surfaces insights to the executive at the right moment, right channel, right depth. Interfaces must reduce cognitive load, not add to it.[^22][^23]

### 4.1 Menu Bar & Command Palette

| Component | Status | Complexity | Prerequisites | Phase |
|-----------|--------|-----------|---------------|-------|
| Menu bar (NSStatusItem + SwiftUI popover) | ✅ DONE | M | — | P1 |
| Command palette (spotlight-style input) | ✅ DONE | M | — | P1 |
| Contextual quick-actions in menu bar | 🔲 NOT STARTED | M | Menu bar (✅), reflection engine outputs | P2 |
| Status indicator (active/idle/processing) | 🔲 NOT STARTED | S | Menu bar (✅) | P1 |
| Keyboard shortcut global trigger | 🔲 NOT STARTED | S | Menu bar (✅) | P1 |

### 4.2 Focus Timer & Flow Interface

| Component | Status | Complexity | Prerequisites | Phase |
|-----------|--------|-----------|---------------|-------|
| Focus timer | ✅ DONE | S | — | P1 |
| AI-suggested session length (EMA-driven) | 🔲 NOT STARTED | M | Focus timer (✅), EMA model (✅) | P2 |
| Interruption scoring during session | 🔲 NOT STARTED | M | Focus timer (✅), AX app observer | P2 |
| Post-session micro-reflection prompt | 🔲 NOT STARTED | S | Focus timer (✅), Haiku | P2 |

### 4.3 Notification & Alert Delivery

| Component | Status | Complexity | Prerequisites | Phase |
|-----------|--------|-----------|---------------|-------|
| `UNUserNotificationCenter` integration | 🔲 NOT STARTED | S | macOS entitlement | P1 |
| Urgency-gated notification delivery | 🔲 NOT STARTED | M | Thompson scoring (✅), UNNotification | P2 |
| Notification action handlers (dismiss/snooze/expand) | 🔲 NOT STARTED | M | UNNotification | P2 |
| Rich notification (custom UI extension) | 🔲 NOT STARTED | M | UNNotificationContent extension | P3 |
| Quiet hours / DND observer | 🔲 NOT STARTED | S | UNNotification, user profile | P2 |

`UNUserNotificationCenter` supports banners, sounds, categories with action buttons, and custom content UI extensions on macOS. Urgency gating — routing only high-Thompson-score signals to notification — prevents the notification saturation that degrades executive attention.[^24][^25][^22]

### 4.4 Insight Dashboard (SwiftUI)

| Component | Status | Complexity | Prerequisites | Phase |
|-----------|--------|-----------|---------------|-------|
| Daily summary card view | 🔲 NOT STARTED | M | Reflection engine outputs | P2 |
| Email / calendar load timeline | 🔲 NOT STARTED | M | Signal store, CoreData | P2 |
| Energy & focus pattern charts (Swift Charts) | 🔲 NOT STARTED | M | Daily summary, EMA model | P2 |
| Weekly trend visualization | 🔲 NOT STARTED | L | Weekly summary, trend surfacing | P3 |
| Knowledge graph browser (people + topics) | 🔲 NOT STARTED | XL | Knowledge graph, entity extraction | P3 |
| Export / share insight snapshot | 🔲 NOT STARTED | M | Dashboard views | P3 |

### 4.5 Conversational Interface

| Component | Status | Complexity | Prerequisites | Phase |
|-----------|--------|-----------|---------------|-------|
| Chat window (SwiftUI, non-modal) | 🔲 NOT STARTED | M | Model router, command palette (✅) | P2 |
| Streaming response renderer | 🔲 NOT STARTED | M | Anthropic streaming API, SwiftUI | P2 |
| Memory-augmented conversation (RAG) | 🔲 NOT STARTED | L | Semantic memory, pgvector RPC, chat window | P2 |
| Conversation history persistence | 🔲 NOT STARTED | M | CoreData, chat window | P2 |
| Query intent classifier (Haiku pre-pass) | 🔲 NOT STARTED | S | Model router, chat window | P2 |

***

## Infrastructure & Integrations

### 5.1 Auth & Identity

| Component | Status | Complexity | Prerequisites | Phase |
|-----------|--------|-----------|---------------|-------|
| MSAL OAuth initial flow (Microsoft 365) | 🔲 NOT STARTED | M | MSAL SPM dependency, Azure app registration | P1 |
| MSAL silent token refresh | 🔲 NOT STARTED | M | MSAL initial flow | P1 |
| Supabase auth (email or Apple Sign-In) | 🔲 NOT STARTED | S | Supabase project | P1 |
| Keychain token storage | 🔲 NOT STARTED | S | MSAL flow | P1 |
| Multi-account support (exec + EA roles) | 🔲 NOT STARTED | L | Auth, user profile | P3 |

MSAL for macOS uses `MSALPublicClientApplication` with `MSALWebviewParameters()` (no view controller needed on macOS). Silent token acquisition via `acquireTokenSilentWithParameters` requires `macOS 10.15+`. Store tokens in the macOS Keychain (not UserDefaults) to survive app restarts securely.[^26][^27]

### 5.2 Data Layer

| Component | Status | Complexity | Prerequisites | Phase |
|-----------|--------|-----------|---------------|-------|
| Supabase Swift client setup | 🔲 NOT STARTED | S | Supabase project | P1 |
| pgvector table schema (signals, embeddings) | 🔲 NOT STARTED | S | Supabase client | P1 |
| Row-level security (RLS) policies | 🔲 NOT STARTED | M | pgvector schema | P1 |
| Background sync queue (Swift actor, async/await) | 🔲 NOT STARTED | M | CoreData, Supabase client | P2 |
| Data retention + GDPR-style purge mechanism | 🔲 NOT STARTED | M | Data layer | P2 |
| Encryption at rest (CoreData NSPersistentStore + Supabase) | 🔲 NOT STARTED | M | Data layer | P2 |

### 5.3 Entitlements & Privacy

| Component | Status | Complexity | Prerequisites | Phase |
|-----------|--------|-----------|---------------|-------|
| Entitlements file (calendar, speech, network, accessibility) | 🔲 NOT STARTED | S | — | P1 |
| Non-sandbox distribution configuration | 🔲 NOT STARTED | S | Xcode signing, Notarization | P1 |
| Privacy manifest (PrivacyInfo.xcprivacy) | 🔲 NOT STARTED | S | All data-accessing agents | P2 |
| Usage description strings (all NSUsageDescription keys) | 🔲 NOT STARTED | S | All data-accessing agents | P1 |
| Notarization + Gatekeeper signing workflow | 🔲 NOT STARTED | M | Non-sandbox config | P2 |

### 5.4 Observability & Testing

| Component | Status | Complexity | Prerequisites | Phase |
|-----------|--------|-----------|---------------|-------|
| Structured logging (OSLog / Logger) | 🔲 NOT STARTED | S | — | P1 |
| Supabase-side event analytics | 🔲 NOT STARTED | M | Supabase client | P2 |
| Unit tests: Thompson scorer | 🔲 NOT STARTED | S | Thompson sampling (✅) | P1 |
| Unit tests: EMA estimator | 🔲 NOT STARTED | S | EMA model (✅) | P1 |
| Integration tests: signal pipeline | 🔲 NOT STARTED | M | Signal agents | P2 |
| Performance profiling (Instruments, token cost) | 🔲 NOT STARTED | M | Full pipeline | P3 |

***

## Dependency Graph

```
MSAL OAuth ──────────────────────────────────────────────────────┐
                                                                  │
SFSpeechRecognizer (✅) → [Voice Morning Session (✅)] ──────────┐│
EventKit permissions → [Calendar Allocator (✅)] ────────────────┤│
Thompson Sampling (✅) ──────────────────────────────────────────┤│
EMA Model (✅) ──────────────────────────────────────────────────┤│
                                                                  ││
                        Email Triage (✅) ─────────────────────────┤│
                                                                  ││
                                                                  ▼▼
Supabase Setup ─→ pgvector Schema ─→ Jina Embedding Pipeline ──→ Semantic Memory
                                                                       │
CoreData Schema ─────────────────────────────────────────────────────→┤
                                                                       │
AX Observer ──────────────────────────────────────────────────────────┤
                                                                       │
                                                                       ▼
                                              Reflection Engine (scoring, synthesis, routing)
                                                                       │
                         ┌─────────────────────────────────────────────┘
                         ▼
Model Router (Haiku/Sonnet/Opus) ─→ Intelligence Delivery
                         │                    │
                         │          ┌─────────┴─────────────┐
                         │          ▼                       ▼
                         │   Menu Bar / Command     UNNotification
                         │   Palette (✅)            + Dashboard
                         │
                         └──────────────────→ Chat (RAG + streaming)
```

***

## Critical Path

The critical path is the longest chain of dependencies. Blocking items must be resolved before most other work can proceed.

```
Phase 1 (Foundation)
├── [P1-A] Entitlements + non-sandbox config         (S) — unblocks AX, Mail
├── [P1-B] Supabase project + pgvector schema        (S) — unblocks all memory work
├── [P1-C] MSAL OAuth (silent refresh)               (M) — unblocks email threading
├── [P1-D] CoreData schema                            (M) — unblocks sync, context
├── [P1-E] Model router (Haiku/Sonnet/Opus)          (M) — unblocks all AI tiers
└── [P1-F] UNUserNotificationCenter integration      (S) — unblocks delivery

Phase 2 (Signal + Memory)
├── [P2-A] Jina embedding pipeline → pgvector        (M) — requires P1-B
├── [P2-B] AXObserver app context agent              (M) — requires P1-A
├── [P2-C] Variance-adaptive Thompson upgrade        (M) — requires (✅ Thompson)
├── [P2-D] NLTagger sentiment + NER                  (S) — independent
├── [P2-E] CoreData ↔ Supabase sync                  (L) — requires P1-B, P1-D
└── [P2-F] Mid-day + evening reflection stages       (M) — requires P1-E, P2-A

Phase 3 (Intelligence)
├── [P3-A] RAG chat (memory-augmented)               (L) — requires P2-A, P2-E
├── [P3-B] Knowledge graph (entity extract → edges)  (L) — requires P2-D, P2-A
├── [P3-C] Trend surfacing (30/60/90-day)            (L) — requires P2-F, P3-B
├── [P3-D] Meeting energy + decision fatigue models  (XL) — requires P2-B, P2-C
└── [P3-E] Speaker diarization                       (XL) — requires external model

Critical bottleneck: P1-A (entitlements/sandbox) and P1-B (Supabase setup)
are both zero-dependency and unlock the most parallel work.
Start both on Day 1.
```

***

## Build Phase Summary

| Phase | Focus | Key Deliverable | Estimated Duration |
|-------|-------|----------------|--------------------|
| P1 — Foundation | Auth, data infra, model router, entitlements | Working end-to-end skeleton: ingest → store → deliver one insight | 2–3 weeks |
| P2 — Signal + Memory | All signal agents, embedding pipeline, reflection stages | Full passive observation + daily briefings | 6–10 weeks |
| P3 — Intelligence | RAG chat, knowledge graph, trend models, diarization | Full intelligence layer, predictive insights | 10–16 weeks |

***

## Recommended Approach Upgrades

### 1. SpeechAnalyzer over SFSpeechRecognizer
Apple's `SpeechAnalyzer` API (WWDC 2025, macOS 26 / iOS 26) is strictly superior to `SFSpeechRecognizer`: fully on-device, zero latency, no model downloads required, and already powering system apps including Notes and Call Summarization. Since Timed targets executives with sensitive conversations, on-device transcription is architecturally preferable. Migrate when macOS 26 SDK is adopted.[^2][^3][^1]

### 2. Variance-Adaptive Thompson Sampling
The shipped Thompson scorer uses a standard Beta conjugate prior. Apple Research published a variance-adaptive extension for Gaussian bandits with heterogeneous reward variances that achieves lower regret by paying only for uncertainty. For Timed's use case — email/task scoring across executives with very different communication patterns — this upgrade delivers more accurate prioritisation as the model cold-starts per user.[^15]

### 3. Jina Embeddings v4 (not v2/v3)
Jina Embeddings v4 is a 3.8B-parameter multimodal model supporting text and image in a unified vector space with both single-vector and multi-vector outputs. Use `retrieval.passage` task type for ingested signals and `retrieval.query` for reflection-time retrieval. The free tier (10M tokens) covers a meaningful development runway.[^12][^11]

### 4. Hybrid Search in pgvector
Beyond pure cosine similarity, Supabase's pgvector supports hybrid queries combining vector similarity with relational filters (date range, person ID, signal source). This is essential for the reflection engine's temporal reasoning: "Show me semantically similar decisions the exec made in Q3" requires both vector similarity and a date-range filter.[^13]

### 5. Non-Sandbox Distribution
Distributing outside the Mac App Store via direct download + Notarization is the correct choice for Timed. The App Store sandbox since 2022 progressively restricts Mail access, security-scoped bookmarks, and inter-app communication in ways that would cripple the Signal Ingestion layer. Notarization still provides Gatekeeper verification, acceptable for an enterprise executive tool sold direct to organisations.[^5][^6][^4]

### 6. Haiku-First AI Routing
Given Haiku's 5x cost advantage over Sonnet and 19x advantage over Opus, route all classification, extraction, and short pulse tasks to Haiku 4.5. Escalate to Sonnet for synthesis and analysis, and reserve Opus for complex multi-factor reasoning (less than 10% of tasks). This single architectural decision can cut LLM API costs by 60–70% at scale.[^19][^20][^28][^18]

---

## References

1. [Bring advanced speech-to-text to your app with SpeechAnalyzer](https://www.youtube.com/watch?v=0m6dimDDj8M) - Discover the new SpeechAnalyzer API for speech to text. We'll learn about the Swift API and its capa...

2. [Bring advanced speech-to-text to your app with SpeechAnalyzer](https://developer.apple.com/videos/play/wwdc2025/277/) - Discover the new SpeechAnalyzer API for speech to text. We'll learn about the Swift API and its capa...

3. [Tahoe ships with Apple's SpeechAnalyzer - I've built a free voice ...](https://www.reddit.com/r/MacOSBeta/comments/1rty0ko/tahoe_ships_with_apples_speechanalyzer_ive_built/) - Tahoe ships with Apple's SpeechAnalyzer - I've built a free voice dictation app that leverages it (p...

4. [macOS App Sandbox Changes: Email User Guide 2026 - Mailbird](https://www.getmailbird.com/macos-app-sandbox-email-changes/) - The sandbox restricts network operations and background processing in ways that make it difficult to...

5. [What are app entitlements, and what do they do?](https://eclecticlight.co/2025/03/24/what-are-app-entitlements-and-what-do-they-do/) - Entitlements are settings baked into an app's signature that enable it to do things that otherwise w...

6. [Analyzing CVE-2025-31191: A macOS security-scoped bookmarks ...](https://www.microsoft.com/en-us/security/blog/2025/05/01/analyzing-cve-2025-31191-a-macos-security-scoped-bookmarks-based-sandbox-escape/) - In April 2024, Microsoft uncovered a vulnerability in macOS that could allow specially crafted codes...

7. [Getting access to the user's calendar - Create with Swift](https://www.createwithswift.com/getting-access-to-the-users-calendar/) - The first step is to configure the message that will be shown when requesting access, which is done ...

8. [What's new in ScreenCaptureKit - WWDC23 - Videos](https://developer.apple.com/videos/play/wwdc2023/10136/) - Level up your screen sharing experience with the latest features in ScreenCaptureKit. Explore the bu...

9. [DevilFinger/DFAXUIElement: A fastway to use Accessibility ... - GitHub](https://github.com/DevilFinger/DFAXUIElement) - This is a Swift version to let you use Accessibility API with AXUIElement、AXObserver. It's a fastway...

10. [How I used macOS Accessibility API to fix my VSCode workflow](https://dev.to/augiefra/how-i-used-macos-accessibility-api-to-fix-my-vscode-workflow-23a9) - Using Swift and the ApplicationServices framework, I built a small "parser" that: Detects the active...

11. [Integrating with Jina AI - Qdrant](https://qdrant.tech/course/essentials/day-7/jina/) - The Jina Embeddings v4 model represents a breakthrough in multimodal embedding technology, enabling ...

12. [jina-embeddings-v4 - Search Foundation Models](https://jina.ai/models/jina-embeddings-v4/) - Jina Embeddings V4 is a 3.8 billion parameter multimodal embedding model that provides unified text ...

13. [Querying Vectors | Supabase Docs](https://supabase.com/docs/guides/storage/vector/querying-vectors) - You can query vectors using the JavaScript SDK or directly from Postgres using SQL. Comparison to pg...

14. [Semantic search using Supabase Vector - OpenAI Developers](https://developers.openai.com/cookbook/examples/vector_databases/supabase/semantic-search/) - Since Supabase Vector is built on pgvector, you can store your embeddings within the same database t...

15. [Only Pay for What Is Uncertain: Variance-Adaptive Thompson ...](https://machinelearning.apple.com/research/variance-adaptive-thompson-sampling) - We study Gaussian bandits with \emph{unknown heterogeneous reward variances} and develop a Thompson ...

16. [Applying sentiment analysis using the Natural Language framework](https://www.createwithswift.com/applying-sentiment-analysis-using-natural-language-framework/) - In this short tutorial, we delve into the usage of Apple's Natural Language framework, powered by Co...

17. [Advances in Natural Language Framework - WWDC19 - Videos](https://developer.apple.com/la/videos/play/wwdc2019/232/) - ... natural language processing tasks across all Apple platforms. Learn about the addition of Sentim...

18. [OpenClaw routing guide (Opus vs Sonnet vs Haiku) : r/ClaudeAI](https://www.reddit.com/r/ClaudeAI/comments/1riyfrj/stop_burning_money_on_the_wrong_claude_model/) - Haiku 4.5 - everything automated ; Sonnet 4.6 - 80% of real work ; Opus 4.6 - 10-20% premium only ; ...

19. [Claude Opus 4.5 API Pricing: $5/$25 per Million Tokens](https://www.cloudcostchefs.com/blog/claude-opus-4-5-pricing-analysis) - Claude Opus 4.5 costs $5/$25 per million tokens—5-10x more than Sonnet ... Get comprehensive guides ...

20. [The Frugal Approach to Anthropic Claude API Costs](https://frugal.co/blog/the-frugal-approach-to-anthropic-claude-api-costs) - These tokens are billed at output token rates: $15 per 1M for Sonnet, $40 per 1M for Opus. Extended ...

21. [Models overview - Claude API Docs](https://platform.claude.com/docs/en/about-claude/models/overview) - Claude is a family of state-of-the-art large language models developed by Anthropic. This guide intr...

22. [Using AI to Combat Cognitive Overload & Enhance Executive Function](https://www.agavehealth.com/post/using-ai-to-combat-cognitive-overload-enhance-executive-function) - Personalized Work Environments: AI can adjust settings (like notifications and screen time limits) t...

23. [When AI Assistance Becomes Cognitive Overload: Understanding ...](https://www.innovativehumancapital.com/article/when-ai-assistance-becomes-cognitive-overload-understanding-and-managing-brain-fry-in-the-modern) - Second, cognitive fatigue translates into organizational performance costs through compromised decis...

24. [UNUserNotificationCenter | Apple Developer Documentation](https://developer.apple.com/documentation/usernotifications/unusernotificationcenter) - Use the shared UNUserNotificationCenter object to manage all notification-related behaviors in your ...

25. [receive local notifications within own app / view (or how to register a ...](https://stackoverflow.com/questions/65782435/receive-local-notifications-within-own-app-view-or-how-to-register-a-unuserno) - If a notification arrives while your app is in the foreground, you can silence that notification or ...

26. [MSAL on CocoaPods.org](https://cocoapods.org/pods/MSAL) - The MSAL library for iOS and macOS gives your app the ability to begin using the Microsoft Identity ...

27. [Microsoft Authentication Library for iOS and macOS](https://learn.microsoft.com/en-us/entra/msal/objc/) - The Microsoft Authentication Library (MSAL) for iOS and macOS is an auth SDK that can be used to sea...

28. [Claude Model Selection Guide | Sonnet vs Opus vs Haiku - SitePoint](https://www.sitepoint.com/claude-model-selection-framework/) - Anthropic prices Opus at $15.00 per million input tokens and $75.00 per million output tokens, makin...

