import { serve } from "https://deno.land/std@0.208.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { callAnthropic, extractText } from "../_shared/anthropic.ts";

// Real-time importance scoring via Haiku 4.5 at ingestion time.
// Called by Swift client after Tier0Writer writes observations.
// Research grounding: v3-02 (no CoT on classification), v3-05 (dual-scoring architecture)

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

// Alert thresholds from v3-05 research
const ALERT_IMMEDIATE = 0.90;
const ALERT_PRELIMINARY = 0.80;
const ALERT_BATCH_GATE = 0.75;

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { status: 200 });
  }

  const client = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY);
  const start = Date.now();

  const { observation_ids } = await req.json() as { observation_ids: string[] };
  if (!observation_ids?.length) {
    return new Response(JSON.stringify({ error: "No observation_ids provided" }), { status: 400 });
  }

  // Fetch the observations to score
  const { data: observations, error: fetchError } = await client
    .from("tier0_observations")
    .select("id, profile_id, summary, source, event_type, raw_data, occurred_at")
    .in("id", observation_ids)
    .is("rt_score", null);

  if (fetchError || !observations?.length) {
    return new Response(JSON.stringify({
      status: "ok",
      detail: observations?.length ? "Fetch error" : "No unscored observations",
      duration_ms: Date.now() - start,
    }), { status: 200, headers: { "Content-Type": "application/json" } });
  }

  // Build day-context bundle for debiasing (v3-05 recommendation)
  const now = new Date();
  const todayStart = now.toISOString().slice(0, 10);
  const { count: todayCount } = await client
    .from("tier0_observations")
    .select("id", { count: "exact", head: true })
    .eq("profile_id", observations[0].profile_id)
    .gte("occurred_at", todayStart);

  const dayContext = {
    hour_of_day: now.getHours(),
    day_of_week: now.toLocaleDateString("en-AU", { weekday: "long" }),
    observations_today: todayCount ?? 0,
  };

  // Format observations for Haiku scoring
  const obsSummaries = observations.map((obs, i) =>
    `[${i}] ${obs.source}/${obs.event_type}: ${obs.summary ?? JSON.stringify(obs.raw_data).slice(0, 200)}`
  ).join("\n");

  // Haiku classification — NO thinking (CoT degrades classification accuracy per v3-02)
  const response = await callAnthropic({
    model: "claude-haiku-4-5-20251001",
    max_tokens: 1024,
    messages: [{
      role: "user",
      content: `Rate each observation's importance from 1 to 10 for a C-suite executive. Anchors: 1=routine (daily email check), 5=notable deviation (unusual response time), 10=unprecedented (emergency meeting, board escalation).

Day context: ${dayContext.day_of_week}, ${dayContext.hour_of_day}:00, ${dayContext.observations_today} observations so far today.

Output ONLY a JSON array of integers, one per observation, in order.

${obsSummaries}`,
    }],
  });

  const scoreText = extractText(response).trim();
  let scores: number[];
  try {
    scores = JSON.parse(scoreText);
  } catch {
    scores = scoreText.match(/\d+/g)?.map(Number) ?? [];
  }

  let scored = 0;
  const alerts: Array<{ observation_id: string; score: number; level: string }> = [];

  for (let i = 0; i < Math.min(scores.length, observations.length); i++) {
    const rtScore = Math.max(1, Math.min(10, scores[i])) / 10.0;
    const obs = observations[i];

    // Write RT score
    await client
      .from("tier0_observations")
      .update({
        rt_score: rtScore,
        rt_scored_at: new Date().toISOString(),
        rt_model: "claude-haiku-4-5-20251001",
      })
      .eq("id", obs.id);

    // Log to audit
    await client
      .from("score_audit_log")
      .insert({
        workspace_id: obs.profile_id,
        observation_id: obs.id,
        event_type: "realtime_scored",
        rt_score: rtScore,
        details: { source: obs.source, event_type: obs.event_type, day_context: dayContext },
      });

    // Check alert thresholds
    if (rtScore >= ALERT_IMMEDIATE) {
      alerts.push({ observation_id: obs.id, score: rtScore, level: "immediate" });
      await client.from("alert_states").insert({
        profile_id: obs.profile_id,
        observation_id: obs.id,
        status: "fired",
        fire_score: rtScore,
        fire_model: "claude-haiku-4-5-20251001",
      });
    } else if (rtScore >= ALERT_PRELIMINARY) {
      alerts.push({ observation_id: obs.id, score: rtScore, level: "preliminary" });
      await client.from("alert_states").insert({
        profile_id: obs.profile_id,
        observation_id: obs.id,
        status: "fired",
        fire_score: rtScore,
        fire_model: "claude-haiku-4-5-20251001",
        annotation_text: "Preliminary — awaiting batch confirmation",
      });
    } else if (rtScore >= ALERT_BATCH_GATE) {
      alerts.push({ observation_id: obs.id, score: rtScore, level: "batch_gate" });
      await client.from("alert_states").insert({
        profile_id: obs.profile_id,
        observation_id: obs.id,
        status: "pending",
        fire_score: rtScore,
        fire_model: "claude-haiku-4-5-20251001",
      });
    }

    scored++;
  }

  return new Response(JSON.stringify({
    pipeline: "score-observation-realtime",
    scored,
    alerts: alerts.length,
    alert_details: alerts,
    tokens_used: response.usage.input_tokens + response.usage.output_tokens,
    duration_ms: Date.now() - start,
  }), { status: 200, headers: { "Content-Type": "application/json" } });
});
