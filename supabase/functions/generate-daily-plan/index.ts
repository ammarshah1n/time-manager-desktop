// generate-daily-plan/index.ts
// THE CORE. Generates an ordered time-boxed plan for generatePlan(availableMinutes, userId).
// Model: Claude Opus 4.6 — reasoning matters here.
// Algorithm: deterministic knapsack first; LLM only generates rank_reason text post-selection.
// Caches user profile card (7-day TTL) to reduce Opus token cost.
// See: ~/Timed-Brain/06 - Context/planning-algorithm-architecture.md

import { serve } from "https://deno.land/std@0.208.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import Anthropic from "https://esm.sh/@anthropic-ai/sdk@0.27.0";
import { verifyAuth, AuthError, authErrorResponse } from "../_shared/auth.ts";
import { requireEnv } from "../_shared/config.ts";

const supabase = createClient(
  requireEnv("SUPABASE_URL"),
  requireEnv("SUPABASE_SERVICE_ROLE_KEY")
);
const anthropic = new Anthropic({ apiKey: requireEnv("ANTHROPIC_API_KEY") });

// Score constants — must match Sources/Core/Services/PlanningEngine.swift
const SCORE = {
  FIXED_FIRST:   100_000,
  FIXED_SECOND:   99_000,
  OVERDUE:         1_000,
  ACTION:            400,
  READ:              100,
  DEADLINE_24H:      500,
  DEADLINE_72H:      200,
  DEADLINE_1W:       100,
  QUICK_WIN:         150,  // est <= 5 min
  DURATION_PENALTY:   -2,  // per minute
  MOOD_BOOST:        500,
  DEEP_FOCUS_KILL: -9_999,
};

const BUFFER_MINUTES = 5;

