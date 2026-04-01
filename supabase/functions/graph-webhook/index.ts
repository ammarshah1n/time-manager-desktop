// graph-webhook/index.ts
// Receives Microsoft Graph push notifications for email changes.
// Returns 202 immediately; queues processing to pgmq for idempotent async handling.
// See: ~/Timed-Brain/06 - Context/edge-function-pipeline-architecture.md

import { serve } from "https://deno.land/std@0.208.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
);

serve(async (req: Request) => {
  // Graph sends a validation token on subscription registration
  const url = new URL(req.url);
  const validationToken = url.searchParams.get("validationToken");
  if (validationToken) {
    return new Response(validationToken, {
      status: 200,
      headers: { "Content-Type": "text/plain" },
    });
  }

  // Acknowledge immediately — Graph requires 202 within 3s
  const response = new Response(null, { status: 202 });

  // Process in background (up to 400s on paid plan via waitUntil)
  EdgeRuntime.waitUntil(processNotifications(req));

  return response;
});

async function processNotifications(req: Request): Promise<void> {
  let payload: { value: GraphNotification[] };
  try {
    payload = await req.json();
  } catch {
    console.error("[graph-webhook] Failed to parse payload");
    return;
  }

  for (const notification of payload.value ?? []) {
    // Idempotency gate: ON CONFLICT DO NOTHING
    const { error } = await supabase
      .from("webhook_events")
      .insert({
        graph_event_id: notification.id,
        message_id: notification.resourceData?.id ?? "unknown",
        workspace_id: await resolveWorkspaceId(notification),
        status: "received",
      })
      .onConflict("graph_event_id")
      .ignoreDuplicates();

    if (error && error.code !== "23505") {
      console.error("[graph-webhook] DB insert error:", error.message);
      continue;
    }

    // Queue to pgmq for async processing
    await supabase.rpc("pgmq.send", {
      queue_name: "email_pipeline",
      msg: {
        graph_event_id: notification.id,
        message_id: notification.resourceData?.id,
        change_type: notification.changeType,
      },
    });
  }
}

async function resolveWorkspaceId(
  notification: GraphNotification
): Promise<string | null> {
  // Look up workspace from email account associated with the subscription
  const { data } = await supabase
    .from("email_accounts")
    .select("workspace_id")
    .eq("graph_subscription_id", notification.subscriptionId)
    .single();
  return data?.workspace_id ?? null;
}

interface GraphNotification {
  id: string;
  subscriptionId: string;
  changeType: string;
  resource: string;
  resourceData?: { id?: string; "@odata.type"?: string };
  clientState?: string;
}
