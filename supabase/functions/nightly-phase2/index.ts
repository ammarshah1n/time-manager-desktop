import { serve } from "https://deno.land/std@0.208.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { callAnthropic, extractText, submitBatch } from "../_shared/anthropic.ts";
import { requireEnv } from "../_shared/config.ts";

// Phase 2 of nightly pipeline: daily summary + ACB generation + self-improvement
// Cron: 5 2 * * * (2:05 AM local — 5 minutes after phase1)
// Estimated runtime: 90-120s (under 150s Edge Function limit)

const SUPABASE_URL = requireEnv("SUPABASE_URL");
const SUPABASE_SERVICE_KEY = requireEnv("SUPABASE_SERVICE_ROLE_KEY");

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

// ── Daily Summary Generation (Opus) ──

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
    .select("*")
    .eq("profile_id", executiveId)
    .gte("occurred_at", today)
    .order("occurred_at", { ascending: true });

  if (!observations?.length) {
    return { status: "skipped", detail: "No observations today", duration_ms: Date.now() - start };
  }

  const { data: baselines } = await client
    .from("baselines")
    .select("*")
    .eq("profile_id", executiveId);

  const { data: acb } = await client.rpc("get_acb_full", { exec_id: executiveId });

  const obsFormatted = observations.map((obs) => {
    const time = new Date(obs.occurred_at).toLocaleTimeString("en-AU", { hour: "2-digit", minute: "2-digit" });
    return `[${time}] ${obs.source}/${obs.event_type} (importance: ${obs.importance_score}): ${obs.summary ?? JSON.stringify(obs.raw_data).slice(0, 300)}`;
  }).join("\n");

  const baselineContext = baselines?.length
    ? baselines.map((b) => `${b.signal_type}/${b.metric_name}: mean=${b.mean?.toFixed(2)}, stddev=${b.stddev?.toFixed(2)}, n=${b.sample_count}`).join("\n")
    : "Baselines not yet established (establishment period).";

  const acbContext = acb ? JSON.stringify(acb).slice(0, 30000) : "ACB not yet generated.";

  const response = await callAnthropic({
    model: "claude-opus-4-6",
    max_tokens: 8192,
    thinking: { type: "enabled", effort: "high" },
    system: `You are the nightly intelligence engine for a C-suite executive's cognitive system. Your task is to generate a daily summary that captures what happened today — descriptively, not interpretively. Flag anomalies that deviate >1.5\u03C3 from baselines. Note cross-signal co-occurrences (e.g., high email volume + calendar cancellation + idle period).\n\nACTIVE CONTEXT BUFFER:\n${acbContext}`,
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

// ── ACB Generation (Dual Document) ──

async function runACBGeneration(client: SupabaseClient, executiveId: string): Promise<StepResult> {
  const start = Date.now();

  const { data: tier3Traits } = await client
    .from("tier3_personality_traits")
    .select("*")
    .eq("profile_id", executiveId)
    .is("valid_to", null);

  const { data: tier2Sigs } = await client
    .from("tier2_behavioural_signatures")
    .select("*")
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
    .select("*")
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
    thinking: { type: "enabled", effort: "high" },
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

// ── Self-Improvement Loop (Batch API) ──

async function runSelfImprovement(client: SupabaseClient, executiveId: string): Promise<StepResult> {
  const start = Date.now();

  const sevenDaysAgo = new Date(Date.now() - 7 * 86400000).toISOString().slice(0, 10);
  const { data: recentSummaries } = await client
    .from("tier1_daily_summaries")
    .select("*")
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

  try {
    const batchId = await submitBatch([{
      custom_id: `self-improve-${executiveId}-${new Date().toISOString().slice(0, 10)}`,
      params: {
        model: "claude-opus-4-6",
        max_tokens: 8192,
        thinking: { type: "enabled", effort: "max" },
        messages: [{
          role: "user",
          content: `You are the self-improvement engine for a cognitive intelligence system. Analyse the last 7 days of daily summaries and identify patterns that existing Tier 2 signatures did NOT capture.\n\n5-phase process:\n1. INVENTORY: enumerate all summaries\n2. EXTRACT: identify novel patterns not in existing signatures\n3. PROPOSE: draft new signature definitions with evidence chains\n4. VALIDATE: assess whether each pattern appears across 3+ non-adjacent sessions\n5. COMMIT: for patterns passing validation, output full signature definitions\n\nOutput JSON:\n{\n  "inventory_count": number,\n  "novel_patterns": [{name, description, evidence_sessions, confidence}],\n  "proposed_signatures": [{signature_name, pattern_type, description, supporting_dates, confidence, passes_bocpd_floor: boolean}],\n  "log": "reasoning summary"\n}\n\nEXISTING SIGNATURES:\n${JSON.stringify(existingSigs ?? [])}\n\nLAST 7 SUMMARIES:\n${JSON.stringify(recentSummaries)}`,
        }],
      },
    }]);

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
    const message = error instanceof Error ? error.message : "Unknown error";
    return {
      status: "error",
      detail: `Batch API submission failed: ${message}. Will retry next night.`,
      duration_ms: Date.now() - start,
    };
  }
}

// ── Phase 2 Orchestrator ──

const PHASE2_STEPS = [
  { name: "daily_summary", run: runDailySummary },
  { name: "acb_generation", run: runACBGeneration },
  { name: "self_improvement", run: runSelfImprovement },
];

serve(async (req: Request) => {
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
      for (const step of PHASE2_STEPS) {
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
    details: { phase: "phase2", results, total_duration_ms: Date.now() - pipelineStart },
  });

  return new Response(JSON.stringify({
    pipeline: "nightly-phase2",
    duration_ms: Date.now() - pipelineStart,
    results,
  }), { status: 200, headers: { "Content-Type": "application/json" } });
});
