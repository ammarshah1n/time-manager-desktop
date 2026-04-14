import { serve } from "https://deno.land/std@0.208.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { callAnthropic, extractText } from "../_shared/anthropic.ts";

// Executive cognitive bias detection — 6-phase nightly pipeline
// Cron: 0 3 * * * (3 AM, one hour after nightly phase2)
// Research grounding: v3-01 (cognitive bias detection from passive digital signals)
//
// 6 viable biases (confidence >= 0.70):
//   Planning fallacy (0.78), Sunk cost (0.74), Escalation of commitment (0.73),
//   Overconfidence (0.72), Confirmation bias (0.71), Status quo bias (0.70)
// 3 experimental (monitor only): Anchoring (0.68), Recency (0.67), Availability (0.65)
//
// Critical: NO extended thinking on classification passes (CoT increases FPR).
// Only the insight card generation step uses Opus adaptive thinking.
// Requires 90-day personal baseline before surfacing insights.

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const BIAS_TYPES = [
  "overconfidence", "anchoring", "sunk_cost", "availability",
  "confirmation", "status_quo", "planning_fallacy",
  "escalation_of_commitment", "recency",
] as const;

const VIABLE_BIASES = new Set([
  "overconfidence", "sunk_cost", "escalation_of_commitment",
  "confirmation", "status_quo", "planning_fallacy",
]);

