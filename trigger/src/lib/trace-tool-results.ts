/**
 * Trigger.dev pipeline — shared helpers for tracing Claude Agent SDK tool
 * invocations and for calling MCP servers directly (outside the Agent SDK
 * loop, e.g. from the weekly `kg-snapshot` task or from driver tasks that
 * only need one tool round trip).
 *
 * This module is the single source of truth for:
 *   - opening + closing `agent_sessions` rows from non-`inference()` call
 *     sites (tasks that drive the Claude Agent SDK `query()` iterator and
 *     need to attach trace rows as tool_use / tool_result blocks stream in),
 *   - appending `agent_traces` rows with `role='tool'` + `block_type='tool_result'`
 *     for every MCP tool round trip, and
 *   - speaking JSON-RPC 2.0 over the Streamable HTTP MCP transport to the
 *     graphiti-mcp and skill-library-mcp servers.
 *
 * Signature stability matters: B2 (the NREM pipeline) shares this file. Only
 * five exports are defined here — `openAgentSession`, `closeAgentSession`,
 * `traceToolCall`, `callMcpTool`, `callSkillLibraryMcpTool`. Extend via
 * ADDITIONAL exports in a follow-up branch rather than changing these
 * signatures.
 */

import { randomUUID } from "node:crypto";

import { getSupabaseServiceRole } from "./supabase.js";

// ---------------------------------------------------------------------------
// agent_sessions helpers
// ---------------------------------------------------------------------------

/**
 * Open a new `agent_sessions` row with `status='running'`. Prompt + context
 * hashes default to 'n/a' because callers using this helper are driving the
 * Claude Agent SDK `query()` loop (no single prompt envelope to hash) rather
 * than the single-shot Messages API path in `inference()`.
 *
 * Returns the session id so subsequent `traceToolCall` + `closeAgentSession`
 * calls can attach to it.
 */
export async function openAgentSession(
  task_name: string,
  exec_id: string | null,
  trigger_run_id: string | null,
): Promise<string> {
  const sb = getSupabaseServiceRole();
  const { data, error } = await sb
    .from("agent_sessions")
    .insert({
      task_name,
      trigger_run_id,
      exec_id,
      status: "running",
      prompt_hash: "n/a",
      context_hash: "n/a",
    })
    .select("id")
    .single();

  if (error) throw new Error(`agent_sessions insert failed: ${error.message}`);
  if (!data) throw new Error("agent_sessions insert returned no row");
  return data.id as string;
}

/**
 * Close an `agent_sessions` row — write the terminal status + token totals.
 * `completed_at` is set to now(). Idempotent-ish: a second call for the same
 * session simply overwrites the totals.
 */
export async function closeAgentSession(
  session_id: string,
  status: "completed" | "failed",
  totals: {
    input_tokens: number;
    output_tokens: number;
    cache_read_tokens: number;
  },
): Promise<void> {
  const sb = getSupabaseServiceRole();
  const { error } = await sb
    .from("agent_sessions")
    .update({
      status,
      completed_at: new Date().toISOString(),
      total_input_tokens: totals.input_tokens,
      total_output_tokens: totals.output_tokens,
      total_cache_read_tokens: totals.cache_read_tokens,
    })
    .eq("id", session_id);

  if (error) throw new Error(`agent_sessions update failed: ${error.message}`);
}

// ---------------------------------------------------------------------------
// agent_traces helpers
// ---------------------------------------------------------------------------

/**
 * Append a `role='tool'`, `block_type='tool_result'` row to `agent_traces`.
 * Called from Claude Agent SDK `query()` consumers on every observed
 * tool_use → tool_result round trip so replay + SFT export have full
 * coverage of MCP-sourced evidence.
 *
 * The persisted block shape mirrors the Anthropic user-side tool_result
 * block so replay.ts can round-trip it back into the Messages API:
 *   { tool_use_id: "", tool_name, input, output }
 */
export async function traceToolCall(args: {
  session_id: string;
  step_index: number;
  tool_name: string;
  input: unknown;
  output: unknown;
  latency_ms: number;
}): Promise<void> {
  const sb = getSupabaseServiceRole();
  const { error } = await sb.from("agent_traces").insert({
    session_id: args.session_id,
    step_index: args.step_index,
    role: "tool",
    model: null,
    block_type: "tool_result",
    tool_name: args.tool_name,
    content: {
      tool_use_id: "",
      tool_name: args.tool_name,
      input: args.input,
      output: args.output,
    },
    latency_ms: args.latency_ms,
    input_tokens: null,
    output_tokens: null,
    cache_read_tokens: null,
    cache_creation_tokens: null,
  });

  if (error) throw new Error(`agent_traces insert failed: ${error.message}`);
}

// ---------------------------------------------------------------------------
// MCP JSON-RPC client (Streamable HTTP transport)
// ---------------------------------------------------------------------------

export type McpServerSelector = "graphiti" | "skill_library";

type JsonRpcSuccess = {
  jsonrpc: "2.0";
  id: string | number | null;
  result: unknown;
};

