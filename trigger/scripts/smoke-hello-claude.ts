import { inference } from "../src/inference.js";
import { getSupabaseServiceRole } from "../src/lib/supabase.js";

async function main() {
  const { response, session_id } = await inference({
    model_alias: "haiku_classify",
    task_name: "hello-claude-smoke",
    messages: [{ role: "user", content: "Say 'ok' in one word." }],
  });

  const sb = getSupabaseServiceRole();
  const { data: sessionRow, error: sessErr } = await sb
    .from("agent_sessions")
    .select("id, status, total_input_tokens, total_output_tokens, total_cache_read_tokens")
    .eq("id", session_id)
    .single();
  if (sessErr) throw new Error(`agent_sessions lookup failed: ${sessErr.message}`);

  const { data: traceRows, error: traceErr } = await sb
    .from("agent_traces")
    .select("id, block_type, input_tokens, output_tokens")
    .eq("session_id", session_id);
  if (traceErr) throw new Error(`agent_traces lookup failed: ${traceErr.message}`);

  console.log(JSON.stringify({
    ok: true,
    session_id,
    stop_reason: response.stop_reason,
    blocks: response.content.length,
    session_status: sessionRow?.status,
    total_input_tokens: sessionRow?.total_input_tokens,
    total_output_tokens: sessionRow?.total_output_tokens,
    total_cache_read_tokens: sessionRow?.total_cache_read_tokens,
    trace_count: traceRows?.length,
    trace_block_types: traceRows?.map((r) => r.block_type),
  }, null, 2));
}

main().catch((e) => { console.error("SMOKE FAILED:", e); process.exit(1); });
