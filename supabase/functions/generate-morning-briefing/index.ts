import { serve } from "https://deno.land/std@0.208.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { callAnthropic, extractText } from "../_shared/anthropic.ts";
import { requireEnv } from "../_shared/config.ts";
import { loadCalibrationContext, formatCalibrationForPrompt, type CalibrationContext } from "../_shared/calibration.ts";

import { verifyServiceRole, AuthError, authErrorResponse } from "../_shared/auth.ts";
// Cron: 30 5 * * * (5:30 AM local, 15 min after refresh)
// Two-pass Opus briefing generation with adversarial review

const SUPABASE_URL = requireEnv("SUPABASE_URL");
const SUPABASE_SERVICE_KEY = requireEnv("SUPABASE_SERVICE_ROLE_KEY");

type BriefingSection = {
  section: string;
  insight: string;
  supporting_data: string | null;
  confidence: "high" | "moderate";
  category: string;
  source_signals: string[];
  // Wave 1 Task 22: stamped post-insert so Swift client can cite the
  // recommendation in outcome events.
  recommendation_id?: string;
};

// Wave 1 Task 22 helpers — briefing -> recommendations emission.
//
// `section_key` is a stable, slug-style identifier derived from the LLM's
// free-form `section` label. Normalising here means that retries with the
// same section name resolve to the same key, enabling the UNIQUE
// (briefing_id, section_key) conflict target below.
function sectionKey(raw: string): string {
  return (raw ?? "unknown")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "_")
    .replace(/^_+|_+$/g, "")
    .slice(0, 64) || "unknown";
}

