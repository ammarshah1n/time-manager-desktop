import { query, type SDKMessage } from "@anthropic-ai/claude-agent-sdk";
import { logger, schedules } from "@trigger.dev/sdk";

// See nrem-amem-evolution.ts for rationale: derive Beta types from SDKMessage
// rather than importing from @anthropic-ai/sdk directly. The claude-agent-sdk
// pins 0.81.x while the rest of the trigger package uses 0.91.x, and the two
// BetaMessage shapes differ by one field (`stop_details`).
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
 * T27 -- Nemori-style episode distillation.
 *
 * Runs nightly at 02:45. For each episode added in the last 24 hours:
 *   1. Call `search_facts` to retrieve existing priors about the episode's
 *      subject / entities.
 *   2. Ask Opus to predict the episode's content from those priors alone.
 *   3. Compare prediction with reality and compute a delta -- the pieces
 *      Opus could not have predicted from priors.
 *   4. Call `add_fact` ONLY for that delta, not for facts already implied
 *      by priors. This keeps the knowledge graph dense-but-non-redundant.
 *
 * We don't enumerate episodes in Postgres first -- Graphiti MCP exposes
 * `search_episodes` with a time-range argument, so we tell the agent to
 * scope its own search to the last 24h. If at some point we add a local
 * mirror table, we can pre-enumerate here; for now the agent drives.
 *
 * Traces land in agent_traces via the shared helper; session envelope via
 * openAgentSession / closeAgentSession.
 */

const MODEL = "claude-opus-4-7";
const GRAPHITI_SERVER_NAME = "graphiti";

const SYSTEM_PROMPT = [
  "You are the Nemori distillation pass for Timed, an executive cognitive OS.",
  "",
  "Goal: for every episode added to the Graphiti knowledge graph in the last",
  "24 hours, add only the facts that could NOT have been predicted from the",
  "existing priors. This keeps the graph information-dense.",
  "",
  "Procedure per episode:",
  "  1. Call `search_episodes` with a time filter of the last 24h to obtain",
  "     the list of new episodes. Work through them one at a time.",
  "  2. For each episode, call `search_facts` with the episode's entities to",
  "     retrieve existing priors.",
  "  3. Privately reason: given only those priors, what would you predict",
  "     this episode said? Compare prediction with the actual episode content.",
  "  4. For each fact in the actual episode that you would NOT have predicted",
  "     from priors, call `add_fact` with a `summary` explaining why it was",
  "     surprising.",
  "  5. Skip facts that priors already imply. Do not emit duplicates.",
  "",
  "Leave your reasoning in the tool `summary` arguments so it is captured in",
  "the trace ledger. Stop when no unexplored episodes remain.",
].join("\n");

const USER_PROMPT = [
  "Run the Nemori distillation pass. Process every episode added in the last",
  "24 hours. Stop when you've drained them.",
].join("\n");

async function persistAssistantMessage(args: {
  session_id: string;
  step_index: number;
  message: BetaMessage;
}): Promise<number> {
  let stepIndex = args.step_index;
  const sb = getSupabaseServiceRole();
  const usage = args.message.usage;
  const input_tokens = usage?.input_tokens ?? null;
  const output_tokens = usage?.output_tokens ?? null;
  const cache_read_tokens = usage?.cache_read_input_tokens ?? null;
  const cache_creation_tokens = usage?.cache_creation_input_tokens ?? null;

  const rows = args.message.content.map((block: BetaContentBlock) => ({
    session_id: args.session_id,
    step_index: stepIndex++,
    role: "assistant" as const,
    model: MODEL,
    block_type: classifyBlock(block),
    tool_name: toolNameOf(block),
    content: block as unknown,
    latency_ms: null,
    input_tokens,
    output_tokens,
    cache_read_tokens,
    cache_creation_tokens,
  }));

  if (rows.length > 0) {
    const { error } = await sb.from("agent_traces").insert(rows);
    if (error) {
      throw new Error(`agent_traces insert (assistant) failed: ${error.message}`);
    }
  }
  return stepIndex;
}

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
      stepIndex = await persistAssistantMessage({
        session_id: args.session_id,
        step_index: stepIndex,
        message: msg.message,
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
        logger.info("nemori-distillation agent finished", {
          duration_ms: msg.duration_ms,
          num_turns: msg.num_turns,
          total_cost_usd: msg.total_cost_usd,
        });
      } else {
        logger.error("nemori-distillation agent errored", {
          alert: true,
          result: msg,
        });
      }
    }
  }

  return totals;
}

export const nremNemoriDistillation = schedules.task({
  id: "nrem-nemori-distillation",
  cron: "45 2 * * *",
  maxDuration: 900,
  run: async (_payload, { ctx }) => {
    logger.info("nrem-nemori-distillation starting");

    const mcp_url = process["env"]["GRAPHITI_MCP_URL"];
    const mcp_token = process["env"]["GRAPHITI_MCP_TOKEN"];
    if (!mcp_url || !mcp_token) {
      throw new Error(
        "nrem-nemori-distillation: GRAPHITI_MCP_URL and GRAPHITI_MCP_TOKEN must be set",
      );
    }

    const session_id = await openAgentSession(
      "nrem-nemori-distillation",
      null,
      ctx.run.id ?? null,
    );

    try {
      const totals = await runAgent({ session_id, mcp_url, mcp_token });
      await closeAgentSession(session_id, "completed", totals);
      logger.info("nrem-nemori-distillation done", { session_id, totals });
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
