/**
 * Timed overnight cognitive OS — T28: REM-phase synthesis task.
 *
 * Cron: 03:30 UTC daily. After the NREM consolidation pass has finished
 * writing extracted entities into Graphiti for the previous day, the REM
 * pass runs the Claude Agent SDK `query()` loop with Opus 4.7 + extended
 * thinking and drives the four canonical REM queries iteratively via tool
 * use:
 *
 *   1. Cross-episode patterns — search_episodes over the last 7 days, cluster
 *      and synthesise.
 *   2. Stated-vs-enacted priority divergence — compare stated priorities from
 *      voice_session_learnings against enacted behaviour in behaviour_events
 *      task completions.
 *   3. Relationship evolution — search_facts on :Entity nodes over time,
 *      detect shifts.
 *   4. Strongest disconfirming evidence — actively search for facts that
 *      contradict the agent's own prior synthesis.
 *
 * When the agent identifies a novel analytical procedure we instruct it to
 * persist that procedure via skill-library-mcp `write_skill` so the skill
 * library compounds month over month.
 *
 * The final assistant text block is the synthesis body; we upsert it into
 * `semantic_synthesis` keyed by (exec_id, date). Every tool_use /
 * tool_result block the agent emits is persisted to `agent_traces` via
 * `traceToolCall` so replay + SFT export are fully covered.
 *
 * Session envelope is opened via `openAgentSession` before the `query()`
 * call and closed via `closeAgentSession` on completion; the session id is
 * also stamped on the `semantic_synthesis` row as the replay key.
 *
 * Pragmatic defaults (documented explicitly — see PR body):
 *   - The Claude Agent SDK exposes `thinking.budgetTokens` (camelCase) rather
 *     than the Messages API `thinking.budget_tokens`. We use the SDK form.
 *   - The SDK `Options` type has no `max_tokens` field; instead the spec's
 *     "max_tokens: 16000" is honoured at the Messages-API layer inside the
 *     SDK. We keep the 12k thinking budget and rely on the SDK/CLI default
 *     for the final response window, which is ≥ 16k for Opus.
 *   - `exec_id` resolution is "single-exec-for-now": we read `YASSER_EMAIL`
 *     and fall back to the oldest executives row if the env var is unset.
 *   - Evidence refs are scraped by regex from any text-block payloads found
 *     in tool_result blocks: `episode:<id>` / `fact:<id>` / `entity:<id>`.
 *     MCP tools that return structured payloads should mint ids in one of
 *     those forms; anything we don't recognise is ignored rather than
 *     stored opaquely.
 */

import { schedules, logger } from "@trigger.dev/sdk";
import { query, type SDKMessage } from "@anthropic-ai/claude-agent-sdk";

import { getSupabaseServiceRole } from "../lib/supabase.js";
import {
  openAgentSession,
  closeAgentSession,
  traceToolCall,
} from "../lib/trace-tool-results.js";

// ---------------------------------------------------------------------------
// Types for SDK stream bookkeeping — kept local so we do not spread the
// @anthropic-ai/claude-agent-sdk surface area across the task tree.
// ---------------------------------------------------------------------------

type AnthropicTextBlock = { type: "text"; text: string };
type AnthropicToolUseBlock = {
  type: "tool_use";
  id?: string;
  name: string;
  input: unknown;
};
type AnthropicToolResultBlock = {
  type: "tool_result";
  tool_use_id?: string;
  content?: unknown;
  is_error?: boolean;
};
type AnthropicBlock =
  | AnthropicTextBlock
  | AnthropicToolUseBlock
  | AnthropicToolResultBlock
  | { type: string; [k: string]: unknown };

// ---------------------------------------------------------------------------
// System prompt — drives the four canonical REM queries.
// ---------------------------------------------------------------------------