// Normalised content hash — insight + supporting_data collapsed to a single
// canonical form so superficial whitespace / casing drift does not change
// the hash. Used for dedup by the outcome harvester (Wave 2 Task 24).
async function contentHash(section: BriefingSection): Promise<string> {
  const canonical = [
    section.section ?? "",
    section.insight ?? "",
    section.supporting_data ?? "",
    section.category ?? "",
  ]
    .join("\n")
    .replace(/\s+/g, " ")
    .trim()
    .toLowerCase();
  const data = new TextEncoder().encode(canonical);
  const digest = await crypto.subtle.digest("SHA-256", data);
  return Array.from(new Uint8Array(digest))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

// Emit one `recommendations` row per briefing section and mutate each section
// in place to stamp its `recommendation_id`. Idempotent: upsert uses
// UNIQUE(briefing_id, section_key) so re-invocations update instead of
// duplicating. Returns the operation error (if any) and whether any section
// was freshly stamped (so callers know when to persist the enriched JSONB).
async function emitRecommendations(
  // deno-lint-ignore no-explicit-any
  client: any,
  briefingId: string,
  sections: BriefingSection[],
): Promise<{ healed: boolean; error: string | null }> {
  const upsertPayload = await Promise.all(
    sections.map(async (s) => ({
      briefing_id: briefingId,
      section_key: sectionKey(s.section),
      // task_ref is NULL because briefing sections are topic-level; Wave 2
      // Task 24 matches on content_hash when task_ref is absent.
      task_ref: null as string | null,
      content_hash: await contentHash(s),
    })),
  );

  const { data: recRows, error: recError } = await client
    .from("recommendations")
    .upsert(upsertPayload, {
      onConflict: "briefing_id,section_key",
      ignoreDuplicates: false,
    })
    .select("id, section_key");

  if (recError) return { healed: false, error: recError.message };
  if (!recRows) return { healed: false, error: null };

  const byKey = new Map<string, string>();
  for (const row of recRows as Array<{ id: string; section_key: string }>) {
    byKey.set(row.section_key, row.id);
  }
  let healed = false;
  for (const s of sections) {
    const rid = byKey.get(sectionKey(s.section));
    if (rid && s.recommendation_id !== rid) {
      s.recommendation_id = rid;
      healed = true;
    }
  }
  return { healed, error: null };
}

function errorMessage(err: unknown): string {
  return err instanceof Error ? err.message : String(err);
}

function calibrationBriefingSection(calibration: CalibrationContext): BriefingSection | null {
  const overrides = calibration.yesterdayOverrides;
  const hasDrift = calibration.thirtyDayDriftPct !== null
    && Math.abs(calibration.thirtyDayDriftPct) >= 10;
  const bucketBias = calibration.perBucketBias.filter((b) => Math.abs(b.bias_minutes) >= 10);

  if (!overrides.length && !hasDrift && !bucketBias.length) return null;

  const overrideSummary = overrides.slice(0, 3).map((o) => {
    const direction = o.delta_pct >= 0 ? "+" : "";
    const reason = o.reason ? `, reason: ${o.reason}` : "";
    return `${o.old_minutes}m to ${o.new_minutes}m (${direction}${o.delta_pct}%${reason})`;
  }).join("; ");
  const driftSummary = hasDrift
    ? `30-day average estimate error is ${calibration.thirtyDayDriftPct!.toFixed(1)}%.`
    : null;
  const bucketSummary = bucketBias.slice(0, 3)
    .map((b) => `${b.bucket_type} bias ${b.bias_minutes >= 0 ? "+" : ""}${b.bias_minutes}m over ${b.n_samples} samples`)
    .join("; ");

  const evidence = [
    overrides.length ? `manual overrides: ${overrideSummary}` : null,
    driftSummary,
    bucketSummary ? `bucket bias: ${bucketSummary}` : null,
  ].filter(Boolean).join(" ");

  return {
    section: "Emerging Patterns",
    insight: "Task estimates need calibration attention because recent manual corrections show material variance from the AI estimate.",
    supporting_data: evidence,
    confidence: overrides.length >= 2 || bucketBias.length ? "high" : "moderate",
    category: "pattern",
    source_signals: ["estimate_override/behaviour_events", "estimate_calibration"],
  };
}

function ensureCalibrationSection(
  sections: BriefingSection[],
  calibration: CalibrationContext,
): BriefingSection[] {
  const calibrationSection = calibrationBriefingSection(calibration);
  if (!calibrationSection) return sections;

  const existing = sections.find((s) => sectionKey(s.section) === "emerging_patterns");
  if (!existing) return [...sections, calibrationSection];

  existing.insight = `${existing.insight}\n\n${calibrationSection.insight}`;
  existing.supporting_data = [existing.supporting_data, calibrationSection.supporting_data]
    .filter(Boolean)
    .join("\n");
  existing.source_signals = Array.from(new Set([
    ...(existing.source_signals ?? []),
    ...calibrationSection.source_signals,
  ]));
  return sections;
}

function fallbackSections(calibration: CalibrationContext): BriefingSection[] {
  return ensureCalibrationSection([
    {
      section: "Lead Insight",
      insight: "Timed could not complete the full AI briefing pass in time, so this briefing is limited to deterministic operational signals.",
      supporting_data: "Generation fallback triggered before the briefing write completed.",
      confidence: "moderate",
      category: "anomaly",
      source_signals: ["briefing_generation"],
    },
  ], calibration);
}

function parseSections(text: string): BriefingSection[] | null {
  const candidates = [
    text.trim(),
    text.trim().replace(/^```(?:json)?\s*/i, "").replace(/\s*```$/i, "").trim(),
  ];
  const firstBracket = text.indexOf("[");
  const lastBracket = text.lastIndexOf("]");
  if (firstBracket >= 0 && lastBracket > firstBracket) {
    candidates.push(text.slice(firstBracket, lastBracket + 1));
  }

  for (const candidate of candidates) {
    try {
      const parsed = JSON.parse(candidate);
      if (Array.isArray(parsed) && parsed.length) return parsed as BriefingSection[];
    } catch {
      // Try the next likely JSON shape.
    }
  }
  return null;
}

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { status: 200 });
  }
  try {
    verifyServiceRole(req);
  } catch (err) {
    if (err instanceof AuthError) return authErrorResponse(err);
    throw err;
  }


  const client = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY);
  const start = Date.now();
  let body: { executiveId?: string; executive_id?: string; date?: string } = {};
  try {
    body = await req.json();
  } catch {
    body = {};
  }
  const requestedExecutiveId = body.executiveId ?? body.executive_id;
  const requestedDate = body.date;

  let executivesQuery = client.from("executives").select("id, timezone");
  if (requestedExecutiveId) {
    executivesQuery = executivesQuery.eq("id", requestedExecutiveId);
  }
  const { data: executives } = await executivesQuery;
  if (!executives?.length) {
    return new Response(JSON.stringify({ error: "No executives found" }), { status: 500 });
  }

  const results: Record<string, unknown> = {};

  for (const executive of executives) {
    const executiveId = executive.id;
    const today = requestedDate ?? new Date().toISOString().slice(0, 10);

    // Check if briefing already exists for today
    const { data: existing } = await client
      .from("briefings")
      .select("id, content")
      .eq("profile_id", executiveId)
      .eq("date", today)
      .maybeSingle();

    if (existing) {
      // Wave 1 Task 22: if a prior invocation crashed between inserting the
      // briefing and emitting recommendations, heal here. The upsert below is
      // a no-op when rows already exist with matching content_hash.
      const existingContent = (existing.content ?? {}) as {
        sections?: BriefingSection[];
      };
      const existingSections = existingContent.sections ?? [];
      const missingRecommendationIds = existingSections.some(
        (s) => !s.recommendation_id,
      );
      if (existingSections.length && missingRecommendationIds) {
        const backfillResult = await emitRecommendations(
          client,
          existing.id as string,
          existingSections,
        );
        if (backfillResult.healed) {
          await client
            .from("briefings")
            .update({ content: { ...existingContent, sections: existingSections } })
            .eq("id", existing.id);
        }
        results[executiveId] = {
          status: "healed",
          detail: `Recommendations backfilled for existing briefing ${existing.id}`,
          recommendations_error: backfillResult.error,
        };
      } else {
        results[executiveId] = {
          status: "skipped",
          detail: `Briefing already exists for ${today}`,
        };
      }
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

    // ── Pass 1: Opus Generation ──
    const engagementContext = lowEngagement
      ? "\n\nENGAGEMENT SELF-CORRECTION: The executive spent <60s on the last 2 briefings. This briefing is being ignored. Restructure: lead with the single most surprising finding, cut any section that repeats prior briefings, reduce total word count by 40%."
      : "";

    const acbText = acb ? JSON.stringify(acb).slice(0, 30000) : "ACB not yet generated.";
    const summaryText = (summaries ?? []).map((s) =>
      `[${s.summary_date}] ${s.day_narrative}\nAnomalies: ${JSON.stringify(s.anomalies ?? [])}\nEnergy: ${JSON.stringify(s.energy_profile ?? {})}`
    ).join("\n\n");
    const calendarText = (calendarToday ?? []).map((c) =>
      `${new Date(c.occurred_at).toLocaleTimeString("en-AU", { hour: "2-digit", minute: "2-digit" })}: ${c.summary ?? JSON.stringify(c.raw_data).slice(0, 200)}`
    ).join("\n");
    const relationshipText = (atRiskRelationships ?? []).map((r) => {
      const node = (r as { ona_nodes?: { display_name?: string; relationship_type?: string } }).ona_nodes;
      return `${node?.display_name ?? "Unknown"} (${node?.relationship_type ?? "unknown"}): health=${r.health_score}, trajectory=${r.health_trajectory}`;
    }).join("\n");
    const calibration = await loadCalibrationContext(client, executiveId);
    const calibrationText = formatCalibrationForPrompt(calibration);

    let pass1Response: Awaited<ReturnType<typeof callAnthropic>> | null = null;
    let pass1Error: string | null = null;
    let sections: BriefingSection[];
    try {
      pass1Response = await callAnthropic({
        model: "claude-opus-4-6",
        max_tokens: 8192,
        timeout_ms: 45000,
        max_retries: 1,
        thinking: { type: "enabled", budget_tokens: 2048 },
        system: `You are the morning intelligence director for a C-suite executive's cognitive operating system. Generate a 7-section cognitive briefing. Each section must cite specific data from the observations provided. Be precise, not verbose. Every claim must trace to a data point.${engagementContext}

Output valid JSON array of sections:
[{"section": "Lead Insight|Calendar Intelligence|Email Patterns|Decision Observations|Cognitive Load Forecast|Emerging Patterns|Forward-Looking Observation", "insight": "the finding", "supporting_data": "specific evidence", "confidence": "high|moderate", "category": "pattern|anomaly|prediction|relationship|workload", "source_signals": ["signal_type/source"]}]

Sections:
1. Lead Insight — the single most important thing to know today (primacy effect)
2. Calendar Intelligence — what today's schedule reveals about priorities and load
3. Email Patterns — communication shifts, response latency changes, volume anomalies
4. Decision Observations — only include if there are decisions to note, otherwise omit
5. Cognitive Load Forecast — predicted energy and capacity based on schedule + patterns
6. Emerging Patterns — 0-2 patterns forming across multiple days (only if evidence supports)
7. Forward-Looking Observation — one thing to watch over the next 48-72 hours (recency anchor)

If the ESTIMATE CALIBRATION block shows non-trivial drift, overrides, or per-bucket bias, surface it inside an existing section (typically Emerging Patterns or Forward-Looking Observation). Do not invent a new section name.`,
        messages: [{
          role: "user",
          content: `ACTIVE CONTEXT BUFFER:\n${acbText}\n\nLAST 7 DAILY SUMMARIES:\n${summaryText}\n\nTODAY'S CALENDAR:\n${calendarText}\n\nAT-RISK RELATIONSHIPS:\n${relationshipText}\n\nTOP CONTACTS:\n${JSON.stringify(topContacts ?? []).slice(0, 5000)}${calibrationText}`,
        }],
      });

      const pass1Text = extractText(pass1Response);
      sections = parseSections(pass1Text)
        ?? [{ section: "Lead Insight", insight: pass1Text, supporting_data: null, confidence: "moderate", category: "pattern", source_signals: [] }];
    } catch (err) {
      pass1Error = errorMessage(err);
      sections = fallbackSections(calibration);
    }
    sections = ensureCalibrationSection(sections, calibration);

    // ── Pass 2: Adversarial CCR Review (fresh context, no generation prompt) ──
    const dataSourceManifest = [
      summaries?.length ? `${summaries.length} daily summaries` : null,
      acb ? "ACB-FULL" : null,
      calendarToday?.length ? `${calendarToday.length} calendar events` : null,
      atRiskRelationships?.length ? `${atRiskRelationships.length} at-risk relationships` : null,
      topContacts?.length ? `${topContacts.length} top contacts` : null,
    ].filter(Boolean).join(", ");

    const predictionRegister = (priorBriefings ?? []).slice(0, 5).map((b) => {
      const content = b.content as { sections?: BriefingSection[] };
      const forwardLooking = content?.sections?.find((s: BriefingSection) => s.section === "Forward-Looking Observation");
      return forwardLooking ? `[${b.date}] ${forwardLooking.insight}` : null;
    }).filter(Boolean).join("\n");

    let pass2Response: Awaited<ReturnType<typeof callAnthropic>> | null = null;
    let pass2Error: string | null = null;
    let adversarialReview: {
      checks?: unknown[];
      overall_quality_score?: number;
      release_recommendation?: string;
      critical_findings_count?: number;
      summary?: string;
    };
    if (pass1Response) {
      try {
        pass2Response = await callAnthropic({
          model: "claude-opus-4-6",
          max_tokens: 4096,
          timeout_ms: 45000,
          max_retries: 1,
          system: `You are an adversarial intelligence analyst. Your role is to find analytical failures in the briefing you are about to read. You did not write this briefing. You have no stake in its conclusions. Your job is to prosecute it.

Complete the following ten checks in sequence. For each check:
1. State whether the failure mode is present, absent, or undetectable without external data.
2. If present, cite the exact claim and explain the failure.
3. Assign a severity: CRITICAL (affects decision-making), MAJOR (affects confidence), MINOR (affects clarity).

Do not offer general praise. Do not assess writing quality. Do not confirm what is correct. Find what is wrong.

Output valid JSON:
{
  "checks": [
    {"code": "OCP|MC|SP|HF|ESC|CB|LI|AC|RI|FFC", "status": "present|absent|undetectable", "severity": "CRITICAL|MAJOR|MINOR|null", "claim": "quoted text or null", "explanation": "why this is a failure or null"}
  ],
  "overall_quality_score": 0-100,
  "release_recommendation": "RELEASE|RELEASE_WITH_RIDER|HOLD_FOR_REVISION",
  "critical_findings_count": 0,
  "summary": "one paragraph summary of review"
}`,
      messages: [{
        role: "user",
        content: `BRIEFING TO REVIEW:\n${JSON.stringify(sections, null, 2)}\n\nDATA SOURCES USED IN GENERATION:\n${dataSourceManifest}\n\nPREDICTION REGISTER (prior forward-looking observations):\n${predictionRegister || "No prior predictions."}

ADVERSARIAL CHECKLIST:
CHECK 1 — Over-Claimed Patterns [OCP]: Pattern stated with <3 data points
CHECK 2 — Missing Context [MC]: Contradictory data omitted
CHECK 3 — Stale Predictions [SP]: Forward-looking observation repeated from prior briefing without update
CHECK 4 — Hedging Failures [HF]: False certainty expressed without confidence qualifier
CHECK 5 — Engagement Self-Correction [ESC]: Prior low-engagement not addressed
CHECK 6 — Confirmation Bias Signal [CB]: Only supporting evidence cited, alternatives ignored
CHECK 7 — Linchpin Instability [LI]: Conclusion depends on single assumption that could be wrong
CHECK 8 — Anomaly Classification Error [AC]: Normal variation flagged as anomaly, or vice versa
CHECK 9 — Resolution Insufficiency [RI]: Prior prediction should have been resolved but wasn't
CHECK 10 — False False-Certainty [FFC]: Unnecessary hedging that reduces actionability`,
          }],
        });

        const pass2Text = extractText(pass2Response);
        try {
          adversarialReview = JSON.parse(pass2Text);
        } catch {
          adversarialReview = { overall_quality_score: 75, release_recommendation: "RELEASE_WITH_RIDER", summary: pass2Text };
        }
      } catch (err) {
        pass2Error = errorMessage(err);
        adversarialReview = {
          overall_quality_score: 70,
          release_recommendation: "RELEASE_WITH_RIDER",
          summary: `Adversarial review did not complete: ${pass2Error}`,
        };
      }
    } else {
      adversarialReview = {
        overall_quality_score: 65,
        release_recommendation: "RELEASE_WITH_RIDER",
        summary: `Primary AI generation did not complete: ${pass1Error}`,
      };
    }

    // ── Pass 3: Apply release decision ──
    const qualityScore = adversarialReview.overall_quality_score ?? 75;
    const releaseStatus = adversarialReview.release_recommendation ?? (qualityScore >= 85 ? "RELEASE" : qualityScore >= 70 ? "RELEASE_WITH_RIDER" : "HOLD_FOR_REVISION");

    const wordCount = sections.reduce((sum, s) => sum + (s.insight?.split(/\s+/).length ?? 0) + (s.supporting_data?.split(/\s+/).length ?? 0), 0);

    const briefingContent = {
      sections,
      word_count: wordCount,
      generated_by: "claude-opus-4-6",
      generation_errors: [pass1Error, pass2Error].filter(Boolean),
      adversarial_review: adversarialReview,
      quality_score: qualityScore,
      release_status: releaseStatus,
      quality_hold: releaseStatus === "HOLD_FOR_REVISION",
      context_used: {
        daily_summaries: summaries?.length ?? 0,
        acb_available: acb !== null,
        calendar_events: calendarToday?.length ?? 0,
        prior_briefings: priorBriefings?.length ?? 0,
        at_risk_relationships: atRiskRelationships?.length ?? 0,
        top_contacts: topContacts?.length ?? 0,
        low_engagement_trigger: lowEngagement,
        calibration_overrides: calibration.yesterdayOverrides.length,
      },
      tokens_used: {
        pass1: pass1Response ? pass1Response.usage.input_tokens + pass1Response.usage.output_tokens : 0,
        pass2: pass2Response ? pass2Response.usage.input_tokens + pass2Response.usage.output_tokens : 0,
      },
    };

    // Insert briefing — capture id so we can FK recommendations to it.
    // The `recommendations` table (migration 20260428_recommendation_outcomes.sql,
    // Agent A3) has a FK on briefings.id, so the briefing must exist first.
    const { data: briefingRow, error: insertError } = await client
      .from("briefings")
      .insert({
        profile_id: executiveId,
        date: today,
        content: briefingContent,
        generated_at: new Date().toISOString(),
        word_count: 0,
        was_viewed: false,
      })
      .select("id")
      .maybeSingle();

    // Wave 1 Task 22: emit one `recommendations` row per briefing section and
    // stamp `recommendation_id` back into each section so the Swift client can
    // cite it when writing recommendation_acted_on / _dismissed events.
    //
    // Idempotency: upsert uses UNIQUE(briefing_id, section_key), added by
    // migration 20260425120000_recommendations_unique.sql in this branch.
    // Re-invocations update rather than duplicate.
    let recommendationsError: string | null = null;
    const briefingId = briefingRow?.id as string | undefined;
    if (!insertError && briefingId) {
      const result = await emitRecommendations(client, briefingId, sections);
      recommendationsError = result.error;
      if (!result.error) {
        // Persist enriched sections back onto the briefing so the Swift
        // client sees `recommendation_id` on the JSONB it reads.
        const enrichedContent = { ...briefingContent, sections };
        const { error: updateError } = await client
          .from("briefings")
          .update({ content: enrichedContent })
          .eq("id", briefingId);
        if (updateError) recommendationsError = updateError.message;
      }
    }

    results[executiveId] = {
      status: insertError ? "error" : "ok",
      detail: insertError?.message ?? "Briefing generated (LLM calls pending implementation)",
      context: briefingContent.context_used,
      briefing_id: briefingId ?? null,
      recommendations_error: recommendationsError,
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
