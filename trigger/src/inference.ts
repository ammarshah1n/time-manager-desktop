import Anthropic from "@anthropic-ai/sdk";
import type {
  MessageCreateParams,
  MessageParam,
  Message,
  Tool,
  TextBlockParam,
  ContentBlock,
  ToolUseBlock,
  ToolResultBlockParam,
  ThinkingConfigParam,
} from "@anthropic-ai/sdk/resources/messages";

import { getSupabaseServiceRole } from "./lib/supabase.js";
import { approxTokens, sha256Hex } from "./lib/hash.js";

// ---------------------------------------------------------------------------
// Routing table
// ---------------------------------------------------------------------------
//
// Model-alias -> concrete Anthropic model ID. Every future model-routing
// change (Opus version bump, local fine-tune redirect, experimental A/B) is a
// diff to this object and nothing else. Call sites only reference the alias.
//
// Aliases follow the plan's call-site semantics (opus_synthesis, opus_critic,
// opus_briefing, sonnet_extract, sonnet_estimate, haiku_classify) with room to
// add more as the pipeline grows.

export type ModelAlias =
  | "opus_synthesis"
  | "opus_critic"
  | "opus_briefing"
  | "sonnet_extract"
  | "sonnet_estimate"
  | "haiku_classify";

// Concrete Anthropic model IDs. Claude Opus 4.7, Sonnet 4.6, Haiku 4.5.
// Opus 4.7 ships as `claude-opus-4-7`; Sonnet 4.6 as `claude-sonnet-4-6`;
// Haiku 4.5 uses the dated identifier `claude-haiku-4-5-20251001`.
const MODEL_ROUTING: Record<ModelAlias, string> = {
  opus_synthesis: "claude-opus-4-7",
  opus_critic: "claude-opus-4-7",
  opus_briefing: "claude-opus-4-7",
  sonnet_extract: "claude-sonnet-4-6",
  sonnet_estimate: "claude-sonnet-4-6",
  haiku_classify: "claude-haiku-4-5-20251001",
};

// Default max_tokens per alias — Opus reasoning passes demand headroom; Haiku
// classification returns a short label. Callers may override via opts.
const DEFAULT_MAX_TOKENS: Record<ModelAlias, number> = {
  opus_synthesis: 16_000,
  opus_critic: 12_000,
  opus_briefing: 12_000,
  sonnet_extract: 4_000,
  sonnet_estimate: 2_000,
  haiku_classify: 1_024,
};

// ---------------------------------------------------------------------------
// Retry + backoff — ported from supabase/functions/_shared/anthropic.ts
// ---------------------------------------------------------------------------

const MAX_RETRIES = 3;
const RETRY_BASE_MS = 1_000;
// Node / Trigger.dev have no 60s wall clock — pick a generous ceiling. Opus
// with extended thinking + tool use can legitimately exceed 5 min.
const FETCH_TIMEOUT_MS = 10 * 60 * 1_000;

// ---------------------------------------------------------------------------
// Public types
// ---------------------------------------------------------------------------

export type McpServerConfig = {
  name: string;
  url: string;
  authToken?: string;
};

export type InferenceOptions = {
  /** Routing-table alias — NOT a raw model ID. */
  model_alias: ModelAlias;
  /** Anthropic messages array. Full multi-turn history. */
  messages: MessageParam[];
  /** Optional system prompt (string or block array). */
  system?: string | TextBlockParam[];
  /** Optional tools (Anthropic tool schemas). */
  tools?: Tool[];
  /** Extended-thinking config. budget_tokens must be < max_tokens. */
  thinking?: ThinkingConfigParam;
  /**
   * MCP server bindings. Currently passed through only for downstream
   * Claude Agent SDK callers; the plain Messages API does not consume them.
   * Surfaced here so `inference()` remains the one integration point.
   */
  mcp_servers?: McpServerConfig[];
  /** Override default max_tokens for this alias. */
  max_tokens?: number;
  /** Sampling temperature. */
  temperature?: number;
  /**
   * Logical task context. Surfaces on `agent_sessions.task_name`. Defaults to
   * "inference" when the caller doesn't provide one.
   */
  task_name?: string;
  /** Executive ID — joins traces back to the human the reasoning is about. */
  exec_id?: string | null;
  /** Trigger.dev run ID. Populates `agent_sessions.trigger_run_id`. */
  trigger_run_id?: string | null;
};

export type InferenceResult = {
  /** Parsed Anthropic response, exactly as returned by the SDK. */
  response: Message;
  /** The DB row id for the `agent_sessions` row that was written. */
  session_id: string;
};

// ---------------------------------------------------------------------------
// Anthropic client (lazy singleton)
// ---------------------------------------------------------------------------

let _anthropic: Anthropic | undefined;
function getAnthropic(): Anthropic {
  if (_anthropic) return _anthropic;
  const apiKey = process.env.ANTHROPIC_API_KEY;
  if (!apiKey) throw new Error("ANTHROPIC_API_KEY not set");
  _anthropic = new Anthropic({ apiKey, timeout: FETCH_TIMEOUT_MS, maxRetries: 0 });
  return _anthropic;
}