serve(async (req: Request) => {
  try {
    await verifyAuth(req);
  } catch (err) {
    if (err instanceof AuthError) return authErrorResponse(err);
    throw err;
  }

  const {
    workspaceId,
    profileId,
    availableMinutes,
    moodContext,
    planDate,
  }: PlanRequest = await req.json();

  if (!workspaceId || !profileId || !availableMinutes) {
    return new Response(JSON.stringify({ error: "Missing required fields" }), {
      status: 400,
      headers: { "Content-Type": "application/json" },
    });
  }

  const { data: run } = await supabase
    .from("ai_pipeline_runs")
    .insert({
      workspace_id: workspaceId,
      pipeline_name: "generate-daily-plan",
      model: "claude-opus-4-6",
      status: "running",
    })
    .select()
    .single();

  const startTime = Date.now();

  try {
    // Fetch pending tasks + user profile card
    const [tasksResult, profileResult] = await Promise.all([
      supabase
        .from("tasks")
        .select(
          "id,title,bucket_type,estimated_minutes_ai,estimated_minutes_manual," +
          "priority,due_at,is_overdue,is_do_first,deferred_count,is_transit_safe,status"
        )
        .eq("workspace_id", workspaceId)
        .eq("profile_id", profileId)
        .eq("status", "pending"),
      supabase
        .from("user_profiles")
        .select("profile_card_text,behaviour_rules")
        .eq("workspace_id", workspaceId)
        .eq("profile_id", profileId)
        .single(),
    ]);

    const tasks = tasksResult.data ?? [];
    const profileCard = profileResult.data?.profile_card_text ?? "";

    // === DETERMINISTIC PLANNING PHASE ===
    const now = new Date();
    const deadline = new Date(planDate ?? now.toISOString().split("T")[0]);

    // Score all tasks
    const scoredTasks: ScoredTask[] = tasks.map((t) => ({
      ...t,
      score: scoreTask(t, now, moodContext),
      effectiveMinutes:
        (t.estimated_minutes_manual ?? t.estimated_minutes_ai ?? 30) + BUFFER_MINUTES,
    }));

    // Separate fixed-position tasks
    const fixedFirst = scoredTasks.filter((t) => isDailyUpdate(t));
    const fixedSecond = scoredTasks.filter((t) => isFamilyEmail(t));
    const pool = scoredTasks
      .filter((t) => !isDailyUpdate(t) && !isFamilyEmail(t))
      .sort((a, b) => b.score - a.score);

    // Greedy knapsack
    const selected: ScoredTask[] = [
      ...fixedFirst.slice(0, 1),
      ...fixedSecond.slice(0, 1),
    ];
    let budgetUsed = selected.reduce((s, t) => s + t.effectiveMinutes, 0);

    for (const task of pool) {
      if (task.score <= SCORE.DEEP_FOCUS_KILL + 1) continue; // deep focus kill
      if (budgetUsed + task.effectiveMinutes <= availableMinutes) {
        selected.push(task);
        budgetUsed += task.effectiveMinutes;
      }
    }

    const overflow = pool.filter((t) => !selected.includes(t));

    // === LLM PHASE: rank_reason only (never blocks plan if fails) ===
    let rankReasons: Record<string, string> = {};
    try {
      rankReasons = await generateRankReasons(selected, profileCard, moodContext);
    } catch (err) {
      console.warn("[generate-daily-plan] LLM rank_reason failed:", err);
      // Plan proceeds with empty reasons
    }

    // Build plan items
    const planItems = selected.map((task, idx) => ({
      task_id: task.id,
      position: idx,
      estimated_minutes: task.effectiveMinutes - BUFFER_MINUTES,
      buffer_after_minutes: BUFFER_MINUTES,
      rank_reason: rankReasons[task.id] ?? null,
    }));

    // Persist plan
    const dateStr = planDate ?? now.toISOString().split("T")[0];
    const { data: plan } = await supabase
      .from("daily_plans")
      .upsert(
        {
          workspace_id: workspaceId,
          profile_id: profileId,
          plan_date: dateStr,
          available_minutes: availableMinutes,
          total_planned_minutes: budgetUsed,
          mood_context: moodContext ?? null,
          status: "draft",
        },
        { onConflict: "workspace_id,profile_id,plan_date" }
      )
      .select()
      .single();

    if (plan) {
      await supabase.from("plan_items").delete().eq("plan_id", plan.id);
      await supabase.from("plan_items").insert(
        planItems.map((item) => ({ ...item, workspace_id: workspaceId, plan_id: plan.id }))
      );
    }

    await supabase.from("ai_pipeline_runs").update({
      status: "success",
      duration_ms: Date.now() - startTime,
      completed_at: new Date().toISOString(),
    }).eq("id", run?.id);

    return new Response(
      JSON.stringify({ plan, planItems, overflowCount: overflow.length }),
      { status: 200, headers: { "Content-Type": "application/json" } }
    );
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    await supabase.from("ai_pipeline_runs").update({
      status: "failed",
      error_message: msg,
      duration_ms: Date.now() - startTime,
      completed_at: new Date().toISOString(),
    }).eq("id", run?.id);
    return new Response(JSON.stringify({ error: msg }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }
});

// ─── Pure scoring logic ─────────────────────────────────────────────────────

function scoreTask(task: Task, now: Date, mood?: string): number {
  // Special cases handled by position, not score
  if (isDailyUpdate(task)) return SCORE.FIXED_FIRST;
  if (isFamilyEmail(task))  return SCORE.FIXED_SECOND;

  // Deep focus: kill non-action tasks
  if (mood === "deep_focus" && task.bucket_type !== "action") {
    return SCORE.DEEP_FOCUS_KILL;
  }

  let score = 0;

  // Overdue
  if (task.is_overdue) score += SCORE.OVERDUE;

  // Bucket type
  if (task.bucket_type === "action")                            score += SCORE.ACTION;
  else if (task.bucket_type.startsWith("read"))                 score += SCORE.READ;

  // Deadline proximity
  if (task.due_at) {
    const hoursUntil = (new Date(task.due_at).getTime() - now.getTime()) / 3_600_000;
    if (hoursUntil < 24)       score += SCORE.DEADLINE_24H;
    else if (hoursUntil < 72)  score += SCORE.DEADLINE_72H;
    else if (hoursUntil < 168) score += SCORE.DEADLINE_1W;
  }

  // Quick wins
  const est = task.estimated_minutes_manual ?? task.estimated_minutes_ai ?? 30;
  if (est <= 5) score += SCORE.QUICK_WIN;

  // Duration penalty
  score += est * SCORE.DURATION_PENALTY;

  // Priority bump
  score += (task.priority ?? 0) * 50;

  // Mood modifiers
  if (mood === "easy_wins" && est <= 5) score += SCORE.MOOD_BOOST;
  if (mood === "avoidance" && (task.deferred_count ?? 0) >= 2) score += SCORE.MOOD_BOOST;

  return score;
}

function isDailyUpdate(t: Task): boolean {
  return t.is_do_first === true &&
    (t.title?.toLowerCase().includes("daily update") || false);
}

function isFamilyEmail(t: Task): boolean {
  return t.is_do_first === true && !isDailyUpdate(t);
}

async function generateRankReasons(
  tasks: ScoredTask[],
  profileCard: string,
  mood?: string
): Promise<Record<string, string>> {
  if (tasks.length === 0) return {};

  const taskList = tasks
    .map((t, i) => `${i + 1}. [${t.id}] ${t.title} (${t.bucket_type}, ${t.estimated_minutes_manual ?? t.estimated_minutes_ai ?? 30}min)`)
    .join("\n");

  const msg = await anthropic.messages.create({
    model: "claude-opus-4-6",
    max_tokens: 1024,
    system: [
      {
        type: "text",
        text: profileCard
          ? `You are a planning assistant. User profile:\n${profileCard}`
          : "You are a planning assistant for a busy executive.",
        // @ts-ignore
        cache_control: { type: "ephemeral" },
      },
    ],
    messages: [
      {
        role: "user",
        content: `For each task below, write a 1-sentence rank_reason explaining why it was selected for this ${mood ?? "standard"} session. Format: JSON object mapping task ID → reason string.\n\n${taskList}`,
      },
    ],
  });

  const text = msg.content.find((b) => b.type === "text")?.text ?? "{}";
  const jsonMatch = text.match(/\{[\s\S]*\}/);
  if (!jsonMatch) return {};
  return JSON.parse(jsonMatch[0]);
}

// ─── Types ──────────────────────────────────────────────────────────────────

interface PlanRequest {
  workspaceId: string;
  profileId: string;
  availableMinutes: number;
  moodContext?: string;
  planDate?: string;
}

interface Task {
  id: string;
  title: string;
  bucket_type: string;
  estimated_minutes_ai?: number;
  estimated_minutes_manual?: number;
  priority?: number;
  due_at?: string;
  is_overdue: boolean;
  is_do_first: boolean;
  deferred_count?: number;
  is_transit_safe: boolean;
  status: string;
}

interface ScoredTask extends Task {
  score: number;
  effectiveMinutes: number;
}
