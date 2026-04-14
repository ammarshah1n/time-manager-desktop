import { serve } from "https://deno.land/std@0.208.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { callAnthropic, extractText } from "../_shared/anthropic.ts";
import { createRequestLogger } from "../_shared/logger.ts";
import { requireEnv } from "../_shared/config.ts";

// Phase 8.06: Multi-agent council for high-stakes decisions
// 3 specialist Opus agents in parallel + leader synthesis
// Trigger: alert composite > 0.7 AND prediction confidence > 0.75 AND coaching stage >= workingAlliance

const SUPABASE_URL = requireEnv("SUPABASE_URL");
const SUPABASE_SERVICE_KEY = requireEnv("SUPABASE_SERVICE_ROLE_KEY");

serve(async (req: Request) => {
  const log = createRequestLogger("multi-agent-council");
  try {
  if (req.method === "OPTIONS") {
    return new Response("ok", { status: 200 });
  }

  const client = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY);
  const start = Date.now();

  let body: { executive_id: string; trigger_context: string; alert_score?: number } | null = null;
  try {
    body = await req.json();
  } catch {
    return new Response(JSON.stringify({ error: "Invalid request body" }), { status: 400 });
  }

  if (!body?.executive_id) {
    return new Response(JSON.stringify({ error: "executive_id required" }), { status: 400 });
  }

  const executiveId = body.executive_id;
  const triggerContext = body.trigger_context ?? "high-stakes decision detected";

  // Fetch ACB-FULL for all agents
  const { data: acb } = await client
    .rpc("get_acb_full", { exec_id: executiveId });

  // Fetch today's calendar
  const today = new Date().toISOString().slice(0, 10);
  const { data: calendarToday } = await client
    .from("tier0_observations")
    .select("summary, raw_data, occurred_at")
    .eq("profile_id", executiveId)
    .eq("source", "calendar")
    .gte("occurred_at", today)
    .order("occurred_at", { ascending: true })
    .limit(20);

  // Fetch recent predictions
  const { data: activePredictions } = await client
    .from("predictions")
    .select("prediction_type, predicted_behaviour, confidence, status")
    .eq("profile_id", executiveId)
    .eq("status", "active")
    .limit(10);

  // Fetch Tier 2 signatures
  const { data: signatures } = await client
    .from("tier2_behavioural_signatures")
    .select("signature_name, pattern_type, description, confidence")
    .eq("profile_id", executiveId)
    .eq("status", "confirmed")
    .limit(15);

  const acbText = acb ? JSON.stringify(acb).slice(0, 8000) : "Not available";
  const calendarText = (calendarToday ?? []).map((c) =>
    `[${new Date(c.occurred_at).toLocaleTimeString()}] ${c.summary ?? JSON.stringify(c.raw_data).slice(0, 150)}`
  ).join("\n");
  const predictionText = (activePredictions ?? []).map((p) =>
    `- [${p.prediction_type}] ${p.predicted_behaviour} (confidence: ${p.confidence})`
  ).join("\n");
  const signatureText = (signatures ?? []).map((s) =>
    `- "${s.signature_name}" (${s.pattern_type}): ${s.description?.slice(0, 150)}`
  ).join("\n");

  // === PARALLEL AGENT CALLS ===
  const [energyResult, priorityResult, patternResult] = await Promise.all([
    // Agent 1: Energy specialist
    callAnthropic({
      model: "claude-opus-4-6",
      max_tokens: 2048,
      thinking: { type: "enabled", budget_tokens: 16384 },
      temperature: 0.3,
      messages: [{
        role: "user",
        content: `You are the ENERGY specialist agent in a multi-agent council evaluating a high-stakes moment for an executive.

TRIGGER: ${triggerContext}

ACB-FULL:
${acbText}

TODAY'S CALENDAR:
${calendarText || "No calendar data"}

Your analysis scope:
- Current energy state based on calendar load, time of day, meeting density
- Recent cognitive load trajectory
- Sleep/recovery indicators (if available in ACB)
- Whether this is an optimal moment for high-stakes decision-making

Output JSON:
{"energy_assessment": "...", "optimal_for_decisions": true/false, "risk_factors": ["..."], "recommendation": "...", "confidence": 0.0-1.0}`,
      }],
    }),

    // Agent 2: Priority specialist
    callAnthropic({
      model: "claude-opus-4-6",
      max_tokens: 2048,
      thinking: { type: "enabled", budget_tokens: 16384 },
      temperature: 0.3,
      messages: [{
        role: "user",
        content: `You are the PRIORITY specialist agent in a multi-agent council evaluating a high-stakes moment for an executive.

TRIGGER: ${triggerContext}

ACB-FULL:
${acbText}

ACTIVE PREDICTIONS:
${predictionText || "No active predictions"}

Your analysis scope:
- Task urgency and deadline pressure related to the trigger
- Dependency chains that make this time-sensitive
- What the executive has stated matters most (from traits/ACB)
- Opportunity cost of delay vs action

Output JSON:
{"priority_assessment": "...", "urgency": "critical|high|moderate|low", "delay_cost": "...", "action_benefit": "...", "recommendation": "...", "confidence": 0.0-1.0}`,
      }],
    }),

    // Agent 3: Pattern specialist
    callAnthropic({
      model: "claude-opus-4-6",
      max_tokens: 2048,
      thinking: { type: "enabled", budget_tokens: 16384 },
      temperature: 0.3,
      messages: [{
        role: "user",
        content: `You are the PATTERN specialist agent in a multi-agent council evaluating a high-stakes moment for an executive.

TRIGGER: ${triggerContext}

CONFIRMED BEHAVIOURAL SIGNATURES:
${signatureText || "No confirmed signatures"}

ACTIVE PREDICTIONS:
${predictionText || "No active predictions"}

ACB-FULL:
${acbText}

Your analysis scope:
- Historical patterns that match the current situation
- Past outcomes in similar decision contexts
- Whether current behaviour matches or deviates from established patterns
- Prediction track record for this type of situation

Output JSON:
{"pattern_assessment": "...", "historical_match": "strong|moderate|weak|novel", "similar_past_outcomes": ["..."], "deviation_from_pattern": true/false, "recommendation": "...", "confidence": 0.0-1.0}`,
      }],
    }),
  ]);

  // Parse specialist outputs
  let energyAnalysis, priorityAnalysis, patternAnalysis;
  try { energyAnalysis = JSON.parse(extractText(energyResult)); } catch { energyAnalysis = { raw: extractText(energyResult) }; }
  try { priorityAnalysis = JSON.parse(extractText(priorityResult)); } catch { priorityAnalysis = { raw: extractText(priorityResult) }; }
  try { patternAnalysis = JSON.parse(extractText(patternResult)); } catch { patternAnalysis = { raw: extractText(patternResult) }; }

  // === LEADER SYNTHESIS ===
  const leaderResponse = await callAnthropic({
    model: "claude-opus-4-6",
    max_tokens: 2048,
    thinking: { type: "enabled", budget_tokens: 16384 },
    messages: [{
      role: "user",
      content: `You are the LEADER agent synthesising 3 specialist analyses into a final recommendation for a C-suite executive.

TRIGGER: ${triggerContext}

ENERGY SPECIALIST:
${JSON.stringify(energyAnalysis)}

PRIORITY SPECIALIST:
${JSON.stringify(priorityAnalysis)}

PATTERN SPECIALIST:
${JSON.stringify(patternAnalysis)}

Synthesise into a single recommendation with:
1. Clear action recommendation (1-2 sentences)
2. Confidence interval combining all three perspectives
3. Key risk the executive should be aware of
4. Dissenting view (if any specialist disagrees)

Output JSON:
{
  "recommendation": "...",
  "confidence": 0.0-1.0,
  "key_risk": "...",
  "dissenting_view": "..." or null,
  "reasoning_chain": {"energy": "...", "priority": "...", "pattern": "..."},
  "alert_text": "1-2 sentence alert for the executive"
}`,
    }],
  });

  let synthesis;
  try { synthesis = JSON.parse(extractText(leaderResponse)); } catch { synthesis = { raw: extractText(leaderResponse) }; }

  const totalTokens = [energyResult, priorityResult, patternResult, leaderResponse]
    .reduce((sum, r) => sum + r.usage.input_tokens + r.usage.output_tokens, 0);

  log.info("complete", { executive_id: executiveId, trigger_context: triggerContext, tokens_used: totalTokens });
  return new Response(JSON.stringify({
    status: "ok",
    trigger: triggerContext,
    specialist_outputs: {
      energy: energyAnalysis,
      priority: priorityAnalysis,
      pattern: patternAnalysis,
    },
    synthesis,
    tokens_used: totalTokens,
    duration_ms: Date.now() - start,
  }), { status: 200, headers: { "Content-Type": "application/json" } });
  } catch (err) {
    log.error("unhandled", err);
    return new Response(JSON.stringify({ error: err instanceof Error ? err.message : "Internal error", request_id: log.request_id }), { status: 500, headers: { "Content-Type": "application/json" } });
  }
});
