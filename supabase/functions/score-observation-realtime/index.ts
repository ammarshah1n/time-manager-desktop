import { serve } from "https://deno.land/std@0.208.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { callAnthropic, extractText } from "../_shared/anthropic.ts";
import { verifyAuth, AuthError, authErrorResponse } from "../_shared/auth.ts";
import { createRequestLogger } from "../_shared/logger.ts";
import { requireEnv } from "../_shared/config.ts";

// Real-time importance scoring via Haiku 4.5 at ingestion time.
// Called by Swift client after Tier0Writer writes observations.
// Research grounding: v3-02 (no CoT on classification), v3-05 (dual-scoring architecture)

const SUPABASE_URL = requireEnv("SUPABASE_URL");
const SUPABASE_SERVICE_KEY = requireEnv("SUPABASE_SERVICE_ROLE_KEY");

// Alert thresholds from v3-05 research
const ALERT_IMMEDIATE = 0.90;
const ALERT_PRELIMINARY = 0.80;
const ALERT_BATCH_GATE = 0.75;

serve(async (req: Request) => {
  const log = createRequestLogger("score-observation-realtime");
  try {
  if (req.method === "OPTIONS") {
    return new Response("ok", { status: 200 });
  }

  let authUserId: string;
  try {
    authUserId = await verifyAuth(req);
  } catch (err) {
    if (err instanceof AuthError) return authErrorResponse(err);
    throw err;
  }

  const client = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY);
  const start = Date.now();

  // Bind to the authenticated executive — service role bypasses RLS, so all
  // observation fetches must be filtered by the caller's profile_id.
  const { data: exec, error: execErr } = await client
    .from("executives")
    .select("id")
    .eq("auth_user_id", authUserId)
    .maybeSingle();
  if (execErr || !exec) {
    return new Response(JSON.stringify({ error: "No executive row for this user" }), {
      status: 401, headers: { "Content-Type": "application/json" },
    });
  }
  const executiveId = exec.id as string;

  const { observation_ids } = await req.json() as { observation_ids: string[] };
  if (!observation_ids?.length) {
    return new Response(JSON.stringify({ error: "No observation_ids provided" }), { status: 400 });
  }

  // Fetch the observations to score — scoped to the caller's profile so a user
  // can never trigger scoring on rows they don't own.
  const { data: observations, error: fetchError } = await client
    .from("tier0_observations")
    .select("id, profile_id, summary, source, event_type, raw_data, occurred_at")
    .in("id", observation_ids)
    .eq("profile_id", executiveId)
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
  const rtScoredAt = new Date().toISOString();

  // Accumulate writes for batching
  const rtUpdates = [];
  const auditRows = [];
  const alertRows = [];

  for (let i = 0; i < Math.min(scores.length, observations.length); i++) {
    const rtScore = Math.max(1, Math.min(10, scores[i])) / 10.0;
    const obs = observations[i];

    rtUpdates.push(client
      .from("tier0_observations")
      .update({ rt_score: rtScore, rt_scored_at: rtScoredAt, rt_model: "claude-haiku-4-5-20251001" })
      .eq("id", obs.id));

    auditRows.push({
      profile_id: obs.profile_id,
      observation_id: obs.id,
      event_type: "realtime_scored",
      rt_score: rtScore,
      details: { source: obs.source, event_type: obs.event_type, day_context: dayContext },
    });

    if (rtScore >= ALERT_IMMEDIATE) {
      alerts.push({ observation_id: obs.id, score: rtScore, level: "immediate" });
      alertRows.push({ profile_id: obs.profile_id, observation_id: obs.id, status: "fired", fire_score: rtScore, fire_model: "claude-haiku-4-5-20251001" });
    } else if (rtScore >= ALERT_PRELIMINARY) {
      alerts.push({ observation_id: obs.id, score: rtScore, level: "preliminary" });
      alertRows.push({ profile_id: obs.profile_id, observation_id: obs.id, status: "fired", fire_score: rtScore, fire_model: "claude-haiku-4-5-20251001", annotation_text: "Preliminary — awaiting batch confirmation" });
    } else if (rtScore >= ALERT_BATCH_GATE) {
      alerts.push({ observation_id: obs.id, score: rtScore, level: "batch_gate" });
      alertRows.push({ profile_id: obs.profile_id, observation_id: obs.id, status: "pending", fire_score: rtScore, fire_model: "claude-haiku-4-5-20251001" });
    }

    scored++;
  }

  // Flush in parallel chunks
  await Promise.all(rtUpdates);
  if (auditRows.length) await client.from("score_audit_log").insert(auditRows);
  if (alertRows.length) await client.from("alert_states").insert(alertRows);

  log.info("complete", {
    executive_id: observations[0].profile_id,
    scored,
    alerts: alerts.length,
  });
  return new Response(JSON.stringify({
    pipeline: "score-observation-realtime",
    scored,
    alerts: alerts.length,
    alert_details: alerts,
    tokens_used: response.usage.input_tokens + response.usage.output_tokens,
    duration_ms: Date.now() - start,
  }), { status: 200, headers: { "Content-Type": "application/json" } });
  } catch (err) {
    log.error("unhandled", err);
    return new Response(JSON.stringify({ error: err instanceof Error ? err.message : "Internal error", request_id: log.request_id }), { status: 500, headers: { "Content-Type": "application/json" } });
  }
});
