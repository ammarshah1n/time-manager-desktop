import { serve } from "https://deno.land/std@0.208.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { callAnthropic, extractText } from "../_shared/anthropic.ts";

// Phase 7.01: Weekly Pattern Detection
// Triggered: end of week OR 5+ daily summaries since last run
// Opus 4.6 with extended thinking (32K budget), temp 0.3
// Compares this week's summaries against Tier 2 library + ACB-FULL + last 4 briefings

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { status: 200 });
  }

  const client = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY);
  const start = Date.now();

  let body: { executive_id: string } | null = null;
  try {
    body = await req.json();
  } catch {
    return new Response(JSON.stringify({ error: "Invalid request body" }), { status: 400 });
  }

  if (!body?.executive_id) {
    return new Response(JSON.stringify({ error: "executive_id required" }), { status: 400 });
  }

  const executiveId = body.executive_id;

  // 1. Fetch this week's daily summaries
  const sevenDaysAgo = new Date(Date.now() - 7 * 86400000).toISOString().slice(0, 10);
  const { data: weeklySummaries } = await client
    .from("tier1_daily_summaries")
    .select("summary_date, day_narrative, significant_events, anomalies, energy_profile")
    .eq("profile_id", executiveId)
    .gte("summary_date", sevenDaysAgo)
    .order("summary_date", { ascending: true });

  if (!weeklySummaries || weeklySummaries.length < 3) {
    return new Response(JSON.stringify({
      status: "insufficient_data",
      detail: `Only ${weeklySummaries?.length ?? 0} summaries this week, need 3+`,
    }), { status: 200 });
  }

  // 2. Fetch existing Tier 2 library
  const { data: tier2Signatures } = await client
    .from("tier2_behavioural_signatures")
    .select("id, signature_name, pattern_type, description, confidence, status, observation_count, last_reinforced_at")
    .eq("profile_id", executiveId)
    .in("status", ["confirmed", "developing", "emerging"]);

  // 3. Fetch ACB-FULL
  const { data: acb } = await client
    .rpc("get_acb_full", { exec_id: executiveId });

  // 4. Last 4 morning briefings
  const { data: recentBriefings } = await client
    .from("briefings")
    .select("date, content")
    .eq("profile_id", executiveId)
    .order("date", { ascending: false })
    .limit(4);

  // 5. Opus 4.6 pattern detection
  const summaryText = weeklySummaries.map((s) =>
    `### ${s.summary_date}\n${s.day_narrative}\nSignificant: ${JSON.stringify(s.significant_events).slice(0, 500)}\nAnomalies: ${JSON.stringify(s.anomalies).slice(0, 300)}`
  ).join("\n\n");

  const tier2Text = (tier2Signatures ?? []).map((s) =>
    `- [${s.status}] "${s.signature_name}" (${s.pattern_type}): ${s.description?.slice(0, 200)} | confidence: ${s.confidence} | observations: ${s.observation_count}`
  ).join("\n");

  const briefingText = (recentBriefings ?? []).map((b) =>
    `### Briefing ${b.date}\n${JSON.stringify(b.content).slice(0, 800)}`
  ).join("\n\n");

  const response = await callAnthropic({
    model: "claude-opus-4-6",
    max_tokens: 4096,
    thinking: { type: "enabled", budget_tokens: 32768 },
    temperature: 0.3,
    messages: [{
      role: "user",
      content: `You are analysing ${weeklySummaries.length} daily summaries for an executive to detect behavioural patterns.

EXISTING TIER 2 SIGNATURES (${tier2Signatures?.length ?? 0}):
${tier2Text || "None yet"}

ACB-FULL CONTEXT:
${acb ? JSON.stringify(acb).slice(0, 8000) : "Not available"}

RECENT BRIEFINGS:
${briefingText || "None yet"}

THIS WEEK'S DAILY SUMMARIES:
${summaryText}

TASK:
1. For each existing signature: does this week REINFORCE it (new evidence)? Or VIOLATE it (contradictory evidence)?
2. Are there NEW patterns this week that no existing signature captures? A valid new pattern must:
   - Span >= 2 domains (email+calendar, calendar+app_usage, etc.)
   - Appear across >= 2 non-adjacent days this week
3. Do any patterns from recent briefings need updating or contradicting?

Output JSON:
{
  "reinforcements": [{"signature_id": "...", "evidence": "...", "new_observation_count": N}],
  "violations": [{"signature_id": "...", "evidence": "...", "severity": 0.0-1.0}],
  "new_candidates": [{"signature_name": "...", "pattern_type": "cross_domain|temporal|contextual", "description": "...", "evidence": "...", "domains": ["email","calendar"], "confidence": 0.3}],
  "briefing_updates": [{"briefing_date": "...", "claim": "...", "update": "reinforced|contradicted|evolved", "evidence": "..."}],
  "summary": "2-3 sentences"
}`,
    }],
  });

  const resultText = extractText(response);
  let result;
  try {
    result = JSON.parse(resultText);
  } catch {
    result = { raw: resultText };
  }

  // Apply reinforcements — update existing signatures
  for (const r of result.reinforcements ?? []) {
    if (!r.signature_id) continue;
    const { data: sig } = await client
      .from("tier2_behavioural_signatures")
      .select("observation_count, confidence")
      .eq("id", r.signature_id)
      .single();

    if (sig) {
      const newCount = (sig.observation_count ?? 0) + (r.new_observation_count ?? 1);
      const newConfidence = Math.min(1.0, sig.confidence + 0.05);
      await client
        .from("tier2_behavioural_signatures")
        .update({
          observation_count: newCount,
          confidence: newConfidence,
          last_reinforced_at: new Date().toISOString(),
          updated_at: new Date().toISOString(),
        })
        .eq("id", r.signature_id);
    }
  }

  // Insert new candidates as 'emerging' signatures
  for (const c of result.new_candidates ?? []) {
    // Duplicate check: skip if name too similar to existing
    const existingNames = (tier2Signatures ?? []).map((s) => s.signature_name.toLowerCase());
    if (existingNames.some((n) => n.includes(c.signature_name?.toLowerCase()?.slice(0, 20)))) continue;

    await client.from("tier2_behavioural_signatures").insert({
      profile_id: executiveId,
      signature_name: c.signature_name,
      pattern_type: c.pattern_type ?? "cross_domain",
      description: c.description,
      confidence: c.confidence ?? 0.3,
      status: "emerging",
      observation_count: 1,
      supporting_tier1_ids: weeklySummaries.map((s) => s.summary_date),
      cross_domain_correlations: c.domains ?? [],
    });
  }

  return new Response(JSON.stringify({
    status: "ok",
    summaries_analysed: weeklySummaries.length,
    reinforcements: result.reinforcements?.length ?? 0,
    violations: result.violations?.length ?? 0,
    new_candidates: result.new_candidates?.length ?? 0,
    briefing_updates: result.briefing_updates?.length ?? 0,
    tokens_used: response.usage.input_tokens + response.usage.output_tokens,
    duration_ms: Date.now() - start,
  }), { status: 200, headers: { "Content-Type": "application/json" } });
});