const SYSTEM_PROMPT = `You are the REM-phase synthesis engine inside Timed, a cognitive OS for a single C-suite executive. You run once per night, after the NREM consolidation pass has already written raw observations into Graphiti. Your job is NOT to summarise the day. Your job is to find the deepest, most non-obvious patterns about how this executive thinks and operates, grounded entirely in evidence you retrieve via tools.

You MUST iteratively drive the following four queries, calling tools via the connected MCP servers:

  1. Cross-episode patterns. Call search_episodes on graphiti-mcp with a broad prompt covering the last 7 days. Cluster the returned episodes, then synthesise the strongest 3-5 recurring behavioural or cognitive patterns. Do not describe individual events — describe the shape that emerges across them.

  2. Stated-vs-enacted priority divergence. Read voice_session_learnings (via MCP — search_episodes with query="voice session stated priorities") for what the executive said he was prioritising, then compare against enacted behaviour from behaviour_events task completions (search_episodes with query="task completion behaviour_events"). Name the top 3 divergences between stated and enacted priorities. Be specific and cite evidence.

  3. Relationship evolution. Call search_facts on graphiti-mcp for facts attached to :Entity nodes representing people. Look over time. Detect shifts — relationships warming, cooling, becoming transactional, etc. Report only shifts that are directionally supported by 2+ independent facts.

  4. Strongest disconfirming evidence. After producing the above synthesis, YOU MUST actively search for facts that contradict your own conclusions. Call search_facts with queries designed to surface counter-evidence. If you find disconfirming evidence, revise the synthesis. Explicitly note any conclusion that survives contradiction testing and any that you retracted.

When — and only when — you identify a novel analytical procedure you used that would generalise to future REM passes, call write_skill on skill-library-mcp with:
  { title, context_text, procedure_text, precondition_summary }

Do not call write_skill for trivial procedures. Reserve it for genuinely novel analytical moves that compounded your insight.

Output format — this is strict. Your FINAL assistant text block, after all tool use has concluded, must be the full synthesis as prose with four clearly labelled sections:
  # Cross-episode patterns
  # Stated-vs-enacted priorities
  # Relationship evolution
  # Disconfirming evidence and revisions

Cite evidence inline using identifiers of the form episode:<id>, fact:<id>, or entity:<id>. Every non-trivial claim must cite at least one such id. These are the only strings we mine for evidence_refs — untagged assertions are invisible to audit.

You have Opus 4.7 with extended thinking enabled. Think deeply before each tool call. Depth over breadth.`;

// ---------------------------------------------------------------------------
// Env helpers
// ---------------------------------------------------------------------------

function readEnv(key: string): string | undefined {
  const value = process["env"][key];
  return typeof value === "string" && value.length > 0 ? value : undefined;
}

async function resolveYasserExecId(): Promise<string> {
  const sb = getSupabaseServiceRole();
  const email = readEnv("YASSER_EMAIL");

  if (email) {
    const { data, error } = await sb
      .from("executives")
      .select("id")
      .eq("email", email)
      .limit(1)
      .maybeSingle();
    if (error) throw new Error(`executives lookup by email failed: ${error.message}`);
    if (data?.id) return data.id as string;
    logger.warn(
      "rem-synthesis: YASSER_EMAIL set but no matching executives row; falling back to oldest row",
    );
  }

  // Single-exec default: the oldest executives row by created_at.
  const { data, error } = await sb
    .from("executives")
    .select("id")
    .order("created_at", { ascending: true })
    .limit(1)
    .maybeSingle();
  if (error) throw new Error(`executives fallback lookup failed: ${error.message}`);
  if (!data?.id) throw new Error("rem-synthesis: no executives row found");
  return data.id as string;
}

// ---------------------------------------------------------------------------
// Evidence-ref scraper — tagged tokens of the form episode:<id>, fact:<id>,
// entity:<id>.
// ---------------------------------------------------------------------------

const EVIDENCE_REGEX = /\b(?:episode|fact|entity):[A-Za-z0-9][A-Za-z0-9\-_]{3,}\b/g;

