# Cognitive OS Migration — worked example

> This is the Timed overnight cognitive OS migration plan, preserved verbatim. We executed it 2026-04-24 → 2026-04-25 across two parallel waves of subagents and shipped 14 PRs without major scope creep. **Use it as the example output when you give the meta-prompt at `META-PROMPT.md` to Perplexity for a different migration.**
>
> What makes this plan good (notice the structural moves):
>
> 1. **Context paragraph names the gap concretely** — "10+ sync Edge Functions ... no tool-calling, no temporal knowledge graph, no feedback loop, no deterministic replay". Not vague.
> 2. **File surfaces are tabulated three ways**: New / Reused / Retired. Reviewers and agents both need this map.
> 3. **Tasks are implementable, not high-level.** Each task has paths, function signatures, env vars, cron expressions, schemas, idempotency requirements. An agent can execute a task in one PR.
> 4. **Research grounding is named inline** (Stanford Generative Agents — Park et al. 2023, Voyager skill library, Reflexion, Nemori, A-MEM). The plan is opinionated about *why* the architecture looks the way it does.
> 5. **Parallel Execution Map is the killer feature.** 43 tasks across 5 waves with explicit fan-out: Wave 1 has 5 parallel agents, each with a track name, task numbers, worktree path, and deliverable. Gate condition between waves is unambiguous.
> 6. **Verification is per-task, not per-feature.** Each acceptance criterion is an assertion you can run (`SELECT count(*) FROM agent_traces WHERE session_id = ...`, "disconnect the Mac for 24h, paging must fire within 15 min").
> 7. **Engineering tradeoffs are spelled out** — AuraDB Pro vs Fly Neo4j with cost+capacity reasoning; sync vs Anthropic Batch API; prompt-deterministic vs KG-state-deterministic replay modes.
> 8. **Idempotency is mandated, not assumed.** Backfill watermarks, `episode_exists(content_hash)` pre-checks, `UNIQUE` + `ON CONFLICT DO UPDATE` on every retry-able write.

---

# Timed — Overnight Cognitive OS Implementation Plan

## Context

Timed's overnight reflection pipeline today runs as 10+ sync Edge Functions (each 30–120s) with no tool-calling, no temporal knowledge graph, no feedback loop, no deterministic replay, and — crucially — Graph email/calendar sync driven by the Swift client's MSAL delegated tokens, which breaks when the Mac is off. Embedding generation is disabled; tier1–3 tables have embedding columns but no writer; ONA relationship graph is populated only for email dyads by Swift; all reasoning is single-shot prompting against a pre-assembled context. This is a ceiling on intelligence quality.

This plan migrates the reflection layer to a heterogeneous runtime (Trigger.dev v3 tasks + Claude Agent SDK for agentic passes, Anthropic Batch API for bulk no-tool passes, Edge Functions only for short ingestion) on top of a Graphiti temporal knowledge graph exposed via self-hosted MCP, with A-MEM link evolution, Nemori predict-calibrate distillation, a Voyager-style skill library, a Reflexion feedback loop grounded in recommendation-outcome pairs, and an asymmetric-critic pass on weekly strategic synthesis. Every inference call — prompts, tool calls, tool results, thinking blocks, token accounting — is recorded in Postgres so any nightly run can be replayed deterministically and the trace corpus can later be used for supervised fine-tuning of a local inference layer. The laptop-off problem is solved by migrating Graph sync to Entra ID client-credentials with a server-driven delta loop.

## Critical files / surfaces touched

