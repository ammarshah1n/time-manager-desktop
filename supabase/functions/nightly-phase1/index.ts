import { serve } from "https://deno.land/std@0.208.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { callAnthropic, extractText } from "../_shared/anthropic.ts";

// Phase 1 of nightly pipeline: importance scoring + conflict detection
// Cron: 0 2 * * * (2 AM local)
// Estimated runtime: 30-60s (well under 150s Edge Function limit)

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const MAX_IMPORTANCE_BATCH = 500;

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

// ── Two-Pass Importance Scoring ──

async function runImportanceScoring(client: SupabaseClient, executiveId: string): Promise<StepResult> {
  const start = Date.now();
  let totalTokens = 0;

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

  const scoreText = extractText(pass1Response).trim();
  let scores: number[];
  try {
    scores = JSON.parse(scoreText);
  } catch {
    scores = scoreText.match(/\d+/g)?.map(Number) ?? [];
  }

  for (let i = 0; i < Math.min(scores.length, unscored.length); i++) {
    const score = Math.max(1, Math.min(10, scores[i])) / 10.0;
    await client
      .from("tier0_observations")
      .update({ importance_score: score })
      .eq("id", unscored[i].id);
  }

  // Pass 2: Sonnet re-scores uncertain band (0.55-0.75)
  const { data: uncertain } = await client
    .from("tier0_observations")
    .select("id, summary, source, event_type, raw_data")
    .eq("profile_id", executiveId)
    .gte("importance_score", 0.55)
    .lte("importance_score", 0.75)
    .eq("is_processed", false)
    .limit(150);

  if (uncertain?.length) {
    const uncertainSummaries = uncertain.map((obs, i) =>
      `[${i}] ${obs.source}/${obs.event_type}: ${obs.summary ?? JSON.stringify(obs.raw_data).slice(0, 300)}`
    ).join("\n");

    const pass2Response = await callAnthropic({
      model: "claude-sonnet-4-6",
      max_tokens: 4096,
      thinking: { type: "enabled", effort: "medium" },
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

    for (let i = 0; i < Math.min(pass2Scores.length, uncertain.length); i++) {
      const score = Math.max(1, Math.min(10, pass2Scores[i])) / 10.0;
      await client
        .from("tier0_observations")
        .update({ importance_score: score })
        .eq("id", uncertain[i].id);
    }
  }

  return {
    status: "ok",
    detail: `Scored ${unscored.length} observations (Pass 1: Haiku), ${uncertain?.length ?? 0} re-scored (Pass 2: Sonnet)`,
    duration_ms: Date.now() - start,
    tokens_used: totalTokens,
  };
}

// ── Conflict Detection ──

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
    .limit(50);

  if (!todayObs?.length) {
    return { status: "skipped", detail: "No high-importance observations today", duration_ms: Date.now() - start };
  }

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

  // Route effort: high when anomalies or developing signatures exist, medium otherwise
  const hasAnomalies = todayObs.some((obs) => obs.importance_score >= 0.8);
  const conflictEffort = (hasAnomalies || (tier2?.length ?? 0) >= 3) ? "high" : "medium";

  const existingMemory = [
    ...(tier2 ?? []).map((s) => `[Tier2/${s.status}] ${s.signature_name}: ${s.description}`),
    ...(tier3 ?? []).map((t) => `[Tier3] ${t.trait_name}: ${t.description}`),
  ].join("\n");

  const observationList = todayObs.map((obs) =>
    `- ${obs.source}/${obs.event_type} (importance: ${obs.importance_score}): ${obs.summary ?? JSON.stringify(obs.raw_data).slice(0, 200)}`
  ).join("\n");

  const response = await callAnthropic({
    model: "claude-opus-4-6",
    max_tokens: 4096,
    thinking: { type: "enabled", effort: conflictEffort as "medium" | "high" },
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

  const tagged = contradictions.filter((c) => c.contradiction_score > 0.7);
  for (const c of tagged) {
    if (c.observation_index < todayObs.length) {
      await client
        .from("tier0_observations")
        .update({
          raw_data: {
            ...todayObs[c.observation_index].raw_data,
            contradiction_score: c.contradiction_score,
            contradicts_memory_id: c.contradicts_id,
          },
        })
        .eq("id", todayObs[c.observation_index].id);
    }
  }

  return {
    status: "ok",
    detail: `Checked ${todayObs.length} observations, found ${tagged.length} contradictions (score > 0.7)`,
    duration_ms: Date.now() - start,
    tokens_used: totalTokens,
  };
}

// ── Phase 1 Orchestrator ──

const PHASE1_STEPS = [
  { name: "importance_scoring", run: runImportanceScoring },
  { name: "conflict_detection", run: runConflictDetection },
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
      for (const step of PHASE1_STEPS) {
        try {
          results[executiveId][step.name] = await step.run(client, executiveId);
        } catch (error) {
          const message = error instanceof Error ? error.message : "Unknown error";
          results[executiveId][step.name] = { status: "error", detail: message, duration_ms: 0 };
        }
      }
    } finally {
      await releaseAdvisoryLock(client, executiveId);
    }
  }

  await client.from("pipeline_health_log").insert({
    check_type: "nightly_pipeline",
    status: "ok",
    details: { phase: "phase1", results, total_duration_ms: Date.now() - pipelineStart },
  });

  return new Response(JSON.stringify({
    pipeline: "nightly-phase1",
    duration_ms: Date.now() - pipelineStart,
    results,
  }), { status: 200, headers: { "Content-Type": "application/json" } });
});
