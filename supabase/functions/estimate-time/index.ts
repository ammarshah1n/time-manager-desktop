// estimate-time/index.ts
// Estimates task duration using hybrid: embedding similarity + historical + Claude Sonnet fallback.
// Model: Claude Sonnet 4.6 (LLM), jina-embeddings-v3 (embeddings via Jina AI)
// Loop 2 of AI learning: improves with every user override + actual_minutes logged.
// Auth: JWT verified via _shared/auth.ts
// Resilience: withRetry via _shared/retry.ts
// See: ~/Timed-Brain/06 - Context/ai-learning-loops-architecture-v2.md

import { serve } from "https://deno.land/std@0.208.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import Anthropic from "https://esm.sh/@anthropic-ai/sdk@0.27.0";
import {
  assertOwnedTenant,
  AuthError,
  authErrorResponse,
  resolveExecutiveId,
  verifyAuth,
} from "../_shared/auth.ts";
import { withRetry } from "../_shared/retry.ts";
import { requireEnv } from "../_shared/config.ts";

const supabase = createClient(
  requireEnv("SUPABASE_URL"),
  requireEnv("SUPABASE_SERVICE_ROLE_KEY"),
);
const anthropic = new Anthropic({ apiKey: requireEnv("ANTHROPIC_API_KEY") });

// Jina AI API key for jina-embeddings-v3 (1024-dim embeddings)
// Set via: supabase secrets set JINA_API_KEY=jina_...
const JINA_API_KEY = Deno.env.get("JINA_API_KEY") ?? "";
const EMBEDDING_SIMILARITY_THRESHOLD = 0.7;
const EMBEDDING_MIN_MATCHES = 3;

// Category defaults — cold start fallback
const CATEGORY_DEFAULTS: Record<string, number> = {
  reply_email: 2,
  reply_wa: 2,
  reply_other: 5,
  calls: 10,
  read_today: 5,
  read_this_week: 15,
  action: 30,
  transit: 20,
  waiting: 0,
  other: 15,
};

