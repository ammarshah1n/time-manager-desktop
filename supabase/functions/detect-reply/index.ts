// detect-reply/index.ts
// Checks if a waiting_item has received a reply from the expected person.
// Called after each Graph delta sync or on a schedule.
// Loop 3 signal collection — updates waiting_items.reply_received_at and logs a behaviour_event.

import { serve } from "https://deno.land/std@0.208.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { verifyAuth, AuthError, authErrorResponse } from "../_shared/auth.ts";
import { createRequestLogger } from "../_shared/logger.ts";
import { requireEnv } from "../_shared/config.ts";

const supabase = createClient(
  requireEnv("SUPABASE_URL"),
  requireEnv("SUPABASE_SERVICE_ROLE_KEY")
);

serve(async (req: Request) => {
  const log = createRequestLogger("detect-reply");
  try {
  try {
    await verifyAuth(req);
  } catch (err) {
    if (err instanceof AuthError) return authErrorResponse(err);
    throw err;
  }

  const { workspaceId, waitingItemId, fromAddress, subjectKeywords } = await req.json();

  if (!workspaceId || !waitingItemId || !fromAddress) {
    return new Response(
      JSON.stringify({ error: "Missing required fields: workspaceId, waitingItemId, fromAddress" }),
      { status: 400, headers: { "Content-Type": "application/json" } }
    );
  }

  // 1. Fetch the waiting_item
  const { data: waitingItem, error: waitingError } = await supabase
    .from("waiting_items")
    .select("*")
    .eq("id", waitingItemId)
    .eq("workspace_id", workspaceId)
    .single();

  if (waitingError || !waitingItem) {
    return new Response(
      JSON.stringify({ error: "waiting_item not found" }),
      { status: 404, headers: { "Content-Type": "application/json" } }
    );
  }

  // 2. Already resolved — short circuit
  if (waitingItem.reply_received_at) {
    return new Response(
      JSON.stringify({ alreadyResolved: true }),
      { status: 200, headers: { "Content-Type": "application/json" } }
    );
  }

  // 3. Query email_messages for a matching reply
  let query = supabase
    .from("email_messages")
    .select("id,received_at,subject")
    .eq("workspace_id", workspaceId)
    .ilike("from_address", fromAddress)
    .gt("received_at", waitingItem.created_at)
    .in("bucket", ["inbox", "later"])
    .order("received_at", { ascending: false })
    .limit(5);

  // Add subject keyword filter if provided
  if (subjectKeywords && Array.isArray(subjectKeywords) && subjectKeywords.length > 0) {
    const orClauses = subjectKeywords
      .map((kw: string) => `subject.ilike.%${kw}%`)
      .join(",");
    query = query.or(orClauses);
  }

  const { data: matchingEmails, error: emailError } = await query;

  if (emailError) {
    console.error("[detect-reply] email query error:", emailError.message);
    return new Response(
      JSON.stringify({ error: emailError.message }),
      { status: 500, headers: { "Content-Type": "application/json" } }
    );
  }

  if (matchingEmails && matchingEmails.length > 0) {
    // 4. Reply found — resolve the waiting item
    const matchEmail = matchingEmails[0];
    const createdAt = new Date(waitingItem.created_at).getTime();
    const repliedAt = new Date(matchEmail.received_at).getTime();
    const daysWaited = Math.round((repliedAt - createdAt) / (1000 * 60 * 60 * 24));

    await supabase
      .from("waiting_items")
      .update({
        reply_received_at: matchEmail.received_at,
        status: "replied",
      })
      .eq("id", waitingItemId);

    await supabase.from("behaviour_events").insert({
      workspace_id: workspaceId,
      profile_id: waitingItem.profile_id,
      event_type: "waiting_resolved",
      payload: {
        waiting_item_id: waitingItemId,
        reply_email_id: matchEmail.id,
        days_waited: daysWaited,
      },
      occurred_at: new Date().toISOString(),
    });

    return new Response(
      JSON.stringify({
        resolved: true,
        replyEmailId: matchEmail.id,
        daysWaited,
      }),
      { status: 200, headers: { "Content-Type": "application/json" } }
    );
  }

  // 5. No match — check if overdue
  const now = Date.now();
  const createdAt = new Date(waitingItem.created_at).getTime();
  const daysWaiting = Math.round((now - createdAt) / (1000 * 60 * 60 * 24));
  const isOverdue = waitingItem.expected_by
    ? new Date(waitingItem.expected_by).getTime() < now
    : false;

  log.info("complete", { workspace_id: workspaceId, waiting_item_id: waitingItemId, resolved: false });
  return new Response(
    JSON.stringify({
      resolved: false,
      isOverdue,
      daysWaiting,
    }),
    { status: 200, headers: { "Content-Type": "application/json" } }
  );
  } catch (err) {
    log.error("unhandled", err);
    return new Response(JSON.stringify({ error: err instanceof Error ? err.message : "Internal error", request_id: log.request_id }), { status: 500, headers: { "Content-Type": "application/json" } });
  }
});