function harvestEvidenceFromText(text: string, into: Set<string>): void {
  const matches = text.match(EVIDENCE_REGEX);
  if (!matches) return;
  for (const m of matches) into.add(m);
}

function harvestEvidenceFromValue(value: unknown, into: Set<string>): void {
  if (value == null) return;
  if (typeof value === "string") {
    harvestEvidenceFromText(value, into);
    return;
  }
  if (Array.isArray(value)) {
    for (const v of value) harvestEvidenceFromValue(v, into);
    return;
  }
  if (typeof value === "object") {
    for (const v of Object.values(value as Record<string, unknown>)) {
      harvestEvidenceFromValue(v, into);
    }
  }
}

// ---------------------------------------------------------------------------
// Persist helpers
// ---------------------------------------------------------------------------

async function upsertSemanticSynthesis(args: {
  exec_id: string;
  content: string;
  evidence_refs: string[];
  session_id: string;
}): Promise<void> {
  const sb = getSupabaseServiceRole();
  const { error } = await sb
    .from("semantic_synthesis")
    .upsert(
      {
        exec_id: args.exec_id,
        // CURRENT_DATE in UTC — we key by UTC midnight.
        date: new Date().toISOString().slice(0, 10),
        content: args.content,
        evidence_refs: args.evidence_refs,
        session_id: args.session_id,
        updated_at: new Date().toISOString(),
      },
      { onConflict: "exec_id,date" },
    );
  if (error) throw new Error(`semantic_synthesis upsert failed: ${error.message}`);
}

// ---------------------------------------------------------------------------
// Task body
// ---------------------------------------------------------------------------

