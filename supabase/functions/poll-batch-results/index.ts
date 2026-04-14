import { serve } from "https://deno.land/std@0.208.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { getBatchStatus } from "../_shared/anthropic.ts";

// Polls Anthropic Batch API for completed self-improvement results.
// Writes accepted signatures to tier2_behavioural_signatures.
// Cron: */30 * * * * (every 30 minutes)

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const ANTHROPIC_API_KEY = Deno.env.get("ANTHROPIC_API_KEY")!;

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { status: 200 });
  }

  const client = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY);
  const start = Date.now();
  let processed = 0;
  let skipped = 0;

  // Find pending batch submissions
  const { data: pendingLogs, error: queryError } = await client
    .from("self_improvement_log")
    .select("id, profile_id, proposed_changes")
    .filter("proposed_changes->>status", "eq", "submitted");

  if (queryError || !pendingLogs?.length) {
    return new Response(JSON.stringify({
      status: "ok",
      detail: pendingLogs?.length ? "Query error" : "No pending batches",
      duration_ms: Date.now() - start,
    }), { status: 200, headers: { "Content-Type": "application/json" } });
  }

  for (const log of pendingLogs) {
    const batchId = log.proposed_changes?.batch_id;
    if (!batchId) {
      skipped++;
      continue;
    }

    try {
      const batchStatus = await getBatchStatus(batchId);

      if (batchStatus.processing_status !== "ended") {
        skipped++;
        continue;
      }

      // Fetch results
      if (!batchStatus.results_url) {
        await client.from("self_improvement_log").update({
          proposed_changes: { ...log.proposed_changes, status: "error", error: "No results_url" },
        }).eq("id", log.id);
        continue;
      }

      const resultsResponse = await fetch(batchStatus.results_url);

      if (!resultsResponse.ok) {
        await client.from("self_improvement_log").update({
          proposed_changes: { ...log.proposed_changes, status: "error", error: `Results fetch ${resultsResponse.status}` },
        }).eq("id", log.id);
        continue;
      }

      // Parse JSONL results
      const resultsText = await resultsResponse.text();
      const lines = resultsText.trim().split("\n").filter(Boolean);

      let acceptedSignatures = 0;
      const acceptedChanges: unknown[] = [];
      const rejectedReasons: unknown[] = [];
      const validationResults: unknown[] = [];

      for (const line of lines) {
        try {
          const result = JSON.parse(line);
          if (result.result?.type !== "succeeded") {
            rejectedReasons.push({ custom_id: result.custom_id, reason: "API call failed" });
            continue;
          }

          // Extract the text content from the response
          const textBlocks = result.result.message.content.filter(
            (b: { type: string }) => b.type === "text"
          );
          const responseText = textBlocks.map((b: { text: string }) => b.text).join("");

          let parsed;
          try {
            parsed = JSON.parse(responseText);
          } catch {
            rejectedReasons.push({ custom_id: result.custom_id, reason: "Failed to parse response JSON" });
            continue;
          }

          validationResults.push({
            custom_id: result.custom_id,
            inventory_count: parsed.inventory_count,
            novel_patterns: parsed.novel_patterns?.length ?? 0,
            proposed_signatures: parsed.proposed_signatures?.length ?? 0,
          });

          // Write proposed signatures that pass validation to tier2
          for (const sig of parsed.proposed_signatures ?? []) {
            if (sig.confidence >= 0.6 && sig.passes_bocpd_floor !== false) {
              await client.from("tier2_behavioural_signatures").insert({
                profile_id: log.profile_id,
                signature_name: sig.signature_name,
                pattern_type: sig.pattern_type ?? "emergent",
                description: sig.description,
                confidence: sig.confidence,
                status: "developing",
                supporting_tier1_ids: [],
                first_observed: sig.supporting_dates?.[0] ?? new Date().toISOString().slice(0, 10),
                last_observed: sig.supporting_dates?.at(-1) ?? new Date().toISOString().slice(0, 10),
              });
              acceptedSignatures++;
              acceptedChanges.push(sig);
            } else {
              rejectedReasons.push({
                signature_name: sig.signature_name,
                reason: sig.confidence < 0.6 ? `Low confidence: ${sig.confidence}` : "Failed BOCPD floor",
              });
            }
          }
        } catch {
          rejectedReasons.push({ line: line.slice(0, 100), reason: "Failed to parse result line" });
        }
      }

      // Update the log entry
      await client.from("self_improvement_log").update({
        proposed_changes: { ...log.proposed_changes, status: "completed" },
        accepted_changes: acceptedChanges,
        rejected_reasons: rejectedReasons,
        validation_results: validationResults,
      }).eq("id", log.id);

      processed++;
    } catch (error) {
      const message = error instanceof Error ? error.message : "Unknown error";
      await client.from("self_improvement_log").update({
        proposed_changes: { ...log.proposed_changes, status: "error", error: message },
      }).eq("id", log.id);
    }
  }

  // Log health
  await client.from("pipeline_health_log").insert({
    check_type: "batch_polling",
    status: "ok",
    details: { processed, skipped, total: pendingLogs.length, duration_ms: Date.now() - start },
  });

  return new Response(JSON.stringify({
    pipeline: "poll-batch-results",
    processed,
    skipped,
    duration_ms: Date.now() - start,
  }), { status: 200, headers: { "Content-Type": "application/json" } });
});
