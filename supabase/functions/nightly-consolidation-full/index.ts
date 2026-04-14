import { serve } from "https://deno.land/std@0.208.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { callAnthropic, extractText, submitBatch } from "../_shared/anthropic.ts";
import type { AnthropicModel } from "../_shared/anthropic.ts";
import { createRequestLogger } from "../_shared/logger.ts";
import { requireEnv } from "../_shared/config.ts";

// Cron: 0 2 * * * (2 AM local)
// Orchestrates: importance scoring → conflict detection → daily summary → ACB generation → self-improvement loop

const SUPABASE_URL = requireEnv("SUPABASE_URL");
const SUPABASE_SERVICE_KEY = requireEnv("SUPABASE_SERVICE_ROLE_KEY");
const MAX_IMPORTANCE_BATCH = 200;
const WRITE_CHUNK_SIZE = 50;

type SupabaseClient = ReturnType<typeof createClient>;

type StepResult = {
  status: "ok" | "skipped" | "error";
  detail: string;
  duration_ms: number;
  tokens_used?: number;
};

function hashCode(str: string): number {
  let hash = 0;
  for (let i = 0; i < str.length; i++) {
    hash = ((hash << 5) - hash) + str.charCodeAt(i);
    hash |= 0;
  }
  return Math.abs(hash);
}

async function acquireAdvisoryLock(client: SupabaseClient, executiveId: string): Promise<boolean> {
  const { data } = await client.rpc("pg_try_advisory_lock", { key: hashCode(executiveId) });
  return data === true;
}

async function releaseAdvisoryLock(client: SupabaseClient, executiveId: string): Promise<void> {
  await client.rpc("pg_advisory_unlock", { key: hashCode(executiveId) });
}

// ── Phase 3.03: Two-Pass Importance Scoring ──

