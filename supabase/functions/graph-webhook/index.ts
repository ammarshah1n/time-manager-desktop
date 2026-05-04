// graph-webhook/index.ts
// Receives Microsoft Graph push notifications for email changes.
// Returns 202 only after accepted notifications are queued, so Microsoft retries
// when pgmq or the idempotency insert fails.
// See: ~/Timed-Brain/06 - Context/edge-function-pipeline-architecture.md

import { serve } from "https://deno.land/std@0.208.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { requireEnv } from "../_shared/config.ts";

const supabase = createClient(
  requireEnv("SUPABASE_URL"),
  requireEnv("SUPABASE_SERVICE_ROLE_KEY"),
);

function timingSafeEqual(a: string, b: string): boolean {
  const maxLength = Math.max(a.length, b.length);
  let diff = a.length ^ b.length;
  for (let i = 0; i < maxLength; i++) {
    diff |= (a.charCodeAt(i) || 0) ^ (b.charCodeAt(i) || 0);
  }
  return diff === 0;
}

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

  let payload: { value: GraphNotification[] };
  try {
    payload = await req.json();
    await processNotifications(payload);
    return new Response(null, { status: 202 });
  } catch (error) {
    console.error("[graph-webhook] Queueing failed before ack:", error);
    return new Response(JSON.stringify({ error: "queue_failed" }), {
      status: 503,
      headers: { "Content-Type": "application/json" },
    });
  }
});

async function processNotifications(payload: { value: GraphNotification[] }): Promise<void> {
  for (const notification of payload.value ?? []) {
    const { data: subscription, error: subscriptionError } = await supabase
      .from("graph_subscriptions")
      .select("exec_id,client_state")
      .eq("subscription_id", notification.subscriptionId)
      .maybeSingle();

    if (subscriptionError || !subscription) {
      console.warn(
        `[graph-webhook] Unknown subscription ${notification.subscriptionId} — skipping`,
      );
      continue;
    }

    if (
      typeof subscription.client_state !== "string" ||
      typeof notification.clientState !== "string" ||
      !timingSafeEqual(notification.clientState, subscription.client_state)
    ) {
      console.warn(
        `[graph-webhook] clientState mismatch for ${notification.subscriptionId} — skipping`,
      );
      continue;
    }

    // Idempotency gate: ON CONFLICT DO NOTHING
    const { error } = await supabase
      .from("webhook_events")
      .upsert(
        {
          graph_event_id: notification.id,
          message_id: notification.resourceData?.id ?? "unknown",
          workspace_id: await resolveWorkspaceId(
            notification,
            subscription.exec_id,
          ),
          status: "received",
        },
        { onConflict: "graph_event_id", ignoreDuplicates: true },
      );

    if (error && error.code !== "23505") {
      console.error("[graph-webhook] DB insert error:", error.message);
      throw error;
    }

    await queueNotification(notification);
  }
}

async function queueNotification(notification: GraphNotification): Promise<void> {
  const { error } = await supabase.rpc("pgmq.send", {
    queue_name: "email_pipeline",
    msg: {
      graph_event_id: notification.id,
      message_id: notification.resourceData?.id,
      change_type: notification.changeType,
    },
  });
  if (error) {
    console.error("[graph-webhook] pgmq.send error:", error.message);
    throw error;
  }
}

async function resolveWorkspaceId(
  notification: GraphNotification,
  fallbackExecId: string | null,
): Promise<string | null> {
  // Look up workspace from email account associated with the subscription
  const { data } = await supabase
    .from("email_accounts")
    .select("workspace_id")
    .eq("graph_subscription_id", notification.subscriptionId)
    .maybeSingle();
  return data?.workspace_id ?? fallbackExecId;
}

interface GraphNotification {
  id: string;
  subscriptionId: string;
  changeType: string;
  resource: string;
  resourceData?: { id?: string; "@odata.type"?: string };
  clientState?: string;
}
