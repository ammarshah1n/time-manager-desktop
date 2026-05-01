// renew-graph-subscriptions/index.ts
// Renews Microsoft Graph webhook subscriptions before 3-day expiry.
// Called by pg_cron every 2 days.
// Checks all subscriptions expiring within 24 hours and renews via Graph API PATCH.

import { serve } from "https://deno.land/std@0.208.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import {
  AuthError,
  authErrorResponse,
  verifyServiceRole,
} from "../_shared/auth.ts";
import { createRequestLogger } from "../_shared/logger.ts";
import { requireEnv } from "../_shared/config.ts";

const supabase = createClient(
  requireEnv("SUPABASE_URL"),
  requireEnv("SUPABASE_SERVICE_ROLE_KEY"),
);

const TOKEN_REFRESH_WINDOW_MS = 5 * 60 * 1000;

let graphTokenCache: { access_token: string; expires_at: number } | null = null;

interface SubscriptionRow {
  id: string;
  exec_id: string | null;
  subscription_id: string | null;
  resource: string;
  expires_at: string;
}

interface TokenEndpointResponse {
  access_token: string;
  expires_in: number;
}

interface PatchResponse {
  expirationDateTime?: string;
}

class GraphAuthError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "GraphAuthError";
  }
}

class SubscriptionNotFoundError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "SubscriptionNotFoundError";
  }
}

async function getGraphAppToken(): Promise<string> {
  const now = Date.now();
  if (
    graphTokenCache &&
    now < graphTokenCache.expires_at - TOKEN_REFRESH_WINDOW_MS
  ) {
    return graphTokenCache.access_token;
  }

  const tenantId = requireEnv("MSFT_TENANT_ID");
  const tokenUrl = `https://login.microsoftonline.com/${
    encodeURIComponent(
      tenantId,
    )
  }/oauth2/v2.0/token`;
  const body = new URLSearchParams({
    grant_type: "client_credentials",
    client_id: requireEnv("MSFT_APP_CLIENT_ID"),
    client_secret: requireEnv("MSFT_APP_CLIENT_SECRET"),
    scope: "https://graph.microsoft.com/.default",
  });

  const response = await fetch(tokenUrl, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: body.toString(),
  });
  if (!response.ok) {
    const text = await response.text().catch(() => "<unreadable>");
    throw new Error(
      `Graph token request failed: ${response.status} ${response.statusText}: ${text}`,
    );
  }

  const parsed = (await response.json()) as TokenEndpointResponse;
  graphTokenCache = {
    access_token: parsed.access_token,
    expires_at: Date.now() + parsed.expires_in * 1000,
  };
  return graphTokenCache.access_token;
}

async function patchSubscription(
  subscriptionId: string,
  newExpiry: string,
  token: string,
): Promise<PatchResponse> {
  const response = await fetch(
    `https://graph.microsoft.com/v1.0/subscriptions/${
      encodeURIComponent(
        subscriptionId,
      )
    }`,
    {
      method: "PATCH",
      headers: {
        Authorization: `Bearer ${token}`,
        "Content-Type": "application/json",
        Accept: "application/json",
      },
      body: JSON.stringify({ expirationDateTime: newExpiry }),
    },
  );

  if (response.status === 401) {
    throw new GraphAuthError(`Graph returned 401 for ${subscriptionId}`);
  }
  if (response.status === 404) {
    throw new SubscriptionNotFoundError(
      `Graph subscription ${subscriptionId} was not found`,
    );
  }
  if (!response.ok) {
    const text = await response.text().catch(() => "(no body)");
    throw new Error(
      `Graph ${response.status} for subscription ${subscriptionId}: ${text}`,
    );
  }

  return (await response.json()) as PatchResponse;
}

async function patchSubscriptionWithRetry(
  subscriptionId: string,
  newExpiry: string,
): Promise<PatchResponse> {
  let token = await getGraphAppToken();
  try {
    return await patchSubscription(subscriptionId, newExpiry, token);
  } catch (err) {
    if (err instanceof GraphAuthError) {
      graphTokenCache = null;
      token = await getGraphAppToken();
      return await patchSubscription(subscriptionId, newExpiry, token);
    }
    throw err;
  }
}

serve(async (req: Request) => {
  const log = createRequestLogger("renew-graph-subscriptions");
  if (req.method === "OPTIONS") return new Response("ok", { status: 200 });
  if (req.method !== "POST") {
    return new Response("Method not allowed", { status: 405 });
  }

  try {
    verifyServiceRole(req);
    const renewWindowCutoff = new Date(Date.now() + 24 * 60 * 60 * 1000)
      .toISOString();

    const { data: subscriptions, error: fetchError } = await supabase
      .from("graph_subscriptions")
      .select(
        "id,exec_id,subscription_id,resource,expires_at",
      )
      .not("subscription_id", "is", null)
      .lt("expires_at", renewWindowCutoff);

    if (fetchError) {
      console.error(
        "[renew-graph-subscriptions] fetch error:",
        fetchError.message,
      );
      return new Response(
        JSON.stringify({ error: fetchError.message }),
        { status: 500, headers: { "Content-Type": "application/json" } },
      );
    }

    if (!subscriptions || subscriptions.length === 0) {
      return new Response(
        JSON.stringify({ renewed: 0, failed: 0, deleted: 0 }),
        { status: 200, headers: { "Content-Type": "application/json" } },
      );
    }

    let renewed = 0;
    let failed = 0;
    let deleted = 0;

    for (const subscription of subscriptions as SubscriptionRow[]) {
      const {
        id: rowId,
        exec_id,
        subscription_id,
        resource,
      } = subscription;

      if (!subscription_id) continue;
      const newExpiry = new Date(Date.now() + 3 * 24 * 60 * 60 * 1000)
        .toISOString();

      try {
        const body = await patchSubscriptionWithRetry(
          subscription_id,
          newExpiry,
        );
        const confirmedExpiry = body.expirationDateTime ?? newExpiry;

        await supabase
          .from("graph_subscriptions")
          .update({
            expires_at: confirmedExpiry,
            updated_at: new Date().toISOString(),
          })
          .eq("id", rowId);

        renewed++;
        console.log(
          `[renew-graph-subscriptions] renewed ${subscription_id} (${resource}) for exec ${exec_id}`,
        );
      } catch (err) {
        if (err instanceof SubscriptionNotFoundError) {
          await supabase
            .from("graph_subscriptions")
            .delete()
            .eq("id", rowId);
          deleted++;
          console.warn(
            `[renew-graph-subscriptions] deleted missing subscription ${subscription_id}`,
          );
          continue;
        }

        const msg = err instanceof Error ? err.message : String(err);
        console.error(
          `[renew-graph-subscriptions] renewal error for ${subscription_id}:`,
          msg,
        );
        failed++;
      }
    }

    log.info("complete", { renewed, failed, deleted });
    return new Response(
      JSON.stringify({ renewed, failed, deleted }),
      { status: 200, headers: { "Content-Type": "application/json" } },
    );
  } catch (err) {
    if (err instanceof AuthError) return authErrorResponse(err);
    log.error("unhandled", err);
    return new Response(
      JSON.stringify({
        error: err instanceof Error ? err.message : "Internal error",
        request_id: log.request_id,
      }),
      { status: 500, headers: { "Content-Type": "application/json" } },
    );
  }
});