// ---------------------------------------------------------------------------
// Prompt caching retrofit
// ---------------------------------------------------------------------------

const CACHE_CONTROL_MIN_TOKENS = 1024;

function applyCacheControl(
  system: string | TextBlockParam[] | undefined,
): string | TextBlockParam[] | undefined {
  if (!system) return undefined;

  if (typeof system === "string") {
    if (approxTokens(system) < CACHE_CONTROL_MIN_TOKENS) return system;
    return [
      {
        type: "text",
        text: system,
        cache_control: { type: "ephemeral" },
      },
    ];
  }

  if (system.length === 0) return system;
  const total = system.reduce((acc, b) => acc + (b.text ? approxTokens(b.text) : 0), 0);
  if (total < CACHE_CONTROL_MIN_TOKENS) return system;

  // Mark the final block. Callers who want finer-grained cache breakpoints
  // should construct the array themselves and pass it in.
  const copy = system.map((b) => ({ ...b }));
  const last = copy[copy.length - 1]!;
  copy[copy.length - 1] = {
    ...last,
    cache_control: { type: "ephemeral" as const },
  };
  return copy;
}

// ---------------------------------------------------------------------------
// DB helpers
// ---------------------------------------------------------------------------

type BlockType = "text" | "thinking" | "tool_use" | "tool_result";

async function insertAgentSession(args: {
  task_name: string;
  trigger_run_id: string | null;
  exec_id: string | null;
  prompt_hash: string;
  context_hash: string;
}): Promise<string> {
  const sb = getSupabaseServiceRole();
  const { data, error } = await sb
    .from("agent_sessions")
    .insert({
      task_name: args.task_name,
      trigger_run_id: args.trigger_run_id,
      exec_id: args.exec_id,
      status: "running",
      prompt_hash: args.prompt_hash,
      context_hash: args.context_hash,
    })
    .select("id")
    .single();

  if (error) throw new Error(`agent_sessions insert failed: ${error.message}`);
  if (!data) throw new Error("agent_sessions insert returned no row");
  return data.id as string;
}

async function completeAgentSession(args: {
  session_id: string;
  status: "completed" | "failed";
  input_tokens: number;
  output_tokens: number;
  cache_read_tokens: number;
}): Promise<void> {
  const sb = getSupabaseServiceRole();
  const { error } = await sb
    .from("agent_sessions")
    .update({
      status: args.status,
      completed_at: new Date().toISOString(),
      total_input_tokens: args.input_tokens,
      total_output_tokens: args.output_tokens,
      total_cache_read_tokens: args.cache_read_tokens,
    })
    .eq("id", args.session_id);

  if (error) throw new Error(`agent_sessions update failed: ${error.message}`);
}

type TraceRow = {
  session_id: string;
  step_index: number;
  role: "user" | "assistant" | "tool";
  model: string | null;
  block_type: BlockType;
  tool_name: string | null;
  content: unknown;
  latency_ms: number | null;
  input_tokens: number | null;
  output_tokens: number | null;
  cache_read_tokens: number | null;
  cache_creation_tokens: number | null;
};

async function insertTraces(rows: TraceRow[]): Promise<void> {
  if (rows.length === 0) return;
  const sb = getSupabaseServiceRole();
  const { error } = await sb.from("agent_traces").insert(rows);
  if (error) throw new Error(`agent_traces insert failed: ${error.message}`);
}

function blockTypeOf(
  block: ContentBlock | ToolResultBlockParam,
): BlockType {
  switch (block.type) {
    case "text":
      return "text";
    case "thinking":
    case "redacted_thinking":
      return "thinking";
    case "tool_use":
    case "server_tool_use":
      return "tool_use";
    case "tool_result":
      return "tool_result";
    default:
      // Future block types (e.g., new search results) default to text so we
      // never drop observability rows on SDK upgrades.
      return "text";
  }
}

function toolNameOf(block: ContentBlock | ToolResultBlockParam): string | null {
  if (block.type === "tool_use" || block.type === "server_tool_use") {
    return (block as ToolUseBlock).name ?? null;
  }
  return null;
}

// ---------------------------------------------------------------------------
// Retry loop
// ---------------------------------------------------------------------------

