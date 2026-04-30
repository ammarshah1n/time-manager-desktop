import { serve } from "https://deno.land/std@0.208.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { createRequestLogger } from "../_shared/logger.ts";
import { requireEnv } from "../_shared/config.ts";

import { verifyServiceRole, AuthError, authErrorResponse } from "../_shared/auth.ts";
// Cron: 0 3 * * 0 (Sunday 3 AM)
// Prunes old/low-importance data across memory tiers

const SUPABASE_URL = requireEnv("SUPABASE_URL");
const SUPABASE_SERVICE_KEY = requireEnv("SUPABASE_SERVICE_ROLE_KEY");

serve(async (req: Request) => {
  const log = createRequestLogger("weekly-pruning");
  try {
  if (req.method === "OPTIONS") {
    return new Response("ok", { status: 200 });
  }
  try {
    verifyServiceRole(req);
  } catch (err) {
    if (err instanceof AuthError) return authErrorResponse(err);
    throw err;
  }


  const client = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY);
  const start = Date.now();

  const { data: executives } = await client.from("executives").select("id");
  if (!executives?.length) {
    return new Response(JSON.stringify({ error: "No executives found" }), { status: 500 });
  }

  const results: Record<string, unknown> = {};

  for (const executive of executives) {
    const executiveId = executive.id;
    const now = new Date();
    const thirtyDaysAgo = new Date(now.getTime() - 30 * 86400000).toISOString();
    const oneYearAgo = new Date(now.getTime() - 365 * 86400000).toISOString();
    const sixtyDaysAgo = new Date(now.getTime() - 60 * 86400000).toISOString();

    // Tier 0: >30 days + importance <0.8 → archive raw_data (replace with storage URI)
    const { data: archivable, count: archiveCount } = await client
      .from("tier0_observations")
      .select("id", { count: "exact" })
      .eq("profile_id", executiveId)
      .lt("occurred_at", thirtyDaysAgo)
      .lt("importance_score", 0.8)
      .eq("is_processed", true)
      .not("raw_data", "is", null);

    // TODO: For each archivable observation:
    // 1. Upload raw_data to Supabase Storage (bucket: "tier0-archives")
    // 2. Replace raw_data with { "archived_uri": "storage://tier0-archives/{id}.json" }

    // Tier 0: >365 days + importance <0.8 + processed → tombstone
    const { count: tombstoneCount } = await client
      .from("tier0_observations")
      .select("id", { count: "exact", head: true })
      .eq("profile_id", executiveId)
      .lt("occurred_at", oneYearAgo)
      .lt("importance_score", 0.8)
      .eq("is_processed", true);

    // TODO: For tombstoned observations:
    // 1. Keep id, summary, embedding, importance_score, occurred_at
    // 2. Set raw_data = null, entity_id = null

    // Tier 2: last_reinforced >60 days + confirmed → status='fading'
    const { data: fadingSignatures, count: fadingCount } = await client
      .from("tier2_behavioural_signatures")
      .update({ status: "fading" })
      .eq("profile_id", executiveId)
      .eq("status", "confirmed")
      .lt("last_reinforced", sixtyDaysAgo)
      .select("id", { count: "exact" });

    // Tier 3: NEVER prune (hard rule)

    results[executiveId] = {
      tier0_archivable: archiveCount ?? 0,
      tier0_tombstonable: tombstoneCount ?? 0,
      tier2_fading: fadingCount ?? 0,
      tier3_pruned: 0,
    };
  }

  await client.from("pipeline_health_log").insert({
    check_type: "nightly_pipeline",
    status: "ok",
    details: { pipeline: "weekly-pruning", results, duration_ms: Date.now() - start },
  });

  log.info("complete", { executives_processed: executives.length, duration_ms: Date.now() - start });
  return new Response(JSON.stringify({
    pipeline: "weekly-pruning",
    duration_ms: Date.now() - start,
    results,
  }), {
    status: 200,
    headers: { "Content-Type": "application/json" },
  });
  } catch (err) {
    log.error("unhandled", err);
    return new Response(JSON.stringify({ error: err instanceof Error ? err.message : "Internal error", request_id: log.request_id }), { status: 500, headers: { "Content-Type": "application/json" } });
  }
});
