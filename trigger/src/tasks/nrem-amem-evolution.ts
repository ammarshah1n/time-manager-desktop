import { query, type SDKMessage } from "@anthropic-ai/claude-agent-sdk";
import { logger, schedules } from "@trigger.dev/sdk";

// NOTE: @anthropic-ai/claude-agent-sdk pins @anthropic-ai/sdk@0.81.x while our
// trigger package depends on 0.91.x. The two BetaMessage types drift by one
// field (`stop_details`), so we do NOT import BetaMessage / BetaContentBlock
// from @anthropic-ai/sdk directly here. Instead we derive the exact types
// from SDKMessage, which is sourced from whichever SDK version the agent SDK
// was built against. This keeps us typecheck-clean across both versions.
type AssistantMsg = Extract<SDKMessage, { type: "assistant" }>;
type BetaMessage = AssistantMsg["message"];
type BetaContentBlock = BetaMessage["content"][number];
type BetaToolUseBlock = Extract<BetaContentBlock, { type: "tool_use" }>;

import {
  closeAgentSession,
  openAgentSession,
} from "../lib/trace-tool-results.js";
import { getSupabaseServiceRole } from "../lib/supabase.js";

/**
 * T26 -- AMEM-style knowledge-evolution pass.
 *
 * Runs nightly at 02:30. Binds Opus 4.7 (medium thinking budget, ~5k tokens)
 * to the Graphiti MCP server and asks it to, for each episode added in the
 * last 24 hours:
 *
 *   - call search_episodes to find the top-5 related priors,
 *   - decide whether each newly added fact contradicts, refines, or extends
 *     existing knowledge,
 *   - invalidate contradicted facts via invalidate_fact,
 *   - add clarifying facts via add_fact,
 *   - leave reasoning in the tool arguments themselves.
 *
 * Every SDK message (assistant tool_use block, user tool_result block) is
 * persisted into agent_traces via step_index-ordered inserts so the replay
 * path can reconstruct the exact conversation.
 */

const MODEL = "claude-opus-4-7";
const GRAPHITI_SERVER_NAME = "graphiti";

const SYSTEM_PROMPT = [
  "You are the AMEM evolution pass for Timed, an executive cognitive OS.",
  "",
  "For every episode added to the Graphiti knowledge graph in the last 24 hours:",
  "  1. Call `search_episodes` with the episode content to retrieve up to 5",
  "     related prior episodes.",
  "  2. For each newly-added fact associated with the episode, decide whether it:",
  "       (a) CONTRADICTS an existing fact -> call `invalidate_fact` with the",
  "           contradicted fact's id and a one-sentence reason in `reason`.",
  "       (b) REFINES or EXTENDS existing knowledge -> call `add_fact` with a",
  "           clarifying triple whose `summary` field explains the refinement.",
  "       (c) is already represented -> do nothing.",
  "  3. Prefer evidence-heavy decisions. If uncertainty is high, do nothing.",
  "",
  "Leave your reasoning inside the tool `reason` / `summary` arguments so it",
  "is captured verbatim in the trace ledger. Do NOT produce long free-form",
  "narration outside of tool calls.",
  "",
  "When every recent episode has been processed, stop.",
].join("\n");

const USER_PROMPT = [
  "Run the AMEM evolution pass over every episode added in the last 24 hours.",
  "Work one episode at a time. Stop when you have exhausted them.",
].join("\n");

type ToolUseIndex = Map<string, number>;

/**
 * Per-block handler that writes one agent_traces row for every tool_use /
 * tool_result / text / thinking block emitted by the SDK.
 *
 * Returns the next step_index so the caller can thread it across multiple
 * SDK messages.
 */
async function persistAssistantMessage(args: {
  session_id: string;
  step_index: number;
  message: BetaMessage;
  latency_ms: number | null;
  toolUseIndex: ToolUseIndex;
}): Promise<number> {
  let stepIndex = args.step_index;
  const sb = getSupabaseServiceRole();
  const usage = args.message.usage;
  const input_tokens = usage?.input_tokens ?? null;
  const output_tokens = usage?.output_tokens ?? null;
  const cache_read_tokens = usage?.cache_read_input_tokens ?? null;
  const cache_creation_tokens = usage?.cache_creation_input_tokens ?? null;

  const rows = args.message.content.map((block: BetaContentBlock) => {
    const row = {
      session_id: args.session_id,
      step_index: stepIndex++,
      role: "assistant" as const,
      model: MODEL,
      block_type: classifyBlock(block),
      tool_name: toolNameOf(block),
      content: block as unknown,
      latency_ms: args.latency_ms,
      input_tokens,
      output_tokens,
      cache_read_tokens,
      cache_creation_tokens,
    };
    if (block.type === "tool_use") {
      args.toolUseIndex.set(
        (block as BetaToolUseBlock).id,
        row.step_index,
      );
    }
    return row;
  });

  if (rows.length > 0) {
    const { error } = await sb.from("agent_traces").insert(rows);
    if (error) {
      throw new Error(`agent_traces insert (assistant) failed: ${error.message}`);
    }
  }
  return stepIndex;
}

/**
 * Persist the user-side tool_result blocks returned after each tool_use.
 * The SDK delivers these as an SDKUserMessage with a MessageParam body
 * whose content array mixes tool_result blocks with optional text.
 */