- **New:** `trigger/` project (TypeScript, Trigger.dev v3), `trigger/src/inference.ts`, `trigger/src/lib/graph-app-auth.ts`, `trigger/scripts/replay.ts`, `trigger/scripts/export-training-data.ts`
- **New Fly.io services:** `graphiti-mcp`, `skill-library-mcp` (can share a container), Graphiti core + Neo4j (or AuraDB)
- **New Supabase migrations:** `20260425_agent_traces.sql`, `20260426_skill_library.sql`, `20260427_executive_profile.sql`, `20260428_recommendation_outcomes.sql`, `20260501_drop_legacy_reflection_crons.sql`, plus a `semantic_synthesis` table and `briefings.source`/`recommendations` changes
- **New Entra ID app:** `Timed-Server-Graph` (application permissions, not delegated)
- **Swift edits:** `Sources/Features/Onboarding/OnboardingFlow.swift` (write-through), `Sources/Features/Morning/MorningBriefingPane.swift` (per-section interaction capture), `Sources/Core/Services/SupabaseClient.swift` (`insertBehaviourEvent` extended), `Sources/Core/Services/EmailSyncService.swift` (driver gating), `Sources/Core/Services/Tier0Writer.swift` (unchanged initially; retired post-cutover)
- **Reused:** `supabase/functions/_shared/anthropic.ts` (retry+backoff logic ported into new inference wrapper), existing `briefings`, `behaviour_events`, `executives`, `email_messages`, `calendar_events`, `ona_nodes`, `ona_edges` tables (kept live during parallel run)
- **Retired post-cutover:** `supabase/functions/nightly-phase1|phase2|consolidation-full|consolidation-refresh`, `generate-morning-briefing`, `weekly-strategic-synthesis`, `weekly-pruning`, `weekly-pattern-detection`, `multi-agent-council`, `acb-refresh`, `monthly-trait-synthesis`, `poll-batch-results`

## Tasks