export const remSynthesis = schedules.task({
  id: "rem-synthesis",
  cron: "30 3 * * *",
  maxDuration: 900,
  run: async (payload, { ctx }) => {
    logger.info("rem-synthesis starting", { timestamp: payload.timestamp });

    const graphitiUrl = readEnv("GRAPHITI_MCP_URL");
    const graphitiToken = readEnv("GRAPHITI_MCP_TOKEN");
    const skillsUrl = readEnv("SKILL_LIBRARY_MCP_URL");
    const skillsToken = readEnv("SKILL_LIBRARY_MCP_TOKEN");
    if (!graphitiUrl || !graphitiToken) {
      throw new Error(
        "rem-synthesis: GRAPHITI_MCP_URL / GRAPHITI_MCP_TOKEN not set",
      );
    }
    if (!skillsUrl || !skillsToken) {
      throw new Error(
        "rem-synthesis: SKILL_LIBRARY_MCP_URL / SKILL_LIBRARY_MCP_TOKEN not set",
      );
    }

    const execId = await resolveYasserExecId();
    const triggerRunId = ctx.run?.id ?? null;

    const sessionId = await openAgentSession("rem-synthesis", execId, triggerRunId);
    logger.info("rem-synthesis session opened", { session_id: sessionId, exec_id: execId });

    const evidence = new Set<string>();
    const toolUseInputs = new Map<
      string,
      { name: string; input: unknown; started_at: number }
    >();
    let stepIndex = 0;
    let finalText = "";
    let inputTokens = 0;
    let outputTokens = 0;
    let cacheReadTokens = 0;

    try {
      const iterator = query({
        prompt:
          "Begin the nightly REM synthesis pass. Follow the four canonical queries in order. Think deeply between tool calls.",
        options: {
          model: "claude-opus-4-7",
          // The SDK Options type uses `budgetTokens` (camelCase); spec says
          // `budget_tokens: 12000` — same semantic, same 12k budget.
          thinking: { type: "enabled", budgetTokens: 12000 },
          permissionMode: "bypassPermissions",
          allowDangerouslySkipPermissions: true,
          systemPrompt: SYSTEM_PROMPT,
          mcpServers: {
            "graphiti-mcp": {
              type: "http",
              url: graphitiUrl,
              headers: { Authorization: `Bearer ${graphitiToken}` },
            },
            "skill-library-mcp": {
              type: "http",
              url: skillsUrl,
              headers: { Authorization: `Bearer ${skillsToken}` },
            },
          },
          // SDK-isolation — we must NOT load the host's ~/.claude settings
          // when running inside a Trigger.dev container.
          settingSources: [],
        },
      });

      for await (const message of iterator as AsyncIterable<SDKMessage>) {
        if (message.type === "assistant") {
          const blocks = (message.message.content ?? []) as AnthropicBlock[];
          const usage = message.message.usage;
          if (usage) {
            inputTokens += usage.input_tokens ?? 0;
            outputTokens += usage.output_tokens ?? 0;
            cacheReadTokens += usage.cache_read_input_tokens ?? 0;
          }

          for (const block of blocks) {
            if (block.type === "text") {
              const text = (block as AnthropicTextBlock).text ?? "";
              if (text.length > 0) finalText = text;
              harvestEvidenceFromText(text, evidence);
            } else if (block.type === "tool_use") {
              const useBlock = block as AnthropicToolUseBlock;
              if (useBlock.id) {
                toolUseInputs.set(useBlock.id, {
                  name: useBlock.name,
                  input: useBlock.input,
                  started_at: Date.now(),
                });
              }
            }
          }
        } else if (message.type === "user") {
          // The Agent SDK emits a synthetic user message carrying tool_result
          // blocks for each completed tool call. We pair those against the
          // outstanding tool_use blocks to produce traced rows.
          const rawContent = (message.message as { content?: unknown }).content;
          const blocks: AnthropicBlock[] = Array.isArray(rawContent)
            ? (rawContent as AnthropicBlock[])
            : [];
          for (const block of blocks) {
            if (block.type !== "tool_result") continue;
            const resultBlock = block as AnthropicToolResultBlock;
            const useId = resultBlock.tool_use_id ?? "";
            const use = useId ? toolUseInputs.get(useId) : undefined;
            const latencyMs = use ? Math.max(0, Date.now() - use.started_at) : 0;
            const toolName = use?.name ?? "unknown";
            const input = use?.input ?? null;
            const output = resultBlock.content ?? null;

            harvestEvidenceFromValue(output, evidence);

            await traceToolCall({
              session_id: sessionId,
              step_index: stepIndex++,
              tool_name: toolName,
              input,
              output,
              latency_ms: latencyMs,
            });

            if (useId) toolUseInputs.delete(useId);
          }
        }
      }
    } catch (err) {
      await closeAgentSession(sessionId, "failed", {
        input_tokens: inputTokens,
        output_tokens: outputTokens,
        cache_read_tokens: cacheReadTokens,
      }).catch(() => undefined);
      logger.error("rem-synthesis failed", { error: (err as Error).message });
      throw err;
    }

    if (finalText.length === 0) {
      await closeAgentSession(sessionId, "failed", {
        input_tokens: inputTokens,
        output_tokens: outputTokens,
        cache_read_tokens: cacheReadTokens,
      });
      throw new Error("rem-synthesis: agent produced no final text block");
    }

    await upsertSemanticSynthesis({
      exec_id: execId,
      content: finalText,
      evidence_refs: Array.from(evidence),
      session_id: sessionId,
    });

    await closeAgentSession(sessionId, "completed", {
      input_tokens: inputTokens,
      output_tokens: outputTokens,
      cache_read_tokens: cacheReadTokens,
    });

    logger.info("rem-synthesis completed", {
      session_id: sessionId,
      evidence_count: evidence.size,
      final_text_chars: finalText.length,
      input_tokens: inputTokens,
      output_tokens: outputTokens,
      cache_read_tokens: cacheReadTokens,
    });

    return {
      session_id: sessionId,
      exec_id: execId,
      evidence_count: evidence.size,
      final_text_chars: finalText.length,
    };
  },
});
