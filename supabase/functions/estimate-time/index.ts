// estimate-time/index.ts
// Estimates task duration using hybrid: historical similarity + Claude Sonnet fallback.
// Model: Claude Sonnet 4.6
// Loop 2 of AI learning: improves with every user override + actual_minutes logged.
// See: ~/Timed-Brain/06 - Context/ai-learning-loops-architecture-v2.md

import { serve } from "https://deno.land/std@0.208.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import Anthropic from "https://esm.sh/@anthropic-ai/sdk@0.27.0";

const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
);
const anthropic = new Anthropic({ apiKey: Deno.env.get("ANTHROPIC_API_KEY")! });

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
  const { taskId, workspaceId, profileId, title, bucketType, description, fromAddress } =
    await req.json();

  if (!taskId || !workspaceId || !profileId || !bucketType) {
    return new Response(JSON.stringify({ error: "Missing required fields" }), {
      status: 400,
      headers: { "Content-Type": "application/json" },
    });
  }

  const startTime = Date.now();

  // 1. Try historical estimate (similar past tasks)
  const historicalEstimate = await getHistoricalEstimate(
    workspaceId, profileId, bucketType, title, fromAddress
  );

  if (historicalEstimate !== null) {
    await updateTaskEstimate(taskId, historicalEstimate, "ai", "Based on similar task");
    return new Response(
      JSON.stringify({ estimatedMinutes: historicalEstimate, basis: "historical" }),
      { status: 200, headers: { "Content-Type": "application/json" } }
    );
  }

  // 2. Fallback: Claude Sonnet estimate
  try {
    const categoryDefault = CATEGORY_DEFAULTS[bucketType] ?? 15;
    const message = await anthropic.messages.create({
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
    });

    const text = message.content.find((b) => b.type === "text")?.text ?? "{}";
    const parsed = JSON.parse(text.match(/\{[\s\S]*\}/)![0]);
    const estimated = Math.max(1, Math.round(parsed.estimated_minutes ?? categoryDefault));

    await updateTaskEstimate(taskId, estimated, "ai", "AI estimate");

    return new Response(
      JSON.stringify({
        estimatedMinutes: estimated,
        basis: "ai",
        confidence: parsed.confidence,
      }),
      { status: 200, headers: { "Content-Type": "application/json" } }
    );
  } catch (_err) {
    // Final fallback: category default
    const def = CATEGORY_DEFAULTS[bucketType] ?? 15;
    await updateTaskEstimate(taskId, def, "default", "Category default");
    return new Response(
      JSON.stringify({ estimatedMinutes: def, basis: "default" }),
      { status: 200, headers: { "Content-Type": "application/json" } }
    );
  }
});

async function getHistoricalEstimate(
  workspaceId: string,
  profileId: string,
  bucketType: string,
  title: string | undefined,
  fromAddress: string | undefined
): Promise<number | null> {
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
      return weightedAverage(
        senderMatches.map((r: { actual_minutes: number }) => r.actual_minutes)
      );
    }
  }

  // Category average
  return weightedAverage(
    data.map((r: { actual_minutes: number }) => r.actual_minutes)
  );
}

function weightedAverage(values: number[]): number {
  // Exponentially weight recent values more (most recent = weight n, oldest = weight 1)
  let weightedSum = 0;
  let totalWeight = 0;
  for (let i = 0; i < values.length; i++) {
    const weight = i + 1;
    weightedSum += values[values.length - 1 - i] * weight;
    totalWeight += weight;
  }
  return Math.max(1, Math.round(weightedSum / totalWeight));
}

async function updateTaskEstimate(
  taskId: string,
  estimatedMinutes: number,
  source: string,
  basis: string
): Promise<void> {
  await supabase
    .from("tasks")
    .update({
      estimated_minutes_ai: estimatedMinutes,
      estimate_source: source,
      estimate_basis: basis,
      updated_at: new Date().toISOString(),
    })
    .eq("id", taskId);
}
