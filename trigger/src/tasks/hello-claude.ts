import { logger, task } from "@trigger.dev/sdk";

import { inference } from "../inference.js";
import { getSupabaseServiceRole } from "../lib/supabase.js";

/**
 * Wave 1 smoke task — the bare minimum that proves:
 *   1. `inference()` routes `haiku_classify` to Haiku 4.5 and completes,
 *   2. `agent_sessions` gets exactly one row,
 *   3. `agent_traces` gets ≥ 1 row with non-null token fields,
 *   4. Trigger.dev picks up the task file via `dirs: ["./src/tasks"]`.
 *
 * This task makes a real network call — it is invoked manually after Ammar
 * completes Task 2 (secret upload). The gate for this file compiling is
 * proven via `pnpm tsc --noEmit`, not runtime.
 */
export const helloClaude = task({
  id: "hello-claude",
  maxDuration: 60,
  run: async (payload: { probe_text?: string } = {}) => {
    logger.info("hello-claude starting", { payload });

    const { response, session_id } = await inference({
      model_alias: "haiku_classify",
      task_name: "hello-claude",
      messages: [
        {
          role: "user",
          content: payload.probe_text ?? "Say 'ok' in one word.",
        },
      ],
    });

    logger.info("hello-claude inference returned", {
      session_id,
      stop_reason: response.stop_reason,
      content_block_count: response.content.length,
      input_tokens: response.usage.input_tokens,
      output_tokens: response.usage.output_tokens,
    });

    // Post-condition assertions — fail the run loudly if the trace plumbing
    // is broken. Catching this at smoke time beats discovering it at the
    // nightly cutover.
    const sb = getSupabaseServiceRole();

    const { data: sessionRow, error: sessErr } = await sb
      .from("agent_sessions")
      .select("id, status, total_input_tokens, total_output_tokens, total_cache_read_tokens")
      .eq("id", session_id)
      .single();
    if (sessErr) throw new Error(`agent_sessions lookup failed: ${sessErr.message}`);
    if (!sessionRow) throw new Error("hello-claude: agent_sessions row missing");
    if (sessionRow.status !== "completed") {
      throw new Error(`hello-claude: session status=${sessionRow.status}, expected 'completed'`);
    }
    if (
      sessionRow.total_input_tokens == null ||
      sessionRow.total_output_tokens == null
    ) {
      throw new Error("hello-claude: session token totals are null");
    }

    const { data: traceRows, error: traceErr } = await sb
      .from("agent_traces")
      .select("id, block_type, input_tokens, output_tokens")
      .eq("session_id", session_id);
    if (traceErr) throw new Error(`agent_traces lookup failed: ${traceErr.message}`);
    if (!traceRows || traceRows.length === 0) {
      throw new Error("hello-claude: no agent_traces rows written");
    }
    for (const row of traceRows) {
      if (row.input_tokens == null || row.output_tokens == null) {
        throw new Error(
          `hello-claude: trace row ${row.id} has null token fields (block_type=${row.block_type})`,
        );
      }
    }

    return {
      session_id,
      trace_count: traceRows.length,
      total_input_tokens: sessionRow.total_input_tokens,
      total_output_tokens: sessionRow.total_output_tokens,
      total_cache_read_tokens: sessionRow.total_cache_read_tokens,
    };
  },
});
