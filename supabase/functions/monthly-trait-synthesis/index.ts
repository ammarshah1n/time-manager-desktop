import { serve } from "https://deno.land/std@0.208.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { callAnthropic, extractText } from "../_shared/anthropic.ts";
import { createRequestLogger } from "../_shared/logger.ts";
import { requireEnv } from "../_shared/config.ts";

// Phase 7.03: Monthly Trait Synthesis
// Stage A: Opus 4.6 + extended thinking (64K budget), temp 1.0 — trait synthesis
// Stage B: Opus 4.6 — prediction generation from traits with precision >= 0.7

const SUPABASE_URL = requireEnv("SUPABASE_URL");
const SUPABASE_SERVICE_KEY = requireEnv("SUPABASE_SERVICE_ROLE_KEY");

serve(async (req: Request) => {
  const log = createRequestLogger("monthly-trait-synthesis");
  try {
  if (req.method === "OPTIONS") {
    return new Response("ok", { status: 200 });
  }

  const client = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY);
  const start = Date.now();

  let body: { executive_id: string } | null = null;
  try {
    body = await req.json();
  } catch {
    return new Response(JSON.stringify({ error: "Invalid request body" }), { status: 400 });
  }

  if (!body?.executive_id) {
    return new Response(JSON.stringify({ error: "executive_id required" }), { status: 400 });
  }

  const executiveId = body.executive_id;

  // Fetch confirmed Tier 2 signatures
  const { data: confirmedSigs } = await client
    .from("tier2_behavioural_signatures")
    .select("*")
    .eq("profile_id", executiveId)
    .eq("status", "confirmed");

  // Fetch current Tier 3 traits
  const { data: currentTraits } = await client
    .from("tier3_personality_traits")
    .select("*")
    .eq("profile_id", executiveId)
    .is("valid_to", null); // Only active traits

  // Fetch last 30 daily summaries for evidence
  const thirtyDaysAgo = new Date(Date.now() - 30 * 86400000).toISOString().slice(0, 10);
  const { data: monthlySummaries } = await client
    .from("tier1_daily_summaries")
    .select("summary_date, day_narrative, significant_events, anomalies")
    .eq("profile_id", executiveId)
    .gte("summary_date", thirtyDaysAgo)
    .order("summary_date", { ascending: true });

  if (!confirmedSigs || confirmedSigs.length < 2) {
    return new Response(JSON.stringify({
      status: "insufficient_data",
      detail: `Only ${confirmedSigs?.length ?? 0} confirmed signatures, need 2+`,
    }), { status: 200 });
  }

  // === STAGE A: Trait Synthesis ===
  const sigText = confirmedSigs.map((s) =>
    `- "${s.signature_name}" (${s.pattern_type}): ${s.description?.slice(0, 300)} | confidence: ${s.confidence} | obs: ${s.observation_count} | cross-domain: ${JSON.stringify(s.cross_domain_correlations)}`
  ).join("\n");

  const traitText = (currentTraits ?? []).map((t) =>
    `- "${t.trait_name}" (${t.trait_type}): precision ${t.precision} | version ${t.version} | trajectory: ${t.trajectory_narrative?.slice(0, 200)}`
  ).join("\n");

  const summaryText = (monthlySummaries ?? []).map((s) =>
    `[${s.summary_date}] ${s.day_narrative?.slice(0, 200)}`
  ).join("\n");

  const synthesisResponse = await callAnthropic({
    model: "claude-opus-4-6",
    max_tokens: 8192,
    thinking: { type: "enabled", budget_tokens: 65536 },
    temperature: 1.0,
    messages: [{
      role: "user",
      content: `You are synthesising personality traits from confirmed behavioural signatures for a C-suite executive.

CONFIRMED TIER 2 SIGNATURES (${confirmedSigs.length}):
${sigText}

CURRENT TIER 3 TRAITS (${currentTraits?.length ?? 0}):
${traitText || "None yet — this is the first synthesis"}

LAST 30 DAYS OF DAILY SUMMARIES:
${summaryText}

TASK:
For each existing trait: is evidence still supporting it? Should precision increase/decrease? Split/merge/retire?
For confirmed signatures without a parent trait: should a new trait emerge?
For each trait: write a trajectory narrative (how this trait has evolved).

Apply cathartic update rules:
- Temporary deviation → precision *= 0.9
- Permanent shift → new version (supersede old)
- Novel emergence → new trait with precision 0.3

Output JSON:
{
  "trait_updates": [{"trait_id": "...", "action": "reinforce|weaken|split|merge|retire", "new_precision": 0.0-1.0, "trajectory_narrative": "...", "evidence": "..."}],
  "new_traits": [{"trait_name": "...", "trait_type": "cognitive|behavioural|interpersonal|temporal", "description": "...", "precision": 0.3, "evidence_chain": ["sig_id1", "sig_id2"], "trajectory_narrative": "...", "valence_vector": {"openness": 0.0, "conscientiousness": 0.0, "extraversion": 0.0, "agreeableness": 0.0, "neuroticism": 0.0}}],
  "retired_traits": [{"trait_id": "...", "reason": "..."}],
  "summary": "2-3 sentences on the executive's evolving cognitive profile"
}`,
    }],
  });

  const synthesisText = extractText(synthesisResponse);
  let synthesis;
  try {
    synthesis = JSON.parse(synthesisText);
  } catch {
    synthesis = { raw: synthesisText, trait_updates: [], new_traits: [], retired_traits: [] };
  }

  // Apply trait updates
  for (const update of synthesis.trait_updates ?? []) {
    if (!update.trait_id) continue;
    if (update.action === "retire") {
      await client
        .from("tier3_personality_traits")
        .update({ valid_to: new Date().toISOString(), updated_at: new Date().toISOString() })
        .eq("id", update.trait_id);
    } else {
      await client
        .from("tier3_personality_traits")
        .update({
          precision: update.new_precision,
          trajectory_narrative: update.trajectory_narrative,
          updated_at: new Date().toISOString(),
        })
        .eq("id", update.trait_id);
    }
  }

  // Insert new traits
  for (const t of synthesis.new_traits ?? []) {
    await client.from("tier3_personality_traits").insert({
      profile_id: executiveId,
      trait_name: t.trait_name,
      trait_type: t.trait_type ?? "behavioural",
      version: 1,
      precision: t.precision ?? 0.3,
      valence_vector: t.valence_vector ?? {},
      evidence_chain: t.evidence_chain ?? [],
      trajectory_narrative: t.trajectory_narrative,
      valid_from: new Date().toISOString(),
    });
  }

  // === STAGE B: Prediction Generation ===
  // Only from traits with precision >= 0.7
  const highPrecisionTraits = [
    ...(currentTraits ?? []).filter((t) => t.precision >= 0.7),
    ...(synthesis.new_traits ?? []).filter((t: { precision: number }) => t.precision >= 0.7),
  ];

  let predictions: unknown[] = [];

  if (highPrecisionTraits.length > 0) {
    // Fetch next 14 days of calendar
    const fourteenDaysOut = new Date(Date.now() + 14 * 86400000).toISOString();
    const { data: upcomingCalendar } = await client
      .from("tier0_observations")
      .select("summary, raw_data, occurred_at")
      .eq("profile_id", executiveId)
      .eq("source", "calendar")
      .gte("occurred_at", new Date().toISOString())
      .lte("occurred_at", fourteenDaysOut)
      .limit(50);

    const traitContext = highPrecisionTraits.map((t) =>
      `- "${t.trait_name}" (precision ${t.precision}): ${t.trajectory_narrative?.slice(0, 200) ?? t.description?.slice(0, 200)}`
    ).join("\n");

    const calendarContext = (upcomingCalendar ?? []).map((c) =>
      `[${new Date(c.occurred_at).toLocaleDateString()}] ${c.summary ?? JSON.stringify(c.raw_data).slice(0, 150)}`
    ).join("\n");

    const predictionResponse = await callAnthropic({
      model: "claude-opus-4-6",
      max_tokens: 4096,
      thinking: { type: "enabled", budget_tokens: 32768 },
      messages: [{
        role: "user",
        content: `Based on confirmed personality traits, generate falsifiable behavioural predictions for the next 14 days.

HIGH-PRECISION TRAITS:
${traitContext}

UPCOMING CALENDAR (14 days):
${calendarContext || "No calendar data available"}

RULES:
- Only predict from traits with precision >= 0.7
- Cross-trait predictions require minimum confidence 0.7
- Each prediction must have explicit falsification criteria
- Language: "patterns consistent with..." never "you will..."
- Include grounding trait IDs

Output JSON:
{
  "predictions": [{
    "prediction_type": "avoidance|decision_pattern|energy|communication|relationship",
    "predicted_behaviour": "...",
    "time_window_days": 14,
    "confidence": 0.0-1.0,
    "grounding_trait_names": ["..."],
    "falsification_criteria": "This prediction is wrong if...",
    "evidence_basis": "..."
  }]
}`,
      }],
    });

    const predText = extractText(predictionResponse);
    try {
      const parsed = JSON.parse(predText);
      predictions = parsed.predictions ?? [];
    } catch {
      // Non-fatal
    }

    // Insert predictions
    for (const p of predictions as Array<Record<string, unknown>>) {
      await client.from("predictions").insert({
        profile_id: executiveId,
        prediction_type: p.prediction_type,
        predicted_behaviour: p.predicted_behaviour,
        time_window: `${p.time_window_days ?? 14} days`,
        confidence: p.confidence,
        grounding_trait_ids: p.grounding_trait_names ?? [],
        falsification_criteria: p.falsification_criteria,
        status: "active",
      });
    }
  }

  log.info("complete", {
    executive_id: executiveId,
    confirmed_signatures: confirmedSigs.length,
    predictions_generated: predictions.length,
  });
  return new Response(JSON.stringify({
    status: "ok",
    stage_a: {
      confirmed_signatures: confirmedSigs.length,
      trait_updates: synthesis.trait_updates?.length ?? 0,
      new_traits: synthesis.new_traits?.length ?? 0,
      retired_traits: synthesis.retired_traits?.length ?? 0,
    },
    stage_b: {
      high_precision_traits: highPrecisionTraits.length,
      predictions_generated: predictions.length,
    },
    synthesis_tokens: synthesisResponse.usage.input_tokens + synthesisResponse.usage.output_tokens,
    duration_ms: Date.now() - start,
  }), { status: 200, headers: { "Content-Type": "application/json" } });
  } catch (err) {
    log.error("unhandled", err);
    return new Response(JSON.stringify({ error: err instanceof Error ? err.message : "Internal error", request_id: log.request_id }), { status: 500, headers: { "Content-Type": "application/json" } });
  }
});