async function callWithRetry(params: MessageCreateParams): Promise<Message> {
  let lastErr: unknown;

  for (let attempt = 1; attempt <= MAX_RETRIES; attempt++) {
    try {
      const response = await getAnthropic().messages.create(params);
      return response as Message;
    } catch (err) {
      lastErr = err;
      const status = (err as { status?: number; statusCode?: number })?.status
        ?? (err as { statusCode?: number })?.statusCode;

      const retryable =
        status === 429 ||
        status === 529 ||
        (typeof status === "number" && status >= 500) ||
        isTimeoutError(err);

      if (!retryable || attempt === MAX_RETRIES) {
        throw err;
      }

      const delay = RETRY_BASE_MS * Math.pow(2, attempt - 1);
      // eslint-disable-next-line no-console -- Trigger.dev logger captures stdout as structured events
      console.warn(
        `[inference] status=${status ?? "timeout"} attempt=${attempt}/${MAX_RETRIES} retry_in_ms=${delay}`,
      );
      await new Promise((r) => setTimeout(r, delay));
    }
  }

  throw lastErr ?? new Error("inference: max retries exceeded");
}

function isTimeoutError(err: unknown): boolean {
  if (err instanceof Error) {
    if (err.name === "TimeoutError") return true;
    if (err.message.toLowerCase().includes("timeout")) return true;
  }
  return false;
}

// ---------------------------------------------------------------------------
// Public entry point
// ---------------------------------------------------------------------------

/**
 * Centralised Anthropic inference wrapper. Every nightly + morning pass in
 * Timed flows through here so:
 *   - model routing is a single-file change,
 *   - retries + backoff are uniform,
 *   - every text/thinking/tool_use/tool_result block lands in `agent_traces`
 *     with full token accounting for deterministic replay and future
 *     supervised-fine-tuning corpus export,
 *   - prompt caching is retrofitted automatically when the system prompt
 *     crosses the 1024-token threshold.
 *
 * Returns the full parsed Anthropic response plus the DB session id so
 * callers can attach follow-up rows (e.g., tool-result insertions from
 * Claude Agent SDK loops).
 */
export async function inference(opts: InferenceOptions): Promise<InferenceResult> {
  const model = MODEL_ROUTING[opts.model_alias];
  if (!model) throw new Error(`inference: unknown model_alias "${opts.model_alias}"`);

  const max_tokens = opts.max_tokens ?? DEFAULT_MAX_TOKENS[opts.model_alias];

  if (opts.thinking && opts.thinking.type === "enabled") {
    const budget = (opts.thinking as { budget_tokens?: number }).budget_tokens;
    if (typeof budget === "number" && budget >= max_tokens) {
      throw new Error(
        `inference: thinking.budget_tokens (${budget}) must be < max_tokens (${max_tokens})`,
      );
    }
  }

  const system = applyCacheControl(opts.system);

  const params: MessageCreateParams = {
    model,
    max_tokens,
    messages: opts.messages,
    ...(system !== undefined ? { system } : {}),
    ...(opts.tools && opts.tools.length > 0 ? { tools: opts.tools } : {}),
    ...(opts.thinking ? { thinking: opts.thinking } : {}),
    ...(opts.temperature !== undefined ? { temperature: opts.temperature } : {}),
  };

  const prompt_hash = sha256Hex({
    model,
    system: opts.system ?? null,
    messages: opts.messages,
    tools: opts.tools ?? null,
    thinking: opts.thinking ?? null,
  });
  const context_hash = sha256Hex({ mcp_servers: opts.mcp_servers ?? null });

  const session_id = await insertAgentSession({
    task_name: opts.task_name ?? "inference",
    trigger_run_id: opts.trigger_run_id ?? null,
    exec_id: opts.exec_id ?? null,
    prompt_hash,
    context_hash,
  });

  const startedAt = Date.now();
  let response: Message;
  try {
    response = await callWithRetry(params);
  } catch (err) {
    await completeAgentSession({
      session_id,
      status: "failed",
      input_tokens: 0,
      output_tokens: 0,
      cache_read_tokens: 0,
    }).catch(() => undefined);
    throw err;
  }
  const latency_ms = Date.now() - startedAt;

  // Token accounting — Anthropic returns these on every response.
  const usage = response.usage;
  const input_tokens = usage.input_tokens ?? 0;
  const output_tokens = usage.output_tokens ?? 0;
  const cache_read_tokens = usage.cache_read_input_tokens ?? 0;
  const cache_creation_tokens = usage.cache_creation_input_tokens ?? 0;

  // Write one trace row per returned block. Step index is content-array order.
  // Token columns are replicated on every row — the *session* totals are
  // authoritative, but per-row duplication keeps single-block queries simple.
  const rows: TraceRow[] = response.content.map((block, idx) => ({
    session_id,
    step_index: idx,
    role: response.role, // always "assistant" for Messages API responses
    model,
    block_type: blockTypeOf(block),
    tool_name: toolNameOf(block),
    content: block,
    latency_ms,
    input_tokens,
    output_tokens,
    cache_read_tokens,
    cache_creation_tokens,
  }));

  await insertTraces(rows);
  await completeAgentSession({
    session_id,
    status: "completed",
    input_tokens,
    output_tokens,
    cache_read_tokens,
  });

  return { response, session_id };
}

// Re-export useful types so task files don't import from Anthropic SDK directly
// for the common path.
export type { Message, MessageParam, Tool, ThinkingConfigParam };
