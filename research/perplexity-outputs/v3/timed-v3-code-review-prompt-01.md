> **INSTRUCTIONS FOR COMET ASSISTANT**
> This file contains 1 Perplexity Deep Research prompt for the Timed Intelligence System project.
> For each prompt below:
> 1. Navigate to perplexity.ai in a new browser tab
> 2. Select **Deep Research** mode (not standard search)
> 3. Copy the full prompt exactly as written — do not truncate or summarise it
> 4. Paste into the search bar and submit
> 5. Wait for the full report to complete before opening the next tab
> Run each prompt in a completely separate tab. Do not combine prompts.
> Save each completed report before closing the tab.

---

## Prompt 1: Comprehensive Code Review & Architecture Assessment — Timed Intelligence System

I am building Timed — a macOS-native cognitive intelligence system for a single C-suite executive. It passively observes how the user works (email, calendar, app usage, keystrokes, voice) and builds a compounding cognitive model using frontier LLMs (Claude Opus 4.6 at max effort, no cost cap). The system uses a 5-tier memory hierarchy (Raw Observations → Daily Summaries → Behavioural Signatures → Personality Traits → Active Context Buffer), a 4-cron nightly Opus reflection pipeline, ONA relationship graph, behavioural prediction (avoidance, burnout, decision reversal), and a morning CIA-PDB-format intelligence briefing. 95 of 120 planned deliverables are implemented. OAuth is now working.

**You have MCP access to the full codebase and planning documents via GitHub.** Ground your entire analysis against the actual code and plans, not hypotheticals.

**Primary repo:** `github.com/ammarshah1n/time-manager-desktop` (branch: `ui/apple-v1-restore`)

Key source paths to read and assess:
- `Sources/Core/Services/` — 40+ service files (MemoryStore, RetrievalEngine, AlertEngine, PlanningEngine, TimeSlotAllocator, EmailSyncService, CalendarSyncService, DataBridge, PrivacyManager, ConsentStateMachine, BOCPDDetector, AvoidanceDetector, BurnoutPredictor, DecisionReversalTracker, CoachingTrustCalibrator, InterruptWindowDetector, ONAGraphBuilder, RelationshipHealthService, DisengagementDetector, EmbeddingService, LocalVectorStore, GracefulDegradation, XPCServiceManager, etc.)
- `Sources/Core/Agents/` — 9 signal agents (AgentCoordinator, AppUsageAgent, KeystrokeAgent, ChronotypeModel, CognitiveLoadIndex, IdleTimeAgent, FirstLastActivityAgent, HealthKitAgent, OuraRingAgent)
- `Sources/Core/Clients/` — GraphClient.swift (489 lines, MSAL OAuth + Graph API), SupabaseClient.swift (764 lines, 20+ operations)
- `Sources/Core/Models/` — Domain models (TimedTask, Tier0Observation, CalendarBlock, EmailMessage, MorningBriefing, etc.)
- `Sources/Core/Ports/` — SignalIngestionPort.swift (protocol)
- `Sources/Features/` — 20 UI feature modules (TimedRootView, TriagePane, TasksPane, PlanPane, DishMeUpSheet, FocusPane, CalendarPane, MorningInterviewPane, MorningBriefingPane, AlertDeliveryView, OnboardingFlow, etc.)
- `Sources/Features/PreviewData.swift` — 587-line file containing ALL domain models (known issue)
- `supabase/functions/` — 21 Edge Functions (_shared/anthropic.ts, nightly-consolidation-full, nightly-consolidation-refresh, generate-morning-briefing, weekly-pattern-detection, weekly-pruning, monthly-trait-synthesis, multi-agent-council, extract-voice-features, thin-slice-inference, pipeline-health-check, bootstrap-executive, classify-email, estimate-time, generate-embedding, generate-profile-card, detect-reply, graph-webhook, renew-graph-subscriptions, parse-voice-capture, generate-daily-plan)
- `supabase/migrations/` — 30 SQL migrations (initial schema through ONA tables, validation gates, TFT views)
- `MASTER-PLAN.md` — Full 120-deliverable phased implementation plan with status
- `BUILD_STATE.md` — Current build state, known issues, architecture status
- `docs/` — 9 architecture documents (00-project-overview through 08-decisions-log)

**Planning vault:** `github.com/ammarshah1n/Timed-Brain` — Obsidian vault with architecture decisions, session logs, and working context. Key files:
- `VAULT-INDEX.md` — navigation index
- `Working-Context/timed-brain-state.md` — current project state
- `06 - Context/` — architectural decisions and context notes

**Core question: Given the full codebase, Edge Functions, database schema, and planning documents — what is the real quality, completeness, and production-readiness of this system, and what are the critical gaps, architectural risks, and integration failures that would prevent it from delivering compounding intelligence to a live user?**