serve(async (req: Request) => {
  // JWT auth
  let authUserId: string;
  try {
    authUserId = await verifyAuth(req);
  } catch (err) {
    if (err instanceof AuthError) return authErrorResponse(err);
    return new Response(JSON.stringify({ error: "Auth failed" }), {
      status: 401,
      headers: { "Content-Type": "application/json" },
    });
  }

  const {
    taskId,
    workspaceId,
    profileId,
    title,
    bucketType,
    description,
    fromAddress,
  } = await req.json();

  if (!taskId || !workspaceId || !profileId || !bucketType) {
    return new Response(JSON.stringify({ error: "Missing required fields" }), {
      status: 400,
      headers: { "Content-Type": "application/json" },
    });
  }

  try {
    const executiveId = await resolveExecutiveId(supabase, authUserId);
    assertOwnedTenant(executiveId, workspaceId, profileId);
  } catch (err) {
    if (err instanceof AuthError) return authErrorResponse(err);
    throw err;
  }

  const startTime = Date.now();

  // Tier 3: personalised bucket default from bucket_estimates, fallback to static CATEGORY_DEFAULTS
  const { data: userDefault } = await supabase
    .from("bucket_estimates")
    .select("mean_minutes")
    .eq("profile_id", profileId)
    .eq("bucket_type", bucketType)
    .maybeSingle();

  const categoryDefault = userDefault?.mean_minutes ??
    CATEGORY_DEFAULTS[bucketType] ?? 15;

  // Generate embedding for the task title (used in tier 1 and stored on task + history)
  const titleEmbedding = title ? await generateEmbedding(title) : null;

  // 1a. Embedding-based similarity search (highest signal for action/read tasks)
  if (titleEmbedding) {
    const embeddingResult = await getEmbeddingSimilarityEstimate(
      workspaceId,
      profileId,
      titleEmbedding,
      categoryDefault,
    );
    if (embeddingResult !== null) {
      await storeEmbeddingOnTask(
        taskId,
        workspaceId,
        profileId,
        titleEmbedding,
      );
      await updateTaskEstimate(
        taskId,
        workspaceId,
        profileId,
        embeddingResult.estimate,
        "ai",
        "Embedding similarity (top 5)",
        embeddingResult.uncertainty,
      );
      return new Response(
        JSON.stringify({
          estimatedMinutes: embeddingResult.estimate,
          source: "ai",
          estimate_uncertainty: embeddingResult.uncertainty,
          confident: embeddingResult.confident,
          basis: "embedding_similarity",
        }),
        { status: 200, headers: { "Content-Type": "application/json" } },
      );
    }
  }

  // 1b. Try historical estimate (sender-specific → bucket category average)
  const historicalResult = await getHistoricalEstimate(
    workspaceId,
    profileId,
    bucketType,
    title,
    fromAddress,
    categoryDefault,
  );

  if (historicalResult !== null) {
    if (titleEmbedding) {
      await storeEmbeddingOnTask(
        taskId,
        workspaceId,
        profileId,
        titleEmbedding,
      );
    }
    await updateTaskEstimate(
      taskId,
      workspaceId,
      profileId,
      historicalResult.estimate,
      "ai",
      "Based on similar task",
      historicalResult.uncertainty,
    );
      return new Response(
        JSON.stringify({
          estimatedMinutes: historicalResult.estimate,
          source: "ai",
          estimate_uncertainty: historicalResult.uncertainty,
          confident: historicalResult.confident,
          basis: "historical",
      }),
      { status: 200, headers: { "Content-Type": "application/json" } },
    );
  }

  // 2. Fallback: Claude Sonnet estimate
  try {
    // ── Behavioural signature (Tier 2) ──
    // In this schema, profile_id IS the executive_id (FK to executives.id).
    const sigRes = await supabase
      .from("tier2_behavioural_signatures")
      .select("description, signature_name, created_at")
      .eq("profile_id", profileId)
      .eq("status", "confirmed")
      .order("created_at", { ascending: false })
      .limit(3);
    const signatureText = (sigRes.data ?? [])
      .map((s: any) => `- ${s.signature_name}: ${s.description}`)
      .join("\n") || "(no confirmed signatures yet)";

    // ── Recent same-bucket overrides (Bayesian-ish prior) ──
    const overrideRes = await supabase
      .from("behaviour_events")
      .select("old_value, new_value, occurred_at")
      .eq("workspace_id", workspaceId)
      .eq("profile_id", profileId)
      .eq("event_type", "estimate_override")
      .eq("bucket_type", bucketType)
      .gte("occurred_at", new Date(Date.now() - 30 * 86400000).toISOString())
      .order("occurred_at", { ascending: false })
      .limit(20);
    const overrideHints = (overrideRes.data ?? [])
      .map((r: any) => `${r.old_value}m → ${r.new_value}m`)
      .join(", ");

    // ── Time-of-day + day-of-week ──
    const now = new Date();
    const tod = `${now.getHours()}:00 (${["Sun","Mon","Tue","Wed","Thu","Fri","Sat"][now.getDay()]})`;

    // ── Calendar density (current ±2h) ──
    // calendar_observations uses executive_id (== profile_id) and event_start/event_end.
    const winStart = new Date(now.getTime() - 2 * 3600000).toISOString();
    const winEnd = new Date(now.getTime() + 2 * 3600000).toISOString();
    const calRes = await supabase
      .from("calendar_observations")
      .select("id")
      .eq("executive_id", profileId)
      .gte("event_start", winStart)
      .lte("event_end", winEnd);
    const calendarDensity = `${(calRes.data ?? []).length} events in ±2h window`;

    const message = await withRetry(
      () =>
        anthropic.messages.create({
          model: "claude-sonnet-4-6",
          max_tokens: 2048,
          // @ts-ignore
          thinking: { type: "enabled", budget_tokens: 1500 },
          system: [
            {
              type: "text",
              text:
                `You are Timed's estimation engine for an executive. Estimate how many minutes a task will take given the user's behavioural signature, recent corrections on similar tasks, and the schedule context.

You are reasoning about a real human's productivity, not running a generic classifier. Cite which signal drove your number. Prefer odd-but-honest numbers (37, 52) over round-but-empty ones (30, 60). Output JSON only — keys MUST be snake_case to match the parser:
{"estimated_minutes": <int>, "uncertainty": <stddev minutes>, "basis": "<one short sentence>"}`,
              // @ts-ignore
              cache_control: { type: "ephemeral" },
            },
          ],
          messages: [
            {
              role: "user",
              content: `Task: "${title}"
Type: ${bucketType}
${description ? `Description: ${description}\n` : ""}${fromAddress ? `From: ${fromAddress}\n` : ""}
Time-of-day: ${tod}
Calendar density: ${calendarDensity}

Behavioural signature (Tier 2):
${signatureText || "(not yet computed)"}

Recent overrides on same bucket (last 30d):
${overrideHints || "(none)"}

Category default: ${categoryDefault}m`,
            },
          ],
        }),
      { label: "estimate-time-anthropic" },
    ) as any;

    const text = message.content.find((b: { type: string; text?: string }) =>
      b.type === "text"
    )?.text ?? "{}";
    const jsonMatch = text.match(/\{[\s\S]*\}/);
    if (!jsonMatch) {
      throw new Error("No JSON in LLM response");
    }
    const parsed = JSON.parse(jsonMatch[0]);
    const estimated = Math.max(
      1,
      Math.round(parsed.estimated_minutes ?? categoryDefault),
    );
    const aiUncertainty = Math.max(
      1,
      Math.round(parsed.uncertainty ?? categoryDefault * 0.5),
    );
    const aiBasis = typeof parsed.basis === "string" ? parsed.basis : "AI estimate";

    if (titleEmbedding) {
      await storeEmbeddingOnTask(
        taskId,
        workspaceId,
        profileId,
        titleEmbedding,
      );
    }
    await updateTaskEstimate(
      taskId,
      workspaceId,
      profileId,
      estimated,
      "ai",
      aiBasis,
      aiUncertainty,
    );

    return new Response(
      JSON.stringify({
        estimatedMinutes: estimated,
        source: "ai",
        estimate_uncertainty: aiUncertainty,
        confident: false,
        basis: aiBasis,
      }),
      { status: 200, headers: { "Content-Type": "application/json" } },
    );
  } catch (_err) {
    // Final fallback: category default — maximum uncertainty
    const def = categoryDefault;
    const defaultUncertainty = Math.round(def * 0.5);
    if (titleEmbedding) {
      await storeEmbeddingOnTask(
        taskId,
        workspaceId,
        profileId,
        titleEmbedding,
      );
    }
    await updateTaskEstimate(
      taskId,
      workspaceId,
      profileId,
      def,
      "default",
      "Category default",
      defaultUncertainty,
    );
    return new Response(
      JSON.stringify({
        estimatedMinutes: def,
        source: "default",
        estimate_uncertainty: defaultUncertainty,
        confident: false,
        basis: "default",
      }),
      { status: 200, headers: { "Content-Type": "application/json" } },
    );
  }
});