async function runImportanceScoring(client: SupabaseClient, executiveId: string): Promise<StepResult> {
  const start = Date.now();
  let totalTokens = 0;

  // Fetch unscored observations (default importance_score = 0.5)
  const { data: unscored } = await client
    .from("tier0_observations")
    .select("id, summary, source, event_type, raw_data")
    .eq("profile_id", executiveId)
    .eq("importance_score", 0.5)
    .eq("is_processed", false)
    .limit(MAX_IMPORTANCE_BATCH);

  if (!unscored?.length) {
    return { status: "skipped", detail: "No unscored observations", duration_ms: Date.now() - start };
  }

  // Pass 1: Haiku batch-scores all observations
  const observationSummaries = unscored.map((obs, i) =>
    `[${i}] ${obs.source}/${obs.event_type}: ${obs.summary ?? JSON.stringify(obs.raw_data).slice(0, 200)}`
  ).join("\n");

  const pass1Response = await callAnthropic({
    model: "claude-haiku-4-5-20251001",
    max_tokens: 2048,
    temperature: 0,
    messages: [{
      role: "user",
      content: `Rate each observation's importance from 1 to 10. Anchors: 1=routine (daily email check), 5=notable deviation (unusual response time), 10=unprecedented (emergency meeting, board escalation). Output ONLY a JSON array of integers, one per observation, in order.\n\n${observationSummaries}`,
    }],
  });

  totalTokens += pass1Response.usage.input_tokens + pass1Response.usage.output_tokens;

  // Parse Haiku scores
  const scoreText = extractText(pass1Response).trim();
  let scores: number[];
  try {
    scores = JSON.parse(scoreText);
  } catch {
    // Fallback: extract numbers from text
    scores = scoreText.match(/\d+/g)?.map(Number) ?? [];
  }

  // Update batch scores in parallel chunks
  const pass1ScoredAt = new Date().toISOString();
  const pass1Updates = [];
  for (let i = 0; i < Math.min(scores.length, unscored.length); i++) {
    const score = Math.max(1, Math.min(10, scores[i])) / 10.0;
    pass1Updates.push(client
      .from("tier0_observations")
      .update({ batch_score: score, batch_scored_at: pass1ScoredAt, batch_model: "claude-haiku-4-5-20251001" })
      .eq("id", unscored[i].id));
  }
  for (let j = 0; j < pass1Updates.length; j += WRITE_CHUNK_SIZE) {
    await Promise.all(pass1Updates.slice(j, j + WRITE_CHUNK_SIZE));
  }

  // Pass 2: Sonnet re-scores uncertain band (0.55-0.75)
  const { data: uncertain } = await client
    .from("tier0_observations")
    .select("id, summary, source, event_type, raw_data")
    .eq("profile_id", executiveId)
    .gte("batch_score", 0.55)
    .lte("batch_score", 0.75)
    .eq("is_processed", false)
    .limit(50);

  if (uncertain?.length) {
    const uncertainSummaries = uncertain.map((obs, i) =>
      `[${i}] ${obs.source}/${obs.event_type}: ${obs.summary ?? JSON.stringify(obs.raw_data).slice(0, 300)}`
    ).join("\n");

    const pass2Response = await callAnthropic({
      model: "claude-sonnet-4-6",
      max_tokens: 4096,
      thinking: { type: "enabled", budget_tokens: 4096 },
      messages: [{
        role: "user",
        content: `You are scoring observations for a C-suite executive's cognitive intelligence system. Rate each observation 1-10. Consider behavioural context: a subtle change in communication pattern may be more important than an obvious schedule change. Output ONLY a JSON array of integers.\n\n${uncertainSummaries}`,
      }],
    });

    totalTokens += pass2Response.usage.input_tokens + pass2Response.usage.output_tokens;

    const pass2Text = extractText(pass2Response).trim();
    let pass2Scores: number[];
    try {
      pass2Scores = JSON.parse(pass2Text);
    } catch {
      pass2Scores = pass2Text.match(/\d+/g)?.map(Number) ?? [];
    }

    const pass2ScoredAt = new Date().toISOString();
    const pass2Updates = [];
    for (let i = 0; i < Math.min(pass2Scores.length, uncertain.length); i++) {
      const score = Math.max(1, Math.min(10, pass2Scores[i])) / 10.0;
      pass2Updates.push(client
        .from("tier0_observations")
        .update({ batch_score: score, batch_scored_at: pass2ScoredAt, batch_model: "claude-sonnet-4-6" })
        .eq("id", uncertain[i].id));
    }
    for (let j = 0; j < pass2Updates.length; j += WRITE_CHUNK_SIZE) {
      await Promise.all(pass2Updates.slice(j, j + WRITE_CHUNK_SIZE));
    }
  }

  return {
    status: "ok",
    detail: `Scored ${unscored.length} observations (Pass 1: Haiku), ${uncertain?.length ?? 0} re-scored (Pass 2: Sonnet)`,
    duration_ms: Date.now() - start,
    tokens_used: totalTokens,
  };
}

// ── Phase 3.04: Conflict Detection ──

