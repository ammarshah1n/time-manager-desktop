// generate-profile-card/index.ts
// Weekly job: reads behaviour_events + estimation_history and generates a user profile card + rules.
// Model: claude-opus-4-6
// Loop 3 of AI learning. Runs on pg_cron weekly (Sunday 02:00 UTC).
// Upserts user_profiles.profile_card + rules_json, and individual behaviour_rules rows.

import { serve } from "https://deno.land/std@0.208.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import Anthropic from "https://esm.sh/@anthropic-ai/sdk@0.27.0";

const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
);
const anthropic = new Anthropic({ apiKey: Deno.env.get("ANTHROPIC_API_KEY")! });

interface BehaviourRule {
  rule_text: string;
  rule_type: "scheduling" | "avoidance" | "estimation" | "context";
  confidence: number;
  supporting_evidence: string;
}

interface ProfileCardResponse {
  profile_summary: string;
  rules: BehaviourRule[];
}

serve(async (req: Request) => {
  const { workspaceId, profileId } = await req.json();

  if (!workspaceId || !profileId) {
    return new Response(
      JSON.stringify({ error: "Missing required fields: workspaceId, profileId" }),
      { status: 400, headers: { "Content-Type": "application/json" } }
    );
  }

  const startTime = Date.now();

  try {
    // Fetch data in parallel
    const ninetyDaysAgo = new Date(Date.now() - 90 * 24 * 60 * 60 * 1000).toISOString();

    const [eventsResult, estimationResult, existingRulesResult] = await Promise.all([
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
    const userMessage = `BEHAVIOUR EVENTS (last 90 days, ${events.length} total):
${JSON.stringify(events.slice(0, 50), null, 2)}
${events.length > 50 ? `... and ${events.length - 50} more events` : ""}

ESTIMATION HISTORY (last ${estimationHistory.length} completed tasks):
${JSON.stringify(estimationHistory, null, 2)}

EXISTING RULES (current active rules for context):
${existingRules.length > 0 ? JSON.stringify(existingRules, null, 2) : "No existing rules yet."}

Based on the above data, generate an updated profile card and refined rules.`;

    // Call Claude Opus
    const message = await anthropic.messages.create({
      model: "claude-opus-4-6",
      max_tokens: 1024,
      system: [
        {
          type: "text",
          text: `You are a behaviour pattern analyst for an executive productivity assistant. Given a log of how an executive actually worked over the past 90 days, extract actionable rules that should change how their daily plan is built. Focus on: timing preferences (when they do certain task types), avoidance patterns (tasks they consistently push), estimation errors (actual vs estimated), and context preferences (what they do during transit, focus time, etc). Return a JSON object: { "profile_summary": "2-3 sentence summary of this person's work style", "rules": [{ "rule_text": "string", "rule_type": "scheduling"|"avoidance"|"estimation"|"context", "confidence": 0.0-1.0, "supporting_evidence": "brief" }] }`,
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
    });

    const text = message.content.find((b) => b.type === "text")?.text ?? "{}";
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
        { onConflict: "workspace_id,profile_id" }
      );

    if (profileUpsertError) {
      throw new Error(`Upsert user_profiles failed: ${profileUpsertError.message}`);
    }

    // Upsert each rule into behaviour_rules
    for (const rule of profileData.rules) {
      const { data: existing } = await supabase
        .from("behaviour_rules")
        .select("id,confidence")
        .eq("workspace_id", workspaceId)
        .eq("profile_id", profileId)
        .eq("rule_text", rule.rule_text)
        .maybeSingle();

      if (existing) {
        // Update confidence on existing rule
        await supabase
          .from("behaviour_rules")
          .update({ confidence: rule.confidence })
          .eq("id", existing.id);
      } else {
        // Insert new rule
        await supabase.from("behaviour_rules").insert({
          workspace_id: workspaceId,
          profile_id: profileId,
          rule_text: rule.rule_text,
          rule_type: rule.rule_type,
          confidence: rule.confidence,
          is_active: true,
        });
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
      cached_tokens: (message.usage as { cache_read_input_tokens?: number }).cache_read_input_tokens ?? 0,
      latency_ms: Date.now() - startTime,
      status: "success",
    });

    return new Response(
      JSON.stringify({
        rulesCount: profileData.rules.length,
        profileSummary: profileData.profile_summary,
      }),
      { status: 200, headers: { "Content-Type": "application/json" } }
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
      { status: 500, headers: { "Content-Type": "application/json" } }
    );
  }
});
