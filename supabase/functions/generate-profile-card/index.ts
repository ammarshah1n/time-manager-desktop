// generate-profile-card/index.ts
// Weekly job: reads behaviour_events + estimation_history and generates a user profile card + rules.
// Model: claude-opus-4-6
// Loop 3 of AI learning. Runs on pg_cron weekly (Sunday 02:00 UTC).
// Auth: JWT verified via _shared/auth.ts
// Resilience: withRetry via _shared/retry.ts
// Upserts user_profiles.profile_card + rules_json, and individual behaviour_rules rows.

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

interface BehaviourRule {
  rule_text: string;
  rule_key?: string;
  rule_type:
    | "scheduling"
    | "avoidance"
    | "estimation"
    | "context"
    | "timing"
    | "ordering";
  rule_value_json?: Record<string, unknown>;
  confidence: number;
  supporting_evidence: string;
}

interface ProfileCardResponse {
  profile_summary: string;
  rules: BehaviourRule[];
}

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

  const { workspaceId, profileId } = await req.json();

  if (!workspaceId || !profileId) {
    return new Response(
      JSON.stringify({
        error: "Missing required fields: workspaceId, profileId",
      }),
      { status: 400, headers: { "Content-Type": "application/json" } },
    );
  }

  try {
    const executiveId = await resolveExecutiveId(supabase, authUserId);
    assertOwnedTenant(executiveId, workspaceId, profileId);
  } catch (err) {
    if (err instanceof AuthError) return authErrorResponse(err);
    throw err;
  }

  const startTime = Date.now();

  try {
    // Fetch data in parallel
    const ninetyDaysAgo = new Date(Date.now() - 90 * 24 * 60 * 60 * 1000)
      .toISOString();

    const [eventsResult, estimationResult, existingRulesResult] = await Promise
      .all([
        supabase
          .from("behaviour_events")
          .select("*")
          .eq("workspace_id", workspaceId)
          .eq("profile_id", profileId)
          .gte("occurred_at", ninetyDaysAgo)
          .order("occurred_at", { ascending: false })
          .limit(200),
        supabase
          .from("estimation_history")
          .select("*")
          .eq("workspace_id", workspaceId)
          .eq("profile_id", profileId)
          .not("actual_minutes", "is", null)
          .order("created_at", { ascending: false })
          .limit(50),
        supabase
          .from("behaviour_rules")
          .select("rule_text,rule_type,confidence")
          .eq("workspace_id", workspaceId)
          .eq("profile_id", profileId)
          .eq("is_active", true),
      ]);

    const events = eventsResult.data ?? [];
    const estimationHistory = estimationResult.data ?? [];
    const existingRules = existingRulesResult.data ?? [];

    // Build user message from fetched data
    const userMessage =
      `BEHAVIOUR EVENTS (last 90 days, ${events.length} total):
${JSON.stringify(events.slice(0, 50), null, 2)}
${events.length > 50 ? `... and ${events.length - 50} more events` : ""}

ESTIMATION HISTORY (last ${estimationHistory.length} completed tasks):
${JSON.stringify(estimationHistory, null, 2)}

EXISTING RULES (current active rules for context):
${
        existingRules.length > 0
          ? JSON.stringify(existingRules, null, 2)
          : "No existing rules yet."
      }

Based on the above data, generate an updated profile card and refined rules.`;

    // Call Claude Opus with retry
    const message = await withRetry(
      () =>
        anthropic.messages.create({
          model: "claude-opus-4-6",
          max_tokens: 1024,
          system: [
            {
              type: "text",
              text:
                `You are a behaviour pattern analyst for an executive productivity assistant. Given a log of how an executive actually worked over the past 90 days, extract actionable rules that should change how their daily plan is built. Focus on: timing preferences (when they do certain task types), avoidance patterns (tasks they consistently push), estimation errors (actual vs estimated), and context preferences (what they do during transit, focus time, etc).

TIMING ANALYSIS (IMPORTANT):
Analyze the hour_of_day field in behaviour_events per bucket_type (action, reply, calls, transit, read). If a bucket_type has >60% of its task_completed events falling within a specific 4-hour window, emit a timing rule. The timing rule format is:
{
  "rule_text": "User completes 80% of calls before noon",
  "rule_key": "timing.<bucket_type>.<window_name>",
  "rule_type": "timing",
  "rule_value_json": {"bucket_type": "<bucket>", "preferred_hours": [8, 9, 10, 11]},
  "confidence": <fraction of completions in that window, 0.0-1.0>,
  "supporting_evidence": "User completes X% of <bucket> tasks between H:00-H:00"
}
Window names: "morning" (6-10), "late_morning" (9-13), "afternoon" (12-16), "late_afternoon" (14-18), "evening" (17-21). Pick the 4-hour window with the highest concentration. You may emit multiple timing rules if different bucket_types have different preferred windows.

ESTIMATION ANALYSIS (IMPORTANT):
For each bucket_type in the estimation history, compute the average estimate_error. If |avg_error| > 0.20 (20%), emit an estimation rule:
{
  "rule_text": "User underestimates [bucket] tasks by [X]%",
  "rule_key": "estimation.[bucket].bias",
  "rule_type": "estimation",
  "rule_value_json": {"bucket_type": "[bucket]", "avg_error": [error], "correction_factor": [1/(1+error)]},
  "confidence": min(sample_count / 20, 1.0),
  "supporting_evidence": "Based on N completions"
}
If the user overestimates, use "User overestimates [bucket] tasks by [X]%" instead.

ORDER OVERRIDE ANALYSIS:
Look for plan_order_override events where old_value and new_value contain task positions and bucket types.
If the same bucket_type is consistently moved earlier or later, emit an ordering rule:
{"rule_type": "ordering", "rule_key": "ordering.<bucket>.<direction>", "rule_value_json": {"bucket_type": "<bucket>", "direction": "earlier|later"}, "confidence": <count/10 capped at 1.0>, "supporting_evidence": "User moved <bucket> tasks <direction> N times"}

Return a JSON object: { "profile_summary": "2-3 sentence summary of this person's work style", "rules": [{ "rule_text": "string", "rule_key": "optional string for timing/estimation/ordering rules", "rule_type": "scheduling"|"avoidance"|"estimation"|"context"|"timing"|"ordering", "rule_value_json": "optional object for timing/estimation/ordering rules", "confidence": 0.0-1.0, "supporting_evidence": "brief" }] }`,
              // @ts-ignore
              cache_control: { type: "ephemeral" },
            },
          ],
          messages: [
            {
              role: "user",
              content: userMessage,
            },
          ],
        }),
      { label: "generate-profile-card-anthropic" },
    ) as any;

    const text = message.content.find((b: { type: string; text?: string }) =>
      b.type === "text"
    )?.text ?? "{}";
    const jsonMatch = text.match(/\{[\s\S]*\}/);
    if (!jsonMatch) {
      throw new Error("Claude returned no valid JSON object");
    }
    const profileData: ProfileCardResponse = JSON.parse(jsonMatch[0]);

    // Upsert user_profiles
    const { error: profileUpsertError } = await supabase
      .from("user_profiles")
      .upsert(
        {
          workspace_id: workspaceId,
          profile_id: profileId,
          profile_card: profileData.profile_summary,
          rules_json: profileData.rules,
          generated_at: new Date().toISOString(),
        },
        { onConflict: "workspace_id,profile_id" },
      );

    if (profileUpsertError) {
      throw new Error(
        `Upsert user_profiles failed: ${profileUpsertError.message}`,
      );
    }

    // Upsert each rule into behaviour_rules
    for (const rule of profileData.rules) {
      // Timing rules match on rule_key; other rules match on rule_text
      const matchColumn = rule.rule_type === "timing" && rule.rule_key
        ? "rule_key"
        : "rule_text";
      const matchValue = matchColumn === "rule_key"
        ? rule.rule_key!
        : rule.rule_text;

      const { data: existing } = await supabase
        .from("behaviour_rules")
        .select("id,confidence")
        .eq("workspace_id", workspaceId)
        .eq("profile_id", profileId)
        .eq(matchColumn, matchValue)
        .maybeSingle();

      if (existing) {
        // Update confidence (and rule_value_json for timing rules) on existing rule
        const updatePayload: Record<string, unknown> = {
          confidence: rule.confidence,
        };
        if (rule.rule_value_json) {
          updatePayload.rule_value_json = rule.rule_value_json;
        }
        await supabase
          .from("behaviour_rules")
          .update(updatePayload)
          .eq("id", existing.id);
      } else {
        // Insert new rule
        const insertPayload: Record<string, unknown> = {
          workspace_id: workspaceId,
          profile_id: profileId,
          rule_text: rule.rule_text,
          rule_type: rule.rule_type,
          confidence: rule.confidence,
          is_active: true,
        };
        if (rule.rule_key) {
          insertPayload.rule_key = rule.rule_key;
        }
        if (rule.rule_value_json) {
          insertPayload.rule_value_json = rule.rule_value_json;
        }
        await supabase.from("behaviour_rules").insert(insertPayload);
      }
    }

    // Log to ai_pipeline_runs
    await supabase.from("ai_pipeline_runs").insert({
      workspace_id: workspaceId,
      profile_id: profileId,
      function_name: "generate-profile-card",
      model: "claude-opus-4-6",
      input_tokens: message.usage.input_tokens,
      output_tokens: message.usage.output_tokens,
      cached_tokens: (message.usage as { cache_read_input_tokens?: number })
        .cache_read_input_tokens ?? 0,
      latency_ms: Date.now() - startTime,
      status: "success",
    });

    return new Response(
      JSON.stringify({
        rulesCount: profileData.rules.length,
        profileSummary: profileData.profile_summary,
      }),
      { status: 200, headers: { "Content-Type": "application/json" } },
    );
  } catch (err) {
    const errorMsg = err instanceof Error ? err.message : String(err);
    console.error("[generate-profile-card] error:", errorMsg);

    await supabase.from("ai_pipeline_runs").insert({
      workspace_id: workspaceId,
      profile_id: profileId,
      function_name: "generate-profile-card",
      model: "claude-opus-4-6",
      input_tokens: 0,
      output_tokens: 0,
      cached_tokens: 0,
      latency_ms: Date.now() - startTime,
      status: "error",
      error_message: errorMsg,
    });

    return new Response(
      JSON.stringify({ error: errorMsg }),
      { status: 500, headers: { "Content-Type": "application/json" } },
    );
  }
});