async function runConflictDetection(client: SupabaseClient, executiveId: string): Promise<StepResult> {
  const start = Date.now();
  let totalTokens = 0;

  const today = new Date().toISOString().slice(0, 10);
  const { data: todayObs } = await client
    .from("tier0_observations")
    .select("id, summary, source, event_type, raw_data, importance_score")
    .eq("profile_id", executiveId)
    .gte("occurred_at", today)
    .gte("importance_score", 0.6)
    .order("importance_score", { ascending: false })
    .limit(20);

  if (!todayObs?.length) {
    return { status: "skipped", detail: "No high-importance observations today", duration_ms: Date.now() - start };
  }

  // Fetch existing Tier 2+3 signatures/traits for contradiction checking
  const { data: tier2 } = await client
    .from("tier2_behavioural_signatures")
    .select("id, signature_name, description, status")
    .eq("profile_id", executiveId)
    .in("status", ["confirmed", "developing"]);

  const { data: tier3 } = await client
    .from("tier3_personality_traits")
    .select("id, trait_name, description")
    .eq("profile_id", executiveId)
    .is("valid_to", null);

  if (!tier2?.length && !tier3?.length) {
    return { status: "skipped", detail: "No existing signatures/traits to check against", duration_ms: Date.now() - start };
  }

  const existingMemory = [
    ...(tier2 ?? []).map((s) => `[Tier2/${s.status}] ${s.signature_name}: ${s.description}`),
    ...(tier3 ?? []).map((t) => `[Tier3] ${t.trait_name}: ${t.description}`),
  ].join("\n");

  const observationList = todayObs.map((obs) =>
    `- ${obs.source}/${obs.event_type} (importance: ${obs.importance_score}): ${obs.summary ?? JSON.stringify(obs.raw_data).slice(0, 200)}`
  ).join("\n");

  const response = await callAnthropic({
    model: "claude-sonnet-4-6",
    max_tokens: 4096,
    thinking: { type: "enabled", budget_tokens: 8192 },
    messages: [{
      role: "user",
      content: `You are a behavioural contradiction detector for a cognitive intelligence system. Compare today's observations against existing behavioural signatures and personality traits.\n\nFor each observation, determine if it contradicts an existing memory. Score each potential contradiction 0.0-1.0 (0=no contradiction, 1=direct contradiction).\n\nOutput JSON array: [{observation_index: number, contradicts_id: string, contradiction_score: number, explanation: string}]\nOnly include entries with score > 0.5. If no contradictions, output [].\n\nEXISTING MEMORY:\n${existingMemory}\n\nTODAY'S OBSERVATIONS:\n${observationList}`,
    }],
  });

  totalTokens += response.usage.input_tokens + response.usage.output_tokens;

  const responseText = extractText(response).trim();
  let contradictions: Array<{ observation_index: number; contradicts_id: string; contradiction_score: number }> = [];
  try {
    contradictions = JSON.parse(responseText);
  } catch {
    contradictions = [];
  }

  // Tag observations with contradiction > 0.7 — use jsonb merge to avoid stale spread
  const tagged = contradictions.filter((c) => c.contradiction_score > 0.7);
  const tagUpdates = tagged
    .filter((c) => c.observation_index < todayObs.length)
    .map((c) => client.rpc("merge_observation_raw_data", {
      obs_id: todayObs[c.observation_index].id,
      merge_data: { contradiction_score: c.contradiction_score, contradicts_memory_id: c.contradicts_id },
    }));
  for (let j = 0; j < tagUpdates.length; j += WRITE_CHUNK_SIZE) {
    await Promise.all(tagUpdates.slice(j, j + WRITE_CHUNK_SIZE));
  }

  return {
    status: "ok",
    detail: `Checked ${todayObs.length} observations, found ${tagged.length} contradictions (score > 0.7)`,
    duration_ms: Date.now() - start,
    tokens_used: totalTokens,
  };
}

// ── Phase 3.05: Daily Summary Generation (Opus) ──