// ============================================================
// Embedding generation via Jina AI jina-embeddings-v3 (1024 dims)
// ============================================================

async function generateEmbedding(text: string): Promise<number[] | null> {
  if (!JINA_API_KEY) return null;

  try {
    const res = await fetch("https://api.jina.ai/v1/embeddings", {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${JINA_API_KEY}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model: "jina-embeddings-v3",
        input: [text],
        task: "retrieval.passage",
        dimensions: 1024,
      }),
    });

    if (!res.ok) {
      console.error(
        `Jina AI embedding error: ${res.status} ${await res.text()}`,
      );
      return null;
    }

    const json = await res.json();
    return json.data?.[0]?.embedding ?? null;
  } catch (err) {
    console.error("Jina AI embedding call failed:", err);
    return null;
  }
}

// ============================================================
// Tier 1a: Embedding similarity search on estimation_history
// ============================================================

async function getEmbeddingSimilarityEstimate(
  workspaceId: string,
  profileId: string,
  embedding: number[],
  categoryDefault: number,
): Promise<BayesianResult | null> {
  // pgvector cosine distance operator: <=>
  // 1 - cosine_distance = cosine_similarity
  // We query the 5 nearest neighbours, then filter by similarity threshold
  const { data, error } = await supabase.rpc("match_estimation_history", {
    query_embedding: JSON.stringify(embedding),
    match_workspace_id: workspaceId,
    match_profile_id: profileId,
    match_threshold: EMBEDDING_SIMILARITY_THRESHOLD,
    match_count: 5,
  });

  if (error) {
    console.error("Embedding similarity RPC error:", error.message);
    return null;
  }

  if (!data || data.length < EMBEDDING_MIN_MATCHES) return null;

  const actuals = data.map((r: { actual_minutes: number }) => r.actual_minutes);
  return bayesianEstimate(categoryDefault, actuals);
}