const MIN_BASELINE_DAYS = 90;

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { status: 200 });
  }

  const client = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY);
  const start = Date.now();

  const { data: executives } = await client.from("executives").select("id, created_at");
  if (!executives?.length) {
    return new Response(JSON.stringify({ error: "No executives found" }), { status: 500 });
  }

  const results: Record<string, unknown> = {};

  for (const executive of executives) {
    const executiveId = executive.id;

    // Check baseline maturity
    const accountAge = Math.floor(
      (Date.now() - new Date(executive.created_at).getTime()) / 86400000
    );
    if (accountAge < MIN_BASELINE_DAYS) {
      results[executiveId] = {
        status: "accumulating",
        detail: `Day ${accountAge}/${MIN_BASELINE_DAYS} — accumulating baseline, no insights surfaced yet`,
      };
      // Still run extraction phases 1-3 to build evidence chains, just skip phases 4-6
    }

    const thirtyDaysAgo = new Date(Date.now() - 30 * 86400000).toISOString();
    const ninetyDaysAgo = new Date(Date.now() - 90 * 86400000).toISOString();

    // ── Phase 1: Data Collection (parallel) ──
    const [emailsResult, calendarResult, tasksResult, existingChains] = await Promise.all([
      client.from("tier0_observations")
        .select("id, summary, raw_data, occurred_at, authoritative_score")
        .eq("profile_id", executiveId)
        .eq("source", "email")
        .gte("occurred_at", thirtyDaysAgo)
        .order("occurred_at", { ascending: false })
        .limit(500),
      client.from("tier0_observations")
        .select("id, summary, raw_data, occurred_at, authoritative_score")
        .eq("profile_id", executiveId)
        .eq("source", "calendar")
        .gte("occurred_at", thirtyDaysAgo)
        .order("occurred_at", { ascending: false })
        .limit(300),
      client.from("tier0_observations")
        .select("id, summary, raw_data, occurred_at, authoritative_score")
        .eq("profile_id", executiveId)
        .in("source", ["system", "app_usage"])
        .gte("occurred_at", thirtyDaysAgo)
        .limit(200),
      client.from("bias_evidence_chains")
        .select("*")
        .eq("profile_id", executiveId)
        .in("status", ["accumulating", "tentative", "active"]),
    ]);

    const emails = emailsResult.data ?? [];
    const calendar = calendarResult.data ?? [];
    const tasks = tasksResult.data ?? [];

    if (!emails.length && !calendar.length) {
      results[executiveId] = { status: "skipped", detail: "No email or calendar data in last 30 days" };
      continue;
    }

    // ── Phase 2: Signal Extraction (Haiku, NO thinking, parallel per bias type) ──
    const signalContext = [
      `EMAILS (${emails.length}):`,
      ...emails.slice(0, 100).map((e) =>
        `[${new Date(e.occurred_at).toISOString().slice(0, 16)}] ${e.summary ?? JSON.stringify(e.raw_data).slice(0, 150)}`
      ),
      `\nCALENDAR (${calendar.length}):`,
      ...calendar.slice(0, 50).map((c) =>
        `[${new Date(c.occurred_at).toISOString().slice(0, 16)}] ${c.summary ?? JSON.stringify(c.raw_data).slice(0, 150)}`
      ),
    ].join("\n");

    const extractionResponse = await callAnthropic({
      model: "claude-haiku-4-5-20251001",
      max_tokens: 4096,
      messages: [{
        role: "user",
        content: `Classify the following executive communications and calendar data for cognitive bias signals. For each of the 9 bias types, output a JSON object with detected signals.

BIAS TYPES AND DETECTION RULES:
1. overconfidence: certainty:hedge ratio in emails. HIGH if certainty markers >= 8% and hedge < 2%
2. anchoring: first numeric value vs final agreed value in threads. Flag if delta < 0.15
3. sunk_cost: continued meetings on project with negative status + no cancellation within 7 days
4. availability: topic frequency spike within 14 days of salient event
5. confirmation: asymmetric response latency (confirming < 2x median, disconfirming > 3x median)
6. status_quo: calendar events unmodified > 90 days despite project change
7. planning_fallacy: estimate:actual ratio < 0.70 across tasks
8. escalation_of_commitment: >= 3 sequential resource increases without scope change
9. recency: strategic emails reference only events < 30 days old

Output ONLY valid JSON array:
[{"bias_type": "...", "signals_found": N, "signal_details": [{"description": "...", "evidence": "...", "strength": 0.0-1.0}]}]

DATA:
${signalContext}`,
      }],
    });

    const extractionText = extractText(extractionResponse).trim();
    let biasSignals: Array<{
      bias_type: string;
      signals_found: number;
      signal_details: Array<{ description: string; evidence: string; strength: number }>;
    }>;
    try {
      biasSignals = JSON.parse(extractionText);
    } catch {
      biasSignals = [];
    }

    // ── Phase 3: Evidence Accumulation ──
    let newObservations = 0;
    let chainsUpdated = 0;

    for (const biasResult of biasSignals) {
      if (!biasResult.signal_details?.length) continue;

      for (const signal of biasResult.signal_details) {
        if (signal.strength < 0.3) continue;

        // Write signal observation
        await client.from("bias_signal_observations").insert({
          profile_id: executiveId,
          bias_type: biasResult.bias_type,
          signal_type: "extracted",
          signal_value: signal.strength,
          classification: signal.strength >= 0.6 ? "strong" : "moderate",
          context_snapshot: { description: signal.description, evidence: signal.evidence },
          meets_minimum_data: emails.length >= 10,
        });
        newObservations++;
      }

      // Update or create evidence chain
      const existingChain = (existingChains.data ?? []).find(
        (c) => c.bias_type === biasResult.bias_type
      );

      const avgStrength = biasResult.signal_details.reduce((s, d) => s + d.strength, 0) / biasResult.signal_details.length;

      if (existingChain) {
        const newConfidence = Math.min(1.0,
          existingChain.confidence * 0.7 + avgStrength * 0.3
        );
        const newConsistency = existingChain.consistency_rate * 0.8 + (avgStrength > 0.5 ? 0.2 : 0);

        await client.from("bias_evidence_chains").update({
          signal_strength_avg: (existingChain.signal_strength_avg + avgStrength) / 2,
          consistency_rate: newConsistency,
          confidence: newConfidence,
          updated_at: new Date().toISOString(),
          // Promote to tentative if thresholds met
          status: (newConfidence >= 0.65 && newConsistency >= 0.6 && existingChain.status === "accumulating")
            ? "tentative" : existingChain.status,
        }).eq("id", existingChain.id);
        chainsUpdated++;
      } else {
        await client.from("bias_evidence_chains").insert({
          profile_id: executiveId,
          bias_type: biasResult.bias_type,
          signal_strength_avg: avgStrength,
          consistency_rate: avgStrength > 0.5 ? 0.5 : 0.3,
          confidence: avgStrength * 0.5,
          status: "accumulating",
        });
        chainsUpdated++;
      }
    }

    // ── Phase 4: Competing Hypothesis Gate (only for tentative chains, only if baseline mature) ──
    if (accountAge >= MIN_BASELINE_DAYS) {
      const { data: tentativeChains } = await client
        .from("bias_evidence_chains")
        .select("*")
        .eq("profile_id", executiveId)
        .eq("status", "tentative");

      for (const chain of tentativeChains ?? []) {
        if (!VIABLE_BIASES.has(chain.bias_type)) continue;

        const hypothesisResponse = await callAnthropic({
          model: "claude-haiku-4-5-20251001",
          max_tokens: 1024,
          messages: [{
            role: "user",
            content: `A cognitive bias detection system flagged "${chain.bias_type}" bias for a C-suite executive with confidence ${chain.confidence.toFixed(2)} and consistency ${chain.consistency_rate.toFixed(2)}.

Is there a plausible alternative explanation for this pattern? Consider: workload changes, seasonal effects, organizational changes, legitimate strategic pivots, data artifacts.

Output JSON: {"competing_hypothesis": "description or null", "competing_confidence": 0.0-1.0, "recommendation": "promote|dismiss|continue_monitoring"}`,
          }],
        });

        const hypText = extractText(hypothesisResponse).trim();
        let hypothesis;
        try {
          hypothesis = JSON.parse(hypText);
        } catch {
          hypothesis = { recommendation: "continue_monitoring" };
        }

        if (hypothesis.competing_confidence > 0.50) {
          await client.from("bias_evidence_chains")
            .update({ status: "dismissed", updated_at: new Date().toISOString() })
            .eq("id", chain.id);
        } else if (hypothesis.recommendation === "promote") {
          await client.from("bias_evidence_chains")
            .update({ status: "active", updated_at: new Date().toISOString() })
            .eq("id", chain.id);
        }
      }

      // ── Phase 5: Insight Card Generation (Opus adaptive, ONLY step with CoT) ──
      const { data: activeChains } = await client
        .from("bias_evidence_chains")
        .select("*")
        .eq("profile_id", executiveId)
        .eq("status", "active")
        .is("insight_card", null);

      for (const chain of activeChains ?? []) {
        const insightResponse = await callAnthropic({
          model: "claude-opus-4-6",
          max_tokens: 2048,
          thinking: { type: "enabled", effort: "high" },
          messages: [{
            role: "user",
            content: `Generate a cognitive bias insight card for a C-suite executive. The bias detection system has identified a "${chain.bias_type}" pattern with confidence ${chain.confidence.toFixed(2)}.

Frame the insight using ONE of these approaches (pick the most appropriate):
- CURIOSITY: "I noticed something interesting about your [X] this week..."
- PATTERN: "There's a pattern forming in how you approach [X]..."
- OPTION: "You might want to consider [X] as an alternative to your current approach..."

NEVER use accusatory language. NEVER say "you have a bias." Present as a neutral observation with evidence.

Output JSON:
{
  "framing": "curiosity|pattern|option",
  "headline": "12 words max",
  "body": "3-4 sentences with specific evidence",
  "evidence_summary": "bullet points of supporting data",
  "confidence_label": "high|medium|low",
  "suggested_action": "one specific thing to try"
}`,
          }],
        });

        const insightText = extractText(insightResponse).trim();
        let insightCard;
        try {
          insightCard = JSON.parse(insightText);
        } catch {
          insightCard = { headline: "Bias pattern detected", body: insightText, framing: "pattern" };
        }

        await client.from("bias_evidence_chains")
          .update({ insight_card: insightCard, updated_at: new Date().toISOString() })
          .eq("id", chain.id);
      }
    }

    // ── Phase 6: Decay Pass ──
    const thirtyDaysAgoDate = new Date(Date.now() - 30 * 86400000).toISOString();
    await client.from("bias_evidence_chains")
      .update({ status: "decayed", updated_at: new Date().toISOString() })
      .eq("profile_id", executiveId)
      .in("status", ["accumulating", "tentative"])
      .lt("updated_at", thirtyDaysAgoDate);

    // Log run
    await client.from("bias_analysis_runs").insert({
      profile_id: executiveId,
      run_date: new Date().toISOString().slice(0, 10),
      emails_analysed: emails.length,
      calendar_analysed: calendar.length,
      tasks_analysed: tasks.length,
      signals_extracted: newObservations,
      chains_updated: chainsUpdated,
      tokens_used: extractionResponse.usage.input_tokens + extractionResponse.usage.output_tokens,
    });

    results[executiveId] = {
      status: accountAge >= MIN_BASELINE_DAYS ? "ok" : "accumulating",
      detail: `Extracted ${newObservations} signals, updated ${chainsUpdated} chains`,
      account_age_days: accountAge,
      baseline_ready: accountAge >= MIN_BASELINE_DAYS,
      duration_ms: Date.now() - start,
    };
  }

  await client.from("pipeline_health_log").insert({
    check_type: "bias_detection",
    status: "ok",
    details: { results, duration_ms: Date.now() - start },
  });

  return new Response(JSON.stringify({
    pipeline: "nightly-bias-detection",
    duration_ms: Date.now() - start,
    results,
  }), { status: 200, headers: { "Content-Type": "application/json" } });
});
