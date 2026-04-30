import { serve } from "https://deno.land/std@0.208.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { callAnthropic, extractText } from "../_shared/anthropic.ts";
import { verifyAuth, AuthError, authErrorResponse } from "../_shared/auth.ts";
import { createRequestLogger } from "../_shared/logger.ts";
import { requireEnv } from "../_shared/config.ts";

// Relationship intelligence card generation
// Triggered when RelationshipHealthService detects health drop below 0.6
// Research grounding: v3-03 (relationship intelligence card design)
//
// 15-field schema with 3-layer progressive disclosure:
//   Glance (5-8s): name, health dot, delta, primary signal
//   Summary (15-30s): latency, meetings, email freq, interpretations, CTA
//   Detail (60-90s): timeline, charts, tone, feedback controls
//
// Top predictors: reply latency delta (#1), meeting cancellation (#2), tone/formality (#3)

const SUPABASE_URL = requireEnv("SUPABASE_URL");
const SUPABASE_SERVICE_KEY = requireEnv("SUPABASE_SERVICE_ROLE_KEY");

serve(async (req: Request) => {
  const log = createRequestLogger("generate-relationship-card");
  try {
  if (req.method === "OPTIONS") {
    return new Response("ok", { status: 200 });
  }

  let authUserId: string;
  try {
    authUserId = await verifyAuth(req);
  } catch (err) {
    if (err instanceof AuthError) return authErrorResponse(err);
    throw err;
  }

  const client = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY);
  const start = Date.now();

  const { profile_id, contact_id, health_score, health_trajectory } = await req.json() as {
    profile_id: string;
    contact_id: string;
    health_score: number;
    health_trajectory: string;
  };

  if (!profile_id || !contact_id) {
    return new Response(JSON.stringify({ error: "profile_id and contact_id required" }), { status: 400 });
  }

  // Ownership: body-supplied profile_id must match the executive the
  // authenticated user owns. Without this, any signed-in user could read
  // any other executive's contact data and email observation summaries
  // by submitting another profile_id.
  const { data: ownedExec } = await client
    .from("executives")
    .select("id")
    .eq("auth_user_id", authUserId)
    .maybeSingle();
  if (!ownedExec || ownedExec.id !== profile_id) {
    return new Response(JSON.stringify({ error: "Forbidden" }), { status: 403 });
  }

  // Fetch contact data
  const { data: contact } = await client
    .from("ona_nodes")
    .select("*")
    .eq("id", contact_id)
    .eq("profile_id", profile_id)
    .maybeSingle();

  if (!contact) {
    return new Response(JSON.stringify({ error: "Contact not found" }), { status: 404 });
  }

  // Fetch recent email observations with this contact
  const thirtyDaysAgo = new Date(Date.now() - 30 * 86400000).toISOString();
  const { data: emailObs } = await client
    .from("tier0_observations")
    .select("summary, raw_data, occurred_at, authoritative_score")
    .eq("profile_id", profile_id)
    .eq("source", "email")
    .gte("occurred_at", thirtyDaysAgo)
    .order("occurred_at", { ascending: false })
    .limit(100);

  // Filter emails related to this contact
  const contactEmails = (emailObs ?? []).filter((e) => {
    const raw = e.raw_data;
    const summary = e.summary ?? "";
    const contactName = contact.display_name ?? "";
    const contactEmail = contact.email ?? "";
    return summary.includes(contactName) || summary.includes(contactEmail) ||
      JSON.stringify(raw).includes(contactEmail);
  });

  // Fetch calendar observations with this contact
  const { data: calendarObs } = await client
    .from("tier0_observations")
    .select("summary, raw_data, occurred_at")
    .eq("profile_id", profile_id)
    .eq("source", "calendar")
    .gte("occurred_at", thirtyDaysAgo)
    .limit(100);

  const contactMeetings = (calendarObs ?? []).filter((c) => {
    const summary = c.summary ?? "";
    return summary.includes(contact.display_name ?? "") || summary.includes(contact.email ?? "");
  });

  // Check data sufficiency — grey status if < 14 days
  const { data: relationship } = await client
    .from("relationships")
    .select("created_at, health_score, health_trajectory, last_contact_at")
    .eq("profile_id", profile_id)
    .eq("node_id", contact_id)
    .maybeSingle();

  const relationshipAge = relationship
    ? Math.floor((Date.now() - new Date(relationship.created_at).getTime()) / 86400000)
    : 0;

  if (relationshipAge < 14) {
    // Insufficient data — store grey card
    await client.from("contact_intelligence").upsert({
      profile_id,
      contact_id,
      contact_display_name: contact.display_name,
      health_status: "grey",
      health_delta: 0,
      primary_signal_label: "Insufficient data — tracking started",
      confidence_level: "low",
      card_generated_at: new Date().toISOString(),
    }, { onConflict: "profile_id,contact_id" });

    return new Response(JSON.stringify({
      status: "grey",
      detail: `Only ${relationshipAge} days of data (need 14+)`,
    }), { status: 200, headers: { "Content-Type": "application/json" } });
  }

  // Generate card via Opus with thinking
  const response = await callAnthropic({
    model: "claude-opus-4-6",
    max_tokens: 4096,
    thinking: { type: "enabled", effort: "high" },
    system: `You are a relationship intelligence analyst for a C-suite executive's cognitive operating system. Generate a relationship intelligence card for one specific contact.

CRITICAL RULES:
- ALWAYS surface multiple interpretations. Never single-cause framing.
- Frame interpretations as possibilities, not conclusions.
- One recommended action per card, max 8 words.
- Use neutral, non-judgmental language.

Output valid JSON matching this exact schema:
{
  "health_status": "green|yellow|red",
  "health_delta": -100 to 100 (30-day trend as percentage change),
  "primary_signal_label": "<=12 words, most significant change",
  "reply_latency_delta": "multiplier vs 30-day baseline, e.g. 4.2",
  "meeting_attendance_rate": 0.0-1.0,
  "email_frequency_trend": "rising|stable|declining",
  "initiated_ratio_delta": "description of who-initiates shift",
  "tone_formality_index": 0.0-1.0 (relative to contact's baseline),
  "interpretation_set": [
    {"label": "interpretation", "probability": 0.0-1.0, "corroborating_signals": ["signal1", "signal2"]}
  ],
  "recommended_action": "<=8 words",
  "confidence_level": "high|medium|low"
}`,
    messages: [{
      role: "user",
      content: `CONTACT: ${contact.display_name} (${contact.email})
Role: ${contact.relationship_type ?? "unknown"}, Authority: ${contact.authority_tier ?? "unknown"}
Relationship health: ${health_score}, trajectory: ${health_trajectory}
Total emails sent: ${contact.total_emails_sent ?? 0}, received: ${contact.total_emails_received ?? 0}
Avg response latency: ${contact.avg_response_latency_seconds ?? "unknown"}s
Current health trend: ${contact.health_trend ?? "unknown"}
Formality trend: ${contact.formality_trend ?? "unknown"}
Responsiveness symmetry: ${contact.responsiveness_symmetry ?? "unknown"}

RECENT EMAILS WITH THIS CONTACT (${contactEmails.length}):
${contactEmails.slice(0, 30).map((e) =>
  `[${new Date(e.occurred_at).toISOString().slice(0, 16)}] ${e.summary ?? ""}`.slice(0, 200)
).join("\n")}

RECENT MEETINGS WITH THIS CONTACT (${contactMeetings.length}):
${contactMeetings.slice(0, 15).map((m) =>
  `[${new Date(m.occurred_at).toISOString().slice(0, 16)}] ${m.summary ?? ""}`.slice(0, 200)
).join("\n")}`,
    }],
  });

  const cardText = extractText(response);
  let cardData;
  try {
    cardData = JSON.parse(cardText);
  } catch {
    cardData = {
      health_status: health_score >= 0.7 ? "green" : health_score >= 0.4 ? "yellow" : "red",
      health_delta: 0,
      primary_signal_label: "Analysis incomplete",
      confidence_level: "low",
    };
  }

  // Store the card
  await client.from("contact_intelligence").upsert({
    profile_id,
    contact_id,
    contact_display_name: contact.display_name,
    health_status: cardData.health_status,
    health_delta: cardData.health_delta ?? 0,
    primary_signal_label: cardData.primary_signal_label,
    reply_latency_delta: cardData.reply_latency_delta,
    meeting_attendance_rate: cardData.meeting_attendance_rate,
    email_frequency_trend: cardData.email_frequency_trend,
    initiated_ratio_delta: cardData.initiated_ratio_delta,
    tone_formality_index: cardData.tone_formality_index,
    interpretation_set: cardData.interpretation_set ?? [],
    recommended_action: cardData.recommended_action,
    confidence_level: cardData.confidence_level ?? "medium",
    card_generated_at: new Date().toISOString(),
    tokens_used: response.usage.input_tokens + response.usage.output_tokens,
  }, { onConflict: "profile_id,contact_id" });

  log.info("complete", { executive_id: profile_id, contact_id, health_status: cardData.health_status });
  return new Response(JSON.stringify({
    status: "ok",
    contact: contact.display_name,
    health_status: cardData.health_status,
    health_delta: cardData.health_delta,
    interpretations: cardData.interpretation_set?.length ?? 0,
    tokens_used: response.usage.input_tokens + response.usage.output_tokens,
    duration_ms: Date.now() - start,
  }), { status: 200, headers: { "Content-Type": "application/json" } });
  } catch (err) {
    log.error("unhandled", err);
    return new Response(JSON.stringify({ error: err instanceof Error ? err.message : "Internal error", request_id: log.request_id }), { status: 500, headers: { "Content-Type": "application/json" } });
  }
});
