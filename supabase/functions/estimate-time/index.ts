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
import { verifyAuth, AuthError, authErrorResponse } from "../_shared/auth.ts";
import { withRetry } from "../_shared/retry.ts";

const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
);
const anthropic = new Anthropic({ apiKey: Deno.env.get("ANTHROPIC_API_KEY")! });

// Jina AI API key for jina-embeddings-v3 (1024-dim embeddings)
// Set via: supabase secrets set JINA_API_KEY=jina_...
const JINA_API_KEY = Deno.env.get("JINA_API_KEY") ?? "";
const EMBEDDING_SIMILARITY_THRESHOLD = 0.7;
const EMBEDDING_MIN_MATCHES = 3;

// Category defaults — cold start fallback
const CATEGORY_DEFAULTS: Record<string, number> = {
  reply_email:    2,
  reply_wa:       2,
  reply_other:    5,
  calls:         10,
  read_today:     5,
  read_this_week: 15,
  action:        30,
  transit:       20,
  waiting:        0,
  other:         15,
};

serve(async (req: Request) => {
  // JWT auth
  try {
    await verifyAuth(req);
  } catch (err) {
    if (err instanceof AuthError) return authErrorResponse(err);
    return new Response(JSON.stringify({ error: "Auth failed" }), { status: 401, headers: { "Content-Type": "application/json" } });
  }

  const { taskId, workspaceId, profileId, title, bucketType, description, fromAddress } =
    await req.json();

  if (!taskId || !workspaceId || !profileId || !bucketType) {
    return new Response(JSON.stringify({ error: "Missing required fields" }), {
      status: 400,
      headers: { "Content-Type": "application/json" },
    });
  }

  const startTime = Date.now();

  // Tier 3: personalised bucket default from bucket_estimates, fallback to static CATEGORY_DEFAULTS
  const { data: userDefault } = await supabase
    .from("bucket_estimates")
    .select("mean_minutes")
    .eq("profile_id", profileId)
    .eq("bucket_type", bucketType)
    .maybeSingle();

  const categoryDefault = userDefault?.mean_minutes ?? CATEGORY_DEFAULTS[bucketType] ?? 15;

  // Generate embedding for the task title (used in tier 1 and stored on task + history)
  const titleEmbedding = title ? await generateEmbedding(title) : null;

  // 1a. Embedding-based similarity search (highest signal for action/read tasks)
  if (titleEmbedding) {
    const embeddingResult = await getEmbeddingSimilarityEstimate(
      workspaceId, profileId, titleEmbedding, categoryDefault
    );
    if (embeddingResult !== null) {
      await storeEmbeddingOnTask(taskId, titleEmbedding);
      await updateTaskEstimate(taskId, embeddingResult.estimate, "ai", "Embedding similarity (top 5)", embeddingResult.uncertainty);
      return new Response(
        JSON.stringify({
          estimatedMinutes: embeddingResult.estimate,
          estimate_uncertainty: embeddingResult.uncertainty,
          confident: embeddingResult.confident,
          basis: "embedding_similarity",
        }),
        { status: 200, headers: { "Content-Type": "application/json" } }
      );
    }
  }

  // 1b. Try historical estimate (sender-specific → bucket category average)
  const historicalResult = await getHistoricalEstimate(
    workspaceId, profileId, bucketType, title, fromAddress, categoryDefault
  );

  if (historicalResult !== null) {
    if (titleEmbedding) await storeEmbeddingOnTask(taskId, titleEmbedding);
    await updateTaskEstimate(taskId, historicalResult.estimate, "ai", "Based on similar task", historicalResult.uncertainty);
    return new Response(
      JSON.stringify({
        estimatedMinutes: historicalResult.estimate,
        estimate_uncertainty: historicalResult.uncertainty,
        confident: historicalResult.confident,
        basis: "historical",
      }),
      { status: 200, headers: { "Content-Type": "application/json" } }
    );
  }

  // 2. Fallback: Claude Sonnet estimate
  try {
    const message = await withRetry(
      () => anthropic.messages.create({
        model: "claude-sonnet-4-6",
        max_tokens: 128,
        system: [
          {
            type: "text",
            text: `You are a time estimation assistant for an executive productivity app.
Estimate how many minutes a task will take. Be realistic, not optimistic.
Respond ONLY with a JSON object: {"estimated_minutes": <integer>, "confidence": <0.0-1.0>}`,
            // @ts-ignore
            cache_control: { type: "ephemeral" },
          },
        ],
        messages: [
          {
            role: "user",
            content: `Task type: ${bucketType}
Title: ${title ?? "(untitled)"}
Description: ${description ?? "(none)"}
${fromAddress ? `From: ${fromAddress}` : ""}
Category default: ${categoryDefault} min

Estimate the actual time this will take.`,
          },
        ],
      }),
      { label: "estimate-time-anthropic" }
    );

    const text = message.content.find((b) => b.type === "text")?.text ?? "{}";
    const jsonMatch = text.match(/\{[\s\S]*\}/);
    if (!jsonMatch) throw new Error("No JSON in LLM response");
    const parsed = JSON.parse(jsonMatch[0]);
    const estimated = Math.max(1, Math.round(parsed.estimated_minutes ?? categoryDefault));
    // AI LLM fallback: no historical data, so uncertainty = 50% of category default (high)
    const aiUncertainty = Math.round(categoryDefault * 0.5);

    if (titleEmbedding) await storeEmbeddingOnTask(taskId, titleEmbedding);
    await updateTaskEstimate(taskId, estimated, "ai", "AI estimate", aiUncertainty);

    return new Response(
      JSON.stringify({
        estimatedMinutes: estimated,
        estimate_uncertainty: aiUncertainty,
        confident: false,
        basis: "ai",
        confidence: parsed.confidence,
      }),
      { status: 200, headers: { "Content-Type": "application/json" } }
    );
  } catch (_err) {
    // Final fallback: category default — maximum uncertainty
    const def = categoryDefault;
    const defaultUncertainty = Math.round(def * 0.5);
    if (titleEmbedding) await storeEmbeddingOnTask(taskId, titleEmbedding);
    await updateTaskEstimate(taskId, def, "default", "Category default", defaultUncertainty);
    return new Response(
      JSON.stringify({
        estimatedMinutes: def,
        estimate_uncertainty: defaultUncertainty,
        confident: false,
        basis: "default",
      }),
      { status: 200, headers: { "Content-Type": "application/json" } }
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
      console.error(`Jina AI embedding error: ${res.status} ${await res.text()}`);
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
  categoryDefault: number
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
  categoryDefault: number
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
      (r: { from_address: string }) => r.from_address === fromAddress
    );
    if (senderMatches.length >= 2) {
      return bayesianEstimate(
        categoryDefault,
        senderMatches.map((r: { actual_minutes: number }) => r.actual_minutes)
      );
    }
  }

  // Category average
  return bayesianEstimate(
    categoryDefault,
    data.map((r: { actual_minutes: number }) => r.actual_minutes)
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
  historicalActuals: number[]
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
  const posteriorSigma2 =
    1 / (1 / priorSigma2 + n / Math.max(sampleVar, 1));
  const posteriorMu =
    posteriorSigma2 *
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
  embedding: number[]
): Promise<void> {
  await supabase
    .from("tasks")
    .update({
      embedding: JSON.stringify(embedding),
      updated_at: new Date().toISOString(),
    })
    .eq("id", taskId);
}

async function updateTaskEstimate(
  taskId: string,
  estimatedMinutes: number,
  source: string,
  basis: string,
  uncertainty?: number
): Promise<void> {
  await supabase
    .from("tasks")
    .update({
      estimated_minutes_ai: estimatedMinutes,
      estimate_source: source,
      estimate_basis: basis,
      estimate_uncertainty: uncertainty ?? null,
      updated_at: new Date().toISOString(),
    })
    .eq("id", taskId);
}
