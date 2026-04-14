import { serve } from "https://deno.land/std@0.208.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { callAnthropic, extractText } from "../_shared/anthropic.ts";

// Weekly avoidance stream 3 synthesis — Sonnet correlates:
//   1. Calendar reschedules by contact/domain
//   2. Email latency spikes by contact/domain
//   3. Task deferrals by bucket/topic
// Cross-stream convergence (>= 2 of 3) → avoidance pattern
// Cron: Sunday 4 AM (after weekly-strategic-synthesis at 3 AM)
// Research grounding: v3-05 (dual-scoring for signal quality)

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

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
    const fourWeeksAgo = new Date(Date.now() - 28 * 86400000).toISOString();

    // Stream 1: Email latency spikes — contacts with avg response > 5 business days
    const { data: latencyContacts } = await client
      .from("ona_nodes")
      .select("email, display_name, avg_response_latency_seconds, health_trend")
      .eq("profile_id", executiveId)
      .gt("avg_response_latency_seconds", 432000)
      .gte("last_seen_at", fourWeeksAgo)
      .limit(20);

    // Stream 2: Calendar reschedules grouped by organiser
    const { data: reschedules } = await client
      .from("tier0_observations")
      .select("raw_data, occurred_at, summary")
      .eq("profile_id", executiveId)
      .eq("source", "calendar")
      .eq("event_type", "calendar.rescheduled")
      .gte("occurred_at", fourWeeksAgo)
      .order("occurred_at", { ascending: false })
      .limit(100);

    // Stream 3: Task deferrals grouped by bucket
    const { data: deferrals } = await client
      .from("behaviour_events")
      .select("task_id, bucket_type, occurred_at")
      .eq("profile_id", executiveId)
      .eq("event_type", "task_deferred")
      .gte("occurred_at", fourWeeksAgo)
      .order("occurred_at", { ascending: false })
      .limit(200);

    // Count deferrals per task
    const taskDeferrals: Record<string, { count: number; bucket: string }> = {};
    for (const d of deferrals ?? []) {
      if (!d.task_id) continue;
      if (!taskDeferrals[d.task_id]) {
        taskDeferrals[d.task_id] = { count: 0, bucket: d.bucket_type ?? "unknown" };
      }
      taskDeferrals[d.task_id].count++;
    }

    // Tasks deferred 3+ times
    const avoidedTasks = Object.entries(taskDeferrals)
      .filter(([, v]) => v.count >= 3)
      .map(([taskId, v]) => `${v.bucket}: ${v.count} deferrals (task ${taskId.slice(0, 8)})`);

    // Group reschedules by organiser
    const reschedulesByOrg: Record<string, number> = {};
    for (const r of reschedules ?? []) {
      const org = (r.raw_data as Record<string, unknown>)?.organiser_email as string ?? "unknown";
      reschedulesByOrg[org] = (reschedulesByOrg[org] ?? 0) + 1;
    }

    const highRescheduleContacts = Object.entries(reschedulesByOrg)
      .filter(([, count]) => count >= 3)
      .map(([email, count]) => `${email}: ${count} reschedules`);

    const latencyFormatted = (latencyContacts ?? []).map((c) =>
      `${c.display_name ?? c.email}: ${Math.round((c.avg_response_latency_seconds ?? 0) / 86400)}d avg latency, health trend: ${c.health_trend ?? "unknown"}`
    );

    if (!latencyFormatted.length && !highRescheduleContacts.length && !avoidedTasks.length) {
      results[executiveId] = { status: "skipped", detail: "No avoidance signals detected" };
      continue;
    }

    // Sonnet cross-stream correlation analysis
    const response = await callAnthropic({
      model: "claude-sonnet-4-6",
      max_tokens: 4096,
      thinking: { type: "enabled", effort: "high" },
      messages: [{
        role: "user",
        content: `Analyze avoidance patterns for a C-suite executive by correlating 3 data streams over the past 4 weeks.

STREAM 1 — EMAIL LATENCY SPIKES (contacts with >5 business day avg response):
${latencyFormatted.length ? latencyFormatted.join("\n") : "None detected"}

STREAM 2 — CALENDAR RESCHEDULES (contacts with 3+ reschedules in 4 weeks):
${highRescheduleContacts.length ? highRescheduleContacts.join("\n") : "None detected"}

STREAM 3 — TASK DEFERRALS (tasks deferred 3+ times):
${avoidedTasks.length ? avoidedTasks.join("\n") : "None detected"}

CRITICAL RULES:
- Cross-stream convergence: if the SAME domain/contact/topic appears in 2+ streams, flag as avoidance pattern
- Always consider strategic delay as alternative explanation (e.g., delegation, waiting for information)
- False negatives are cheaper than false positives — only flag high-confidence patterns
- If network is expanding for that contact/domain, classify as strategic NOT avoidance

Output valid JSON:
{
  "avoidance_patterns": [
    {
      "domain_or_topic": "string",
      "streams_involved": ["email_latency", "calendar_reschedule", "task_deferral"],
      "confidence": 0.0-1.0,
      "is_strategic_delay": false,
      "strategic_delay_reason": null,
      "evidence_summary": "1-2 sentences",
      "recommended_action": "<=10 words"
    }
  ],
  "single_stream_signals": [
    {
      "stream": "email_latency|calendar_reschedule|task_deferral",
      "domain_or_topic": "string",
      "severity": "low|medium|high",
      "detail": "1 sentence"
    }
  ],
  "executive_summary": "2-3 sentences on overall avoidance posture this week"
}`,
      }],
    });

    const analysisText = extractText(response);
    let analysis;
    try {
      analysis = JSON.parse(analysisText);
    } catch {
      analysis = { avoidance_patterns: [], single_stream_signals: [], executive_summary: "Analysis incomplete" };
    }

    // Store avoidance patterns as behavioral observations
    const crossStreamPatterns = analysis.avoidance_patterns?.filter(
      (p: { is_strategic_delay: boolean }) => !p.is_strategic_delay
    ) ?? [];

    if (crossStreamPatterns.length > 0) {
      await client.from("tier0_observations").insert(
        crossStreamPatterns.map((p: { domain_or_topic: string; evidence_summary: string; confidence: number; streams_involved: string[] }) => ({
          profile_id: executiveId,
          occurred_at: new Date().toISOString(),
          source: "system",
          event_type: "avoidance.cross_stream",
          summary: `Avoidance pattern: ${p.domain_or_topic} — ${p.evidence_summary}`,
          raw_data: p,
          importance_score: p.confidence,
        }))
      );
    }

    results[executiveId] = {
      status: "ok",
      stream1_signals: latencyFormatted.length,
      stream2_signals: highRescheduleContacts.length,
      stream3_signals: avoidedTasks.length,
      cross_stream_patterns: crossStreamPatterns.length,
      executive_summary: analysis.executive_summary,
      tokens_used: response.usage.input_tokens + response.usage.output_tokens,
    };
  }

  await client.from("pipeline_health_log").insert({
    check_type: "weekly_avoidance_synthesis",
    status: "ok",
    details: { results, duration_ms: Date.now() - start },
  });

  return new Response(JSON.stringify({
    pipeline: "weekly-avoidance-synthesis",
    duration_ms: Date.now() - start,
    results,
  }), { status: 200, headers: { "Content-Type": "application/json" } });
});
