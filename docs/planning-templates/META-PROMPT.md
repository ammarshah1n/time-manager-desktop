# Meta-prompt — generate a migration plan in the same shape as `cognitive-os-migration-plan.md`

> Paste this prompt into Perplexity Pro Search (or any frontier model) along with the FILL-IN block, and you'll get back a plan that an orchestrator session can fan out to parallel subagents without further refinement.
>
> The example output that proved this template: `cognitive-os-migration-plan.md` in this folder. Keep that file open in another tab while you read the prompt — every clause below maps to a structural choice you can see in the example.

---

## The prompt

You are a senior staff engineer producing an implementation plan for a non-trivial migration. The downstream consumer of this plan is an orchestrator that fans out parallel subagents — each subagent reads its assigned tasks and executes them in one PR each, without further clarification. Your plan must therefore be concrete, dependency-ordered, and parallelisable. It is the contract between the orchestrator and every subagent.

### Inputs (use these to ground every decision)

```
PROJECT:                 [name + 1-line description]
CURRENT STATE:           [what runs today, infrastructure, what's blocked. ~150 words. Be specific — name files, services, tables, cron jobs.]
THE GAP:                 [what's missing or limiting. Tie each item to an observable failure mode (e.g. "laptop-off operation breaks email sync", "no replay possible because tool-result blocks aren't persisted"). ~100 words.]
TARGET ARCHITECTURE:     [bullets — new components, the data path, what's preserved. Cite research/tools where applicable. e.g. "Graphiti temporal KG", "Stanford Generative Agents-style reflection", "Voyager skill library", "Reflexion feedback loop", "Anthropic Batch API for bulk no-tool passes".]
HARD CONSTRAINTS:        [non-negotiables — cost, latency, vendor, data residency, compliance, deployment shape, single-tenant vs multi-tenant.]
PARALLEL BUDGET:         [how many subagents the orchestrator can run in parallel. Default 4–6.]
TIMEZONE / OPERATIONAL:  [user's local timezone, expected uptime, on-call posture. e.g. "Australia/Adelaide, single user, laptop may be off overnight, paging acceptable".]
RESEARCH GROUNDING:      [paper / product references that inform the architecture. The plan should cite these inline at the points where they shape decisions.]
```

### Output structure (mandatory — match exactly)

#### 1. Context (one paragraph, ~150 words)

Restate CURRENT STATE → THE GAP → the migration target → what stays live during cutover. This is the only narrative section. Everything below is structured.

#### 2. Critical files / surfaces touched

Three buckets, named verbatim:

- **New:** every new file, service, app registration, third-party project. Group by location.
- **Reused:** existing files/tables/EFs whose behaviour is preserved. Especially highlight anything that runs in parallel with new code during a cutover.
- **Retired post-cutover:** the kill list. Be exhaustive. Every retired EF / table / column must have a successor named in the new bucket.

#### 3. Tasks — numbered, dependency-ordered

Each task must:

- Be implementable in **one PR by one subagent**.
- Name **paths**, **function signatures**, **env var names**, **cron expressions**, **schemas** (column names + types + indexes).
- State **idempotency requirements** explicitly when the task is retry-able. Mention `ON CONFLICT DO UPDATE`, watermarks, content-hash pre-checks where appropriate.
- Cite the research grounding at the *point* where it shapes the decision (not in a footnote).
- Use sub-numbers (e.g. `12a`) when one task spawns a tightly coupled companion — this signals to the orchestrator that they belong to the same subagent.

Avoid:

- High-level tasks ("integrate with X"). Decompose into concrete file edits.
- Tasks that depend on knowledge the subagent won't have. Inline the relevant API shape if the agent is likely to guess wrong.
- Optional steps ("if you want, also do Y"). Either it's required or it's a future task.

#### 4. Parallel Execution Map (the critical-path analysis)

Group the tasks above into **waves**. A wave is the largest set of tasks that can run in parallel without cross-dependencies. Each wave is gated by the previous wave's completion.

For each wave, table-format with these columns:

| Agent | Track | Tasks | Worktree | Deliverable |
|---|---|---|---|---|

- **Agent** is a stable handle (`A1`, `B3`, etc.) that the orchestrator passes to the subagent for branch naming.
- **Track** is a 1–3 word descriptor of what the agent owns.
- **Tasks** is a comma-separated list of task numbers.
- **Worktree** is the suggested directory name.
- **Deliverable** is the specific assertion that says "this agent is done" — must be testable.

After the table, state the **wave gate** — the cross-agent assertions that must hold before the next wave fans out.

After all waves, an **Orchestration notes** section listing:

- Resource-collision rules. Migration timestamp slots. Branch naming. File-level boundaries (which agent owns which directory). Cross-PR concerns the parallel reviewers won't catch.
- Append-only invariants on shared state.
- Whether wave-N agents need real cloud credentials or can stop at code-complete.

#### 5. Verification — per-task acceptance criteria

For every task whose output is observable in production, write a single-line assertion the orchestrator can run after merge:

- SQL queries with concrete predicates: `SELECT count(*) FROM X WHERE created_at > now() - interval '1 hour'`
- Curl checks with expected status codes
- Trigger.dev / cron log assertions: "task fires every minute, completes in <Xms"
- End-to-end behaviours: "disconnect the Mac for 24h, paging fires within 15 min"

Plus an **Ongoing SLO** section: what crosses the threshold for paging.

### Forbidden moves

- **No timeline-based planning.** Don't say "week 1: foo, week 2: bar". Use dependency-ordered waves where a wave fires when its predecessor's gate is green, regardless of wall time.
- **No vague tasks.** "Build the integration layer" is not a task. "Implement `trigger/src/lib/graph-app-auth.ts` — client-credentials acquisition against {url}, in-memory cache per tenant, 5-min pre-expiry refresh, 401-forced refresh" is.
- **No optional features in the main plan.** Either it's a numbered task or it's deferred to a follow-up plan.
- **No padding.** If a wave has only one agent, it's a wave of one. Don't invent siblings.

### Quality bars (the plan must satisfy these — score yourself before responding)

1. Could a subagent execute task N reading only that task plus its assigned task list? (If they need to read sibling tasks, decompose further.)
2. Could the orchestrator predict merge conflicts from the file-level boundaries alone? (If two agents touch the same directory or migration prefix, mark it as a coordination point.)
3. Is every retry-able write idempotent by design, not by hope?
4. Could a Reviewer subagent decide SHIP vs FIX-THEN-SHIP using only the verification criteria? (If they need to interpret intent, the criteria are too vague.)
5. Could the user, six months later, reconstruct the original intent from this document alone?

### One worked example to anchor on

The Timed overnight cognitive OS migration, 43 tasks, 5 waves, executed 2026-04-24 → 2026-04-25 across 9 PRs without scope creep. Available at `cognitive-os-migration-plan.md` next to this prompt. Mimic the structural moves in that example, not the topic.

---

## How to use this in practice

1. Fill in the inputs block above.
2. Paste prompt + filled-in inputs into Perplexity (or Claude / GPT / whichever).
3. Read the response. Score it against the five quality bars above.
4. Iterate on the inputs (usually CURRENT STATE and TARGET ARCHITECTURE need 1–2 rewrites) until the response passes all five.
5. Save the final plan to `~/.claude/plans/<slug>.md`.
6. Hand it to an orchestrator session (`/prime` then read the plan, fan out Wave 1 in parallel, review, merge, advance to Wave 2).
7. The orchestrator pattern lives in `docs/sessions/2026-04-25-wave-1-2-shipped.md` if you need a worked example of the execution side.