async function runDailySummary(client: SupabaseClient, executiveId: string): Promise<StepResult> {
  const start = Date.now();

  const today = new Date().toISOString().slice(0, 10);
  const { data: existing } = await client
    .from("tier1_daily_summaries")
    .select("id")
    .eq("profile_id", executiveId)
    .eq("summary_date", today)
    .maybeSingle();

  if (existing) {
    return { status: "skipped", detail: `Summary exists for ${today}`, duration_ms: Date.now() - start };
  }

  const { data: observations } = await client
    .from("tier0_observations")
    .select("id, profile_id, occurred_at, source, event_type, summary, raw_data, importance_score, batch_score, authoritative_score, baseline_deviation, is_processed")
    .eq("profile_id", executiveId)
    .gte("occurred_at", today)
    .order("occurred_at", { ascending: true });

  if (!observations?.length) {
    return { status: "skipped", detail: "No observations today", duration_ms: Date.now() - start };
  }

  const { data: baselines } = await client
    .from("baselines")
    .select("id, signal_type, metric_name, mean, stddev, sample_count")
    .eq("profile_id", executiveId);

  // Fetch ACB-FULL for context injection
  const { data: acb } = await client.rpc("get_acb_full", { exec_id: executiveId });

  const obsFormatted = observations.map((obs) => {
    const time = new Date(obs.occurred_at).toLocaleTimeString("en-AU", { hour: "2-digit", minute: "2-digit" });
    return `[${time}] ${obs.source}/${obs.event_type} (importance: ${obs.importance_score}): ${obs.summary ?? JSON.stringify(obs.raw_data).slice(0, 300)}`;
  }).join("\n");

  const baselineContext = baselines?.length
    ? baselines.map((b) => `${b.signal_type}/${b.metric_name}: mean=${b.mean?.toFixed(2)}, stddev=${b.stddev?.toFixed(2)}, n=${b.sample_count}`).join("\n")
    : "Baselines not yet established (establishment period).";

  const acbContext = acb ? JSON.stringify(acb).slice(0, 10000) : "ACB not yet generated.";

  const response = await callAnthropic({
    model: "claude-opus-4-6",
    max_tokens: 8192,
    thinking: { type: "enabled", budget_tokens: 16384 },
    system: `You are the nightly intelligence engine for a C-suite executive's cognitive system. Your task is to generate a daily summary that captures what happened today — descriptively, not interpretively. Flag anomalies that deviate >1.5σ from baselines. Note cross-signal co-occurrences (e.g., high email volume + calendar cancellation + idle period).\n\nACTIVE CONTEXT BUFFER:\n${acbContext}`,
    messages: [{
      role: "user",
      content: `Generate today's daily summary. Output valid JSON with this exact structure:\n{\n  "day_narrative": "2-4 paragraph narrative of the day",\n  "significant_events": [{"time": "HH:MM", "event": "description", "source": "signal_type", "importance": 0.0-1.0}],\n  "anomalies": [{"description": "what deviated", "sigma": 1.5, "baseline_metric": "metric_name", "actual_value": 0, "expected_value": 0}],\n  "energy_profile": {"morning": "high|medium|low", "afternoon": "high|medium|low", "evening": "high|medium|low", "overall_trajectory": "description"}\n}\n\nBASELINES:\n${baselineContext}\n\nOBSERVATIONS (${observations.length} total):\n${obsFormatted}`,
    }],
  });

  const summaryText = extractText(response);
  let summaryJson;
  try {
    summaryJson = JSON.parse(summaryText);
  } catch {
    summaryJson = { day_narrative: summaryText, significant_events: [], anomalies: [], energy_profile: {} };
  }

  // Generate embedding for the summary (Tier 1 → OpenAI 3072-dim)
  let embedding = null;
  try {
    const embedResponse = await client.functions.invoke("generate-embedding", {
      body: { texts: [summaryJson.day_narrative?.slice(0, 2000) ?? summaryText.slice(0, 2000)], tier: 1 },
    });
    if (embedResponse.data?.embeddings?.[0]) {
      embedding = embedResponse.data.embeddings[0];
    }
  } catch {
    // Embedding failure is non-fatal
  }

  // Insert daily summary
  await client.from("tier1_daily_summaries").insert({
    profile_id: executiveId,
    summary_date: today,
    day_narrative: summaryJson.day_narrative ?? summaryText,
    significant_events: summaryJson.significant_events ?? [],
    anomalies: summaryJson.anomalies ?? [],
    energy_profile: summaryJson.energy_profile ?? {},
    signals_aggregated: observations.length,
    embedding,
    generated_by: "claude-opus-4-6",
    source_tier0_count: observations.length,
  });

  // Mark all today's observations as processed
  await client
    .from("tier0_observations")
    .update({ is_processed: true, processed_at: new Date().toISOString() })
    .eq("profile_id", executiveId)
    .gte("occurred_at", today);

  return {
    status: "ok",
    detail: `Generated daily summary from ${observations.length} observations, ${summaryJson.anomalies?.length ?? 0} anomalies detected`,
    duration_ms: Date.now() - start,
    tokens_used: response.usage.input_tokens + response.usage.output_tokens,
  };
}

// ── Phase 3.07: ACB Generation (Dual Document) ──

