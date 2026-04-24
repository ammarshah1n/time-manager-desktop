# Timed — MASTER-PLAN.md

## STATUS

Last updated: 2026-04-11

### Pre-Build: Development Infrastructure
- [x] PRE-01 — Session Handoff Protocol
- [x] PRE-02 — CLAUDE.md Restructuring (<200 lines each)
- [ ] PRE-03 — Obsidian Vault Cross-Linking ⏸️ BLOCKED: requires manual Obsidian plugin install

### Phase 0: Auth & Data Bridge
- [x] 0.01 — Configure Microsoft OAuth provider in Supabase Auth dashboard
- [x] 0.02 — Refactor AuthService to use Supabase Auth
- [x] 0.03 — Create `executives` table + bootstrap Edge Function
- [x] 0.04 — Create DataBridge actor
- [x] 0.05 — Wire TimedRootView data loading through DataBridge
- [x] 0.06 — Add GRDB.swift for local SQLite buffering
- [ ] 0.07 — Verify end-to-end auth → data flow ⏸️ BLOCKED: requires manual E2E test with real Microsoft credentials + DataBridge Supabase write path (wired incrementally as schemas align)
- [x] 0.08 — Build pipeline health dashboard

### Phase 1: Observation Pipeline (Tier 1 Signals)
- [x] 1.01 — Deploy tier0_observations table
- [x] 1.02 — Deploy observation source tables
- [x] 1.03 — Define SignalIngestionPort protocol + Tier0Observation DTO
- [x] 1.04 — Create Tier0Writer actor
- [x] 1.05 — Wire EmailSyncService → Tier 0 observations
- [x] 1.06 — Wire CalendarSyncService → Tier 0 observations
- [x] 1.07 — Create AppUsageAgent
- [x] 1.08 — Create IdleTimeAgent
- [x] 1.09 — Create FirstLastActivityAgent
- [x] 1.10 — Create AgentCoordinator actor
- [x] 1.11 — Create HealthKitAgent (stub — research gap #12 unresolved)
- [x] 1.12 — Create OuraRingAgent (stub — optional, Oura API research pending)
- [ ] 1.13 — Verify observation pipeline end-to-end ⏸️ BLOCKED: requires manual E2E test with live signals

### Phase 2: Memory Infrastructure
- [x] 2.01 — Deploy tier1_daily_summaries table
- [x] 2.02 — Deploy tier2_behavioural_signatures table
- [x] 2.03 — Deploy tier3_personality_traits table
- [x] 2.04 — Deploy active_context_buffer table (dual ACB)
- [x] 2.05 — Deploy predictions + tracking tables
- [x] 2.06 — Create generate-embedding Edge Function (dual-provider)
- [x] 2.07 — Create EmbeddingService actor (client-side)
- [x] 2.08 — Integrate USearch for local vector search
- [x] 2.09 — Create MemoryStore protocol + implementation
- [x] 2.10 — Implement 5-dimension retrieval engine
- [ ] 2.11 — Verify memory infrastructure ⏸️ BLOCKED: requires live data + embedding calls
- [x] 2.12 — Define TFT-compatible time-series schema (views layer)

### Phase 3: Nightly Pipeline (Intelligence Core)
- [x] 3.01 — Create 4-cron pipeline architecture
- [x] 3.02 — Deploy baselines table + computation
- [x] 3.03 — Implement Phase 1: Importance Scoring (Two-Pass)
- [x] 3.04 — Implement Phase 2: Conflict Detection
- [x] 3.05 — Implement Phase 3: Daily Summary Generation
- [x] 3.06 — Implement Pruning (weekly, decoupled)
- [x] 3.07 — Implement ACB generation (dual document)
- [x] 3.08 — Implement self-improving consolidation loop
- [ ] 3.09 — Verify nightly pipeline end-to-end ⏸️ BLOCKED: requires ANTHROPIC_API_KEY in Supabase secrets + live data

### Phase 3.5: KeystrokeXPC
- [x] 3.5.01 — Build KeystrokeXPC service (in-process agent, XPC deferred to Phase 12)
- [x] 3.5.02 — Build CognitiveLoadIndex (CCLI)
- [x] 3.5.03 — Build ChronotypeModel
- [x] 3.5.04 — Wire keystroke signals to Tier 0
- [x] 3.5.05 — Activation gate (AXIsProcessTrusted gating in AgentCoordinator)

### Phase 4: Intelligence Delivery (Morning Briefing)
- [x] 4.01 — Create generate-morning-briefing Edge Function
- [x] 4.02 — Deploy briefings table
- [x] 4.03 — Define MorningBriefing Swift data model
- [x] 4.04 — Build MorningBriefingPane (SwiftUI)
- [x] 4.05 — Wire morning briefing to app launch (pane built, full routing in UI integration)
- [x] 4.06 — Build briefing generation system prompt (embedded in Edge Function)
- [x] 4.07 — Implement briefing engagement tracking (in MorningBriefingPane)
- [ ] 4.08 — Update MenuBarManager with intelligence headline ⏸️ deferred to UI integration
- [ ] 4.09 — Verify morning briefing flow ⏸️ BLOCKED: requires live briefing data

### Phase 5: Cold Start & Onboarding
- [ ] 5.01 — Redesign OnboardingFlow for SOKA model ⏸️ deferred to UI integration pass
- [x] 5.02 — Implement historical data backfill (HistoricalBackfillService actor, Graph API wiring in Phase 0.07)
- [ ] 5.03 — Build default intelligence library ⏸️ deferred — requires live calendar/email data for base-rate insights
- [x] 5.04 — Implement 48-hour thin-slice inference (Edge Function deployed)
- [x] 5.05 — Implement engagement monitoring during learning period (EngagementMonitor actor)
- [x] 5.06 — Implement endowed progress effect (EngagementMonitor.progressDimensions)
- [x] 5.07 — Implement communication style mirroring (EngagementMonitor.inferCommunicationStyle)

### Phase 6: ONA & Relationship Intelligence
- [x] 6.01 — Deploy ONA tables (ona_nodes, ona_edges, relationships + RLS)
- [x] 6.02 — Build ONA graph builder service (ONAGraphBuilder actor)
- [x] 6.03 — Implement centrality metrics computation (compute_degree_centrality RPC)
- [x] 6.04 — Implement relationship health scoring (compute_relationship_health RPC + RelationshipHealthService actor)
- [x] 6.05 — Implement disengagement detection (DisengagementDetector actor, RDI 5-dimension composite)
- [x] 6.06 — Wire relationship intelligence to morning briefing (at_risk_relationships + top_contacts in context assembly)

### Phase 7: Pattern Detection & Trait Synthesis
- [x] 7.01 — Implement Phase 4: Weekly Pattern Detection (Edge Function deployed)
- [x] 7.02 — Implement 4-gate validation protocol (validation_gates migration + check_validation_gates RPC)
- [x] 7.03 — Implement Phase 5: Monthly Trait Synthesis (Edge Function deployed, Stage A + B)
- [x] 7.04 — Implement BOCPD change detection (BOCPDDetector struct, student-t, CDI)
- [x] 7.05 — Implement CCR evaluation (ccr_evaluations table + compute_weekly_ccr RPC)

### Phase 8: Real-Time Alert System
- [x] 8.01 — Create AlertEngine actor (5-dimension multiplicative scoring)
- [x] 8.02 — Implement frequency management (3/day cap, 60-min gap, adaptive threshold)
- [x] 8.03 — Implement interrupt window detection (InterruptWindowDetector)
- [x] 8.04 — Build alert delivery UI (AlertDeliveryView + AlertViewModel)
- [x] 8.05 — Implement coaching trust calibration (CoachingTrustCalibrator, 4-stage, rupture protocol)
- [x] 8.06 — Implement multi-agent council (Edge Function, 3 parallel Opus + leader synthesis)

### Phase 9: Prediction Layer
- [x] 9.01 — Implement avoidance detection (AvoidanceDetector actor, 3-stream cross-validation, network expansion guard)
- [x] 9.02 — Implement burnout prediction (BurnoutPredictor actor, 3 MBI dimensions, triple gate, sprint discriminator)
- [x] 9.03 — Implement decision reversal tracking (DecisionReversalTracker actor, 4-state HMM)
- [x] 9.04 — Wire predictions to delivery (PredictionGate, engagement-gated 5-tier system)

### Phase 10: Voice Signal Expansion
- [x] 10.01 — Build VoiceFeatureExtractor via Gemini Audio API (Edge Function deployed)
- [ ] 10.02 — Migrate voice to Whisper.cpp ⏸️ deferred — requires whisper.cpp SPM research (gap #2)
- [x] 10.03 — Wire voice signals to Tier 0 observations (VoiceFeatureService actor)

### Phase 11: Privacy & Trust Architecture
- [x] 11.01 — Implement consent state machine (ConsentStateMachine, 7 states, transition gates)
- [ ] 11.02 — Implement progressive permission UI ⏸️ deferred to UI integration pass
- [x] 11.03 — Implement client-side encryption (PrivacyManager, KEK/DEK in Keychain, AES-256)
- [ ] 11.04 — Privacy nutrition labels in settings ⏸️ deferred to UI integration pass
- [x] 11.05 — Implement data export + cryptographic deletion (PrivacyManager.exportAllData + destroyKEK)
- [ ] 11.06 — EU AI Act compliance ⏸️ deferred — documentation/audit task, not code

### Phase 12: Production Hardening
- [x] 12.01 — Build XPC service mesh (XPCServiceManager, SMAppService registration, health monitoring)
- [x] 12.02 — App Nap prevention + low battery mode (PowerProfile, beginActivity, battery-aware sampling)
- [ ] 12.03 — Sparkle auto-updates ⏸️ deferred — requires Sparkle SPM + CDN setup
- [ ] 12.04 — Developer ID signing + notarisation ⏸️ deferred — requires Apple Developer cert
- [x] 12.05 — Graceful degradation (GracefulDegradation actor, NWPathMonitor, service health checks)
- [ ] 12.06 — Battery/CPU validation ⏸️ deferred — requires Instruments profiling on real workload

### Phase 13: Advanced Intelligence (Month 11+)
- [ ] 13.01 — WavLM/HuBERT neural voice embeddings ⏸️ requires 12+ weeks voice data + Core ML research
- [ ] 13.02 — Personal vocal biomarker library ⏸️ requires 13.01
- [ ] 13.03 — Multi-modal fusion (CCLI, BEWI, RDS, DQEI) ⏸️ requires 13.01 + 3+ modalities active
- [ ] 13.04 — Temporal Fusion Transformer ⏸️ requires 12+ months data accumulation

### Research Gaps
- [ ] RG-02 — whisper.cpp Swift package + Core ML integration
- [x] RG-03 — USearch Swift bindings production readiness (resolved: USearch 2.24.0 SPM works)
- [x] RG-04 — OpenAI text-embedding-3-large integration patterns (resolved: dual-provider Edge Function)
- [ ] RG-05 — WavLM Core ML INT8 quantisation
- [x] RG-06 — BOCPD Swift implementation (resolved: BOCPDDetector struct, student-t, CDI)
- [x] RG-07 — Secure Enclave KEK management on macOS (resolved: Keychain-based, PrivacyManager)
- [x] RG-08 — SMAppService + XPC LaunchAgent patterns (resolved: XPCServiceManager)
- [x] RG-09 — Gemini 1.5 Pro Audio API capabilities (resolved: extract-voice-features Edge Function)
- [ ] RG-10 — Microsoft Graph delta token persistence + crash recovery
- [ ] RG-11 — Supabase Edge Function timeout handling
- [ ] RG-12 — Apple HealthKit macOS access patterns
- [ ] RG-13 — Oura Ring v2 API OAuth2 integration
- [x] RG-14 — Anthropic Batch API for Supabase Edge Functions (resolved: _shared/anthropic.ts submitBatch)
- [x] RG-15 — Multi-agent council orchestration patterns (resolved: multi-agent-council Edge Function)

**Total: 120 deliverables | ~95 complete | ~25 remaining (mostly verification, UI integration, and Month 11+ deferred)**

---

# Timed — Complete Build Pathway (Current State → Production)

## Core Product Understanding

Timed is NOT a productivity app. It does NOT compete with Motion, Sunsama, or any task manager.

Timed is a **cognitive intelligence system** for one C-suite executive (Yasser Shahin). It passively observes how he works — email patterns, calendar structure, communication rhythms, decision timing — and builds a **compounding model** of how he thinks, decides, avoids, and operates.

**The key insight**: intelligence compounds *structurally*, not volumetrically. Month 6 Timed is qualitatively different from Month 1 because higher-tier memory representations (behavioural signatures, personality traits) are structurally impossible without lower tiers having been built and validated first. No competitor can replicate 6 months of accumulated intelligence by shipping features. This is the moat.

**4 layers:**
1. **Signal Ingestion** — passively captures 30+ signals (email, calendar, app usage, keystrokes, voice)
2. **Memory Store** — 5-tier hierarchy: Raw Observation → Daily Summary → Behavioural Signature → Personality Trait → Active Context Buffer
3. **Reflection Engine** — 4-cron intelligence pipeline (Opus at every memory-generating layer) consolidates observations into compounding intelligence
4. **Intelligence Delivery** — morning briefing (CIA PDB format, ~610 words), real-time alerts (3/day hard cap), coaching layer with trust calibration

**Hard constraints:**
- Observation only. NEVER acts on the world. Non-negotiable.
- No cost cap. Opus 4.6 at max effort for the core intelligence engine.
- Morning session = intelligence briefing, not a task list.
- Month 6 >> Month 1. Every architectural decision supports compounding.

---

## What Exists Today

**Working:**
- Complete UI shell (16 screens/panes, all functional)
- GraphClient with MSAL OAuth + delta email sync (489 lines)
- EmailSyncService actor + CalendarSyncService actor + VoiceCaptureService
- PlanningEngine (Thompson sampling, mood filtering, behaviour rules)
- TimeSlotAllocator (calendar-aware, energy tiers)
- SupabaseClient (20+ operations defined, 764 lines)
- AuthService (Microsoft OAuth flow, 310 lines)
- 29 Edge Functions deployed + 48 SQL migrations
- 49 tests passing, `swift build` clean

**THE GAP (what makes this plan necessary):**
- UI still uses local JSON DataStore — SupabaseClient is wired but not called from UI
- No 5-tier memory system (Tier 0-3 + ACB)
- No nightly consolidation pipeline
- No intelligence delivery (morning briefing is an interview, not a briefing)
- No ONA / relationship graph
- No signal expansion beyond email/calendar
- No prediction layer (avoidance, burnout, reversal)
- No privacy/trust architecture (encryption, consent machine)
- No cold start pipeline (thin-slice, default library)
- No XPC background services

---

## Architecture Conflicts Resolved

| Conflict | Resolution |
|----------|-----------|
| specs/CLAUDE.md says CoreData; BUILD_STATE.md says JSON+Supabase | **Supabase is source of truth. SQLite (GRDB.swift) for local buffering. No CoreData. No SwiftData.** |
| Embedding provider: Jina v3 vs Voyage vs OpenAI | **Dual-provider strategy per NO-COST-CAP-AUDIT.md:** Tier 0 → voyage-context-3 (1024-dim). Tier 1-3 → text-embedding-3-large (OpenAI, 3072-dim). Higher discriminative space where it matters most. |
| Current voice uses SFSpeechRecognizer; architecture says Whisper.cpp | **Keep SFSpeechRecognizer for morning interview. Whisper.cpp for background transcription. Gemini 1.5 Pro Audio API for acoustic feature extraction (replaces openSMILE C++ bridge).** |
| specs/IMPLEMENTATION_PLAN.md references CoreData entities | **Superseded by this plan.** |
| ACB token budget: 2K vs full context | **Two ACB documents per NO-COST-CAP-AUDIT.md:** ACB-FULL (10-12K tokens for Opus intelligence calls) + ACB-LIGHT (500-800 tokens for Haiku/Sonnet utility calls). |
| Model routing: Haiku at foundation | **Opus at every layer that generates durable memory.** Haiku only for importance scoring and utility. Cost ~$63/week against $800/week budget. See model routing table below. |
| Pipeline frequency: single nightly run | **4 cron jobs:** full nightly (2 AM), lightweight refresh (5:15 AM), morning briefing (5:30 AM), weekly pruning (Sunday 3 AM). |
| Backfill depth: 90 days | **Up to 3 years** (or Outlook retention limit). 4-gate validation can run on Day 1 against historical data. |
| Prediction surfacing: calendar-gated | **Engagement-gated.** Behavioural hypotheses surface at Day 15 if engagement thresholds met, not Month 4. |
| Signal expansion sequencing | **KeystrokeXPC promoted to Phase 3.5.** Build in parallel with nightly pipeline, activate at Week 4 trust gate. |

## Model Routing Table (Uncapped — Adaptive Thinking + Batch API)

**Architecture note:** All Opus calls use `thinking: {type: "adaptive"}` with effort levels as specified. **Critical constraint:** keep thinking effort consistent within a session type — switching effort levels between calls invalidates prompt cache breakpoints, wiping the 90% input cost saving. Nightly async pipeline runs via **Batch API (50% discount)** on all tokens.

| Call Site | Model | Thinking Effort | Temperature | Batch API | Rationale |
|-----------|-------|----------------|-------------|-----------|-----------|
| Importance scoring Pass 1 (3.03) | Haiku 3.5 | None | 0.0 | Yes (nightly) | Simple 1-10 classification |
| Importance scoring Pass 2 (3.03) | **Sonnet 3.7** | `effort: "medium"` | 0.0 | Yes (nightly) | Uncertain band 0.55–0.75 |
| Overnight importance audit (5:15 AM) | **Sonnet 3.7** | `effort: "medium"` | 0.0 | No (time-critical) | Conditional — overnight uncertain band |
| Conflict detection (3.04) | **Sonnet 3.7** | `effort: "high"` | 0.0 | Yes (nightly) | Cross-temporal contradiction detection |
| Daily summary (3.05) | **Opus 4.6** | `effort: "high"` | 0.0 | Yes (nightly) | **HIGHEST PRIORITY** — Tier 1 feeds all downstream |
| ACB generation (3.07) | **Opus 4.6** | `effort: "medium"` | 0.0 | Yes (nightly) | ACB injected into every intelligence call |
| Morning briefing Pass 1 (4.01) | **Opus 4.6** | `effort: "medium"` | — | No (time-critical) | Highest-stakes user-facing output |
| Morning briefing Pass 2 (4.01) | **Opus 4.6** | `effort: "medium"` | 0.0 | No (time-critical) | Adversarial review — challenges overconfidence |
| Thin-slice inference (5.04) | **Opus 4.6** | `effort: "high"` | — | No (onboarding) | First impression of system intelligence |
| ONA entity resolution (6.02) | **Sonnet 3.7** | None | — | Yes (batch) | Dedup errors corrupt relationship graph |
| ONA role inference (6.02) | **Sonnet 3.7** | None | — | Yes (batch) | Authority-tier labels for top-30 contacts |
| ONA tone trajectory (6.02) | **Sonnet 3.7** | None | 0.0 | Yes (weekly) | Qualitative tone trend for top-20 contacts |
| Weekly pattern detection (7.01) | **Opus 4.6** | `effort: "high"` | 0.3 | Yes (weekly) | Cross-domain patterns require deep reasoning |
| Gate 4 plausibility review (7.02) | **Opus 4.6** | `effort: "high"` | 0.0 | Yes (weekly) | False-positive signatures contaminate traits |
| Monthly trait synthesis (7.03A) | Opus 4.6 | `effort: "high"` | 1.0 | Yes (monthly) | Highest-complexity synthesis |
| Prediction generation (7.03B) | Opus 4.6 | `effort: "high"` | 1.0 | Yes (monthly) | Falsifiable behavioural predictions |
| Alert salience + actionability (8.01) | **Opus 4.6** | `effort: "low"` | 0.0 | No (real-time) | Context-aware with ACB-FULL, needs speed |
| Real-time session response | **Opus 4.6** | `effort: "low"` | — | No (real-time) | Interactive latency requirement |
| Multi-agent council (high-stakes) | **Opus 4.6** × 3 | `effort: "high"` | 0.3 | No (on-demand) | Energy/Priority/Pattern specialist agents |
| Self-improvement loop (nightly) | **Opus 4.6** | `effort: "high"` | — | Yes (nightly, 50% off) | Inventory→Extract→Propose→Validate→Commit |

**Weekly cost at maximum intelligence: ~$120-180/week** ($800 budget leaves $620-680 headroom)

**Cost recovery via prompt caching:**

| Cache Segment | Content | Tokens | Hit Rate | Saving |
|---------------|---------|--------|----------|--------|
| System prompt + executive profile | Static per session | ~8K | ~95% | ~$4/week |
| ACB-FULL document | Updated nightly | ~12K | ~80% | ~$8/week |
| Tier 2/3 library context | Updated weekly | ~15K | ~85% | ~$6/week |
| Session history context | Per conversation | ~6K | ~60% | ~$3/week |
| **Effective cost after caching** | | | | **~$100-150/week** |

---

## Pre-Build: Development Infrastructure (Do Before Phase 0)

These are not app features — they are development workflow fixes that prevent silent compounding failure during the build.

### PRE-01 — Session Handoff Protocol (encoded as Claude Skill)
- **Problem:** Every tool in the stack is stateless between sessions. Without formalised handoff, Opus boots cold and re-derives context every session. "A session that ends without a handoff did not end. It crashed."
- Create Claude Skill at `.claude/skills/session-handoff/SKILL.md`:
  - **On session close** (triggered manually or via `/wrap-up`): write `HANDOFF.md` to vault root:
    ```
    - Done: [what completed this session]
    - Open decisions: [framed as QUESTIONS not tasks — AI agents bias toward action, questions create a gate]
    - Deferred: [what was parked and why]
    - Next: [single most important next action]
    ```
  - **On session start** (SessionStart hook or manual): read order is `VAULT-INDEX.md` → `HANDOFF.md` → `Working-Context/<project>-state.md`. This is not optional — encode in the skill, not left to inference.
- Update `CLAUDE.md` Session Protocol to reference this skill
- **Depends on:** nothing — do this FIRST

### PRE-02 — CLAUDE.md Restructuring (under 200 lines each)
- **Problem:** Community-validated rule: Claude starts selectively ignoring instructions in CLAUDE.md files over 200 lines, even critical ones. The project `CLAUDE.md` is ~400 lines.
- **Current state:** `~/CLAUDE.md` = ~182 lines (OK). `~/time-manager-desktop/CLAUDE.md` = ~402 lines (OVER LIMIT).
- **Fix:** Split `time-manager-desktop/CLAUDE.md` into:
  - `CLAUDE.md` — core identity, tech stack, 3 most critical rules. Under 200 lines.
  - `.claude/rules/coding-standards.md` — concurrency, repository pattern, error handling, DTOs, SwiftUI rules
  - `.claude/rules/testing-rules.md` — test framework, mock patterns, test locations
  - `.claude/rules/session-protocol.md` — session start/end procedures, key files
  - `.claude/rules/ai-assistant-rules.md` — MUST/MUST NOT/NEVER lists
  - `.claude/rules/naming-conventions.md` — file naming, Swift naming
- Wrap domain-critical rules in `<important>` tags to force attention under context pressure
- **Depends on:** nothing — do this FIRST

### PRE-03 — Obsidian Vault Cross-Linking (Auto Keyword Linker)
- **Problem:** 7 wikilinks across 144 notes in Timed-Brain. The vault is a flat filing cabinet — no cross-references means no graph intelligence.
- Install **Auto Keyword Linker** plugin (released Jan 2026): converts terms into wikilinks across entire vault automatically with AI-powered suggestions
- Install **Conditional Properties** plugin: IF/THEN rules for frontmatter automation
- Run Auto Keyword Linker in **preview mode first** — shows every cross-reference the vault never formalised
- Then bulk-apply across all vaults: Timed-Brain, PFF-Brain, AIF-Decisions, Brain-Meta-Vault
- **Depends on:** nothing — do this FIRST

---

## Phase 0: Auth & Data Bridge

Everything mounts on this. The app can't talk to Supabase without auth. No signal flows without a wired data pipeline.

### 0.01 — Configure Microsoft OAuth provider in Supabase Auth dashboard
- Azure Portal: create new client secret scoped for Supabase (existing one is for MSAL direct)
- Supabase Auth dashboard → Providers → Microsoft: paste client ID + secret + tenant ID
- Configure Supabase redirect callback URL in Azure app registration
- Verify: Supabase dashboard shows Microsoft provider enabled
- **Depends on:** nothing

### 0.02 — Refactor AuthService to use Supabase Auth
- Current problem: AuthService creates its own SupabaseClient (violates DI)
- Inject shared SupabaseClient via @Dependency
- Auth flow: MSAL interactive login → get Microsoft access token → exchange with Supabase Auth via `signInWithIdToken` → get Supabase JWT session
- Store Supabase session token in Keychain (not UserDefaults)
- Handle dual token refresh: Supabase JWT + MSAL refresh token for Graph API
- **Depends on:** 0.01

### 0.03 — Create `executives` table + bootstrap Edge Function
- Migration: `CREATE TABLE executives (id UUID PK, auth_user_id UUID REFERENCES auth.users, display_name, email, timezone DEFAULT 'UTC', onboarded_at, created_at)`
- RLS: `auth.uid() = auth_user_id`
- Edge Function `bootstrap-executive`: on first sign-in, creates executives row from Microsoft profile, returns executive_id
- Idempotent: skip if row exists for auth_user_id
- **Depends on:** 0.01

### 0.04 — Create DataBridge actor
- Single interface for all data reads/writes
- Routes to SupabaseClient when authenticated + online
- Falls back to DataStore (local JSON) when offline
- Write path: always write to local first (instant), then sync to Supabase
- Read path: Supabase when available, local cache when not
- **Depends on:** 0.02, 0.03

### 0.05 — Wire TimedRootView data loading through DataBridge
- Currently: all @State arrays loaded from `DataStore.loadTasks()`, `DataStore.loadTriageItems()`, etc.
- Replace all DataStore calls with DataBridge calls
- Existing UI panes (TasksPane, TriagePane, etc.) unchanged — only the data source shifts
- **Depends on:** 0.04

### 0.06 — Add GRDB.swift for local SQLite buffering
- SPM dependency: GRDB.swift
- Create `pending_operations` table: (id, operation_type, payload_json, created_at, synced_at)
- When offline: queue Supabase writes to SQLite
- On network restore (via NetworkMonitor): flush queue chronologically
- Exponential backoff: 1s, 2s, 4s, 8s, max 5min
- 7-day buffer capacity (~50MB typical)
- **Depends on:** 0.04

### 0.07 — Verify end-to-end auth → data flow
- Launch app → sign in with Microsoft → Supabase session → executive record created → create a task in UI → verify it appears in Supabase dashboard → toggle airplane mode → create another task → reconnect → verify sync
- **Depends on:** 0.05, 0.06

### 0.08 — Build pipeline health dashboard (developer-facing, not user feature)
- Edge Function: `pipeline-health-check`, runs every 30 minutes
- Checks:
  - tier0_observations: count by day (flag if <50 in last 24h)
  - tier1_daily_summaries: gap detection (flag any date with no summary)
  - ACB-FULL: last_generated age (flag if >25 hours)
  - Backfill status: estimated completion, pages remaining, last delta token timestamp
  - Nightly pipeline: last_run_at, last_run_status, duration
- Output: Supabase table `pipeline_health_log` + Slack/email webhook on any flag
- **WHY HERE:** During Phases 1-5 Yasser is not using the app. Pipeline failures are silent. Without this, Ammar discovers at Phase 4.09 verification that Tier 1 summaries have 3-week gaps. This catches failures within 30 minutes.
- Cost: negligible (lightweight Edge Function, no LLM calls)
- **Depends on:** 0.07

---

## Phase 1: Observation Pipeline (Tier 1 Signals)

Get real-world signals flowing into Supabase as structured Tier 0 observations. This is the data that feeds the entire intelligence engine.

### 1.01 — Deploy tier0_observations table
- Schema from ARCHITECTURE-MEMORY.md §1:
  - `id UUID PK, profile_id UUID FK→executives, occurred_at TIMESTAMPTZ, source TEXT, event_type TEXT, entity_id UUID, entity_type TEXT, summary TEXT, raw_data JSONB, importance_score FLOAT DEFAULT 0.5, baseline_deviation FLOAT NULL, embedding VECTOR(1024) NULL, is_processed BOOL DEFAULT false, processed_at TIMESTAMPTZ NULL, created_at TIMESTAMPTZ`
- BRIN index on `(profile_id, occurred_at)`
- HNSW index on `embedding` (m=16, ef_construction=128)
- RLS: `profile_id = get_executive_id(auth.uid())`
- **Depends on:** 0.03

### 1.02 — Deploy observation source tables
- `email_observations`: graph_message_id, sender_address, sender_name, recipient_count, subject_hash (SHA-256), folder, importance, is_reply, is_forward, response_latency_seconds, thread_depth, categories — BRIN on (executive_id, observed_at)
- `calendar_observations`: event times, attendee_count, organiser_is_self, response_status, was_cancelled, was_rescheduled, original_start — BRIN on (executive_id, observed_at)
- `app_usage_events`: bundle_id, window_title_hash (SHA-256), focus_duration, app_category — BRIN on (executive_id, observed_at)
- All with RLS scoped to executive
- **Depends on:** 0.03

### 1.03 — Define SignalIngestionPort protocol + Tier0Observation DTO
- `Sources/Core/Ports/SignalIngestionPort.swift`
- Protocol: `func recordObservation(_ observation: Tier0Observation) async`
- Tier0Observation struct: mirrors tier0_observations schema, `Sendable`, `Codable`
- **Depends on:** nothing (protocol only)

### 1.04 — Create Tier0Writer actor
- Implements SignalIngestionPort
- Writes to tier0_observations via SupabaseClient
- Batches: max 50 rows or 5 minutes, whichever first
- Falls back to SQLite offline queue when network unavailable
- Logs all writes via TimedLogger.layer1
- **Depends on:** 1.01, 0.06

### 1.05 — Wire EmailSyncService → Tier 0 observations
- Currently: EmailSyncService fetches delta messages, stores locally
- Add: for each email event, create Tier0Observation:
  - source: `"email"`, event_type: `"email.received"` / `"email.sent"` / `"email.response_sent"`
  - summary: auto-generated from metadata ("Responded to CFO email in 45 seconds (typical: 8 minutes)")
  - raw_data: `{ sender_category, response_time_sec, thread_depth, recipient_count }`
- Also write to `email_observations` for ONA graph (Phase 6)
- **Depends on:** 1.04

### 1.06 — Wire CalendarSyncService → Tier 0 observations
- For each calendar change, create Tier0Observation:
  - source: `"calendar"`, event_type: `"calendar.event_created"` / `"calendar.cancelled"` / `"calendar.rescheduled"` / `"calendar.attended"`
  - raw_data: `{ attendee_count, duration_minutes, is_organiser, is_back_to_back, meeting_type }`
- Also write to `calendar_observations`
- **Depends on:** 1.04

### 1.07 — Create AppUsageAgent
- `NSWorkspace.shared.notificationCenter` → `didActivateApplicationNotification`
- On each app switch: log bundleIdentifier, timestamp, duration of previous app
- Categorise apps by domain (communication, coding, browsing, creative) via local mapping table
- Create Tier0Observation for sessions > 30 seconds: source `"app_usage"`, event_type `"app.session"`
- Hash window titles with SHA-256 (privacy: never store raw titles)
- **NO permissions required** (NSWorkspace is unrestricted)
- **Depends on:** 1.04

### 1.08 — Create IdleTimeAgent
- IOKit: `IOServiceGetMatchingService` for IOHIDSystem
- Poll every 60 seconds
- Detect idle > 10 minutes → Tier0Observation: source `"system"`, event_type `"system.idle_start"` / `"system.idle_end"`
- Feeds energy model and break detection
- **NO permissions required**
- **Depends on:** 1.04

### 1.09 — Create FirstLastActivityAgent
- CGEvent tap: record daily first and last keyDown timestamps ONLY (never key values)
- Two Tier0Observations per day: `"system.first_activity"` and `"system.last_activity"`
- Feeds chronotype model
- **Requires:** Accessibility permission (TCC)
- **Depends on:** 1.04

### 1.10 — Create AgentCoordinator actor
- Manages lifecycle of all signal agents (1.05-1.09)
- Starts agents on auth success, stops on sign-out
- Monitors agent health, restarts crashed agents
- Provides unified observation rate metrics (target: 100-200/day)
- **Depends on:** 1.05, 1.06, 1.07, 1.08, 1.09

### 1.11 — Create HealthKitAgent (physiological ground truth)
- **This is the layer that separates Timed from every competitor.** No productivity tool integrates real-time physiological state into behavioural prediction.
- HealthKit bridge: request permissions for HRV SDNN, HRV RMSSD, resting HR, sleep analysis (stages), respiratory rate
- Write hourly HRV snapshot to local SQLite + Tier0Observation (source: "healthkit")
- Compute within-person HRV deviation: rolling 30-day personal baseline. Feature: `(today_HRV - baseline_HRV) / baseline_std`
- **Scientific basis:** Nature Digital Medicine 2026 — within-person HRV/HR deviations from personal baseline predict crash, fatigue, brain fog more than population norms. Lower morning HRV predicts acute stress episodes; sustained elevated HR predicts chronic fatigue accumulation.
- **NO population-level norms** — all comparisons are to Yasser's own 30-day rolling baseline
- **Requires:** HealthKit permission (iOS companion app or Apple Watch data via iCloud sync)
- **Depends on:** 1.04

### 1.12 — Create OuraRingAgent (optional — enriches HealthKit)
- Oura v2 API (OAuth2, personal access tokens): sleep stages, HRV, temperature trends, readiness scores
- Falls back gracefully if Yasser doesn't use Oura — HealthKit alone is sufficient
- 50+ metrics available; extract: sleep_score, readiness_score, hrv_balance, temperature_deviation
- Each daily reading → Tier0Observation (source: "oura")
- **Depends on:** 1.04

### 1.13 — Verify observation pipeline end-to-end
- Sign in → receive emails → Tier 0 observations in Supabase → calendar events flow → app usage events flow → idle detection works → HealthKit data flows (if available)
- Supabase dashboard: verify 100+ observations after a normal workday
- **Depends on:** 1.10, 1.11

---

## Phase 2: Memory Infrastructure

The 5-tier warehouse the intelligence engine reads from and writes to.

### 2.01 — Deploy tier1_daily_summaries table
- Schema: `id, profile_id, summary_date (UNIQUE per profile per day), day_narrative TEXT, significant_events JSONB[], anomalies JSONB[], energy_profile JSONB, signals_aggregated INT, embedding VECTOR(3072), generated_by TEXT, source_tier0_count INT, created_at`
- HNSW on embedding (m=32, ef_construction=200) — increased for 3072-dim
- BRIN on (profile_id, summary_date)
- **Depends on:** 1.01

### 2.02 — Deploy tier2_behavioural_signatures table
- Full schema from ARCHITECTURE-MEMORY.md §1 (signature_name, pattern_type, description, cross_domain_correlations, supporting_tier1_ids, observation_count, confidence, validation_gates, status lifecycle, next_revalidation, embedding)
- embedding VECTOR(3072) — OpenAI text-embedding-3-large
- HNSW on embedding (m=48, ef_construction=256), GIN on supporting_tier1_ids
- **Depends on:** nothing

### 2.03 — Deploy tier3_personality_traits table
- Full schema (trait_name, trait_type, version, valence_vector, precision, valid_from/to bi-temporal, evidence_chain, contradiction_log, predictions_enabled, supersedes chain, trajectory_narrative, embedding)
- embedding VECTOR(3072) — OpenAI text-embedding-3-large
- HNSW on embedding (m=64, ef_construction=300) — maximum recall for highest-stakes matching
- Partial B-tree WHERE valid_to IS NULL
- **Depends on:** nothing

### 2.04 — Deploy active_context_buffer table (dual ACB)
- Two documents per profile:
  - `acb_full JSONB` — 10,000-12,000 tokens for Opus intelligence calls:
    - All active Tier 3 traits with precision scores and evidence chains (~3K tokens)
    - All confirmed Tier 2 signatures, full descriptions (~2.5K tokens)
    - Developing signatures (>0.5 confidence) (~1K tokens)
    - Last 7 daily summaries, full text (~2K tokens)
    - ONA snapshot: top-20 relationship health scores, RDI trends, dormancy alerts (~800 tokens)
    - Active predictions with brier scores (~500 tokens)
    - Session context: today's calendar, overnight email metadata (~800 tokens)
  - `acb_light JSONB` — 500-800 tokens for Haiku/Sonnet utility calls:
    - Trait names + one-line descriptions only
    - Today's date, timezone, primary goals
    - Active predictions summary
  - `acb_version INT`, `acb_generated_at TIMESTAMPTZ`
- RPC functions: `get_acb_full(executive_id)` and `get_acb_light(executive_id)`
- **Depends on:** nothing

### 2.05 — Deploy predictions + tracking tables
- `predictions`: prediction_type, predicted_behaviour, time_window, confidence, grounding_trait_ids, falsification_criteria, status, brier_score
- `burnout_assessments`, `avoidance_flags`, `decision_tracking` — derived output tables
- `tier2_candidates`: staging table for self-improvement loop proposals that fail the BOCPD confidence floor (probability < 0.85 or < 3 non-adjacent sessions). Schema mirrors tier2_behavioural_signatures + `bocpd_probability FLOAT, session_count INT, proposed_at, reviewed_at, review_decision TEXT`. Human-reviewable via pipeline health dashboard.
- `self_improvement_log`: date, proposed_changes JSONB, accepted_changes JSONB, rejected_reasons JSONB, validation_results JSONB
- **Depends on:** nothing

### 2.06 — Create generate-embedding Edge Function (dual-provider)
- Replace Jina v3 calls with dual-provider routing:
  - Tier 0: `voyage-context-3` (1024-dim) — high volume, contextual retrieval
  - Tier 1, 2, 3: `text-embedding-3-large` (OpenAI, 3072-dim) — maximum discriminative space for durable memory
- Input: text + tier (0/1/2/3) → function routes to correct provider + model
- Set `VOYAGE_API_KEY` and `OPENAI_API_KEY` in Supabase secrets
- Batch support: up to 10 texts per call (both providers support batching)
- Cost: Voyage $0.18/M tokens (Tier 0 only), OpenAI $0.13/M tokens (Tier 1-3) — actually cheaper than all-Voyage
- **Depends on:** nothing

### 2.07 — Create EmbeddingService actor (client-side)
- Calls generate-embedding Edge Function with tier parameter
- Batches requests (10 texts/call)
- LRU cache: 500 entries in memory
- Handles mixed dimensionality: 1024 (Tier 0) vs 3072 (Tier 1-3)
- **Depends on:** 2.06

### 2.08 — Integrate USearch for local vector search
- Add USearch SPM dependency
- LocalVectorStore actor: per-tier HNSW indexes
  - Tier 0 index: 1024-dim
  - Tier 1-3 indexes: 3072-dim
- Sub-10ms on Apple Silicon
- Sync from Supabase on launch, then incrementally
- Primary query path (pgvector is backup/sync)
- **Depends on:** nothing (library integration)

### 2.09 — Create MemoryStore protocol + implementation
- Protocol: `writeObservation()`, `retrieve(query:intent:limit:)`, `activeContextBuffer()`
- MemoryStoreActor: routes writes to Supabase + local index, retrieval via 5-dimension composite scoring
- **Depends on:** 2.01-2.05, 2.07, 2.08

### 2.10 — Implement 5-dimension retrieval engine
- Dimensions: recency (exp decay, half-life ~5.8 days), importance, relevance (cosine similarity), temporal_proximity, tier_boost
- Intent classification: WHAT / WHEN / WHY / PATTERN / CHANGE → different weight profiles
- Hierarchical drill-down: Tier 3 → 2 → 1 → 0
- Retrieval floor: composite < 0.15 → excluded
- **Depends on:** 2.09

### 2.11 — Verify memory infrastructure
- Write Tier 0 → embed → query semantically → result returned
- Write 7 daily summaries → PATTERN query → relevant summaries returned
- ACB read → structured XML document
- **Depends on:** 2.10

### 2.12 — Define TFT-compatible time-series schema (views layer)
- For each Tier 0 observation type (email, calendar, keystroke, voice, app_usage):
  - Define static covariates (executive_id, day_of_week, month)
  - Define time-varying known covariates (calendar_load, meeting_count, public_holiday)
  - Define time-varying unknown covariates (email_volume, response_latency, keystroke_IKI)
  - Define target variables (decision_speed, avoidance_score, burnout_index)
- Implement as Supabase views layer — computed from existing tables, no migration needed
- Zero storage cost, zero runtime cost
- **WHY NOW:** Phase 13.04 (Temporal Fusion Transformer) needs 12+ months of TFT-compatible data. If this schema is deferred to month 11, re-processing a year of Tier 0 observations is required. Defining views now means TFT training data accumulates automatically from day one.
- **Depends on:** 2.01

---

## Phase 3: Nightly Pipeline (Intelligence Core)

The beating heart. This is where observations become intelligence.

### 3.01 — Create 4-cron pipeline architecture
- **`nightly-consolidation-full`** — Cron: `0 2 * * *` (2 AM local)
  - Advisory lock per executive_id, idempotent
  - Runs Phases 3.03 → 3.04 → 3.05 → 3.07
  - Checks if weekly (Phase 4) or monthly (Phase 5) should run
- **`nightly-consolidation-refresh`** — Cron: `15 5 * * *` (5:15 AM local)
  - **Step 0 (conditional overnight importance audit):** Query tier0 WHERE occurred_at BETWEEN 9 PM AND 5 AM AND importance_score BETWEEN 0.55 AND 0.75. IF count > 0: run Sonnet 3.7 (4K thinking) re-scoring on these observations BEFORE the addendum step. IF count == 0: skip (no cost). Ensures high-stakes overnight signals (board email at 11 PM, 3 AM calendar reschedule) are scored at Sonnet quality before the briefing generates at 5:30.
  - Lightweight: re-score new Tier 0 since 2 AM (Haiku), append to daily summary (Sonnet addendum), refresh ACB with morning calendar
  - Ensures morning briefing captures late-night signals (9 PM - 5 AM window)
  - Cost: ~$0.15-0.25/run (+ ~$0.05-0.15 on nights with uncertain-band overnight observations)
- **`generate-morning-briefing`** — Cron: `30 5 * * *` (5:30 AM local, 15 min after refresh)
  - Opus 4.6 with ACB-FULL injection
- **`weekly-pruning`** — Cron: `0 3 * * 0` (Sunday 3 AM)
  - Phase 3.06 decoupled from nightly — volume is trivially small daily
- **Depends on:** 2.01-2.05

### 3.02 — Deploy baselines table + computation
- `baselines`: profile_id, signal_type, metric_name, mean, stddev, sample_count, updated_at
- Compute per-signal rolling averages over trailing 30 days
- Updated after each daily summary
- Weeks 1-2: baselines NULL (establishment period, no deviations computed)
- **Depends on:** 1.01

### 3.03 — Implement Phase 1: Importance Scoring (Two-Pass)
- Fetch unprocessed tier0 WHERE importance_score = 0.5 (default)
- **Pass 1 — Haiku 3.5** batch-scores all observations: "Rate 1-10 using anchors: 1=routine, 5=notable deviation, 10=unprecedented. Output only integer." Temperature 0.0
- Update importance_score = score/10.0
- Batch: up to 200 per run
- **Pass 2 — Sonnet 3.7 (4K thinking)** re-scores observations WHERE importance_score BETWEEN 0.55 AND 0.75 (the uncertain middle band where behavioural nuance lives — Haiku flattens to 6 what Sonnet recognises as 8.2)
- Final importance_score = Sonnet result where Pass 2 triggered
- Estimated ~30-40 observations/night in the uncertain band, ~$0.10-0.15/night
- **Depends on:** 3.01

### 3.04 — Implement Phase 2: Conflict Detection
- For each scored observation today: vector search Tier 2+3 (top_k=5, min_similarity=0.75)
- **Sonnet 3.7 with extended thinking (8K budget)**: "Does this new observation contradict the existing memory? Score 0.0-1.0." Temperature 0.0
- Sonnet required: subtle contradictions need cross-temporal behavioural context that Haiku misses
- Contradiction > 0.7 → tag both items
- **Depends on:** 3.03, 2.06

### 3.05 — Implement Phase 3: Daily Summary Generation ← HIGHEST PRIORITY MODEL UPGRADE
- Fetch today's Tier 0 observations (ordered by occurred_at)
- Fetch baselines, compute sigma deviations per observation
- **Opus 4.6 with extended thinking (16K budget)**: observations + baselines + ACB-FULL + calendar context
  - "Describe what happened. Do not interpret. Flag anomalies >1.5σ. Note cross-signal co-occurrences. Structure: day_narrative, significant_events[], anomalies[], energy_profile."
  - Temperature 0.0
- **WHY OPUS HERE:** A Haiku summary that misses a nuanced behavioural anomaly poisons Tier 2 and Tier 3 FOREVER. Quality at the foundation, not just the synthesis layer.
- Insert tier1_daily_summaries, embed with **text-embedding-3-large (3072-dim)**
- Mark tier0 as processed
- **Depends on:** 3.04, 3.02

### 3.06 — Implement Pruning (weekly, decoupled)
- Runs Sunday 3 AM via `weekly-pruning` cron, NOT nightly
- Tier 0 >30 days + importance <0.8 → move raw_data to Supabase Storage, replace with URI
- Tier 0 >365 days + importance <0.8 + processed → tombstone (keep summary+embedding)
- Tier 2 last_reinforced >60 days + confirmed → status='fading'
- Tier 3: NEVER prune
- **Depends on:** 3.01

### 3.07 — Implement ACB generation (dual document)
- **Opus 4.6, temp 0.0** — ACB quality determines every downstream LLM call
- Generate ACB-FULL (10-12K tokens):
  - All active Tier 3 traits with precision + evidence chains (~3K)
  - All confirmed Tier 2 signatures, full descriptions (~2.5K)
  - Developing signatures >0.5 confidence (~1K)
  - Last 7 daily summaries, full text (~2K)
  - ONA top-20 relationship health, RDI trends, dormancy (~800)
  - Active predictions + brier scores (~500)
  - **Prediction performance history (~400):** last 20 resolved predictions with type, predicted_behaviour, actual_outcome, brier_score, was_correct. Accuracy rate by prediction_type. Current calibration bias (over/under confident by domain). This transforms Opus from generating predictions to reasoning about its own calibration.
  - **Active contradiction log (~300):** all tier0/tier1 observations currently flagged contradiction_score > 0.7. Per item: observation_id, summary, what_it_contradicts (tier + name), contradiction_score, days_since_flagged. Rarely >5 active contradictions. Every downstream Opus call knows where the model is currently uncertain rather than radiating confidence over unresolved conflicts.
  - Session context: calendar, overnight email (~800)
- Generate ACB-LIGHT (500-800 tokens): trait names + one-liners, date/timezone/goals, prediction summary
- Write both to active_context_buffer via `get_acb_full()` / `get_acb_light()` RPCs
- **Depends on:** 3.05

### 3.08 — Implement self-improving consolidation loop (nightly, Batch API)
- Runs as final stage of `nightly-consolidation-full`, after ACB generation
- **5-phase HyperAgents-style loop** — the model improves *how it improves*:
  1. **Inventory**: enumerate all Tier 1 summaries from past 7 days
  2. **Extract**: identify patterns that existing Tier 2 signatures did not capture — what was novel this week?
  3. **Propose**: draft new signature definitions or trait updates with evidence chains
  4. **Validate**: back-test proposed changes against last 90 days of data (BOCPD confirms structural novelty, not noise)
  5. **Confidence floor gate (CRITICAL):** BOCPD changepoint probability must exceed **0.85** AND pattern must appear across **≥3 non-adjacent sessions** before committing to Tier 2. Below threshold → write to `tier2_candidates` staging table for human review. **WHY:** Without this floor, the loop commits noise patterns as durable memory on low-signal weeks. Supabase's conflict detection catches logical contradictions, not statistical insignificance. This gate is the difference between compounding intelligence and compounding noise.
  6. **Commit**: write approved changes to Tier 2 (only if confidence floor passed), update ACB, log reasoning to `self_improvement_log` table. Below-threshold proposals → `tier2_candidates` table (staging)
- **Opus 4.6 with `effort: "high"` via Batch API (50% discount)** — runs async, results available by morning
- Key insight from research: agents that improve how they improve show +8.9% goal completion while cutting tokens by 59% as skills accumulate
- `self_improvement_log` table: date, proposed_changes JSONB, accepted_changes JSONB, rejected_reasons JSONB, validation_results JSONB
- **Depends on:** 3.07

### 3.09 — Verify nightly pipeline end-to-end
- Seed 100+ Tier 0 observations across email, calendar, app_usage
- Run `nightly-consolidation-full` manually
- Verify: importance scores (Haiku), conflicts (Sonnet), daily summary (Opus), ACB-FULL + ACB-LIGHT populated, self-improvement loop produces proposals
- Run `nightly-consolidation-refresh` → verify addendum appended
- Run `generate-morning-briefing` → verify 7-section output with ACB-FULL context
- **Depends on:** 3.03-3.08

---

## Phase 3.5: KeystrokeXPC (Promoted from Phase 10)

Build in parallel with Phase 3. Architecturally ready before Week 4. Activated when Accessibility permission granted at Week 4 trust gate. Keystroke dynamics are the ONLY signal providing real-time cognitive state — qualitatively different from all other signals.

### 3.5.01 — Build KeystrokeXPC service
- CGEventTap: keyDown/keyUp timestamps ONLY — never key values, never characters
- 5-minute windows: mean IKI, dwell time, flight time, backspace rate, WPM, pause patterns (>2s), top-20 bigraph latencies
- XPC registered as LaunchAgent (SMAppService), KeepAlive=true
- Separate crash domain: keystroke capture isolated from main app
- **Requires:** Accessibility permission (requested at Week 4, not at onboarding)
- **Depends on:** nothing (built in parallel)

### 3.5.02 — Build CognitiveLoadIndex (CCLI)
- Composite: keystroke IKI + error rate + app switch frequency + email latency shifts
- 5-minute rolling windows
- Personal calibration: first 2 weeks establish baseline, then z-score deviations
- Feeds: alert system (cognitiveStatePermit), briefing Section 5, energy model
- **Depends on:** 3.5.01, 1.07

### 3.5.03 — Build ChronotypeModel
- Inputs: first/last activity timestamps (1.09), email send-time distribution, keystroke velocity by hour
- Output: chronotype classification + energy curve prediction
- Target: r=0.74-0.80 with sleep onset/offset
- Feeds: morning briefing Section 5 (Cognitive Load Forecast) + TimeSlotAllocator
- **Depends on:** 1.09, 3.5.01

### 3.5.04 — Wire keystroke signals to Tier 0
- Each 5-minute aggregate → Tier0Observation (source: "keystroke")
- CCLI snapshots → Tier0Observation (source: "composite")
- Nightly pipeline processes alongside email/calendar/app signals
- **Depends on:** 3.5.01, 3.5.02, 1.04

### 3.5.05 — Activation gate
- KeystrokeXPC is BUILT and TESTED but NOT activated until Week 4 consent gate
- Week 4: progressive permission UI requests Accessibility ("focus analytics" framing)
- On grant: AgentCoordinator activates KeystrokeXPC
- On decline: system continues without keystroke data — graceful degradation
- **Depends on:** 3.5.01-3.5.04, 11.02

---

## Phase 4: Intelligence Delivery (Morning Briefing)

What the executive actually sees. The highest-stakes moment.

### 4.01 — Create generate-morning-briefing Edge Function (Two-Pass with Adversarial Review)
- Triggered at 5:30 AM local (15 min after `nightly-consolidation-refresh`)
- Context assembly: last 7 daily summaries + **ACB-FULL** (10-12K tokens) + today's calendar + overnight email metadata + top-5 similar past briefings + pending insights
- **Engagement self-correction:** When `engagement_duration < 60 seconds` for 2+ consecutive briefings, inject into Pass 1 context: "ATTENTION: Last [N] briefings had <60s engagement. Prior briefing content: [last 3 briefings]. Do not repeat any insight category from last 3. Prioritise: highest-importance anomaly from last 7 days NOT yet surfaced." This makes the system self-correct on low engagement before asking Yasser what's wrong — Phase 5.05's recalibration prompt becomes a last resort.
- **Morning HRV gate (if HealthKit available):** If today's morning HRV deviation < -1.5σ from 30-day baseline, inject cognitive load warning into Section 5 (Cognitive Load Forecast): "Your physiological data indicates elevated stress this morning. Consider delaying high-stakes decisions until after recovery." This is the physiological ground truth that no competitor has — the system knows Yasser's stress level before he does.
- **Pass 1 — Opus 4.6 with extended thinking (32K budget)**: generates the 7-section briefing. Highest-stakes user-facing output, no model compromise.
- **Pass 2 — Adversarial Opus 4.6 (16K budget, temp 0.0)**: separate call with Pass 1 output + raw data context + **last 14 briefings**. Task: "For each insight: (1) strongest alternative explanation for the same data, (2) any data that contradicts this interpretation, (3) any overconfidence in the language, (4) does this contradict or resolve a specific claim from a prior briefing? If yes: set superseded_by on the prior insight AND add a one-sentence 'update' note to today's insight." This closes the narrative coherence gap — Yasser sees briefings as a connected intelligence thread, not isolated daily reports.
- **Pass 3**: if Pass 2 flagged changes → apply them. Else → use Pass 1 output.
- Cost: ~$0.60-0.90/morning for the adversarial pass. Weekly: ~$5. Worth it.
- Cache in `briefings` table for instant display
- **Depends on:** 3.05, 3.07

### 4.02 — Deploy briefings table
- `id, profile_id, date (UNIQUE per profile per day), content JSONB (7 sections), generated_at, word_count, was_viewed BOOL, first_viewed_at, engagement_duration_seconds, sections_interacted JSONB, insight_superseded_by JSONB` — superseded_by tracks: {insight_id, superseded_by_briefing_date, superseded_by_insight, reason}. Enables narrative coherence across briefings — the system tracks which prior claims were resolved, contradicted, or updated.
- **Depends on:** nothing

### 4.03 — Define MorningBriefing Swift data model
- Struct: leadInsight, calendarIntelligence, emailPatterns, decisionObservations (optional), cognitiveLoadForecast, emergingPatterns (0-2), forwardLookingObservation
- BriefingItem: insight (1-2 sentences), supportingData (1 data point max), confidence (.high/.moderate), category, sourceSignals, historicalAccuracy (Double?, optional — only for predictions), predictionType (PredictionType?), trackRecord (String? — e.g. "8 of last 10 predictions of this type were correct")
- Show `trackRecord` as subtle subscript under high-stakes predictions (P ≥ 0.75 only). Builds trust (Yasser sees the track record) + creates accountability (system can't claim "high confidence" if its record doesn't support it).
- Confidence: .low NEVER appears in morning brief — hold for strengthening
- **Depends on:** nothing

### 4.04 — Build MorningBriefingPane (SwiftUI)
- 7-section layout:
  - Section 1 (Lead): large, prominent, top position — primacy effect
  - Sections 2-6: body cards with confidence indicators and supporting data
  - Section 7 (Recency Anchor): forward-looking question, visually distinct
- Confidence language: numeric + verbal ("likely, ~70%")
- Total ~610 words, hard cap 800
- **Depends on:** 4.03

### 4.05 — Wire morning briefing to app launch
- Morning detection: before 11 AM local
- Check briefings table for today → display immediately if cached
- If missing → show loading state → fetch from Supabase → trigger generation if needed
- After 11 AM: show as "Today's Intelligence" (same content, different framing)
- **Depends on:** 4.01, 4.04

### 4.06 — Build briefing generation system prompt
- Incorporate coaching principles: data-first, feedforward, curiosity framing, max 1 challenging insight, anchor to stated goals
- Confidence routing: High/High → lead. High/Moderate → body with hedge. Low/any → suppress.
- Voice language: "I notice..." / "I observe..." / "The pattern suggests..." (never "I feel..." or "The algorithm detected...")
- **Depends on:** 4.01

### 4.07 — Implement briefing engagement tracking
- Track: was_viewed, time_to_first_open, engagement_duration, sections_interacted
- Feed back as Tier 0 observations (source: "engagement") — the system observes its own reception
- Meta-feedback loop: system learns which insight types the executive values
- **Depends on:** 4.04

### 4.08 — Update MenuBarManager with intelligence headline
- Add: one-line lead insight from today's briefing
- Click → opens MorningBriefingPane
- **Depends on:** 4.04

### 4.09 — Verify morning briefing flow
- 7+ daily summaries in database
- Run generate-morning-briefing → 7-section output
- Open app before 11 AM → see briefing → interact → engagement tracked → next day's generation incorporates engagement data
- **Depends on:** 4.01-4.08

---

## Phase 5: Cold Start & Onboarding

First-run experience. Must deliver value from Hour 1. The system has 1 week to prove itself.

### 5.01 — Redesign OnboardingFlow for SOKA model
- Replace 9-step generic onboarding with:
  1. Microsoft Graph permissions (calendar + email read-only) — lowest threat
  2. 4-5 SOKA questions (ask ONLY what the executive uniquely knows — internal states):
     - "What keeps you up at night about your role?"
     - "When you make a high-stakes decision, what does your process look like?"
     - "What does a good week vs bad week look like for you?"
     - "Who are the 3-5 people whose input matters most?"
     - Optional: "What should I know that isn't visible from calendar and email?"
  3. Background ingestion of last 90 days email + calendar begins
- 12-minute hard ceiling. 5-minute fast path available.
- **Depends on:** 0.02, 1.10

### 5.02 — Implement historical data backfill (up to 3 years)
- On first auth: Graph API delta query for **maximum available history** (up to 3 years or Outlook retention limit)
- Write all as Tier 0 observations with historical timestamps
- **WHY 3 YEARS:** 4-gate validation (Phase 7.02) requires test-retest across 3+ non-adjacent weeks. With 3-year backfill, Gate 2 can run on Day 1. The system starts with 3 years of evidence, not as a blank slate.
- Run as background process (NSBackgroundTask), show progress in onboarding UI
- Estimated duration: 8-12 hours for 3-year backfill at 150 emails/day
- Rate limit: 4 calls/sec Graph API
- **Depends on:** 1.05, 1.06

### 5.03 — Build default intelligence library (20-30 base-rate insights)
- Available from Hour 1, zero personalisation required:
- **Calendar-derived**: deep work availability, meeting load vs Porter/Nohria baseline (72% meetings / 28% alone), context-switch count, recovery gap analysis, evening/weekend bleed
- **Email-derived**: response time distribution (median, p90, p99), volume by hour heatmap, contact tier map, sent:received ratio, after-hours percentage
- **Research-backed**: Gloria Mark 23-min recovery, Kahneman System 1/2, Klein RPD, Eisenhardt simultaneous alternatives
- Every insight references a specific number from the executive's data. Zero generic output.
- **Depends on:** 5.02

### 5.04 — Implement 48-hour thin-slice inference
- Day 3 Edge Function: **Opus 4.6 with extended thinking (16K budget)**
- Analyse accumulated email+calendar data (with 3-year backfill, this is actually 3 years of patterns):
  - Communication energy (rapid responder vs deliberate batched)
  - Network structure (hub-and-spoke vs distributed vs hierarchical)
  - Time sovereignty (controls own calendar vs calendar-controlled)
  - Cognitive load trajectory (building through week vs front-loaded vs chaotic)
- Frame: "Based on 48 hours of live observation and [N] years of email history, here is what I'm beginning to see."
- **Depends on:** 5.02, 3.05

### 5.05 — Implement engagement monitoring during learning period
- Track morning session open rate daily
- Engagement drops 2 consecutive days → escalate insight specificity (shift from base-rate to thin-slice)
- Drops 5 consecutive days → recalibration prompt: "Here are the 3 most important things I've learned. Are any wrong?"
- Never let 48 hours pass without a novel insight. Repetition = death.
- **Depends on:** 4.07

### 5.06 — Implement endowed progress effect
- Show cognitive model dimensions with fill state:
  - "Communication style: ████████░░ — I can distinguish your strategic from operational contacts"
  - "Decision patterns: ░░░░░░░░░░ — needs 4+ weeks of observation"
- Qualitative calibration (never progress bars or percentages)
- **Depends on:** 4.04

### 5.07 — Implement communication style mirroring
- Detect executive's style from first 48 hours of email metadata
- Terse emails → terse briefing
- Detailed emails → briefing includes more supporting data
- Rapid rapport building — the system adapts to the executive
- **Depends on:** 5.04

---

## Phase 6: ONA & Relationship Intelligence

Build the organisational network analysis from email metadata. Foundation for relationship health, disengagement detection, and the social intelligence layer.

### 6.01 — Deploy ONA tables
- `ona_nodes`: email (unique), display_name, inferred_role/org/department, total_emails_sent/received, avg_response_latency, communication_frequency, importance_tier, all 7 centrality metrics, relationship_health_score, health_trend
- `ona_edges`: from/to node_id, direction, timestamp, response_latency, thread_id/depth, recipient_position, is_initiated, has_attachment, message_graph_id
- `relationships`: full schema from ARCHITECTURE-SIGNALS.md §2.2 (strength + decay, reciprocity, RDI, SWS, health_score, health_trajectory, maintenance_alert_threshold)
- **Depends on:** 1.01

### 6.02 — Build ONA graph builder service
- Process email_observations → ona_nodes + ona_edges
- Entity resolution: deduplicate aliases (same person, different emails) via **Sonnet 3.7** (Haiku dedup errors compound into corrupted relationship graph)
- **LLM role inference for top-30 contacts** (by communication_frequency): Sonnet 3.7 call with sender_address, domain, email volume, thread depth, recipient_position, initiated_rate, response_latency vs executive baseline → returns inferred_role, authority_tier (peer/subordinate/superior/board), relationship_type (operational/strategic/political/social). Runs once on backfill for top-30, then incrementally. "Your response time to board-level contacts has tripled" is qualitatively different from "your response time to HSBC contacts has tripled."
- **ONA tone trajectory for top-20 contacts** (weekly): Sonnet 3.7 (no thinking, temp 0.0) with last 10 email metadata summaries per dyad (subject_hash, response_latency, thread_depth, is_initiated, word_count_bucket) → rates: formality_trend (0-1), responsiveness_symmetry (0-1), engagement_depth (0-1) + one_sentence_trajectory. 10-email rolling window. "Communication with [CFO] has become 40% more formal and 60% more asymmetric over 6 weeks" is a qualitatively different signal than "response time has increased." Cost: ~$0.20/week for 20 contacts.
- Store in ona_nodes: inferred_role, authority_tier, relationship_type, formality_trend, responsiveness_symmetry, engagement_depth, trajectory_summary
- Run on each email sync batch (role inference) + weekly (tone trajectory)
- **Depends on:** 6.01, 1.05

### 6.03 — Implement centrality metrics computation
- Degree centrality: recompute every ingest batch
- Betweenness, eigenvector, PageRank: recompute daily via Supabase RPC
- PostgreSQL recursive CTEs for path-finding (hundreds-to-thousands of nodes, no graph DB needed)
- **Depends on:** 6.02

### 6.04 — Implement relationship health scoring
- Per-dyad 0-100 combining: response latency z-score, reciprocity ratio (flag outside 0.35-0.65), thread depth trend, contact frequency decay (Burt's power function)
- Step-function alerting: Active (<14d) → Cooling (14-30d) → At Risk (30-60d) → Dormant (>60d)
- Thresholds personalised from executive's own cadence per relationship
- **Depends on:** 6.03

### 6.05 — Implement disengagement detection (RDI + SWS)
- RDI: response rate decline (0.25), latency increase (0.25), initiated contact decline (0.20), CC inclusion decline (0.15), meeting participation decline (0.15)
- SWS: compare target's metrics toward executive vs toward others → selective vs general withdrawal
- Executive self-disengagement: detect own unconscious avoidance patterns
- 12-week baseline before activation, 4-week minimum declining trend to flag
- **Depends on:** 6.04

### 6.06 — Wire relationship intelligence to morning briefing
- Section 3 (Email Patterns): "Your response time to [CFO] has tripled in the last 2 weeks"
- Section 6 (Emerging Patterns): multi-week relationship dynamics, dormancy alerts
- **Depends on:** 6.05, 4.01

---

## Phase 7: Pattern Detection & Trait Synthesis

Weekly and monthly intelligence consolidation. Where compounding begins.

### 7.01 — Implement Phase 4: Weekly Pattern Detection
- Trigger: end of week OR 5+ daily summaries since last run
- **Context assembly**: this week's daily summaries + existing Tier 2 library + ACB-FULL + **last 4 morning briefings (full content JSONB)** — Opus must know what it previously told Yasser so it can reinforce rather than re-discover, and explicitly surface contradictions with prior briefings
- **Opus 4.6 with extended thinking (32K budget), temp 0.3**: compare this week's summaries against existing Tier 2 library + ACB-FULL context + last 4 briefings. Identify reinforcements, new candidates, violations. Pattern must span >=2 domains AND >=14 days.
- **WHY OPUS:** Cross-domain pattern detection across 7 daily summaries requires deep reasoning. Sonnet catches obvious patterns but misses non-obvious cross-domain signals — exactly the signals that differentiate Timed from any competitor.
- Duplicate check: vector search Tier 2 (min_similarity=0.85)
  - Match → reinforce: update last_reinforced, observation_count, confidence
  - New → insert as 'emerging' with confidence 0.3
- Embed with **text-embedding-3-large (3072-dim)**
- **Depends on:** 3.05, 2.02, 4.02

### 7.02 — Implement 4-gate validation protocol
- Gate 1: ARIMA-corrected Cohen's d_z >= 0.5 (medium within-person effect)
- Gate 2: Test-retest r >= 0.6 across 3+ non-adjacent weeks (CANNOT run until 3 weeks exist)
- Gate 3: Pattern replicates in >= 2 distinct context conditions
- Gate 4: **Opus 4.6 (16K thinking, temp 0.0)** review — plausible cognitive/behavioural mechanism exists. Upgraded from Sonnet: a false-positive confirmed signature persists for months and generates Tier 3 traits. Runs 2-5 times/week during active emergence, ~$0.50-1.50/week.
- All 4 pass → status = 'confirmed'. Otherwise → stays 'emerging'/'developing', recheck in 7 days.
- **Depends on:** 7.01

### 7.03 — Implement Phase 5: Monthly Trait Synthesis
- **Stage A (Trait Synthesis)**: Opus 4.6 + extended thinking (64K budget), temperature 1.0
  - Review confirmed Tier 2 signatures + current Tier 3 traits + version history + conflict tags
  - For each trait: evidence support? Split/merge/retire? New traits? Trajectory narrative.
  - Cathartic update formula: temporary deviation → precision *= 0.9. Permanent shift → new version, supersede old. Novel emergence → new trait with precision 0.3.
- **Stage B (Prediction Generation)**: Opus 4.6
  - From traits with precision >= 0.7 + upcoming 14-day calendar
  - Falsifiable predictions: predicted behaviour, time window, confidence, grounding traits, falsification criteria
  - Cross-trait predictions: minimum confidence 0.7
  - Insert into predictions table
- **Depends on:** 7.02, 2.03, 2.05

### 7.04 — Implement BOCPD change detection
- 3 levels: signal, pattern, trait
- Hazard rate 1/250, student-t predictive probability
- Change point probability > 0.7 → 14-day quarantine
- CDI (magnitude 0.40 + consistency 0.35 + cross-level concordance 0.25) >= 0.65 → genuine change, version the trait
- CDI < 0.65 → transient, log as episodic
- **Depends on:** 7.03

### 7.05 — Implement CCR evaluation (weekly check + monthly full)
- CCR = model_prediction_accuracy / baseline_prediction_accuracy
- Baseline: raw data + last-7-days heuristic
- Brier score tracking for all predictions
- **Weekly lightweight check (SQL only, no LLM):** compare rolling brier scores to baseline heuristic. If weekly brier > baseline for 2+ consecutive weeks → flag for manual review. Catches regressions early — without this, a failing CCR persists 4 weeks before anyone notices while Yasser receives miscalibrated briefings.
- **Monthly full counterfactual test:** fresh Opus + only Tier 0-1 vs production system
- Expected trajectory: CCR ~1.0 at month 3, ~1.5 at month 6, ~2.0 at month 9
- **Depends on:** 7.03, 2.05

---

## Phase 8: Real-Time Alert System

Complement morning briefings with time-sensitive interruptions (rare, high-value).

### 8.01 — Create AlertEngine actor
- 5-dimension multiplicative scoring: salience × confidence × timeSensitivity × actionability × cognitiveStatePermit
- Any zero kills the alert
- **Pre-score step for salience + actionability:** For any alert candidate above raw threshold 0.3, **Opus 4.6 (no extended thinking, temp 0.0)** with ACB-FULL context rates salience (0.0-1.0) and actionability (0.0-1.0). LLM scores replace heuristic dimensions in the multiplicative formula. Salience isn't just signal strength — it's "how meaningful is this to THIS executive given everything we know." A 2σ email latency deviation has different salience depending on whether Yasser is in his "pre-decision withdrawal" pattern vs just being busy. Runs only for alert candidates (rare — target 0-3/day). Cost: ~$0.05-0.15/day.
- Interrupt threshold > 0.5, hold threshold > 0.2 (queue for briefing), below → discard
- **Depends on:** 2.09

### 8.02 — Implement frequency management
- Hard cap: 3/day (target 0-1). Minimum gap: 60 minutes.
- Rolling 20-alert actionability rate. Below 60% → raise threshold 30%.
- **Depends on:** 8.01

### 8.03 — Implement interrupt window detection
- Open: app switch, post-meeting gap (2-3 min), idle >60s, between deep work blocks
- Closed: sustained focus >15 min, in meeting, back-to-back, recent interrupt <60 min
- **Depends on:** 1.07, 1.06

### 8.04 — Build alert delivery UI
- Menu bar notification: 1-2 sentences max. Text-first.
- Voice only for composite > 0.8 AND executive opted in
- Track: acknowledged, actionable (feedback loop)
- **Depends on:** 8.01-8.03

### 8.05 — Implement coaching trust calibration
- 4 stages gated on engagement metrics (not time alone):
  - Establishment (Days 1-30): intensity 2/10, positive/neutral only
  - Calibration (30-90): intensity 4/10, mild discrepancy observations
  - Working Alliance (90-180): intensity 6/10, avoidance patterns
  - Deep Observation (180+): intensity 8/10, full pattern surfacing (never 10/10)
- Rupture protocol: 3+ consecutive dismissals → drop one stage
- **Depends on:** 4.07

### 8.06 — Implement multi-agent council for high-stakes decisions
- **Council pattern:** when the system detects a high-stakes decision moment (avoidance threshold crossed, burnout signal, major prediction), spawn 3 specialist Opus agents in parallel:
  1. **Energy agent**: evaluates current HRV baseline, sleep quality, CCLI score, time since last break, calendar load
  2. **Priority agent**: evaluates task urgency, deadline pressure, dependency chains, what Yasser said matters most (from Tier 3 traits)
  3. **Pattern agent**: queries Tier 2 library + prediction history for historical outcomes of similar decision contexts
- **Leader agent** synthesises council outputs into a recommendation with explicit confidence intervals and reasoning chain from each agent
- Trigger: alert composite score > 0.7 AND prediction confidence > 0.75 AND coaching stage >= Working Alliance
- Cost: ~$1-3 per council session, target 0-2 sessions/week. $5-15/week at max.
- **WHY:** Single Opus calls produce single-perspective analysis. Three specialist agents with different context windows produce multi-perspective intelligence that catches what any single agent misses.
- **Depends on:** 8.01-8.05, 9.01-9.03

---

## Phase 9: Prediction Layer

Advanced intelligence. Activates at month 3+ with sufficient data.

### 9.01 — Implement avoidance detection
- 3 streams: email latency (z > 2.0 for sender cluster, 5+ business days), calendar rescheduling (>2σ, 2+ weeks), document engagement (opened 3+ times without meaningful edit)
- Cross-stream: >= 2 of 3 for same domain → declare avoidance
- Strategic delay discriminator: expanding information network → NOT avoidance. Static/contracting → avoidance.
- **HARD RULE: never flag if network expanding. False negatives cheaper than false positives.**
- Confirmed patterns (3+ occurrences) promoted to Tier 2 signatures
- **Depends on:** 6.05, 7.02

### 9.02 — Implement burnout prediction
- 17 signals → 3 MBI dimensions (exhaustion, depersonalisation, reduced accomplishment)
- Triple gate: 3+ weeks duration, 3+ modalities converging, 2-of-3 MBI dimensions elevated
- Sprint discriminator: visible end date + stable network → suppress
- Start rule-based; LSTM+XGBoost ensemble when training data accumulates
- Minimum 11 weeks before first alert (8 baseline + 3 sustained signal)
- **Depends on:** 7.02, 1.10

### 9.03 — Implement decision reversal tracking
- 4-state HMM: Committed → Consolidating → Wavering → Reversing
- Features: time-to-decision, post-decision info seeking, new sources, same-source revisits
- T+4 to T+14 day predictive window
- Healthy reconsideration (new sources) vs vacillation (reprocessing)
- Start heuristic; Cox+HMM later
- **Depends on:** 6.02, 7.02

### 9.04 — Wire predictions to delivery (engagement-gated, NOT calendar-gated)
- **Days 3-14** (backfill processed + 2 morning sessions engaged): base-rate insights only — "Based on your last [N] years..."
- **Days 15-30** (60%+ morning open rate + 1 insight interacted): behavioural hypotheses at P >= 0.55 — "I'm beginning to notice..."
- **Months 2-3** (3+ confirmed Tier 2 signatures): soft predictions at P >= 0.65 — "Patterns consistent with..."
- **Months 3-6** (5+ confirmed signatures + 70% briefing engagement): avoidance + decision predictions at P >= 0.75 — "The evidence suggests..."
- **Month 6+** (full trait library): high-stakes (burnout, disengagement, reversal) at P >= 0.85 — "With high confidence..."
- **KEY CHANGE:** Engagement metrics replace calendar time. An executive who engages with insights daily has demonstrated the trust needed for predictions. A 3-month gate is a blunt proxy.
- Language: NEVER "you will..." Always "patterns consistent with..."
- Explicit error acknowledgment after wrong predictions
- **Depends on:** 9.01-9.03, 4.01

---

## Phase 10: Voice Signal Expansion

KeystrokeXPC, CCLI, and ChronotypeModel already built in Phase 3.5. This phase covers voice features and Whisper migration.

### 10.01 — Build VoiceFeatureExtractor via Gemini Audio API
- **REPLACES openSMILE C++ bridge** — research gap RESOLVED
- Audio segments (30-second chunks) → `extract-voice-features` Edge Function → Gemini 1.5 Pro Audio API → structured acoustic features
- Features returned: F0 mean/variance/contour, jitter, shimmer, HNR, speech rate, disfluency rate, spectral centroid, speaking time ratio, confidence indicators
- Cost: ~$0.0015/minute, 8 hours/day = ~$0.72/day
- Gemini's audio encoder captures richer features than hand-crafted eGeMAPS
- 10-15 lines of Edge Function code vs weeks of C++ interop
- **Requires:** Microphone permission (Week 4 trust gate)
- **Depends on:** Phase 5 complete

### 10.02 — Migrate voice to Whisper.cpp
- Replace SFSpeechRecognizer for background transcription
- Whisper-small: 244MB, 8x real-time on M1, ~4.5% WER, ~500MB memory
- On-demand during meetings; continuous only when plugged in
- Keep SFSpeechRecognizer for interactive morning interview voice input
- **Depends on:** nothing (independent)

### 10.03 — Wire voice signals to Tier 0 observations
- Voice features from Gemini → Tier0Observation (source: "voice")
- Whisper transcript summaries (LLM-summarised, never raw) → Tier0Observation
- Nightly pipeline processes alongside all other signals
- **Depends on:** 10.01, 10.02, 1.04

---

## Phase 11: Privacy & Trust Architecture

### 11.01 — Implement consent state machine
- DORMANT → CALENDAR_ONLY → CAL_EMAIL → CAL_EMAIL_APPS → FULL_OBSERVATION
- PARTIAL_REVOKE: toggle individual streams
- PAUSED: all observation stopped, model frozen, data retained encrypted
- DELETED: KEK destroyed, permanently unrecoverable (terminal)
- Transition gates: 7+ days current state, 60%+ morning open rate, 1+ insight engaged, 14+ days since revocation
- **Depends on:** 5.01

### 11.02 — Implement progressive permission UI
- Week 1: Calendar ("schedule intelligence"), Week 2: Email ("communication patterns"), Week 3: Accessibility ("focus analytics"), Week 4: Microphone+Keystroke ("decision rhythm" + "meeting energy")
- Each shows value evidence from prior level
- Decline: no re-ask for 14 days
- **Depends on:** 11.01

### 11.03 — Implement client-side encryption
- KEK in Secure Enclave, biometric-gated (Touch ID)
- Per-data-type DEKs wrapped by KEK: DEK-cal, DEK-eml, DEK-ftr, DEK-cog
- AES-256-GCM before data leaves device
- Zero-knowledge: Supabase never holds plaintext
- **Depends on:** nothing (independent)

### 11.04 — Privacy nutrition labels in settings
- Per data type: what collected, where processed, how long retained, who can access
- Layered consent, dynamic revocation
- Language: "typing rhythm" not "keystroke logging", "observe" not "track"
- **Depends on:** 11.01

### 11.05 — Implement data export + cryptographic deletion
- Export: one-click JSON/CSV (all data + cognitive model + reflections)
- Delete: KEK destruction → ciphertext permanently unrecoverable
- MDM detection: warn if device managed
- **Depends on:** 11.03

### 11.06 — EU AI Act compliance
- Feature extraction → cognitive states ONLY (focus, fragmentation), NEVER emotional states
- Architecturally exclude emotion classification labels
- Document as high-risk AI (Article 6, Annex III point 4)
- Adversarial testing before launch
- **Depends on:** all signal agents

---

## Phase 12: Production Hardening

### 12.01 — Build XPC service mesh (5 processes)
- KeystrokeXPC, VoiceXPC, AccessibilityXPC, AppUsageXPC + main app coordinator
- Each registered as LaunchAgent (SMAppService), KeepAlive=true
- Migrate monolithic agents (1.07-1.09) into isolated XPC crash domains
- **Depends on:** 10.01, 10.02, 1.07, 1.08

### 12.02 — App Nap prevention + low battery mode
- XPC services immune (LaunchAgent). Main app: `beginActivity(.userInitiated, .idleSystemSleepDisabled)`
- Low battery (<20%): keystroke 5min→15min, email 5min→30min, voice pauses
- Resume on charge
- **Depends on:** 12.01

### 12.03 — Sparkle auto-updates
- Sparkle 2.x, EdDSA signing, CDN appcast.xml, delta updates via BinaryDelta
- Update must not interrupt observation (XPC continues during main app update)
- **Depends on:** 12.01

### 12.04 — Developer ID signing + notarisation
- Developer ID certificate, hardened runtime, `xcrun notarytool`
- Not App Store (required for Accessibility API + CGEventTap)
- **Depends on:** nothing

### 12.05 — Graceful degradation
- Offline: XPC continues, local buffer, no Claude calls → reconnect flushes
- Claude down: last synthesis shown, observations accumulate → queue drains
- Supabase down: SQLite absorbs (7-day/50MB) → batch sync on recovery
- XPC crash: launchd restarts, others unaffected, menu bar degraded indicator
- Main crash: XPC continues → restart picks up buffers
- Reboot: SMAppService relaunches all
- **Depends on:** 12.01, 0.06

### 12.06 — Battery/CPU validation
- Target: ~1.5% CPU, ~350mW, ~560MB memory (voice on-demand)
- Voice continuous only when plugged in (~1.3W)
- Instruments profiling: Time Profiler, Energy Log, Allocations
- 10-hour battery workday feasible
- **Depends on:** 12.01

---

## Phase 13: Advanced Intelligence (Tier 3 — Month 11+)

Requires months of accumulated data. These capabilities are the long-term moat.

### 13.01 — WavLM/HuBERT neural voice embeddings
- Core ML quantised INT8 WavLM Large
- Raw waveform → layers 12-24 → mean-pool → 768/1024-dim embedding
- Deep cognitive state features beyond hand-crafted acoustics
- **Research gap:** Core ML WavLM quantisation approach
- **Depends on:** 10.02 + 12 weeks voice data

### 13.02 — Personal vocal biomarker library
- 90-day model: discover individual stress signatures, context-specific baselines
- Fine-tuned classification head on personal data
- **Depends on:** 13.01

### 13.03 — Multi-modal fusion (CCLI, BEWI, RDS, DQEI)
- Bottleneck Transformer: 5 modality embeddings → 4-8 bottleneck tokens → 4 composite indices
- Requires 3+ modalities converging
- **Research gap:** Bottleneck Transformer Core ML implementation
- **Depends on:** 13.01, 10.01, 10.02, 6.05

### 13.04 — Temporal Fusion Transformer
- Multi-horizon behavioural forecasting, interpretable attention weights
- Bayesian head for calibrated uncertainty
- Foundation model integration: Chronos/MOIRAI as zero-shot anomaly detectors
- **Depends on:** 12+ months data, 13.03

---

## Research Gaps (resolve NOW — do not defer to build phase)

Research gaps should be resolved during planning, not at build time. Spend $50-100/week of headroom on Perplexity Deep Research to close these before code touches them.

| # | Gap | Why It Matters | When Needed | Urgency | Status |
|---|-----|---------------|-------------|---------|--------|
| 1 | ~~openSMILE → Swift bridge~~ | ~~Voice feature extraction~~ | ~~Phase 10~~ | — | **RESOLVED — Gemini Audio API replaces openSMILE** |
| 2 | whisper.cpp Swift package + Core ML integration | Background transcription | Phase 10 | Medium | Open — research now |
| 3 | USearch Swift bindings production readiness | Local vector search — blocks Phase 2.08 | Phase 2 | **URGENT** | Open — blocks build |
| 4 | OpenAI text-embedding-3-large integration patterns | 3072-dim embeddings for Tier 1-3 — blocks Phase 2.06 | Phase 2 | **URGENT** | Open — blocks build |
| 5 | WavLM Core ML INT8 quantisation | Neural voice embeddings — needs prototype NOW so it's ready when 12mo data exists | Phase 13 | High | Open — prototype needed |
| 6 | BOCPD Swift implementation | Change point detection — needed at Phase 7.04, NOT Phase 13 | Phase 7 | **URGENT** | Open — blocks build |
| 7 | Secure Enclave KEK management on macOS (non-sandboxed) | Client-side encryption without App Store entitlements | Phase 11 | Medium | Open — research now |
| 8 | SMAppService + XPC LaunchAgent patterns (non-sandboxed) | Background service mesh | Phase 12 | Medium | Open — research now |
| 9 | Gemini 1.5 Pro Audio API — acoustic feature extraction capabilities | What features can Gemini actually return vs hand-crafted eGeMAPS? | Phase 10 | Medium | Open — research now |
| **10** | **Microsoft Graph delta token persistence + crash recovery for 3-year backfill** | **164K+ emails across 164+ pages — delta token must survive app crashes during 8-12h backfill. No recovery = silent data loss.** | **Phase 5** | **URGENT** | **Open — blocks build** |
| **11** | **Supabase Edge Function timeout (150s default) — nightly pipeline exceeds** | **importance scoring + conflict detection + Opus daily summary + ACB gen > 150s. Pipeline fails silently mid-run.** | **Phase 3** | **URGENT** | **Open — blocks build** |
| **12** | **Apple HealthKit macOS access patterns + iCloud sync from Apple Watch** | **HRV/HR data may require iOS companion app or direct Apple Watch — macOS HealthKit access is limited** | **Phase 1** | **High** | **Open — research now** |
| **13** | **Oura Ring v2 API OAuth2 integration + available metrics** | **50+ metrics claimed — verify which are actually accessible via API vs app-only** | **Phase 1** | **Medium** | **Open — research now** |
| **14** | **Anthropic Batch API integration for Supabase Edge Functions** | **50% discount on nightly async — verify Edge Function can submit batch jobs and poll results** | **Phase 3** | **High** | **Open — research now** |
| **15** | **Multi-agent council orchestration patterns (Claude Agent SDK)** | **3 parallel Opus agents + leader synthesis — verify Agent SDK supports council pattern** | **Phase 8** | **Medium** | **Open — research now** |

---

## Critical Path (Updated with No-Cost-Cap Changes)

```
Phase 0 (Auth) → Phase 1 (Signals) → Phase 2 (Memory) → Phase 3 (Nightly) → Phase 4 (Briefing) → Phase 5 (Cold Start)
                                          ↑                     ↑                                        ↓
                                     Phase 3.5 ──────────────────┘ (KeystrokeXPC built in parallel,   USABLE PRODUCT
                                     (built parallel)               activated Week 4)                    ↓
                                                                                          Phase 6 (ONA) ──── Phase 7 (Patterns) ──── Phase 9 (Prediction)
                                                                                                             ↓
                                                                                          Phase 8 (Alerts) — parallel
                                                                                          Phase 10 (Voice) — after Week 4 trust gate
                                                                                          Phase 11 (Privacy) — after Phase 5
                                                                                          Phase 12 (Production) — after Phase 3.5 + 10
                                                                                          Phase 13 (Advanced) — after 12 months
```

**First usable product = Phase 0 through Phase 5** (with Phase 3.5 built in parallel).

After that, intelligence deepens via Phases 6-13 based on engagement gates and data accumulation.

---

## Yasser Onboarding Gate (Live Data Collection)

**When:** Immediately after Phase 0.07 (auth → data flow verified end-to-end).

**Why then:** Phase 0 is the earliest moment the system can accept a real Microsoft account. Onboarding Yasser here means:
- 3-year email/calendar backfill (Phase 5.02) starts accumulating immediately — by the time Phase 3 (nightly pipeline) is ready, there are years of historical data + weeks of live observations to test against
- Every subsequent phase (memory tables, embeddings, nightly pipeline, briefing) is built and debugged against **real executive data**, not synthetic fixtures
- No app usage required from Yasser — he authenticates once via Microsoft OAuth, we collect passively

**What Yasser does:**
1. One-time: sits with Ammar for 15 minutes. Signs into Microsoft account via the app's OAuth flow.
2. Optional (high-value): answers 4-5 SOKA questions verbally while Ammar transcribes (feeds thin-slice inference at Phase 5.04)
3. Nothing else. He doesn't open the app again until Phase 4 (morning briefing) is ready.

**What the system does after onboarding:**
- Backfills up to 3 years of email metadata + calendar events → Tier 0 observations
- Begins live delta sync (new emails, calendar changes) → Tier 0 observations
- All data flows into Supabase for pipeline development
- Ammar uses this data to build/debug Phases 1-5 against real-world signals

**Feedback loop (no app required):**
- Weekly 10-minute call with Yasser: "Here's what the system noticed this week. Is this accurate? What did it miss?"
- Ammar shows raw Tier 1 daily summaries (text) on screen — Yasser reacts, Ammar logs corrections
- Corrections feed directly into pattern validation (Phase 7.02 Gate 4: plausibility review)
- This feedback is the fastest path to calibrating the intelligence engine before Yasser ever sees the app

**Activation sequence:**
1. Phase 0.07 passes → Ammar schedules Yasser onboarding
2. Yasser authenticates → backfill begins (8-12 hours background)
3. Live sync active from that moment
4. Weekly feedback calls begin once Phase 3.05 (daily summaries) produces first output
5. Yasser sees the app for the first time when Phase 4.04 (MorningBriefingPane) ships

## Weekly API Cost at Maximum Intelligence (v4 — Uncapped with Batch API + Caching)

| Component | Frequency | Batch API? | Weekly Cost |
|-----------|-----------|------------|-------------|
| Opus 4.6 daily summaries (effort:high) | 7x/week | Yes (50% off) | ~$6 |
| Opus 4.6 self-improvement loop (effort:high) | 7x/week | Yes (50% off) | ~$8 |
| Opus 4.6 morning briefing Pass 1 (effort:medium) | 7x/week | No | ~$10 |
| Opus 4.6 morning briefing Pass 2 adversarial (effort:medium) | 7x/week | No | ~$5 |
| Sonnet 3.7 conflict detection (effort:high) | 7x/week | Yes (50% off) | ~$1.50 |
| Opus 4.6 ACB refresh (effort:medium) | 7x/week | Yes (50% off) | ~$2 |
| Sonnet 3.7 5:15 AM pipeline refresh | 7x/week | No | ~$3 |
| Sonnet 3.7 overnight importance audit | ~3x/week | No | ~$0.30 |
| Opus 4.6 weekly pattern detection (effort:high) | 1x/week | Yes (50% off) | ~$2.50 |
| Opus 4.6 Gate 4 plausibility (effort:high) | 2-5x/week | Yes (50% off) | ~$0.50 |
| Opus 4.6 alert salience (effort:low) | 0-3x/day | No | ~$1 |
| Opus 4.6 multi-agent council (3 agents) | 0-2x/week | No | ~$5-15 |
| Sonnet 3.7 importance Pass 2 (effort:medium) | 30-40x/night | Yes (50% off) | ~$0.50 |
| Sonnet 3.7 ONA tone trajectory | 1x/week | Yes | ~$0.10 |
| text-embedding-3-large (Tier 1-3) | Daily | — | ~$1 |
| voyage-context-3 (Tier 0, ~200 obs/day) | Daily | — | ~$2 |
| Gemini 1.5 Pro audio (8h/day, Phase 10) | Daily | — | ~$5 |
| Haiku importance Pass 1 + utility | Daily | Yes (50% off) | ~$1.50 |
| Prompt caching savings (90% input reduction) | All sessions | — | ~-$20 |
| Graph API, Supabase, infrastructure | — | — | ~$15 |
| **Total** | | | **~$50-70/week (with caching + batch)** |
| **Total without caching/batch** | | | **~$120-180/week** |

$800/week budget → $730-750 headroom with caching. Intelligence is MAXIMISED while cost is MINIMISED through smart infrastructure (Batch API + prompt caching), not model downgrades.

---

## Plan Assessment Protocol

This plan is subject to iterative Perplexity Deep Research assessment. The goal is a 10/10 rating on execution plan quality before build begins. See Perplexity prompt below — run via `/generate-research-prompts` or manual Deep Research submission.