// ============================================================
// Tier 1b: Historical bucket/sender match (original logic)
// ============================================================

async function getHistoricalEstimate(
  workspaceId: string,
  profileId: string,
  bucketType: string,
  title: string | undefined,
  fromAddress: string | undefined,
  categoryDefault: number,
): Promise<BayesianResult | null> {
  // Find recent tasks of same bucket type that have actual_minutes recorded
  const { data } = await supabase
    .from("estimation_history")
    .select("actual_minutes,estimated_minutes_manual,from_address")
    .eq("workspace_id", workspaceId)
    .eq("profile_id", profileId)
    .eq("bucket_type", bucketType)
    .not("actual_minutes", "is", null)
    .order("created_at", { ascending: false })
    .limit(20);

  if (!data || data.length < 3) return null; // not enough history

  // Sender-specific match first (highest confidence)
  if (fromAddress) {
    const senderMatches = data.filter(
      (r: { from_address: string }) => r.from_address === fromAddress,
    );
    if (senderMatches.length >= 2) {
      return bayesianEstimate(
        categoryDefault,
        senderMatches.map((r: { actual_minutes: number }) => r.actual_minutes),
      );
    }
  }

  // Category average
  return bayesianEstimate(
    categoryDefault,
    data.map((r: { actual_minutes: number }) => r.actual_minutes),
  );
}

// ============================================================
// Bayesian time estimation with uncertainty intervals
// ============================================================

interface BayesianResult {
  estimate: number;
  uncertainty: number;
  confident: boolean;
}

function bayesianEstimate(
  categoryDefault: number,
  historicalActuals: number[],
): BayesianResult {
  // Prior from category default with high initial uncertainty (50%)
  const priorMu = categoryDefault;
  const priorSigma2 = (categoryDefault * 0.5) ** 2;

  if (historicalActuals.length === 0) {
    return {
      estimate: priorMu,
      uncertainty: Math.round(Math.sqrt(priorSigma2)),
      confident: false,
    };
  }

  // Sample statistics
  const n = historicalActuals.length;
  const sampleMean = historicalActuals.reduce((a, b) => a + b, 0) / n;
  const sampleVar =
    historicalActuals.reduce((a, b) => a + (b - sampleMean) ** 2, 0) /
    Math.max(n - 1, 1);

  // Posterior (Gaussian conjugate update)
  const posteriorSigma2 = 1 / (1 / priorSigma2 + n / Math.max(sampleVar, 1));
  const posteriorMu = posteriorSigma2 *
    (priorMu / priorSigma2 + (n * sampleMean) / Math.max(sampleVar, 1));

  const uncertainty = Math.sqrt(posteriorSigma2);
  // Confident when 5+ samples and uncertainty < 25% of the mean
  const confident = n >= 5 && uncertainty < posteriorMu * 0.25;

  return {
    estimate: Math.max(1, Math.round(posteriorMu)),
    uncertainty: Math.max(1, Math.round(uncertainty)),
    confident,
  };
}

// ============================================================
// Task + estimation_history embedding storage
// ============================================================

async function storeEmbeddingOnTask(
  taskId: string,
  workspaceId: string,
  profileId: string,
  embedding: number[],
): Promise<void> {
  await supabase
    .from("tasks")
    .update({
      embedding: JSON.stringify(embedding),
      updated_at: new Date().toISOString(),
    })
    .eq("id", taskId)
    .eq("workspace_id", workspaceId)
    .eq("profile_id", profileId);
}

async function updateTaskEstimate(
  taskId: string,
  workspaceId: string,
  profileId: string,
  estimatedMinutes: number,
  source: string,
  basis: string,
  uncertainty?: number,
): Promise<void> {
  const { data, error } = await supabase
    .from("tasks")
    .update({
      estimated_minutes_ai: estimatedMinutes,
      estimated_minutes_manual: null,
      estimate_source: source,
      estimate_basis: basis,
      estimate_uncertainty: uncertainty ?? null,
      updated_at: new Date().toISOString(),
    })
    .eq("id", taskId)
    .eq("workspace_id", workspaceId)
    .eq("profile_id", profileId)
    .select("id")
    .maybeSingle();

  if (error) {
    throw new Error(`Failed to update task estimate: ${error.message}`);
  }
  if (!data) {
    throw new Error("Failed to update task estimate: task not found");
  }
}
