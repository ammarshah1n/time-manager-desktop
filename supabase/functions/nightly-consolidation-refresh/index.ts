import { serve } from "https://deno.land/std@0.208.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { callAnthropic, extractText } from "../_shared/anthropic.ts";

// Cron: 15 5 * * * (5:15 AM local)
// Lightweight refresh: overnight importance audit → re-score → summary addendum → ACB refresh

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

type SupabaseClient = ReturnType<typeof createClient>;

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

  const results: Record<string, Record<string, unknown>> = {};

  for (const executive of executives) {
    const executiveId = executive.id;
    const stepResults: Record<string, unknown> = {};
    const now = new Date();

    // ── Step 0: Conditional overnight importance audit ──
    // Query tier0 WHERE occurred_at BETWEEN 9 PM yesterday AND 5 AM today
    // AND importance_score BETWEEN 0.55 AND 0.75
    const yesterdayNine = new Date(now);
    yesterdayNine.setDate(yesterdayNine.getDate() - 1);
    yesterdayNine.setHours(21, 0, 0, 0);
    const todayFive = new Date(now);
    todayFive.setHours(5, 0, 0, 0);

    const { data: uncertainOvernight } = await client
      .from("tier0_observations")
      .select("id, summary, source, event_type, raw_data")
      .eq("profile_id", executiveId)
      .gte("occurred_at", yesterdayNine.toISOString())
      .lte("occurred_at", todayFive.toISOString())
      .gte("importance_score", 0.55)
      .lte("importance_score", 0.75);

    if (uncertainOvernight?.length) {
      const summaries = uncertainOvernight.map((obs, i) =>
        `[${i}] ${obs.source}/${obs.event_type}: ${obs.summary ?? JSON.stringify(obs.raw_data).slice(0, 300)}`
      ).join("\n");

      const auditResponse = await callAnthropic({
        model: "claude-sonnet-4-6",
        max_tokens: 2048,
        temperature: 0,
        thinking: { type: "enabled", budget_tokens: 4096 },
        messages: [{
          role: "user",
          content: `Re-score these overnight observations (9 PM - 5 AM) for a C-suite executive. Overnight signals may include board emails, emergency meetings, or pre-dawn calendar changes. Rate 1-10. Output ONLY a JSON array of integers.\n\n${summaries}`,
        }],
      });

      const scoreText = extractText(auditResponse).trim();
      let scores: number[];
      try { scores = JSON.parse(scoreText); } catch { scores = scoreText.match(/\d+/g)?.map(Number) ?? []; }

      for (let i = 0; i < Math.min(scores.length, uncertainOvernight.length); i++) {
        await client
          .from("tier0_observations")
          .update({ importance_score: Math.max(1, Math.min(10, scores[i])) / 10.0 })
          .eq("id", uncertainOvernight[i].id);
      }

      stepResults.overnight_audit = { status: "ok", count: uncertainOvernight.length, tokens: auditResponse.usage.input_tokens + auditResponse.usage.output_tokens };
    } else {
      stepResults.overnight_audit = { status: "skipped", count: 0 };
    }

    // ── Step 1: Re-score new Tier 0 since 2 AM (Haiku) ─���
    const twoAM = new Date(now);
    twoAM.setHours(2, 0, 0, 0);

    const { data: newSince2AM } = await client
      .from("tier0_observations")
      .select("id, summary, source, event_type, raw_data")
      .eq("profile_id", executiveId)
      .gte("occurred_at", twoAM.toISOString())
      .eq("importance_score", 0.5)
      .limit(50);

    if (newSince2AM?.length) {
      const summaries = newSince2AM.map((obs, i) =>
        `[${i}] ${obs.source}/${obs.event_type}: ${obs.summary ?? JSON.stringify(obs.raw_data).slice(0, 200)}`
      ).join("\n");

      const haiku = await callAnthropic({
        model: "claude-haiku-4-5-20251001",
        max_tokens: 1024,
        temperature: 0,
        messages: [{ role: "user", content: `Rate each observation 1-10 importance. Output ONLY JSON array of integers.\n\n${summaries}` }],
      });

      const text = extractText(haiku).trim();
      let scores: number[];
      try { scores = JSON.parse(text); } catch { scores = text.match(/\d+/g)?.map(Number) ?? []; }

      for (let i = 0; i < Math.min(scores.length, newSince2AM.length); i++) {
        await client
          .from("tier0_observations")
          .update({ importance_score: Math.max(1, Math.min(10, scores[i])) / 10.0 })
          .eq("id", newSince2AM[i].id);
      }

      stepResults.rescore = { status: "ok", count: newSince2AM.length };
    } else {
      stepResults.rescore = { status: "skipped", count: 0 };
    }

    // ── Step 2: Append addendum to today's daily summary ──
    const today = now.toISOString().slice(0, 10);
    const { data: existingSummary } = await client
      .from("tier1_daily_summaries")
      .select("id, day_narrative")
      .eq("profile_id", executiveId)
      .eq("summary_date", today)
      .maybeSingle();

    if (existingSummary && (newSince2AM?.length || uncertainOvernight?.length)) {
      // Fetch new observations since the summary was generated
      const { data: newObs } = await client
        .from("tier0_observations")
        .select("source, event_type, summary, raw_data, importance_score, occurred_at")
        .eq("profile_id", executiveId)
        .gte("occurred_at", twoAM.toISOString())
        .order("occurred_at", { ascending: true });

      if (newObs?.length) {
        const newObsFormatted = newObs.map((obs) =>
          `[${new Date(obs.occurred_at).toLocaleTimeString("en-AU", { hour: "2-digit", minute: "2-digit" })}] ${obs.source}/${obs.event_type} (${obs.importance_score}): ${obs.summary ?? JSON.stringify(obs.raw_data).slice(0, 200)}`
        ).join("\n");

        const addendumResponse = await callAnthropic({
          model: "claude-sonnet-4-6",
          max_tokens: 2048,
          temperature: 0,
          messages: [{
            role: "user",
            content: `Append a brief addendum (2-3 sentences) to this daily summary based on overnight observations. Only mention if something noteworthy happened. If nothing notable, output "NO_ADDENDUM".\n\nEXISTING SUMMARY:\n${existingSummary.day_narrative?.slice(0, 2000)}\n\nOVERNIGHT OBSERVATIONS:\n${newObsFormatted}`,
          }],
        });

        const addendum = extractText(addendumResponse).trim();
        if (addendum !== "NO_ADDENDUM" && addendum.length > 10) {
          await client
            .from("tier1_daily_summaries")
            .update({ day_narrative: `${existingSummary.day_narrative}\n\n[5:15 AM Addendum] ${addendum}` })
            .eq("id", existingSummary.id);
          stepResults.summary_addendum = { status: "ok", addendum_length: addendum.length };
        } else {
          stepResults.summary_addendum = { status: "skipped", detail: "Nothing notable overnight" };
        }
      }
    } else {
      stepResults.summary_addendum = { status: "skipped", detail: "No summary or no new observations" };
    }

    // ── Step 3: Refresh ACB with morning calendar ──
    const { data: todayCalendar } = await client
      .from("tier0_observations")
      .select("summary, raw_data, occurred_at")
      .eq("profile_id", executiveId)
      .eq("source", "calendar")
      .gte("occurred_at", today)
      .order("occurred_at", { ascending: true });

    if (todayCalendar?.length) {
      // Update ACB with fresh calendar context
      const { data: currentACB } = await client
        .from("active_context_buffer")
        .select("acb_full")
        .eq("profile_id", executiveId)
        .maybeSingle();

      if (currentACB?.acb_full) {
        const updatedFull = { ...currentACB.acb_full, session_context: { todays_calendar: todayCalendar, refreshed_at: now.toISOString() } };
        await client
          .from("active_context_buffer")
          .update({ acb_full: updatedFull, acb_generated_at: now.toISOString() })
          .eq("profile_id", executiveId);
        stepResults.acb_refresh = { status: "ok", calendar_events: todayCalendar.length };
      } else {
        stepResults.acb_refresh = { status: "skipped", detail: "No ACB to refresh" };
      }
    } else {
      stepResults.acb_refresh = { status: "skipped", detail: "No calendar data for today" };
    }

    results[executiveId] = stepResults;
  }

  await client.from("pipeline_health_log").insert({
    check_type: "nightly_pipeline",
    status: "ok",
    details: { pipeline: "nightly-consolidation-refresh", results, duration_ms: Date.now() - start },
  });

  return new Response(JSON.stringify({
    pipeline: "nightly-consolidation-refresh",
    duration_ms: Date.now() - start,
    results,
  }), { status: 200, headers: { "Content-Type": "application/json" } });
});
