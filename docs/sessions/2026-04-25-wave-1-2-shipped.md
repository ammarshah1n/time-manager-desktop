# 2026-04-25 — Timed overnight cognitive OS, Wave 1+2 shipped

## TL;DR

- 9 PRs merged to `ui/apple-v1-restore` over ~16 hours.
- All 15 schema migrations applied to Supabase project `fpmjuufefhtlwbfinxlx`.
- Local dev stack live: Neo4j 5.20 + APOC, three TS/Python services on Docker Compose, Trigger.dev v4 dev mode firing crons every minute on this Mac.
- 5 real bugs the parallel reviewers missed were caught at execution time and fixed inline.
- One inference end-to-end smoke proven (real Haiku call → `agent_traces` row landed).
- One temporal-retrieval smoke proven (Cypher as-of-time query returns correct historical truth — the foundation Graphiti relies on).
- All Wave 2 runtime gate items now possible from this Mac; only laptop-off operation needs Cloudflare Tunnel + a Fedora migration (queued in TickTick for the day Ammar arrives in Adelaide).

## What we built

The plan is at `docs/planning-templates/cognitive-os-migration-plan.md` (preserved verbatim — 43 tasks, 5 waves).

### Wave 1 (5 PRs)

| PR | Branch | Tasks | What landed |
|----|--------|-------|------------|
| #1 | `wave1-a1-trigger-scaffold` | 1, 3, 4, 5, 6 | `trigger/` v4 SDK workspace, `inference()` central wrapper with routing table + `agent_sessions`/`agent_traces` writes, `hello-claude` smoke task. |
| #2 | `wave1-a2-graph-infra` | 14, 15, 17, 18 | `services/graphiti/` (Python FastAPI), `services/graphiti-mcp/` (TS, 10 MCP tools, bearer auth), `services/skill-library-mcp/` (TS, 3 tools), `skill_library` migration. |
| #3 | `wave1-a3-schemas-swift` | 19, 20, 21, 23 | `executive_profile`, `recommendation_outcomes`, `briefing_interaction_events` migrations + Swift wiring (OnboardingFlow upsert, MorningBriefingPane per-section capture, SupabaseClient event-type expansion). |
| #4 | `wave1-a4-briefing-patch` | 22 | `generate-morning-briefing` EF emits one `recommendations` row per section + stamps `recommendation_id` back into briefing JSONB; `UNIQUE(briefing_id, section_key)` migration. |
| #5 | `wave1-a5-replay-export-stubs` | 41, 42 | `trigger/scripts/replay.ts` and `export-training-data.ts` CLI stubs with full arg parsing + 28 `TODO(wave2)` markers. |

### Wave 2 (4 PRs, fired by a remote routine at 5:20am ACST)

| PR | Branch | Tasks |
|----|--------|-------|
| #6 | `wave2-b1-server-graph` | 8, 9, 10, 11, 12, 12a, 39 — server-side Graph delta sync (email + calendar), client-credentials auth, ingestion-health watchdog, webhook renewal, `email_sync_driver` flag. |
| #7 | `wave2-b2-nrem-pipeline` | 25, 25a, 26, 27, 32 — NREM extraction via Anthropic Batch API + async consumer, A-MEM evolution, Nemori distillation, idempotent backfill, `batch_jobs` + `graphiti_backfill_watermark` schemas, `trace-tool-results` shared helper. |
| #8 | `wave2-b3-outcome-loop` | 24 — `outcome-harvester` matches `behaviour_events` to `recommendations` by `task_ref` + `content_hash`. |
| #9 | `wave2-b4-rem-synthesis` | 28, 28a, 30 — REM synthesis Opus agent, weekly KG snapshot to Supabase Storage, `briefings.source` column, `semantic_synthesis` UNIQUE upsert. |