Sub-questions — assess each by reading the actual code, not by inferring from file names:

1. **Memory architecture integrity:** Read `MemoryStore.swift`, `RetrievalEngine.swift`, `LocalVectorStore.swift`, `EmbeddingService.swift`, `DataBridge.swift`, `OfflineSyncQueue.swift`, and the Tier 0-3 + ACB migration files. Is the 5-tier memory hierarchy actually wired end-to-end? Can a Tier 0 observation flow through importance scoring, daily summary generation, pattern extraction, trait synthesis, and ACB assembly without manual intervention? Identify any broken links in the chain.

2. **Nightly pipeline viability:** Read `supabase/functions/nightly-consolidation-full/`, `nightly-consolidation-refresh/`, `generate-morning-briefing/`, `weekly-pattern-detection/`, `weekly-pruning/`, `monthly-trait-synthesis/`, and `_shared/anthropic.ts`. Are the Anthropic API calls correctly structured (model IDs, thinking parameters, batch API usage)? Are the cron schedules realistic for Supabase Edge Function timeout limits? What happens when a pipeline stage fails mid-execution — is there recovery, or does the whole chain break?

3. **Signal-to-intelligence data flow:** Trace the path from `GraphClient.swift` → `EmailSyncService.swift` → `Tier0Writer.swift` → Supabase `tier0_observations` → nightly consolidation → morning briefing. Read each file. Is this path actually connected, or are there stub/placeholder boundaries where real data would stop flowing? Do the same for `CalendarSyncService` and at least two agents from `Sources/Core/Agents/`.

4. **Swift architecture quality:** Assess actor isolation patterns across the services (DataBridge, EmailSyncService, CalendarSyncService, AgentCoordinator, Tier0Writer). Check for: Sendable conformance issues, potential data races, actor reentrancy hazards, retain cycles in closures, proper structured concurrency usage. Read `TimedRootView.swift` (489-line god-view) and assess whether the current state management approach can survive production use or needs refactoring before launch.

5. **Prediction and alert system soundness:** Read `AvoidanceDetector.swift`, `BurnoutPredictor.swift`, `DecisionReversalTracker.swift`, `PredictionGate.swift`, `AlertEngine.swift`, `InterruptWindowDetector.swift`, `CoachingTrustCalibrator.swift`, `BOCPDDetector.swift`. Are the scoring algorithms mathematically sound? Are the thresholds hardcoded or calibratable? What is the false-positive risk when running against real (noisy, sparse) data rather than clean test scenarios? Is the engagement-gated delivery actually gated, or is it a passthrough?

6. **Database schema and Edge Function contract alignment:** Read the 30 migrations in `supabase/migrations/` and cross-reference against the Edge Functions that query those tables. Are there schema mismatches — columns referenced in Edge Functions that don't exist in migrations, or migration tables with no consumer? Is RLS correctly configured for multi-tenant isolation (even though this is single-user, the schema declares RLS)? Are the RPC functions (`compute_degree_centrality`, `compute_relationship_health`, `check_validation_gates`, `compute_weekly_ccr`) correctly defined and callable from the Edge Functions?

7. **Critical gap analysis for go-live:** Given that OAuth now works, what is the minimum set of changes needed to get from current state to a system that can: (a) sync real emails and calendar from a live Outlook account, (b) run the nightly pipeline against that data, (c) produce a real morning briefing, and (d) display it in the app? Produce a numbered checklist of exactly what's missing, broken, or stub-only between current state and that minimal viable loop.

**Output format instructions:**
- For each sub-question, produce a section with: assessment (what the code actually does), verdict (working / partial / stub / broken), specific file:line references for issues found, and recommended fixes ranked by severity.
- Produce a **risk matrix** (table) with columns: Risk, Severity (Critical/High/Medium/Low), Likelihood, Files Affected, Mitigation.
- Produce a **go-live checklist** (numbered) with each item tagged as: [CODE] (needs code change), [CONFIG] (needs configuration), [DEPLOY] (needs deployment), [TEST] (needs manual testing).
- Produce a **dependency graph** showing which components must be wired before others can function.
- Prefer primary sources: Apple Developer documentation, Anthropic API documentation, Supabase documentation, Microsoft Graph API documentation, and peer-reviewed research for any ML/statistical claims. For each major claim about the code, cite the specific file and line.
- Do not speculate. Where the code is ambiguous or you cannot access a file, say so explicitly.
- The output will be used directly by Claude Opus 4.6 (1M context window) as a technical assessment brief. Write with that reader in mind — maximum technical precision, no hand-holding, no consumer-level explanation.

Produce a comprehensive, deeply cited research report — go deep on every sub-question — this output is the primary technical foundation for taking this system from 95/120 deliverables to production-ready.