1. Scaffold a Trigger.dev v3 TypeScript project at `trigger/` in the repo (pnpm workspace member, `trigger.config.ts` with `runtime: "node"`, logger retention set to store structured logs). Link to a new Trigger.dev organization.
2. Configure Trigger.dev secrets: `ANTHROPIC_API_KEY`, `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`, `VOYAGE_API_KEY`. Verify via `trigger.dev deploy --dry-run`.
3. Install `@anthropic-ai/sdk`, `@anthropic-ai/claude-agent-sdk`, `@modelcontextprotocol/sdk`, `@supabase/supabase-js`, `zod` in the Trigger.dev project.
4. Write migration `20260425_agent_traces.sql` creating `agent_sessions` (id, task_name, trigger_run_id, exec_id, started_at, completed_at, status, prompt_hash, context_hash, total_input_tokens, total_output_tokens, total_cache_read_tokens) and `agent_traces` (id, session_id FK, step_index, role, model, block_type ENUM[text|thinking|tool_use|tool_result], tool_name, content JSONB, latency_ms, input_tokens, output_tokens, cache_read_tokens, cache_creation_tokens, created_at). Indexes on `(session_id, step_index)` and `(task_name, started_at DESC)`.
5. Implement `trigger/src/inference.ts` — a central `inference({ model_alias, messages, system, tools, thinking, mcp_servers })` function that (a) resolves `model_alias` through a routing table with values `opus_synthesis`, `opus_critic`, `opus_briefing`, `sonnet_extract`, `sonnet_estimate`, `haiku_classify`, (b) ports retry + exponential backoff from `supabase/functions/_shared/anthropic.ts`, (c) writes every text/thinking/tool_use/tool_result block to `agent_traces` with token accounting, and (d) returns the parsed Anthropic response. All future model routing changes (local fine-tune) require editing only the routing table.
6. Write a trivial Trigger.dev task `hello-claude` that calls `inference({ model_alias: "haiku_classify", ... })`, verifies a `agent_sessions` + `agent_traces` row set, and asserts token fields are populated. Deploy + run manually.
7. Register Entra ID application `Timed-Server-Graph` in the tenant: add **application** permissions `Mail.Read` and `Calendars.Read` (not delegated). Grant admin consent. Create client secret (24-month expiry). Record `MSFT_APP_CLIENT_ID`, `MSFT_APP_TENANT_ID`, `MSFT_APP_CLIENT_SECRET` in Trigger.dev secrets.
8. Implement `trigger/src/lib/graph-app-auth.ts` — client-credentials token acquisition against `https://login.microsoftonline.com/{tenant}/oauth2/v2.0/token` with `scope=https://graph.microsoft.com/.default`, in-memory cache keyed by tenant, 5-minute pre-expiry refresh, 401-triggered forced refresh.
9. Implement Trigger.dev scheduled task `graph-delta-sync` (cron `*/1 * * * *`): for each row in `executives`, load delta_link from `email_sync_state`, call `GET /users/{exec_email}/messages/delta` with application token, upsert into `email_messages`, advance delta_link; handle `410 Gone` by resetting delta and running a bounded full re-sync (last 30 days).
10. Implement Trigger.dev scheduled task `graph-calendar-delta-sync` (cron `*/5 * * * *`) — analogous to #9 against `/users/{exec_email}/calendarView/delta`, upsert into `calendar_events`.
11. Add column `email_sync_driver TEXT CHECK IN ('client','server') DEFAULT 'client'` to `executives`. Both client-side `EmailSyncService` and server-side #9 run in parallel for 48h; server writes tag messages with `synced_by='server'` in a temp audit column for diff.
12. Verify zero drift from #11 via SQL diff; flip Yasser's `email_sync_driver` to `server`. Update `EmailSyncService.startPolling()` in Swift to no-op when `email_sync_driver='server'` (fetched via DataBridge). Ship a new Swift build.
12a. Implement Trigger.dev scheduled task `ingestion-health-watchdog` (cron `*/15 * * * *`): SELECT MAX(received_at) FROM email_messages WHERE profile_id=$yasser AND MAX(start_time) FROM calendar_events; if either has not advanced in > 90 min during business hours (user's work_hours_start–work_hours_end from executive_profile) or > 8h overall, trigger Trigger.dev alert to Ammar's configured destination (email + SMS via Trigger.dev's alert webhook + PagerDuty integration). Also scans `agent_sessions` for any `status='failed'` in the last 24h and pages the same way. Without this, laptop-off operation has no failure-surface — the nightly pipeline would silently process stale data.
13. Provision Neo4j with persistence guarantees from day one — **do not use AuraDB Free** (200k node / 400k relationship cap will be hit inside 12 months for a compounding single-exec KG). Either (a) Neo4j AuraDB Professional (≈$65/mo, managed backups, no node cap issue at single-user scale) or (b) a Fly.io machine running `neo4j:5.20-community` with 4GB RAM + 50GB persistent volume + nightly volume snapshot. Save `NEO4J_URI`, `NEO4J_USER`, `NEO4J_PASSWORD` to Trigger.dev secrets.
14. Deploy Graphiti (`getzep/graphiti` Python package) as a Fly.io service: Docker image wrapping Graphiti client, configured with Neo4j connection from #13. Use Sonnet via the centralized inference wrapper for internal entity extraction (override Graphiti's default OpenAI settings via environment variables).
15. Build `graphiti-mcp` MCP server (TypeScript, shipped as a Fly.io HTTP service with bearer auth using `GRAPHITI_MCP_TOKEN`): tools `search_episodes(query, time_window)`, `search_facts(query, valid_at)`, `get_entity_timeline(entity_id)`, `get_entity_relationships(entity_id, depth)`, `add_episode(content, timestamp, entity_refs, content_hash)`, **`episode_exists(content_hash)`** — returns episode_id or null, mandatory for backfill/retry idempotency since Graphiti does not natively dedupe on external identifiers, `add_fact(subject, predicate, object, valid_from, valid_to, evidence_episode_ids)`, `invalidate_fact(fact_id, reason, invalidated_at)`, `list_communities()`, **`export_snapshot(session_id)`** — dumps current Neo4j database via `apoc.export.json.all` to Supabase Storage bucket `kg-snapshots/` keyed by session/week, consumed by the forensic replay mode in task 41.
16. Trigger.dev smoke task `graphiti-smoke`: add three synthetic episodes at three different timestamps, add conflicting facts across them, invalidate one, assert that `search_facts(valid_at=T)` returns the correct historical truth. Fails the gate if temporal retrieval is wrong.
17. Migration `20260426_skill_library.sql` — table `skills` (id, name, procedure_text, creation_context JSONB, creation_session_id, embedding VECTOR(1024), usage_count INT DEFAULT 0, success_count INT DEFAULT 0, failure_count INT DEFAULT 0, last_used_at, retired_at, retire_reason). HNSW index on `embedding`. Indexes on `(retired_at)`.
18. Build `skill-library-mcp` MCP server (can share Fly container with `graphiti-mcp`): tools `retrieve_skills(context_text, top_k)` (embeds context via Voyage voyage-3, k-NN in Postgres), `write_skill(name, procedure_text, creation_context)`, `record_skill_usage(skill_id, outcome ENUM[success|failure], session_id, notes)`.
19. Migration `20260427_executive_profile.sql` — table `executive_profile` (exec_id PK ref executives.id, display_name, work_hours_start TIME, work_hours_end TIME, typical_workday_hours NUMERIC, email_cadence_mode SMALLINT, transit_modes JSONB, time_defaults JSONB, pa_email, pa_enabled BOOL, updated_at). Backfill from existing AppStorage `onboarding_*` keys via a one-off script.
20. Edit `Sources/Features/Onboarding/OnboardingFlow.swift` `onComplete` to call a new `SupabaseClient.upsertExecutiveProfile(...)` that writes all extracted fields to `executive_profile`. Keep AppStorage as local cache only.
21. Migration `20260428_recommendation_outcomes.sql` — tables `recommendations` (id, briefing_id FK, section_key, task_ref, content_hash, created_at) and `recommendation_outcomes` (recommendation_id FK, outcome_type ENUM[acted_on|dismissed|ignored|superseded|partial], observed_at, signal_source, raw_signal JSONB). Unique index on `(recommendation_id, outcome_type)`.
22. Temporarily patch the existing `generate-morning-briefing` Edge Function to emit one `recommendations` row per section when it writes to `briefings`; include `recommendation_id` alongside each section in the briefing JSONB so the client can cite it.
23. Extend `BehaviourEventInsert` in `Sources/Core/Services/SupabaseClient.swift` with new `event_type` values `recommendation_acted_on`, `recommendation_dismissed`, `briefing_section_viewed`, `briefing_section_interacted`. In `Sources/Features/Morning/MorningBriefingPane.swift`, capture per-section view, click, act-on, and dismiss gestures; write each to `behaviour_events` and append to `briefings.sections_interacted` JSONB.
24. Implement Trigger.dev scheduled task `outcome-harvester` (cron `0 */4 * * *`): reads `behaviour_events` since last watermark, matches to open `recommendations` by `task_ref` (task_id equivalence) and `content_hash`, writes `recommendation_outcomes`. Tracks a `harvester_watermarks` row for resumability.
25. Implement NREM Trigger.dev scheduled task `nrem-entity-extraction` (cron `0 2 * * *`): loads `tier0_observations` since the previous run, submits an Anthropic Batch API job via `inference()` (Sonnet, no tools, no thinking) with a strict-JSON extraction prompt (episodes, entities, fact triples). Writes one row to new `batch_jobs` table (id, batch_id, submitted_at, kind, status ENUM[pending|ready|consumed|failed], consumed_at, source_session_id). Task exits after submission — does **not** use `wait.for({ minutes: 20 })` because Anthropic Batch API SLA is up to 24h and blocking a Trigger.dev run slot is fragile.
25a. Implement companion scheduled task `nrem-entity-extraction-consume` (cron `*/5 2-8 * * *`): polls Anthropic for every `batch_jobs` row with `kind='nrem-extraction'` and `status='pending'`. If Anthropic reports the batch `ended`, downloads results; for each extracted episode calls Graphiti MCP `episode_exists(content_hash)` first and skips if already present; otherwise calls `add_episode` and `add_fact`; flips `batch_jobs.status='consumed'`. If still running, task exits — next cron tick retries idempotently. If `status` is failed or the batch has been `pending` longer than 26h, writes `status='failed'` and pages via the Trigger.dev alerting path established in task 12a.
26. Implement NREM Trigger.dev task `nrem-amem-evolution` (cron `30 2 * * *`, depends on #25 completion): Claude Agent SDK run with Graphiti MCP bound. System prompt: "for each episode added in the last 24h, call `search_episodes` for top-5 related, decide whether existing facts are contradicted/refined/extended, invalidate or add facts accordingly." Opus with adaptive thinking `medium`. All tool calls traced.
27. Implement NREM Trigger.dev task `nrem-nemori-distillation` (cron `45 2 * * *`, depends on #26): agent-loop over new episodes. For each, call `search_facts` to gather what semantic graph already believes; prompt Opus to predict the episode content from priors; compute the prediction delta; call `add_fact` only for the delta. Writes delta size metrics to `agent_sessions.context_hash`-adjacent columns for observability.
28. Implement REM Trigger.dev task `rem-synthesis` (cron `30 3 * * *`, depends on #27): Claude Agent SDK Opus agent with both Graphiti MCP and skill-library MCP bound. Adaptive thinking `high`, `max_tokens 16000`. System prompt drives four canonical queries (cross-episode patterns, stated-vs-enacted priority divergence, relationship evolution, strongest disconfirming evidence) iteratively via tools. Writes to new `semantic_synthesis` table (id, date, exec_id, content JSONB, evidence_refs JSONB, session_id, created_at) with **`UNIQUE (exec_id, date)` constraint + `ON CONFLICT (exec_id, date) DO UPDATE SET content=EXCLUDED.content, evidence_refs=EXCLUDED.evidence_refs, session_id=EXCLUDED.session_id, updated_at=now()`** so Trigger.dev retries never accumulate duplicates. When the agent identifies a novel analytical procedure, it calls `skill-library-mcp.write_skill(...)`.
28a. Implement post-REM Trigger.dev task `kg-snapshot` (cron `45 3 * * 0` — weekly on Sunday to keep storage bounded; daily is overkill for single-exec): calls `graphiti-mcp.export_snapshot(session_id)` which dumps Neo4j via `apoc.export.json.all` into Supabase Storage `kg-snapshots/` prefixed by ISO week. Retains 52 weekly snapshots. Records `kg_snapshots` table row (session_id, week, storage_path, node_count, rel_count, size_bytes). This is the only mechanism by which `replay.ts --restore-kg` (task 41) can reconstruct historical graph state; without this step, replay is prompt-level only.
29. Implement Integration Trigger.dev task `morning-briefing-v2` (cron `0 5 * * *`, depends on #28): Sonnet drafts briefing sections from `semantic_synthesis` + targeted Graphiti queries via agent loop; Opus reviews + refines + runs the existing adversarial CCR pass. Writes to `briefings` with `source='trigger'`, emits one `recommendations` row per section with `content_hash`.
30. Add a `source TEXT DEFAULT 'legacy'` column to `briefings` + corresponding enum check; legacy Edge Function keeps writing `source='legacy'`, #29 writes `source='trigger'`. Swift client (`MorningBriefingPane`) reads the most recent briefing for the date regardless of source during the parallel run.
31. Retrofit prompt caching in `trigger/src/inference.ts`: detect system prompts ≥1024 tokens and apply `cache_control: { type: "ephemeral" }` to the stable head; confirm `cache_read_tokens > 0` after 3 runs via `agent_traces`.
32. Backfill Graphiti from existing ONA + tier0 state: one-off Trigger.dev task `graphiti-backfill` that iterates existing `ona_nodes` + `ona_edges` + last 90 days of `tier0_observations`, emits synthetic episodes + facts into Graphiti with original timestamps (preserves temporal validity). Idempotency is enforced at two layers: (a) local `backfill_watermark` table tracks last-processed `tier0_observation.id`, so re-runs resume instead of restart; (b) for each episode, the task calls `graphiti-mcp.episode_exists(content_hash)` and skips if the hash is already present in Neo4j — Graphiti does not natively dedupe on external identifiers, so this pre-check is mandatory, not optional. Running the backfill twice must be a no-op.
33. Parallel-run verification gate: for 7 consecutive days, both pipelines run. Build SQL view `briefing_parity` diffing section count, recommendation count, post-delivery engagement_duration_seconds, and executive qualitative tags from a new `briefing_reviews` table (one-field JSONB per day).
34. Cutover migration `20260501_drop_legacy_reflection_crons.sql` once `briefing_parity` shows trigger ≥ legacy on engagement, recommendation coverage, and executive review ≥ 3 consecutive days: `cron.unschedule` for `nightly-phase1`, `nightly-phase2`, `nightly-consolidation-full`, `nightly-consolidation-refresh`, `generate-morning-briefing`, `acb-refresh-morning`, `acb-refresh-midday`, `acb-refresh-evening`, `poll-batch-results`. Edge Function code stays deployed but idle.
35. Implement Trigger.dev task `weekly-strategic-synthesis-v2` (cron `0 2 * * 0`, depends on #28 running ≥ 21 days): Opus agent, `effort: max`, full Graphiti + skill-library MCP access. Prompt includes last 7 days of `recommendation_outcomes` as Reflexion feedback ("here is what the prior cycle got right and wrong"). Writes to `weekly_syntheses` with `source='trigger'`.
36. Implement Trigger.dev task `weekly-asymmetric-critic` (cron `0 3 * * 0`, depends on #35): second Opus agent via `inference({ model_alias: "opus_critic" })`. System prompt: "steel-man the strongest disconfirming case for each claim in the primary synthesis using evidence retrievable from Graphiti." Writes to `weekly_syntheses.critique` column (added via small migration).
37. Implement Trigger.dev task `weekly-skill-pruning` (cron `0 4 * * 0`): reads `skills` rows, retires entries with `success_count / (success_count + failure_count) < 0.5` after ≥ 10 uses OR `last_used_at < now() - 60 days`; writes `retire_reason`.
38. Implement Trigger.dev task `monthly-trait-synthesis-v2` (cron `0 2 1 * *`): equivalent of existing Edge Function with Graphiti access + full trace. Supersedes `monthly-trait-synthesis`.
39. Implement Trigger.dev task `graph-webhook-renewal` (cron `0 */2 * * *`): uses application token to renew Graph change notifications server-side; retires the client-side renewal path once stable.
40. Cutover migration `20260508_drop_weekly_monthly_legacy_crons.sql`: `cron.unschedule` for `weekly-strategic-synthesis`, `weekly-pruning`, `weekly-pattern-detection`, `weekly-avoidance-synthesis`, `monthly-trait-synthesis` after their v2 counterparts run for 2 consecutive cycles.
41. Build deterministic-replay CLI `trigger/scripts/replay.ts` with two explicitly-scoped modes. **(a) `--mode=prompt` (default)**: reads `agent_traces` for the session in order, reconstructs the exact prompt + tool-use trajectory, re-issues each inference() call, diffs outputs against original. This is deterministic at the LLM-input level modulo sampling; it is **not** deterministic at the KG-state level — tool results come from the *current* Graphiti, which has mutated since the original run, so any divergence may be real KG drift rather than a bug. **(b) `--mode=kg-restore --snapshot-week=YYYY-WW`**: locates the `kg_snapshots` row for the snapshot covering the session, restores it into a scratch Neo4j instance (`NEO4J_REPLAY_URI` in secrets), re-points Graphiti MCP at the scratch instance for the replay, then runs the same trajectory. This is the forensic path and is the only mode where KG-state replay is honest. Both modes write a side-by-side diff report to `replays/<session_id>.md` with an explicit header stating which mode was used and what determinism guarantees apply.
42. Build dataset-export CLI `trigger/scripts/export-training-data.ts`: dumps `(system_prompt, user_prompt, tools_available, tool_use_trajectory, final_response, cache_stats)` tuples for a date range as JSONL into Supabase Storage bucket `fine-tuning-corpus`. Preserves the Phase-4 local-model path from the compendium without any current model change.
43. Thirty days after #40 completes without fallback, delete the retired Edge Function directories (`supabase functions delete <name>`) for: `nightly-phase1`, `nightly-phase2`, `nightly-consolidation-full`, `nightly-consolidation-refresh`, `generate-morning-briefing`, `weekly-strategic-synthesis`, `weekly-pruning`, `weekly-pattern-detection`, `weekly-avoidance-synthesis`, `multi-agent-council`, `acb-refresh`, `monthly-trait-synthesis`, `poll-batch-results`. Remove `Sources/Core/Services/ONAGraphBuilder.swift` population call sites (the ONA tables stay read-only as historical reference).

## Parallel Execution Map

The 43 tasks above are dependency-ordered but not serial. Below is the critical-path analysis so independent work can fan out as simultaneous agents in separate git worktrees. Each wave is gated by the **preceding wave's completion**; inside a wave, every track runs in parallel.

### Wave 1 — Foundations (5 parallel agents + 1 manual)

All of these can start simultaneously. No cross-dependencies inside the wave.

| Agent | Track | Tasks | Worktree | Deliverable |
|---|---|---|---|---|
| **A1 — trigger-scaffold** | Trigger.dev + inference + traces | **1, 2, 3, 4, 5, 6** | `wt/trigger-scaffold` | Working Trigger.dev project, `inference()` writing to `agent_traces`, `hello-claude` smoke task green |
| **A2 — graph-infra** | Neo4j + Graphiti + MCP servers | **13, 14, 15** (+ **17, 18**) | `wt/graphiti-mcp` (may live outside repo as its own Fly project) | Graphiti + skill-library MCP servers live on Fly, bearer-auth, HTTP transport |
| **A3 — schemas + swift** | All new migrations + Swift instrumentation | **17, 19, 20, 21, 23** | `wt/schemas-swift` | Migrations merged; Swift client emits per-section interaction events and writes executive_profile |
| **A4 — briefing patch** | Legacy briefing patch for recommendations FK | **22** | `wt/briefing-patch` | `generate-morning-briefing` writes `recommendations` rows and embeds `recommendation_id` per section |
| **A5 — replay + export CLIs** | Long-poll infra scripts (can be built early) | **41, 42** | `wt/trigger-scaffold` (shared with A1) | `replay.ts` and `export-training-data.ts` stubs that read the `agent_traces` schema once #4 lands |
| **Manual — Ammar** | External credential dance | **7, 13-external** | n/a | Entra ID `Timed-Server-Graph` app registered + admin consent; Neo4j AuraDB or Fly Neo4j provisioned; secrets written to Trigger.dev |

Wave 1 gate: A1's smoke task green **and** A2's `graphiti-smoke` task green **and** all Wave 1 migrations merged.

### Wave 2 — Integrated pipelines (4 parallel agents)

All depend on Wave 1 complete. No cross-dependencies inside Wave 2.

| Agent | Track | Tasks | Worktree | Deliverable |
|---|---|---|---|---|
| **B1 — server-graph** | Server-side Graph delta sync + health alerting | **8, 9, 10, 11, 12, 12a, 39** | `wt/server-graph` | Mac-off operation verified end-to-end with paging on failure; `email_sync_driver=server` |
| **B2 — nrem-pipeline** | NREM three-phase reflection + batch consume split | **25, 25a, 26, 27, 32** | `wt/nrem-reflection` | Episodes flowing into Graphiti nightly; A-MEM + Nemori working; batch consumer retries idempotently |
| **B3 — outcome-loop** | Reflexion feedback plumbing | **24** | `wt/outcome-loop` | `outcome-harvester` writing `recommendation_outcomes` rows from behaviour_events |
| **B4 — rem-synthesis + snapshot** | REM Opus agent loop + weekly KG snapshots | **28, 28a, 30, 31** | `wt/rem-synthesis` | `semantic_synthesis` populating nightly with UNIQUE(exec_id,date) upsert; weekly `kg_snapshots` populated for forensic replay |

Wave 2 gate: All NREM + REM runs for 3 consecutive nights with zero `agent_sessions.status='failed'` and `cache_read_tokens > 0` on Opus system prompts.

### Wave 3 — Morning briefing migration + cutover (sequential)

Intentionally serial — cutover must not race itself.

| Agent | Track | Tasks | Deliverable |
|---|---|---|---|
| **C1** | Morning briefing v2 | **29** | `morning-briefing-v2` Trigger.dev task writing `source='trigger'` briefings |
| **C2** | Parallel-run gate | **33** | 7-day `briefing_parity` view green |
| **C3** | Daily cutover | **34** | Legacy daily/ACB crons unscheduled; cutover done |

### Wave 4 — Weekly / monthly / asymmetric critic (3 parallel agents)

All depend on Wave 3 cutover stable for ≥ 21 days.

| Agent | Track | Tasks | Deliverable |
|---|---|---|---|
| **D1 — weekly** | Weekly synthesis + critic + pruning | **35, 36, 37** | v2 weekly cycle live with Reflexion + steel-man critic |
| **D2 — monthly** | Monthly trait synthesis v2 | **38** | `monthly-trait-synthesis-v2` live |
| **D3 — cutover-2** | Weekly/monthly legacy retirement | **40** | Weekly/monthly legacy crons unscheduled |

### Wave 5 — Final cleanup (1 agent, after 30 days stability)

| Agent | Track | Tasks | Deliverable |
|---|---|---|---|
| **E1** | Edge Function deletion + Swift ONA retirement | **43** | Retired Edge Functions deleted; `ONAGraphBuilder` populate path removed |

### Orchestration notes

- **Migrations must use distinct timestamp prefixes.** Each agent that authors a migration picks a unique YYYYMMDDHHMM prefix; no two agents share a timestamp. The migration runner orders by filename, so no collision.
- **Swift edits** in Wave 1 Agent A3 touch disjoint files (`OnboardingFlow.swift`, `MorningBriefingPane.swift`, `SupabaseClient.swift`). No conflict risk.
- **Agent A2 (Fly MCP services)** writes to a **separate repo or subfolder** (`services/graphiti-mcp/`) outside the main Swift repo — zero merge surface with other agents.
- **Each worktree commits to its own branch** (`wave1-<agent>/...`) and opens a PR against `ui/apple-v1-restore` after its gate is green. A human merges the PRs in wave order.
- **Shared state** — `agent_traces`, Graphiti, Trigger.dev project — is append-only during Wave 2 so no concurrent writes corrupt state.
- **Subagent fan-out on approval**: the moment this plan is approved, the main session spawns Wave 1's five Agent-tool calls in a single message (multiple `Agent` tool uses in one turn). Each subagent receives: its worktree path, its assigned task numbers, the shared context (this plan file), and an instruction to commit + push to its branch + stop on its gate.

## Verification

- **After #6:** `SELECT count(*) FROM agent_traces WHERE session_id = <hello-claude session>` returns ≥ 1 with non-null token fields. Deterministic replay primitive confirmed working.
- **After #12 + #12a:** Disconnect the Mac for 24h. `email_messages` and `calendar_events` continue to grow from the server side. Then intentionally break the server sync (revoke the client secret) — `ingestion-health-watchdog` must page within 15 min. Re-enable, confirm paging stops. Laptop-off operation is only truly cleared once the alerting half is verified.
- **After #16:** `graphiti-smoke` Trigger.dev task green across 3 runs, proving temporal retrieval fidelity.
- **After #24:** Manually act on / dismiss a morning briefing section on the Mac; within 4 hours a `recommendation_outcomes` row appears. Manually verify via `psql`.
- **After #29 + #31:** During 3 consecutive nightly runs, `briefings` now has `source='trigger'` rows alongside `source='legacy'`; `agent_traces.cache_read_tokens` > 0 on system-prompt blocks; `semantic_synthesis` is populated.
- **After #33:** `SELECT * FROM briefing_parity WHERE day BETWEEN ... AND ...` — trigger pipeline ≥ legacy on engagement + recommendation coverage for 3 consecutive days.
- **After #34:** `SELECT * FROM cron.job WHERE jobname LIKE 'nightly-%'` returns zero rows; yet next morning the briefing still arrives. Full daily cutover confirmed.
- **After #36:** First Sunday post-#36, `weekly_syntheses` for that week has both a primary synthesis and a non-trivial `critique` column; critique cites specific Graphiti facts by id.
- **After #28a:** First Sunday after #28a is live, confirm `kg_snapshots` row written with non-zero `node_count` and `rel_count`, and that the exported JSON file is downloadable from Supabase Storage and parseable.
- **After #41:** (a) `--mode=prompt` — pick any 7-day-old session_id from `agent_traces`, run the replay, confirm diff report labels any divergence as "prompt-deterministic but KG-state may have drifted"; (b) `--mode=kg-restore` — pick a session from the most recent weekly snapshot window, restore the snapshot into the scratch Neo4j, replay, confirm outputs are byte-identical modulo LLM sampling. If kg-restore diverges beyond sampling noise, the snapshot/restore path is broken.
- **Ongoing SLO:** `agent_sessions` status=completed rate ≥ 99% on daily rollup; any failure page Ammar via Trigger.dev alerting.