async function persistUserMessage(args: {
  session_id: string;
  step_index: number;
  blocks: unknown[];
}): Promise<number> {
  let stepIndex = args.step_index;
  const sb = getSupabaseServiceRole();

  const rows = args.blocks.map((block) => ({
    session_id: args.session_id,
    step_index: stepIndex++,
    role: "tool" as const,
    model: null,
    block_type: classifyBlockUnknown(block),
    tool_name: null,
    content: block,
    latency_ms: null,
    input_tokens: null,
    output_tokens: null,
    cache_read_tokens: null,
    cache_creation_tokens: null,
  }));

  if (rows.length === 0) return stepIndex;

  const { error } = await sb.from("agent_traces").insert(rows);
  if (error) {
    throw new Error(`agent_traces insert (tool_result) failed: ${error.message}`);
  }
  return stepIndex;
}

function classifyBlock(
  block: BetaContentBlock,
): "text" | "thinking" | "tool_use" | "tool_result" {
  switch (block.type) {
    case "text":
      return "text";
    case "thinking":
    case "redacted_thinking":
      return "thinking";
    case "tool_use":
    case "server_tool_use":
    case "mcp_tool_use":
      return "tool_use";
    default:
      return "text";
  }
}

function classifyBlockUnknown(
  block: unknown,
): "text" | "thinking" | "tool_use" | "tool_result" {
  if (
    typeof block === "object" &&
    block !== null &&
    "type" in block &&
    typeof (block as { type: unknown }).type === "string"
  ) {
    const t = (block as { type: string }).type;
    if (t === "tool_result" || t === "mcp_tool_result") return "tool_result";
    if (t === "thinking" || t === "redacted_thinking") return "thinking";
    if (t === "tool_use" || t === "mcp_tool_use") return "tool_use";
  }
  return "text";
}

function toolNameOf(block: BetaContentBlock): string | null {
  if (block.type === "tool_use") {
    return (block as BetaToolUseBlock).name ?? null;
  }
  if ("name" in block && typeof (block as { name?: unknown }).name === "string") {
    return (block as { name: string }).name;
  }
  return null;
}

type RunTotals = {
  input_tokens: number;
  output_tokens: number;
  cache_read_tokens: number;
};

function accumulateTotals(totals: RunTotals, msg: BetaMessage): void {
  const u = msg.usage;
  if (!u) return;
  totals.input_tokens += u.input_tokens ?? 0;
  totals.output_tokens += u.output_tokens ?? 0;
  totals.cache_read_tokens += u.cache_read_input_tokens ?? 0;
}

async function runAgent(args: {
  session_id: string;
  mcp_url: string;
  mcp_token: string;
}): Promise<RunTotals> {
  const totals: RunTotals = {
    input_tokens: 0,
    output_tokens: 0,
    cache_read_tokens: 0,
  };
  const toolUseIndex: ToolUseIndex = new Map();
  let stepIndex = 0;

  const stream = query({
    prompt: USER_PROMPT,
    options: {
      model: MODEL,
      systemPrompt: SYSTEM_PROMPT,
      thinking: { type: "enabled", budgetTokens: 5_000 },
      permissionMode: "bypassPermissions",
      allowDangerouslySkipPermissions: true,
      mcpServers: {
        [GRAPHITI_SERVER_NAME]: {
          type: "http",
          url: args.mcp_url,
          headers: { Authorization: `Bearer ${args.mcp_token}` },
        },
      },
    } as Parameters<typeof query>[0]["options"],
  });

  for await (const msg of stream as AsyncIterable<SDKMessage>) {
    if (msg.type === "assistant") {
      const latency_ms =
        typeof msg.message.usage?.service_tier === "string" ? null : null; // no per-message ms on SDK
      stepIndex = await persistAssistantMessage({
        session_id: args.session_id,
        step_index: stepIndex,
        message: msg.message,
        latency_ms,
        toolUseIndex,
      });
      accumulateTotals(totals, msg.message);
    } else if (msg.type === "user") {
      const content = msg.message.content;
      const blocks = Array.isArray(content) ? content : [];
      stepIndex = await persistUserMessage({
        session_id: args.session_id,
        step_index: stepIndex,
        blocks,
      });
    } else if (msg.type === "result") {
      if (msg.subtype === "success") {
        logger.info("amem-evolution agent finished", {
          duration_ms: msg.duration_ms,
          num_turns: msg.num_turns,
          total_cost_usd: msg.total_cost_usd,
        });
      } else {
        logger.error("amem-evolution agent errored", {
          alert: true,
          result: msg,
        });
      }
    }
  }

  // Minor lint: toolUseIndex is populated for replay joins in future work.
  void toolUseIndex;
  return totals;
}

export const nremAmemEvolution = schedules.task({
  id: "nrem-amem-evolution",
  cron: "30 2 * * *",
  // Opus + thinking + MCP tool loop -- 15 min hard cap from trigger config.
  maxDuration: 900,
  run: async (_payload, { ctx }) => {
    logger.info("nrem-amem-evolution starting");

    const mcp_url = process["env"]["GRAPHITI_MCP_URL"];
    const mcp_token = process["env"]["GRAPHITI_MCP_TOKEN"];
    if (!mcp_url || !mcp_token) {
      throw new Error(
        "nrem-amem-evolution: GRAPHITI_MCP_URL and GRAPHITI_MCP_TOKEN must be set",
      );
    }

    const session_id = await openAgentSession(
      "nrem-amem-evolution",
      null,
      ctx.run.id ?? null,
    );

    try {
      const totals = await runAgent({ session_id, mcp_url, mcp_token });
      await closeAgentSession(session_id, "completed", totals);
      logger.info("nrem-amem-evolution done", { session_id, totals });
      return { session_id, ...totals };
    } catch (err) {
      await closeAgentSession(session_id, "failed", {
        input_tokens: 0,
        output_tokens: 0,
        cache_read_tokens: 0,
      });
      throw err;
    }
  },
});

