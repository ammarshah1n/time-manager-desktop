import { serve } from "https://deno.land/std@0.208.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { callAnthropic, extractText } from "../_shared/anthropic.ts";
import { createRequestLogger } from "../_shared/logger.ts";
import { requireEnv } from "../_shared/config.ts";

import { verifyServiceRole, AuthError, authErrorResponse } from "../_shared/auth.ts";
// Phase 5.04: 48-hour thin-slice inference
// Triggered on Day 3 (or when sufficient observations exist)
// Opus 4.6 analyses accumulated data for initial executive profile

const SUPABASE_URL = requireEnv("SUPABASE_URL");
const SUPABASE_SERVICE_KEY = requireEnv("SUPABASE_SERVICE_ROLE_KEY");

serve(async (req: Request) => {
  const log = createRequestLogger("thin-slice-inference");
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

  // Gather all available observations
  const { data: emailObs, count: emailCount } = await client
    .from("tier0_observations")
    .select("source, event_type, summary, raw_data, occurred_at, importance_score", { count: "exact" })
    .eq("profile_id", executiveId)
    .eq("source", "email")
    .order("occurred_at", { ascending: false })
    .limit(200);

  const { data: calObs, count: calCount } = await client
    .from("tier0_observations")
    .select("source, event_type, summary, raw_data, occurred_at", { count: "exact" })
    .eq("profile_id", executiveId)
    .eq("source", "calendar")
    .order("occurred_at", { ascending: false })
    .limit(100);

  const totalObs = (emailCount ?? 0) + (calCount ?? 0);
  if (totalObs < 20) {
    return new Response(JSON.stringify({
      status: "insufficient_data",
      detail: `Only ${totalObs} observations available, need 20+`,
    }), { status: 200 });
  }

  // Format observations for Opus
  const emailSummary = (emailObs ?? []).map((o) =>
    `[${new Date(o.occurred_at).toLocaleDateString()}] ${o.event_type}: ${o.summary ?? JSON.stringify(o.raw_data).slice(0, 200)}`
  ).join("\n");

  const calSummary = (calObs ?? []).map((o) =>
    `[${new Date(o.occurred_at).toLocaleDateString()}] ${o.event_type}: ${o.summary ?? JSON.stringify(o.raw_data).slice(0, 200)}`
  ).join("\n");

  const response = await callAnthropic({
    model: "claude-opus-4-6",
    max_tokens: 4096,
    thinking: { type: "enabled", budget_tokens: 16384 },
    messages: [{
      role: "user",
      content: `You are generating a thin-slice inference for a C-suite executive based on ${totalObs} observations (${emailCount} email, ${calCount} calendar). This is the system's first impression — frame as "Based on 48 hours of observation and [N] years of email history, here is what I'm beginning to see."\n\nAnalyse for:\n1. Communication energy: rapid responder vs deliberate batched\n2. Network structure: hub-and-spoke vs distributed vs hierarchical\n3. Time sovereignty: controls own calendar vs calendar-controlled\n4. Cognitive load trajectory: building through week vs front-loaded vs chaotic\n\nOutput JSON:\n{\n  "communication_energy": {"style": "...", "evidence": "...", "confidence": 0.0-1.0},\n  "network_structure": {"style": "...", "evidence": "...", "confidence": 0.0-1.0},\n  "time_sovereignty": {"style": "...", "evidence": "...", "confidence": 0.0-1.0},\n  "cognitive_load_trajectory": {"pattern": "...", "evidence": "...", "confidence": 0.0-1.0},\n  "summary_narrative": "2-3 sentences framing what we're beginning to see"\n}\n\nEMAIL OBSERVATIONS (${emailCount}):\n${emailSummary.slice(0, 10000)}\n\nCALENDAR OBSERVATIONS (${calCount}):\n${calSummary.slice(0, 5000)}`,
    }],
  });

  const inferenceText = extractText(response);
  let inference;
  try {
    inference = JSON.parse(inferenceText);
  } catch {
    inference = { raw: inferenceText };
  }

  // Store as Tier 1 summary with special type
  await client.from("tier1_daily_summaries").insert({
    profile_id: executiveId,
    summary_date: new Date().toISOString().slice(0, 10),
    day_narrative: inference.summary_narrative ?? inferenceText,
    significant_events: [{ type: "thin_slice_inference", data: inference }],
    anomalies: [],
    energy_profile: inference.cognitive_load_trajectory ?? {},
    signals_aggregated: totalObs,
    generated_by: "thin-slice-inference",
    source_tier0_count: totalObs,
  });

  log.info("complete", { executive_id: executiveId, observations_analysed: totalObs });
  return new Response(JSON.stringify({
    status: "ok",
    observations_analysed: totalObs,
    inference,
    tokens_used: response.usage.input_tokens + response.usage.output_tokens,
  }), { status: 200, headers: { "Content-Type": "application/json" } });
  } catch (err) {
    log.error("unhandled", err);
    return new Response(JSON.stringify({ error: err instanceof Error ? err.message : "Internal error", request_id: log.request_id }), { status: 500, headers: { "Content-Type": "application/json" } });
  }
});
