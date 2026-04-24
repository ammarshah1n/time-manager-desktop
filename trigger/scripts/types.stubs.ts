/**
 * STUB TYPES — Wave 1 Agent A5 scaffold.
 *
 * These row shapes are hand-written from the schema described in
 * `docs/plans/here-s-the-improved-prompt-snazzy-cookie.md` tasks 4 and 28a.
 * They exist ONLY so the CLI stubs in this folder can typecheck in isolation
 * before Agent A1's Trigger.dev scaffold + B4's KG-snapshot migration land.
 *
 * TODO(wave2): After the following both merge into `ui/apple-v1-restore`:
 *   - A1's `trigger/` workspace (brings Trigger.dev + `@supabase/supabase-js`)
 *   - B4's migration `20260427...agent_traces.sql` (task 4) and
 *     `20260428...kg_snapshots.sql` (task 28a)
 * regenerate canonical row types via `supabase gen types typescript
 * --project-id fpmjuufefhtlwbfinxlx --schema public` and delete this file.
 * Every `import ... from "./types.stubs"` should switch to the generated
 * `Database` type path (usually `@/types/supabase`).
 */

/** Corresponds to the `agent_sessions` table in task 4. */
export interface AgentSessionRow {
  id: string;
  task_name: string;
  trigger_run_id: string | null;
  exec_id: string;
  started_at: string; // ISO timestamp
  completed_at: string | null;
  status: "pending" | "running" | "completed" | "failed";
  prompt_hash: string | null;
  context_hash: string | null;
  total_input_tokens: number | null;
  total_output_tokens: number | null;
  total_cache_read_tokens: number | null;
}

/** Corresponds to the `agent_traces` table in task 4. */
export type AgentTraceBlockType = "text" | "thinking" | "tool_use" | "tool_result";

export interface AgentTraceRow {
  id: string;
  session_id: string;
  step_index: number;
  role: "system" | "user" | "assistant" | "tool";
  model: string;
  block_type: AgentTraceBlockType;
  tool_name: string | null;
  content: unknown; // JSONB — opaque to these scripts
  latency_ms: number | null;
  input_tokens: number | null;
  output_tokens: number | null;
  cache_read_tokens: number | null;
  cache_creation_tokens: number | null;
  created_at: string;
}

/** Corresponds to the `kg_snapshots` table in task 28a. */
export interface KgSnapshotRow {
  session_id: string | null;
  week: string; // ISO week format `YYYY-WW`
  storage_path: string; // Supabase Storage path in bucket `kg-snapshots/`
  node_count: number;
  rel_count: number;
  size_bytes: number;
  created_at: string;
}

/**
 * Reconstructed view of a single `inference()` call, composed from a
 * contiguous span of `agent_traces` rows sharing a `session_id`.
 * Used by `replay.ts` prompt-mode and by `export-training-data.ts`.
 */
export interface InferenceTuple {
  session_id: string;
  /** Starting `step_index` in `agent_traces` for this inference span. */
  step_index_start: number;
  step_index_end: number;
  model: string;
  system_prompt: string;
  user_prompt: string;
  tools_available: string[];
  tool_use_trajectory: Array<{
    tool_name: string;
    input: unknown;
    result: unknown;
  }>;
  final_response: string;
  cache_stats: {
    input_tokens: number;
    output_tokens: number;
    cache_read_tokens: number;
    cache_creation_tokens: number;
  };
}
