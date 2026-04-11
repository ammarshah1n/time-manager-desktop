# Session Handoff — 2026-04-11 16:15 GMT+2

## Done
- **Phases 0-12 of MASTER-PLAN.md implemented** — 95/120 deliverables complete
- 124 files changed, 27,444 lines added across 2 sessions
- 30 Supabase migrations deployed (15 original + 15 intelligence infrastructure)
- 21 Edge Functions active (9 original + 12 intelligence pipeline)
- 9 signal agents built (email, calendar, app usage, idle, first/last activity, keystroke, HealthKit stub, Oura stub, voice)
- 5-tier memory infrastructure: Tier 0 observations → Tier 1 daily summaries → Tier 2 behavioural signatures → Tier 3 personality traits → Active Context Buffer
- 4-cron nightly pipeline: importance scoring (Haiku+Sonnet), conflict detection, Opus daily summary, ACB generation, self-improvement loop
- Morning briefing: 7-section CIA PDB format, adversarial Opus review, engagement tracking
- ONA relationship graph: centrality metrics, health scoring, disengagement detection (RDI + SWS)
- Prediction layer: avoidance (3-stream), burnout (3 MBI dimensions), decision reversal (4-state HMM)
- Alert system: 5-dimension multiplicative scoring, multi-agent council (3 parallel Opus + leader)
- Privacy: consent state machine, KEK/DEK encryption, data export + cryptographic deletion
- Production: XPC service mesh, graceful degradation, App Nap prevention
- Build: clean (0 errors), 49 tests passing
- Pushed to GitHub: `ammarshah1n/time-manager-desktop` branch `ui/apple-v1-restore`

## Open Decisions
- Should Yasser onboarding happen before or after UI integration pass? MASTER-PLAN.md says immediately after Phase 0.07, but auth flow hasn't been E2E tested yet.
- Should the 5 deferred UI tasks (5.01, 4.08, 11.02, 11.04, MenuBarManager) be bundled into one PR or done incrementally?
- HealthKit (1.11) and Oura (1.12) are stubs — is physiological data still a priority or should it wait until the core pipeline is validated?

