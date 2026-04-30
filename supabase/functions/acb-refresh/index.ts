import { serve } from "https://deno.land/std@0.208.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { callAnthropic, extractText } from "../_shared/anthropic.ts";
import { createRequestLogger } from "../_shared/logger.ts";
import { requireEnv } from "../_shared/config.ts";

import { verifyServiceRole, AuthError, authErrorResponse } from "../_shared/auth.ts";
// Lightweight mid-day ACB refresh — Sonnet for intra-day updates
// Keeps the executive's working memory current throughout the day.
// Cron: 0 9,13,17 * * 1-5 (9am, 1pm, 5pm weekdays)
// Full Opus rebuild remains at 2am nightly (nightly-phase2).
// Research grounding: v3-04 (two-call architecture for ACB: generation + adversarial critique)

const SUPABASE_URL = requireEnv("SUPABASE_URL");
const SUPABASE_SERVICE_KEY = requireEnv("SUPABASE_SERVICE_ROLE_KEY");

serve(async (req: Request) => {
  const log = createRequestLogger("acb-refresh");
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

  const { data: executives } = await client.from("executives").select("id, timezone");
  if (!executives?.length) {
    return new Response(JSON.stringify({ error: "No executives found" }), { status: 500 });
  }

  const results: Record<string, unknown> = {};

  for (const executive of executives) {
    const executiveId = executive.id;

    // Fetch current ACB for delta comparison
    const { data: currentAcb } = await client
      .from("active_context_buffer")
      .select("acb_full, acb_light, acb_generated_at")
      .eq("profile_id", executiveId)
      .maybeSingle();

    // Fetch observations since last ACB generation
    const lastGenerated = currentAcb?.acb_generated_at ?? new Date(Date.now() - 86400000).toISOString();
    const { data: newObs } = await client
      .from("tier0_observations")
      .select("summary, source, event_type, occurred_at, authoritative_score")
      .eq("profile_id", executiveId)
      .gte("occurred_at", lastGenerated)
      .order("occurred_at", { ascending: false })
      .limit(50);

    if (!newObs?.length) {
      results[executiveId] = { status: "skipped", detail: "No new observations since last ACB" };
      continue;
    }

    const newObsFormatted = newObs.map((o) =>
      `[${new Date(o.occurred_at).toLocaleTimeString("en-AU", { hour: "2-digit", minute: "2-digit" })}] ${o.source}/${o.event_type} (score: ${o.authoritative_score?.toFixed(2) ?? "?"}): ${o.summary ?? ""}`
    ).join("\n");

    // ── Pass 1: Sonnet generation (effort=high) ──
    const pass1Response = await callAnthropic({
      model: "claude-sonnet-4-6",
      max_tokens: 8192,
      thinking: { type: "enabled", effort: "high" },
      messages: [{
        role: "user",
        content: `Update the Active Context Buffer for a C-suite executive based on new observations since the last refresh.

CURRENT ACB-LIGHT:
${currentAcb?.acb_light ? JSON.stringify(currentAcb.acb_light).slice(0, 2000) : "Not yet generated."}

NEW OBSERVATIONS SINCE LAST REFRESH (${newObs.length}):
${newObsFormatted}

Output valid JSON:
{
  "acb_full": { ... updated full context document ... },
  "acb_light": { ... updated 500-800 token summary ... },
  "delta_summary": "1-2 sentences describing what changed",
  "delta_tokens": number (rough estimate of tokens that changed)
}

Rules:
- Merge new observations into existing context, don't replace wholesale
- Flag any observation that contradicts existing context
- Update energy profile if new observations suggest a shift
- Keep ACB-LIGHT under 800 tokens`,
      }],
    });

    const pass1Text = extractText(pass1Response);
    let refreshData;
    try {
      refreshData = JSON.parse(pass1Text);
    } catch {
      refreshData = { acb_full: { raw: pass1Text }, acb_light: { raw: pass1Text.slice(0, 800) }, delta_tokens: 0 };
    }

    // ── Pass 2 DROPPED (Dish Me Up Ship-It.md, Part 2): Adversarial critique
    // produced a quality_score that no consumer reads at Dish Me Up time. Re-add
    // when the Dish Me Up Opus system prompt actually injects critique_score
    // as a calibration signal.
    const critiqueResult = { quality_score: null, issues_found: null };

    // Update ACB
    await client
      .from("active_context_buffer")
      .upsert({
        profile_id: executiveId,
        acb_full: refreshData.acb_full,
        acb_light: refreshData.acb_light,
        acb_version: Date.now(),
        acb_generated_at: new Date().toISOString(),
      }, { onConflict: "profile_id" });

    results[executiveId] = {
      status: "ok",
      new_observations: newObs.length,
      delta_summary: refreshData.delta_summary,
      critique_score: critiqueResult.quality_score,
      critique_issues: critiqueResult.issues_found,
      tokens_used: {
        generation: pass1Response.usage.input_tokens + pass1Response.usage.output_tokens,
        critique: 0,
      },
      duration_ms: Date.now() - start,
    };
  }

  await client.from("pipeline_health_log").insert({
    check_type: "acb_refresh",
    status: "ok",
    details: { results, duration_ms: Date.now() - start },
  });

  log.info("complete", { executives_processed: executives.length, duration_ms: Date.now() - start });
  return new Response(JSON.stringify({
    pipeline: "acb-refresh",
    duration_ms: Date.now() - start,
    results,
  }), { status: 200, headers: { "Content-Type": "application/json" } });
  } catch (err) {
    log.error("unhandled", err);
    return new Response(JSON.stringify({ error: err instanceof Error ? err.message : "Internal error", request_id: log.request_id }), { status: 500, headers: { "Content-Type": "application/json" } });
  }
});