async function runACBGeneration(client: SupabaseClient, executiveId: string): Promise<StepResult> {
  const start = Date.now();

  // Gather context for ACB generation
  const { data: tier3Traits } = await client
    .from("tier3_personality_traits")
    .select("id, trait_name, description, precision, evidence_chain, valid_from, valid_to")
    .eq("profile_id", executiveId)
    .is("valid_to", null);

  const { data: tier2Sigs } = await client
    .from("tier2_behavioural_signatures")
    .select("id, signature_name, pattern_type, description, confidence, status, supporting_tier1_ids, first_observed, last_observed")
    .eq("profile_id", executiveId)
    .in("status", ["confirmed", "developing"]);

  const { data: recentSummaries } = await client
    .from("tier1_daily_summaries")
    .select("summary_date, day_narrative, significant_events, anomalies, energy_profile")
    .eq("profile_id", executiveId)
    .order("summary_date", { ascending: false })
    .limit(7);

  const { data: predictions } = await client
    .from("predictions")
    .select("id, prediction_type, predicted_behaviour, time_window, confidence, status, brier_score, created_at")
    .eq("profile_id", executiveId)
    .in("status", ["active", "monitoring"]);

  const contextPayload = {
    tier3_traits: tier3Traits ?? [],
    tier2_signatures_confirmed: (tier2Sigs ?? []).filter((s) => s.status === "confirmed"),
    tier2_signatures_developing: (tier2Sigs ?? []).filter((s) => s.status === "developing"),
    last_7_summaries: recentSummaries ?? [],
    active_predictions: predictions ?? [],
  };

  const response = await callAnthropic({
    model: "claude-opus-4-6",
    max_tokens: 16384,
    temperature: 0,
    messages: [{
      role: "user",
      content: `Generate two Active Context Buffer documents for a C-suite executive's cognitive intelligence system.\n\nOutput valid JSON:\n{\n  "acb_full": { ... 10-12K token document with all context sections ... },\n  "acb_light": { ... 500-800 token summary ... }\n}\n\nACB-FULL sections:\n1. Active Tier 3 traits with precision + evidence chains (~3K tokens)\n2. Confirmed Tier 2 signatures, full descriptions (~2.5K tokens)\n3. Developing signatures >0.5 confidence (~1K tokens)\n4. Last 7 daily summaries (~2K tokens)\n5. Active predictions + brier scores (~500 tokens)\n6. Active contradiction log (~300 tokens)\n\nACB-LIGHT: trait names + one-liners, date/timezone/goals, prediction summary only.\n\nCONTEXT DATA:\n${JSON.stringify(contextPayload).slice(0, 30000)}`,
    }],
  });

  const acbText = extractText(response);
  let acbData;
  try {
    acbData = JSON.parse(acbText);
  } catch {
    acbData = { acb_full: { raw: acbText }, acb_light: { raw: acbText.slice(0, 800) } };
  }

  // Upsert ACB
  await client
    .from("active_context_buffer")
    .upsert({
      profile_id: executiveId,
      acb_full: acbData.acb_full,
      acb_light: acbData.acb_light,
      acb_version: Date.now(),
      acb_generated_at: new Date().toISOString(),
    }, { onConflict: "profile_id" });

  return {
    status: "ok",
    detail: `ACB generated: ${tier3Traits?.length ?? 0} traits, ${tier2Sigs?.length ?? 0} signatures, ${recentSummaries?.length ?? 0} summaries`,
    duration_ms: Date.now() - start,
    tokens_used: response.usage.input_tokens + response.usage.output_tokens,
  };
}

// ── Phase 3.08: Self-Improvement Loop (Batch API) ──

