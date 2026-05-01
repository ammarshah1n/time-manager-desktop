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

    // 1. Fetch all email_accounts with subscriptions expiring within 24 hours
    const { data: accounts, error: fetchError } = await supabase
      .from("email_accounts")
      .select(
        "id,workspace_id,graph_subscription_id,subscription_expires_at,oauth_access_token",
      )
      .not("graph_subscription_id", "is", null)
      .lt("subscription_expires_at", renewWindowCutoff)
      .eq("is_active", true);

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

    if (!accounts || accounts.length === 0) {
      return new Response(
        JSON.stringify({ renewed: 0, failed: 0, needsReauth: 0 }),
        { status: 200, headers: { "Content-Type": "application/json" } },
      );
    }

    let renewed = 0;
    let failed = 0;
    let needsReauth = 0;

    // 2. Process each account
    for (const account of accounts) {
      const {
        id: accountId,
        workspace_id,
        graph_subscription_id,
        oauth_access_token,
      } = account;

      // New expiry: now + 3 days (Graph API max)
      const newExpiry = new Date(Date.now() + 3 * 24 * 60 * 60 * 1000)
        .toISOString();

      try {
        const response = await fetch(
          `https://graph.microsoft.com/v1.0/subscriptions/${graph_subscription_id}`,
          {
            method: "PATCH",
            headers: {
              Authorization: `Bearer ${oauth_access_token}`,
              "Content-Type": "application/json",
            },
            body: JSON.stringify({ expirationDateTime: newExpiry }),
          },
        );

        if (response.ok) {
          // 2c. Success — update expiry from response body
          const body = await response.json();
          const confirmedExpiry = body.expirationDateTime ?? newExpiry;

          await supabase
            .from("email_accounts")
            .update({ subscription_expires_at: confirmedExpiry })
            .eq("id", accountId);

          renewed++;
          console.log(
            `[renew-graph-subscriptions] renewed ${graph_subscription_id} for workspace ${workspace_id}`,
          );
        } else if (response.status === 401) {
          // 2d. Token expired — flag for reauth
          await supabase
            .from("email_accounts")
            .update({ needs_reauth: true })
            .eq("id", accountId);

          needsReauth++;
          console.warn(
            `[renew-graph-subscriptions] 401 for account ${accountId} (workspace ${workspace_id}) — marked needs_reauth`,
          );
        } else {
          // 2e. Other error — log and continue
          const errorText = await response.text().catch(() => "(no body)");
          console.error(
            `[renew-graph-subscriptions] ${response.status} for subscription ${graph_subscription_id}:`,
            errorText,
          );
          failed++;
        }
      } catch (err) {
        const msg = err instanceof Error ? err.message : String(err);
        console.error(
          `[renew-graph-subscriptions] network error for ${graph_subscription_id}:`,
          msg,
        );
        failed++;
      }
    }

    // 3. Return summary
    log.info("complete", { renewed, failed, needsReauth });
    return new Response(
      JSON.stringify({ renewed, failed, needsReauth }),
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
