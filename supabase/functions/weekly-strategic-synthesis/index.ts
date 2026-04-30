import { serve } from "https://deno.land/std@0.208.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { callAnthropic, extractText } from "../_shared/anthropic.ts";
import { createRequestLogger } from "../_shared/logger.ts";
import { requireEnv } from "../_shared/config.ts";

import { verifyServiceRole, AuthError, authErrorResponse } from "../_shared/auth.ts";
// Weekly strategic synthesis — Opus effort=max, Sunday cron
// Produces week-over-week strategic analysis personalised to the executive's cognitive model.
// Feeds into Monday's morning briefing as the "strategic context" section.
// Cron: 0 3 * * 0 (3 AM every Sunday)
// Research grounding: v3-02 (effort=max for weekly synthesis, 20K-40K adaptive thinking)

const SUPABASE_URL = requireEnv("SUPABASE_URL");
const SUPABASE_SERVICE_KEY = requireEnv("SUPABASE_SERVICE_ROLE_KEY");

serve(async (req: Request) => {
  const log = createRequestLogger("weekly-strategic-synthesis");
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

    // Last 7 daily summaries
    const { data: summaries } = await client
      .from("tier1_daily_summaries")
      .select("summary_date, day_narrative, significant_events, anomalies, energy_profile, signals_aggregated")
      .eq("profile_id", executiveId)
      .order("summary_date", { ascending: false })
      .limit(7);

    if (!summaries?.length || summaries.length < 3) {
      results[executiveId] = { status: "skipped", detail: `Only ${summaries?.length ?? 0} summaries (need 3+)` };
      continue;
    }

    // ACB-FULL for personality context
    const { data: acb } = await client.rpc("get_acb_full", { exec_id: executiveId });

    // Active predictions for tracking
    const { data: predictions } = await client
      .from("predictions")
      .select("*")
      .eq("profile_id", executiveId)
      .in("status", ["active", "monitoring"]);

    // Prior weekly synthesis (for week-over-week comparison)
    const { data: priorSynthesis } = await client
      .from("weekly_syntheses")
      .select("week_start, strategic_analysis, time_allocation, key_contradictions")
      .eq("profile_id", executiveId)
      .order("week_start", { ascending: false })
      .limit(4);

    // Tier 2 behavioural signatures (for pattern tracking)
    const { data: signatures } = await client
      .from("tier2_behavioural_signatures")
      .select("signature_name, description, confidence, status")
      .eq("profile_id", executiveId)
      .in("status", ["confirmed", "developing"]);

    const thisWeekStart = new Date();
    thisWeekStart.setDate(thisWeekStart.getDate() - thisWeekStart.getDay());
    const weekStartStr = thisWeekStart.toISOString().slice(0, 10);

    const response = await callAnthropic({
      model: "claude-opus-4-6",
      max_tokens: 16384,
      thinking: { type: "enabled", effort: "max" },
      system: `You are the strategic intelligence synthesizer for a C-suite executive's cognitive operating system. Your task is NOT to summarise the week — that's already done in daily summaries. Your task is to produce strategic analysis that reveals what the executive cannot see from inside their own week.

Analyse:
1. TIME ALLOCATION: How did the executive actually spend their time vs their stated priorities? Quantify with percentages. Compare to prior weeks.
2. DECISION PATTERNS: What decisions were made this week? What was the executive's decision-making velocity? Were any decisions delayed beyond their natural shelf life?
3. RELATIONSHIP DYNAMICS: Which relationships received disproportionate attention? Which were neglected? How do communication patterns this week compare to the executive's baseline?
4. ENERGY TRAJECTORY: Map the executive's cognitive load across the week. Where were the peak performance windows? Where was energy wasted?
5. CONTRADICTIONS: What did the executive do this week that contradicts their stated values, priorities, or prior commitments? Be specific and evidence-based.
6. EMERGING RISKS: What patterns are forming that the executive should be aware of but probably isn't?
7. STRATEGIC RECOMMENDATION: One concrete, specific recommendation for next week based on the analysis.

Output valid JSON:
{
  "week_start": "${weekStartStr}",
  "strategic_analysis": "3-5 paragraph strategic narrative",
  "time_allocation": {"category": percentage, ...},
  "decision_velocity": {"decisions_made": N, "avg_days_to_decide": N, "delayed_decisions": [...]},
  "relationship_focus": [{"contact": "name", "attention_level": "high|normal|neglected", "delta_from_baseline": "description"}],
  "energy_map": {"monday": "high|medium|low", ...},
  "key_contradictions": [{"stated": "what they said", "observed": "what they did", "evidence": "specific data"}],
  "emerging_risks": [{"risk": "description", "evidence": "supporting data", "urgency": "high|medium|low"}],
  "strategic_recommendation": "one specific, actionable recommendation"
}`,
      messages: [{
        role: "user",
        content: `ACTIVE CONTEXT BUFFER:\n${acb ? JSON.stringify(acb).slice(0, 20000) : "Not yet generated."}\n\nTHIS WEEK'S DAILY SUMMARIES (${summaries.length} days):\n${JSON.stringify(summaries, null, 2)}\n\nACTIVE PREDICTIONS:\n${JSON.stringify(predictions ?? [])}\n\nBEHAVIOURAL SIGNATURES:\n${JSON.stringify(signatures ?? [])}\n\nPRIOR WEEKLY SYNTHESES (for comparison):\n${JSON.stringify(priorSynthesis ?? []).slice(0, 10000)}`,
      }],
    });

    const synthesisText = extractText(response);
    let synthesisData;
    try {
      synthesisData = JSON.parse(synthesisText);
    } catch {
      synthesisData = { week_start: weekStartStr, strategic_analysis: synthesisText };
    }

    // Store the synthesis
    await client.from("weekly_syntheses").upsert({
      profile_id: executiveId,
      week_start: weekStartStr,
      strategic_analysis: synthesisData.strategic_analysis,
      time_allocation: synthesisData.time_allocation ?? {},
      decision_velocity: synthesisData.decision_velocity ?? {},
      relationship_focus: synthesisData.relationship_focus ?? [],
      energy_map: synthesisData.energy_map ?? {},
      key_contradictions: synthesisData.key_contradictions ?? [],
      emerging_risks: synthesisData.emerging_risks ?? [],
      strategic_recommendation: synthesisData.strategic_recommendation ?? "",
      generated_at: new Date().toISOString(),
      tokens_used: response.usage.input_tokens + response.usage.output_tokens,
    }, { onConflict: "profile_id,week_start" });

    results[executiveId] = {
      status: "ok",
      detail: `Strategic synthesis generated from ${summaries.length} daily summaries`,
      contradictions: synthesisData.key_contradictions?.length ?? 0,
      emerging_risks: synthesisData.emerging_risks?.length ?? 0,
      tokens_used: response.usage.input_tokens + response.usage.output_tokens,
      duration_ms: Date.now() - start,
    };
  }

  // Log health
  await client.from("pipeline_health_log").insert({
    check_type: "weekly_synthesis",
    status: "ok",
    details: { results, duration_ms: Date.now() - start },
  });

  log.info("complete", { executives_processed: executives.length, duration_ms: Date.now() - start });
  return new Response(JSON.stringify({
    pipeline: "weekly-strategic-synthesis",
    duration_ms: Date.now() - start,
    results,
  }), { status: 200, headers: { "Content-Type": "application/json" } });
  } catch (err) {
    log.error("unhandled", err);
    return new Response(JSON.stringify({ error: err instanceof Error ? err.message : "Internal error", request_id: log.request_id }), { status: 500, headers: { "Content-Type": "application/json" } });
  }
});