## Deferred
- **10.02 Whisper.cpp migration** — requires SPM research (research gap #2), not blocking anything
- **Phase 13 (Month 11+)** — WavLM, vocal biomarkers, multi-modal fusion, TFT — requires 12+ months of data
- **12.03 Sparkle auto-updates** — requires Sparkle SPM + CDN infrastructure
- **12.04 Developer ID signing** — requires Apple Developer certificate
- **11.06 EU AI Act compliance** — documentation/audit task, not code

## Next
**Yasser onboarding** — the single most important next action:
1. Set `ANTHROPIC_API_KEY` in Supabase secrets (unblocks all pipeline verification)
2. E2E test auth flow with real Microsoft credentials (Phase 0.07)
3. Sit with Yasser for 15 minutes: Microsoft OAuth → 3-year backfill begins
4. Once backfill completes: run nightly pipeline manually → verify Tier 1 summaries → generate first morning briefing

---

## What Timed Is

Timed is a **cognitive intelligence system** for one C-suite executive (Yasser Shahin). It passively observes how he works — email patterns, calendar structure, communication rhythms, decision timing — and builds a **compounding model** of how he thinks, decides, avoids, and operates.

**It is NOT a productivity app.** It does not compete with Motion, Sunsama, or any task manager.

**The moat:** Intelligence compounds *structurally*, not volumetrically. Month 6 Timed is qualitatively different from Month 1 because higher-tier memory representations (behavioural signatures, personality traits) are structurally impossible without lower tiers having been built and validated first. No competitor can replicate 6 months of accumulated intelligence by shipping features.

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

## Tech Stack
- **Client:** Swift 6.1 macOS app, actor-based concurrency, StrictConcurrency
- **Backend:** Supabase (Postgres + Edge Functions + Auth + Storage)
- **AI:** Claude Opus 4.6 (nightly engine, briefing, patterns, traits), Sonnet (conflict detection, importance Pass 2), Haiku (importance Pass 1, utility)
- **Embeddings:** Voyage (Tier 0, 1024-dim) + OpenAI text-embedding-3-large (Tier 1-3, 3072-dim)
- **Vector search:** USearch (local HNSW) + pgvector (Supabase backup)
- **Voice:** Gemini 1.5 Pro Audio API (acoustic features), SFSpeechRecognizer (interactive)
- **Distribution:** Direct DMG + Sparkle (not App Store — needs Accessibility API + CGEventTap)

## Repo
- **GitHub:** `github.com/ammarshah1n/time-manager-desktop`
- **Branch:** `ui/apple-v1-restore`
- **MASTER-PLAN.md:** root of repo — full 13-phase build pathway with STATUS tracker
- **Supabase project:** `fpmjuufefhtlwbfinxlx`

---

## Perplexity Deep Research Prompt — Critical Assessment

Use this prompt in Perplexity Deep Research to get an independent critical assessment of the entire build:

```
I've built a cognitive intelligence system called "Timed" for a single C-suite executive. I need you to critically assess my architecture, implementation choices, and identify gaps, risks, and places where I could spend more (or differently) for better results.

## What Timed Is

A macOS app that passively observes how one executive works (email, calendar, app usage, keystrokes, voice) and builds a compounding model of how they think, decide, avoid, and operate. It delivers intelligence through morning briefings (CIA PDB format), real-time alerts (3/day max), and a coaching layer with trust calibration.

NOT a productivity app. NOT a task manager. The moat is that intelligence compounds structurally — higher-tier memory representations are impossible without lower tiers being built first. No competitor can replicate 6 months of accumulated intelligence by shipping features.

## Architecture (5-Tier Memory + 4-Cron Pipeline)

**Memory Hierarchy:**
- Tier 0: Raw observations (email metadata, calendar events, app usage, keystroke timing, voice features) — stored in Supabase, embedded with Voyage (1024-dim)
- Tier 1: Daily summaries — Opus 4.6 with 16K thinking synthesises each day's observations, embedded with OpenAI text-embedding-3-large (3072-dim)
- Tier 2: Behavioural signatures — weekly Opus pattern detection across 7 daily summaries, 4-gate validation (Cohen's d_z ≥ 0.5, test-retest r ≥ 0.6, 2+ contexts, Opus plausibility review)
- Tier 3: Personality traits — monthly Opus synthesis from confirmed signatures, versioned with bi-temporal valid_from/valid_to, cathartic update formula
- ACB: Active Context Buffer — dual document (ACB-FULL 10-12K tokens for Opus calls, ACB-LIGHT 500-800 tokens for Haiku/Sonnet utility), regenerated nightly, injected into every intelligence call

**Nightly Pipeline (4 crons):**
1. Full consolidation (2 AM): Haiku importance scoring → Sonnet uncertain-band rescoring → Sonnet conflict detection → Opus daily summary → Opus ACB generation → Opus self-improvement loop (via Batch API, 50% discount)
2. Morning refresh (5:15 AM): Re-score overnight observations, append to daily summary, refresh ACB with morning calendar
3. Morning briefing (5:30 AM): Two-pass Opus (generation + adversarial review), engagement self-correction trigger
4. Weekly pruning (Sunday 3 AM): Tier 0 archival (>30 days), tombstoning (>365 days), Tier 2 fading

**Signal Agents (9):**
- Email (Graph API delta sync), Calendar (Graph API), App usage (NSWorkspace), Idle time (IOKit), First/last activity (CGEventTap), Keystroke dynamics (CGEventTap — timing only, never key values), Voice features (Gemini 1.5 Pro Audio API), HealthKit (stub), Oura Ring (stub)

**Delivery:**
- Morning briefing: 7 sections (lead insight → calendar intelligence → email patterns → decision observations → cognitive load forecast → emerging patterns → forward-looking), ~610 words, confidence badges, track record display
- Real-time alerts: 5-dimension multiplicative scoring (salience × confidence × timeSensitivity × actionability × cognitiveStatePermit), any zero kills the alert, 3/day cap
- Multi-agent council: 3 specialist Opus agents (energy, priority, pattern) in parallel + leader synthesis for high-stakes moments
- Coaching trust: 4-stage progression (establishment → calibration → working alliance → deep observation), rupture protocol on 3+ consecutive dismissals

**Prediction Layer:**
- Avoidance detection: 3-stream cross-validation (email latency, calendar rescheduling, document engagement), network expansion guard (never flag if expanding)
- Burnout prediction: 17 signals → 3 MBI dimensions, triple gate (3+ weeks, 3+ modalities, 2-of-3 MBI elevated), sprint discriminator
- Decision reversal: 4-state HMM (committed → consolidating → wavering → reversing), healthy reconsideration vs vacillation
- BOCPD change detection: student-t predictive, hazard rate 1/250, CDI threshold 0.65

**Relationship Intelligence (ONA):**
- Graph from email metadata: ona_nodes (7 centrality metrics), ona_edges (directional interactions), relationships (health scoring, RDI, SWS)
- LLM role inference for top-30 contacts (authority tier, relationship type)
- Disengagement detection: RDI 5-dimension composite (response rate decline, latency increase, initiated decline, CC decline, meeting decline)

**Privacy:**
- Consent state machine: DORMANT → CALENDAR_ONLY → CAL_EMAIL → CAL_EMAIL_APPS → FULL_OBSERVATION, with progressive gates (7+ days in state, 60%+ open rate, 1+ insight interacted)
- Client-side encryption: KEK in Keychain, per-data-type DEKs, AES-256-GCM before data leaves device
- Cryptographic deletion: KEK destruction renders all data permanently unrecoverable

**Tech Stack:**
- Swift 6.1 macOS, actor-based concurrency, StrictConcurrency
- Supabase (Postgres + 21 Edge Functions + Auth)
- Claude Opus 4.6 (nightly engine, briefing, patterns, traits), Sonnet (conflict detection), Haiku (importance scoring)
- Dual embeddings: Voyage (Tier 0, 1024-dim) + OpenAI text-embedding-3-large (Tier 1-3, 3072-dim)
- USearch local HNSW + pgvector backup
- ~$100-150/week at maximum intelligence (with prompt caching + Batch API)

**Current State:** 95/120 deliverables implemented. Build clean. 49 tests passing. Remaining ~25 are verification (blocked on live data), UI integration, and Month 11+ features.

## What I Need You To Assess

1. **Architecture gaps:** What's missing from the memory hierarchy, pipeline design, or signal architecture that would limit intelligence quality at Month 6? Are there structural bottlenecks that would be expensive to fix later?

2. **Model routing critique:** Am I using the right model at the right layer? Where could I get better results by upgrading (e.g., Sonnet → Opus for conflict detection) or downgrading (e.g., places where Opus is overkill)? Specifically assess the thinking budget allocations.

3. **Compounding mechanism weakness:** The core thesis is that intelligence compounds structurally. Where is this thesis weakest? What could cause the compounding to plateau or degrade? Are the 4-gate validation and BOCPD sufficient to prevent noise from compounding instead of intelligence?

4. **Embedding strategy:** Is dual-provider (Voyage 1024-dim for Tier 0, OpenAI 3072-dim for Tier 1-3) the right call? Would a single provider with consistent dimensionality be better for cross-tier retrieval? Are there newer embedding models (as of April 2026) that would outperform this setup?

5. **Signal quality vs quantity:** With 9 signal agents, am I capturing the right signals? What high-value signals am I missing? Is keystroke dynamics (IKI, dwell time, backspace rate) actually predictive of cognitive state, or is the research overstated? Same question for voice acoustic features via Gemini.

6. **Prediction layer realism:** Can avoidance detection, burnout prediction, and decision reversal tracking actually work with the data I'm collecting? What's the minimum viable data volume for each? Are my confidence thresholds (0.55 for hypotheses, 0.65 for soft predictions, 0.85 for high-stakes) well-calibrated?

7. **Privacy architecture:** Is Keychain-based KEK management sufficient for a non-sandboxed macOS app? What are the attack surfaces I'm missing? Is the consent state machine overengineered or underengineered for a single-user system?

8. **Cost efficiency:** At ~$100-150/week, am I spending the AI budget optimally? Where would an extra $50/week produce the most marginal intelligence improvement? Where am I wasting tokens?

9. **Philosophy critique:** The design philosophy is "observe, never act" + "intelligence compounds over time" + "no cost cap" + "Opus at every memory-generating layer." Challenge this philosophy. Where does it break down? What would a competing philosophy look like, and why might it produce better results?

10. **What would you do differently?** If you were building this system from scratch with the same constraints (one executive, no cost cap, macOS, compounding intelligence), what architectural decisions would you make differently? What would you add that I haven't thought of?

Please be ruthlessly critical. I'd rather hear about fundamental flaws now than discover them at Month 6 when the memory hierarchy is full of compounded noise. Reference specific research papers, benchmarks, or production systems where relevant.
```