Plus the 5 verification fixes (PRs #10–#14): see "Bugs caught" below.

## How we built it

Three reusable patterns came out of this session.

### 1. Parallel-worktree fan-out

For each wave, create N git worktrees off the same base, fan out N agents in a single `Agent` tool message, each with:

- Its own worktree path
- Specific plan-task numbers
- Hard file boundaries (which paths it owns, which it must not touch)
- Pre-assigned migration timestamp slots (or any other resource that could collide)
- Stop-at-gate instruction: build clean, push branch, return summary

We did this 9 times across Wave 1 + Wave 2. The remote routine (a one-off CCR session scheduled for 5:20am ACST when Ammar's quota reset) replicated the same pattern autonomously while Ammar slept.

### 2. Reviewer subagent per PR

For each PR, spawn a separate Opus 4.7 subagent with this framing (`/comet`-style anti-gold-plating, but applied to in-house code reviews):

- The plan is the contract — do NOT second-guess scope.
- Judge: (a) plan faithfulness, (b) correctness, (c) unsanctioned additions.
- Anti-gold-plating applies ONLY to category (c) — never argue plan items are unnecessary.
- Output: `VERDICT [SHIP | FIX-THEN-SHIP | BLOCKER]` + concrete file:line items.

For FIX-THEN-SHIP verdicts, the orchestrating session applied the fixes itself (small, surgical) and re-pushed. We never asked Ammar to apply review feedback.

### 3. Remote routine for autonomous continuation

When Ammar's local quota was running low, we used Claude Code's `/schedule` skill (`RemoteTrigger` API) to create one-time scheduled CCR sessions:

- 5:20am ACST: full Wave 2 execution (4 parallel agents → 4 PRs → reviewed → merged → HANDOFF-wave2.md committed)
- 7:00am ACST: 10-agent validation pass (didn't persist its report — the 5:20 routine had already done the substantive work)

Both fired and completed while Ammar slept. State carried over via the GitHub repo, not via session memory.

## Bugs caught and fixed at execution time

Reviewers parsed code lexically (sqlparse, tsc, structural review) but did not execute against real Postgres / pip / Docker. These five only surfaced when we ran the actual pipeline:

| PR | Bug | Why reviewers missed it |
|----|-----|-------------------------|
| #10 | A1 + A3 both picked migration prefix `20260425000000_*` (suffixes differ but Supabase tracks by version key alone, so the second one fails on `INSERT INTO supabase_migrations.schema_migrations ... ON CONFLICT` duplicate-key) | Reviewers checked syntax + plan-faithfulness, not "would this collide with sibling-PR's version key". Cross-PR collision is invisible during fan-out. |
| #11 | B1's `email_sync_driver.sql` used `'foo ' \|\| 'bar'` inside `COMMENT ON COLUMN ... IS` — Postgres rejects: COMMENT requires a single string literal. | sqlparse accepts the multi-line concat; Postgres doesn't. |
| #12 | Same `\|\|`-in-COMMENT pattern in 3 more places across `email_sync_state.sql` and `harvester_watermarks.sql` (B1+B3). | Same root cause — pattern propagated through one author. |
| #13 | A2's `services/graphiti/requirements.txt` pinned `neo4j==5.20.0`, but `graphiti-core==0.3.14` requires `neo4j>=5.23.0`. Pip refuses to resolve. | No reviewer ran `pip install --dry-run` against the requirements file. |
| #14 | A2's `services/graphiti/app/main.py:31` imported `graphiti_core.cross_encoder.openai_reranker_client.OpenAIRerankerClient` — that path doesn't exist in graphiti-core 0.3.14 (introduced in 0.3.17, became the canonical location later). Container crash-loops on startup. | No reviewer ran `docker build` against the Dockerfile, only structural review. |

**Systemic fix going forward** (added to `BUILD_STATE.md`): pre-merge gate must include `supabase db push --dry-run` against a scratch DB, `pip install --dry-run -r requirements.txt`, `docker build` for every Dockerfile in the diff, and a cross-PR migration-version-collision audit when multiple PRs touch `supabase/migrations/`.

## Infrastructure stack added

### New runtimes

| Runtime | Why | Lives at |
|---------|-----|----------|
| **Trigger.dev v4** (was v3 in the plan; v4 is the stable channel of the v3 runtime) | Cron orchestration, retries, structured task logs, dev-mode local execution. | `trigger/` (pnpm workspace member). Cloud project `proj_vrakwmzenqmmhrzhfqyl` under `ammar@facilitated.com.au`. |
| **Neo4j 5.20-community + APOC 5.20** | Temporal knowledge graph for Graphiti episodes/facts. | `neo4j-timed` Docker container, ports 7474 + 7687, volume `~/neo4j-timed-data`. |
| **graphiti-core 0.11.6** | Episode/entity extraction + temporal fact model. | `services/graphiti/` Python FastAPI service in `timed-graphiti` Docker container. |
| **MCP HTTP servers** (`@modelcontextprotocol/sdk@1.29.0` Streamable HTTP transport, stateless sessions, bearer auth) | Tool surface for Claude Agent SDK loops in NREM/REM tasks. | `services/graphiti-mcp/` (10 tools) and `services/skill-library-mcp/` (3 tools), both Node containers. |
| **Voyage `voyage-3` embeddings** | 1024-dim embeddings for tier-0 observations and skill-library retrieval (matches `skills.embedding VECTOR(1024)` HNSW index). | Used by `skill-library-mcp` and graphiti-python's embedder slot. |

### New schema (15 migrations applied)

Wave 1: `agent_sessions`, `agent_traces`, `executive_profile`, `recommendations`, `recommendation_outcomes`, `briefings.sections_interacted`, `recommendations` UNIQUE constraint, `skills` (vector, HNSW).

Wave 2: `executives.email_sync_driver`, `email_sync_state`, `graph_subscriptions`, `calendar_observations.graph_event_id`, `batch_jobs`, `graphiti_backfill_watermark`, `harvester_watermarks`, `semantic_synthesis` (UNIQUE(exec_id, date)), `briefings.source`, `kg_snapshots`.

### New SDKs in the trigger workspace

`@anthropic-ai/sdk@^0.91.0`, `@anthropic-ai/claude-agent-sdk@^0.2.119`, `@modelcontextprotocol/sdk@^1.29.0`, `@supabase/supabase-js@^2.104.1`, `@trigger.dev/sdk@^4.4.4`, `zod@^4.3.6` (forced by Claude Agent SDK's hard peer; both Anthropic SDK and Trigger.dev SDK accept v4).

### Key architectural decisions made during execution

1. **Trigger.dev v4 over v3**: v4 is the stable channel of the v3-generation runtime. `machine` field replaces older `defaultMachine`. No semantic difference for our usage.
2. **`cache_control: ephemeral` on the final system block, not the message** (Anthropic API contract — block-level cache_control). A1 retrofitted this in `inference.ts` early, ahead of plan task 31.
3. **Tool-result tracing helper as a shared file**: B2 and B4 coordinated on `trigger/src/lib/trace-tool-results.ts` for the user-side `tool_result` blocks that arrive between Claude Agent SDK turns. The single inference() call in A1's wrapper only captures the assistant-side; the helper closes the loop.
4. **`graphiti-mcp` keeps direct Cypher for read paths**, only routes through `services/graphiti` Python for `add_episode` (entity extraction with LLM). This let us validate temporal retrieval without graphiti-python being healthy.
5. **`UNIQUE(briefing_id, section_key)` shipped in A4's PR rather than as a guard inside the Edge Function** — protects both legacy briefing and Wave 3's `morning-briefing-v2` upsert path with one constraint.
6. **`UNIQUE(exec_id, date)` + `ON CONFLICT DO UPDATE` on `semantic_synthesis`** — Trigger.dev retries are guaranteed to never duplicate the day's synthesis row.

## Local dev stack — running right now

```
docker-compose.local.yml           Defines the three services
  timed-graphiti-mcp               port 8001, healthy, talks to Neo4j directly
  timed-skill-library-mcp          port 8002, healthy, talks to Supabase + Voyage
  timed-graphiti                   port 8000, healthy, graphiti-core 0.11.6
neo4j-timed (standalone)           ports 7474 (browser) + 7687 (bolt), APOC loaded
trigger.dev dev (background)       worker version 20260425.1, project proj_vrakwmzenqmmhrzhfqyl
                                   graph-delta-sync firing every minute, success in <700ms
```

Secrets live in `trigger/.env.local` (gitignored). Tokens for the MCP servers are in `/tmp/timed-tokens.txt` — copy them into Trigger.dev's Production env vars when deploying.

## Lessons (for the next migration)

1. **Pre-assign migration timestamp slots before fanning out.** Don't tell parallel agents "pick a unique timestamp" — they can't see each other.
2. **Add a real-Postgres + real-Docker pre-merge gate.** Lexical SQL parsing and tsc are not enough. PRs #10–#14 each cost a fix-roll-forward cycle that a 30-second integration check would have prevented.
3. **Reviewer prompts should default to "execute, don't just read."** When a SQL file or Dockerfile is in the diff, the reviewer should run `psql --check` / `pip install --dry-run` / `docker build` and report exit codes.
4. **Remote routines are excellent for unattended continuation but need self-contained prompts.** Ours worked because we inlined the full plan + all task specs. The 7am validator routine fired but did not commit a report — possibly because it didn't have a clear "you must produce a file" assertion. Future validators should have an explicit failure mode if no artifact lands.
5. **Trigger.dev `dev` mode + a hard-fail `defineConfig` can fight each other.** When `trigger.config.ts` reads `TRIGGER_PROJECT_REF` at import time and throws if absent, the c12 config loader runs before the SDK loads `.env.local`. Source the env explicitly (`set -a && source .env.local && set +a`) or move the env-read into a lazy function.

## What's next

Already on TickTick:

- **Migrate Neo4j + Graphiti to Fedora MBP** when in Adelaide (Apr 27): `neo4j-admin database dump` → scp → `database load`, then Cloudflare Tunnel for `bolt+s://` reachability so Trigger.dev cloud workers can dial in. Free, no Fly.io spend.
- **Trigger.dev cloud production deploy** once the tunnel is live: `trigger deploy` from `trigger/`, paste the env vars from `.env.local` into the Production environment via the Trigger.dev dashboard.

Not yet on TickTick (but should be):

- Build `Task 16 graphiti-smoke` Trigger.dev task — adds 3 episodes at 3 timestamps, sets up conflicting facts, invalidates one, asserts `search_facts(valid_at=T)` returns the right historical truth across all three. The Wave 1 gate's "graphiti-smoke green" remains TBD because A2 deferred it. Easy to add — direct cypher version already proven.
- Wave 3 onwards (briefing migration + cutover, weekly synthesis + asymmetric critic, monthly trait synthesis, edge function deletion) waits on Wave 2 runtime gate (3 nights of clean NREM+REM with `cache_read_tokens > 0`). Can't fire that until production deploy lands.

## References

- Original plan (preserved verbatim): `docs/planning-templates/cognitive-os-migration-plan.md`
- Meta-prompt for generating similar plans: `docs/planning-templates/META-PROMPT.md`
- HANDOFF-wave2.md (committed by the 5:20am routine at the repo root)
- All 14 PRs: `gh pr list --state merged --base ui/apple-v1-restore --limit 14`