async function runSelfImprovement(client: SupabaseClient, executiveId: string): Promise<StepResult> {
  const start = Date.now();

  // Inventory: last 7 days of Tier 1 summaries
  const sevenDaysAgo = new Date(Date.now() - 7 * 86400000).toISOString().slice(0, 10);
  const { data: recentSummaries } = await client
    .from("tier1_daily_summaries")
    .select("summary_date, day_narrative, significant_events, anomalies, energy_profile, signals_aggregated")
    .eq("profile_id", executiveId)
    .gte("summary_date", sevenDaysAgo)
    .order("summary_date", { ascending: true });

  if (!recentSummaries?.length || recentSummaries.length < 3) {
    return { status: "skipped", detail: `Only ${recentSummaries?.length ?? 0} summaries (need 3+)`, duration_ms: Date.now() - start };
  }

  const { data: existingSigs } = await client
    .from("tier2_behavioural_signatures")
    .select("signature_name, description, status, confidence")
    .eq("profile_id", executiveId);

  // Submit as Batch API request (50% discount, async)
  try {
    const batchId = await submitBatch([{
      custom_id: `self-improve-${executiveId}-${new Date().toISOString().slice(0, 10)}`,
      params: {
        model: "claude-opus-4-6",
        max_tokens: 8192,
        thinking: { type: "enabled", budget_tokens: 16384 },
        messages: [{
          role: "user",
          content: `You are the self-improvement engine for a cognitive intelligence system. Analyse the last 7 days of daily summaries and identify patterns that existing Tier 2 signatures did NOT capture.\n\n5-phase process:\n1. INVENTORY: enumerate all summaries\n2. EXTRACT: identify novel patterns not in existing signatures\n3. PROPOSE: draft new signature definitions with evidence chains\n4. VALIDATE: assess whether each pattern appears across 3+ non-adjacent sessions\n5. COMMIT: for patterns passing validation, output full signature definitions\n\nOutput JSON:\n{\n  "inventory_count": number,\n  "novel_patterns": [{name, description, evidence_sessions, confidence}],\n  "proposed_signatures": [{signature_name, pattern_type, description, supporting_dates, confidence, passes_bocpd_floor: boolean}],\n  "log": "reasoning summary"\n}\n\nEXISTING SIGNATURES:\n${JSON.stringify(existingSigs ?? [])}\n\nLAST 7 SUMMARIES:\n${JSON.stringify(recentSummaries)}`,
        }],
      },
    }]);

    // Log batch submission
    await client.from("self_improvement_log").upsert({
      profile_id: executiveId,
      log_date: new Date().toISOString().slice(0, 10),
      proposed_changes: { batch_id: batchId, status: "submitted" },
      accepted_changes: {},
      rejected_reasons: {},
      validation_results: {},
    }, { onConflict: "profile_id,log_date" });

    return {
      status: "ok",
      detail: `Self-improvement batch submitted (ID: ${batchId}), results available by morning`,
      duration_ms: Date.now() - start,
    };
  } catch (error) {
    // Fallback: run synchronously if Batch API fails
    const message = error instanceof Error ? error.message : "Unknown error";
    return {
      status: "error",
      detail: `Batch API submission failed: ${message}. Will retry next night.`,
      duration_ms: Date.now() - start,
    };
  }
}

// ── Pipeline Orchestrator ──

const PIPELINE_STEPS = [
  { name: "importance_scoring", run: runImportanceScoring },
  { name: "conflict_detection", run: runConflictDetection },
  { name: "daily_summary", run: runDailySummary },
  { name: "acb_generation", run: runACBGeneration },
  { name: "self_improvement", run: runSelfImprovement },
];

serve(async (req: Request) => {
  const log = createRequestLogger("nightly-consolidation-full");
  try {
  if (req.method === "OPTIONS") {
    return new Response("ok", { status: 200 });
  }

  const client = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY);
  const pipelineStart = Date.now();

  const { data: executives, error: execError } = await client.from("executives").select("id");
  if (execError || !executives?.length) {
    return new Response(JSON.stringify({ error: "No executives found", detail: execError?.message }), { status: 500 });
  }

  const results: Record<string, Record<string, StepResult>> = {};

  for (const executive of executives) {
    const executiveId = executive.id;
    const locked = await acquireAdvisoryLock(client, executiveId);
    if (!locked) {
      results[executiveId] = { _lock: { status: "skipped", detail: "Advisory lock held", duration_ms: 0 } };
      continue;
    }

    try {
      results[executiveId] = {};
      for (const step of PIPELINE_STEPS) {
        try {
          results[executiveId][step.name] = await step.run(client, executiveId);
        } catch (error) {
          const message = error instanceof Error ? error.message : "Unknown error";
          results[executiveId][step.name] = { status: "error", detail: message, duration_ms: 0 };
        }
      }
      await client.rpc("compute_baselines", { exec_id: executiveId });
    } finally {
      await releaseAdvisoryLock(client, executiveId);
    }
  }

  await client.from("pipeline_health_log").insert({
    check_type: "nightly_pipeline",
    status: "ok",
    details: { results, total_duration_ms: Date.now() - pipelineStart },
  });

  log.info("complete", { executives: Object.keys(results).length, duration_ms: Date.now() - pipelineStart });
  return new Response(JSON.stringify({
    pipeline: "nightly-consolidation-full",
    duration_ms: Date.now() - pipelineStart,
    results,
  }), { status: 200, headers: { "Content-Type": "application/json" } });
  } catch (err) {
    log.error("unhandled", err);
    return new Response(JSON.stringify({ error: err instanceof Error ? err.message : "Internal error", request_id: log.request_id }), { status: 500, headers: { "Content-Type": "application/json" } });
  }
});