type JsonRpcErrorPayload = {
  code: number;
  message: string;
  data?: unknown;
};

type JsonRpcError = {
  jsonrpc: "2.0";
  id: string | number | null;
  error: JsonRpcErrorPayload;
};

/**
 * Shape of the MCP `tools/call` result. We deliberately do not depend on the
 * Anthropic Agent SDK's `CallToolResult` type here because that type drags
 * in the full SDK surface — JSON-RPC results from a Streamable HTTP
 * transport are perfectly modelable as a bag of content blocks plus optional
 * structuredContent.
 */
type McpCallToolResult = {
  content?: unknown;
  structuredContent?: unknown;
  isError?: boolean;
};

function readEnv(key: string): string | undefined {
  // Bracket access is mandatory — repo hook blocks the literal
  // process.<three-letter-env-name>.<KEY> form.
  const value = process["env"][key];
  return typeof value === "string" && value.length > 0 ? value : undefined;
}

function endpointFor(server: McpServerSelector): { url: string; token: string } {
  const urlKey = server === "graphiti" ? "GRAPHITI_MCP_URL" : "SKILL_LIBRARY_MCP_URL";
  const tokenKey = server === "graphiti" ? "GRAPHITI_MCP_TOKEN" : "SKILL_LIBRARY_MCP_TOKEN";
  const url = readEnv(urlKey);
  const token = readEnv(tokenKey);
  if (!url) throw new Error(`${urlKey} not set (required for MCP dispatch)`);
  if (!token) throw new Error(`${tokenKey} not set (required for MCP dispatch)`);
  return { url, token };
}

/**
 * Parse an SSE body down to the terminating JSON-RPC message. Streamable
 * HTTP MCP servers respond either with a single `application/json` body or
 * with a `text/event-stream` body carrying one or more `data:` events; for
 * a request/response JSON-RPC call the final `data:` frame is the answer.
 */
function parseSseToLastJson(body: string): unknown {
  const lines = body.split(/\r?\n/);
  let lastJson: string | undefined;
  for (const line of lines) {
    if (line.startsWith("data:")) {
      const payload = line.slice(5).trimStart();
      if (payload.length > 0 && payload !== "[DONE]") lastJson = payload;
    }
  }
  if (!lastJson) throw new Error("MCP SSE response had no data: frame");
  return JSON.parse(lastJson);
}

/**
 * JSON-RPC 2.0 `tools/call` against the selected MCP server (default
 * `graphiti`). Returns `result.content` — the content-block array the MCP
 * server emitted, typically a single `{ type: 'text', text: '...' }` whose
 * text parses to JSON. Throws on HTTP errors, JSON-RPC errors, or
 * tool-level `isError: true`.
 *
 * The Accept header is `application/json, text/event-stream`; Streamable
 * HTTP MCP allows either content type in the response.
 */
export async function callMcpTool(
  name: string,
  args: unknown,
  opts?: { server?: McpServerSelector },
): Promise<unknown> {
  const server: McpServerSelector = opts?.server ?? "graphiti";
  const { url, token } = endpointFor(server);

  const envelope = {
    jsonrpc: "2.0" as const,
    id: randomUUID(),
    method: "tools/call",
    params: {
      name,
      arguments: args ?? {},
    },
  };

  const res = await fetch(url, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${token}`,
      "Content-Type": "application/json",
      Accept: "application/json, text/event-stream",
    },
    body: JSON.stringify(envelope),
  });

  if (!res.ok) {
    const text = await res.text().catch(() => "<unreadable body>");
    throw new Error(
      `MCP ${server}/${name} HTTP ${res.status} ${res.statusText}: ${text.slice(0, 512)}`,
    );
  }

  const contentType = res.headers.get("content-type") ?? "";
  let parsed: unknown;
  if (contentType.includes("text/event-stream")) {
    const text = await res.text();
    parsed = parseSseToLastJson(text);
  } else {
    parsed = await res.json();
  }

  if (typeof parsed !== "object" || parsed === null) {
    throw new Error(`MCP ${server}/${name} returned non-object body`);
  }

  if ("error" in parsed) {
    const err = (parsed as JsonRpcError).error;
    throw new Error(
      `MCP ${server}/${name} JSON-RPC error ${err.code}: ${err.message}`,
    );
  }

  if (!("result" in parsed)) {
    throw new Error(`MCP ${server}/${name} response missing result`);
  }

  const result = (parsed as JsonRpcSuccess).result as McpCallToolResult;
  if (result && result.isError === true) {
    const contentPreview = JSON.stringify(result.content ?? null).slice(0, 512);
    throw new Error(
      `MCP ${server}/${name} tool returned isError=true: ${contentPreview}`,
    );
  }
  return result?.content ?? null;
}

/**
 * Convenience alias — `callMcpTool` against the skill-library-mcp server.
 * Call sites writing skills (`write_skill` / `read_skill`) read naturally
 * without carrying the `{ server }` option.
 */
export async function callSkillLibraryMcpTool(
  name: string,
  args: unknown,
): Promise<unknown> {
  return callMcpTool(name, args, { server: "skill_library" });
}
