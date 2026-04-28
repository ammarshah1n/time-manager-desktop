---
purpose: Prove every backend integration is wired live end-to-end, not stubbed.
fire: After tonight's 3 deploys land (voice proxies, Trigger.dev, Graphiti backfill)
depends_on: nothing — fire first or in parallel with 2/4/7
---

# Prompt 1 — Backend ↔ Frontend wiring integrity

## Prompt body (paste into Perplexity Deep Research)

Repo: ammarshah1n/time-manager-desktop, branch `unified`. macOS + iOS Swift app (TimedKit) backed by Supabase (project ref fpmjuufefhtlwbfinxlx, 29 Edge Functions), Microsoft Graph (MSAL OAuth), Trigger.dev v4 (deployed tonight), Neo4j + Graphiti on Fedora behind Cloudflare Tunnel. Branch `unified` is the single source of truth.

Audit GOAL: prove every backend integration is wired live end-to-end, not stubbed, and that data actually flows when a user signs in.

Trace these five concrete user journeys hop-by-hop and at every hop answer: "is this live, stubbed, placeholder, or dead?" with file:line citations.

**A) New user signs in** (email/password OR Microsoft) → `AuthService.bootstrapExecutive` → `connectOutlookIfPossible` (cascade shipped 2026-04-28) → `signInWithGraph` → `EmailSyncService.start` + `CalendarSyncService.start` → emails + calendar events arrive → Tier 0 writes happen → embeddings fire (Voyage 1024-dim) → Active Context Buffer (ACB-LIGHT 500-800t) populated → orb voice-llm-proxy can answer "what's in my inbox today" using `search_emails` / `summarise_thread` / `search_graphiti` tools.

**B) Morning Briefing** (5:30 AM Opus 4.6 two-pass adversarial) → `MorningBriefingPane` reachable via `NavSection.briefing` (sidebar entry shipped today) → briefing renders with real Tier 1 daily summary content, not placeholder.

**C) Triage → AlertEngine → AlertsPresenter** (new MainActor bridge) → `AlertDeliveryView` overlay on `TimedRootView` top-trailing edge. Trace what fires an alert and verify the overlay actually mounts.

**D) Capture** (voice or text) → `CaptureAIClient` (Opus 4.6 tool use) → `EmailClassifier.classifyLive` (anthropic-relay → Haiku 4.5, shipped today) → bucket assignment → `DishMeUpPlanItem.bucket` resolves to `TaskBucket.dotColor` for visual rendering.

**E) Nightly engine**: 4 Trigger.dev crons (2 AM consolidation, 5:15 AM refresh, 5:30 AM briefing, Sunday 3 AM pruning) → Tier 1 daily_summaries → Tier 2 behavioural_signatures (4-gate validated) → Tier 3 personality_traits → ACB regen.

For EACH hop produce a row in this table:

| journey | step | file:line | status (LIVE/STUB/PLACEHOLDER/DEAD/UNKNOWN) | what fixes it (no new architecture) | effort | severity |

Also flag any code path where the function name claims "live" but the implementation returns mocked data, returns nil, or short-circuits with a TODO/FIXME comment.

Background already known (do NOT re-research):
- Tonight's deploys (voice proxies, Trigger.dev, Graphiti backfill) ARE the ops backlog. Treat them as "will be live in 30 min" — audit assuming they land successfully.
- Auth cascade, AlertsPresenter, EmailClassifier.classifyLive, MorningBriefingPane sidebar, iOS orb sheet shipped today (commits bcee82b + ec3a7fd).

Hard constraints on suggestions:
- No new architecture. No new services. Wire what exists.
- Timed never acts on the world. Reject any suggestion involving sending email, replying, booking, or contacting anyone.
- Output: a punch list. Each item is a file:line + a one-paragraph fix.
