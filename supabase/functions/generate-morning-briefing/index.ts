import { serve } from "https://deno.land/std@0.208.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

// Cron: 30 5 * * * (5:30 AM local, 15 min after refresh)
// Two-pass Opus briefing generation with adversarial review

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

type BriefingSection = {
  section: string;
  insight: string;
  supporting_data: string | null;
  confidence: "high" | "moderate";
  category: string;
  source_signals: string[];
};

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { status: 200 });
  }

  const client = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY);
  const start = Date.now();

  const { data: executives } = await client.from("executives").select("id, timezone");
  if (!executives?.length) {
    return new Response(JSON.stringify({ error: "No executives found" }), { status: 500 });
  }

  const results: Record<string, unknown> = {};

  for (const executive of executives) {
    const executiveId = executive.id;
    const today = new Date().toISOString().slice(0, 10);

    // Check if briefing already exists for today
    const { data: existing } = await client
      .from("briefings")
      .select("id")
      .eq("profile_id", executiveId)
      .eq("date", today)
      .maybeSingle();

    if (existing) {
      results[executiveId] = { status: "skipped", detail: `Briefing already exists for ${today}` };
      continue;
    }

    // Context assembly
    // 1. Last 7 daily summaries
    const { data: summaries } = await client
      .from("tier1_daily_summaries")
      .select("summary_date, day_narrative, significant_events, anomalies, energy_profile")
      .eq("profile_id", executiveId)
      .order("summary_date", { ascending: false })
      .limit(7);

    // 2. ACB-FULL
    const { data: acb } = await client
      .rpc("get_acb_full", { exec_id: executiveId });

    // 3. Today's calendar (from tier0 calendar observations)
    const { data: calendarToday } = await client
      .from("tier0_observations")
      .select("summary, raw_data, occurred_at")
      .eq("profile_id", executiveId)
      .eq("source", "calendar")
      .gte("occurred_at", today)
      .order("occurred_at", { ascending: true });

    // 4. Last 14 briefings (for adversarial review)
    const { data: priorBriefings } = await client
      .from("briefings")
      .select("date, content")
      .eq("profile_id", executiveId)
      .order("date", { ascending: false })
      .limit(14);

    // 5. ONA relationship intelligence (Phase 6.06)
    const { data: atRiskRelationships } = await client
      .from("relationships")
      .select("health_score, health_trajectory, last_contact_at, ona_nodes(display_name, email, authority_tier, relationship_type, avg_response_latency_seconds)")
      .eq("profile_id", executiveId)
      .in("health_trajectory", ["at_risk", "dormant"])
      .order("health_score", { ascending: true })
      .limit(5);

    const { data: topContacts } = await client
      .from("ona_nodes")
      .select("display_name, email, authority_tier, total_emails_sent, total_emails_received, avg_response_latency_seconds, relationship_health_score, health_trend, formality_trend, responsiveness_symmetry, trajectory_summary")
      .eq("profile_id", executiveId)
      .order("communication_frequency", { ascending: false })
      .limit(20);

    // 6. Check engagement self-correction trigger
    let lowEngagement = false;
    if (priorBriefings && priorBriefings.length >= 2) {
      const recent = priorBriefings.slice(0, 2);
      lowEngagement = recent.every((b: { content: { engagement_duration_seconds?: number } }) =>
        (b.content as { engagement_duration_seconds?: number })?.engagement_duration_seconds !== undefined &&
        ((b.content as { engagement_duration_seconds: number }).engagement_duration_seconds < 60)
      );
    }

    // TODO: Pass 1 — Opus 4.6 with extended thinking (32K budget)
    // Generate 7-section briefing:
    //   1. Lead Insight (primacy effect)
    //   2. Calendar Intelligence
    //   3. Email Patterns
    //   4. Decision Observations (optional)
    //   5. Cognitive Load Forecast
    //   6. Emerging Patterns (0-2)
    //   7. Forward-Looking Observation (recency anchor)
    // If lowEngagement: inject self-correction context

    // TODO: Pass 2 — Adversarial Opus 4.6 (16K budget, temp 0.0)
    // Review Pass 1 output against raw data + last 14 briefings
    // Challenge overconfidence, find alternative explanations

    // TODO: Pass 3 — Apply adversarial corrections if any

    // Placeholder briefing structure
    const briefingContent = {
      sections: [] as BriefingSection[],
      word_count: 0,
      generated_by: "generate-morning-briefing",
      context_used: {
        daily_summaries: summaries?.length ?? 0,
        acb_available: acb !== null,
        calendar_events: calendarToday?.length ?? 0,
        prior_briefings: priorBriefings?.length ?? 0,
        at_risk_relationships: atRiskRelationships?.length ?? 0,
        top_contacts: topContacts?.length ?? 0,
        low_engagement_trigger: lowEngagement,
      },
    };

    // Insert briefing
    const { error: insertError } = await client
      .from("briefings")
      .insert({
        profile_id: executiveId,
        date: today,
        content: briefingContent,
        generated_at: new Date().toISOString(),
        word_count: 0,
        was_viewed: false,
      });

    results[executiveId] = {
      status: insertError ? "error" : "ok",
      detail: insertError?.message ?? "Briefing generated (LLM calls pending implementation)",
      context: briefingContent.context_used,
      duration_ms: Date.now() - start,
    };
  }

  return new Response(JSON.stringify({
    pipeline: "generate-morning-briefing",
    duration_ms: Date.now() - start,
    results,
  }), {
    status: 200,
    headers: { "Content-Type": "application/json" },
  });
});
