import { logger, schedules } from "@trigger.dev/sdk";

import {
  getGraphAppToken,
  invalidateGraphAppToken,
} from "../lib/graph-app-auth.js";
import { getSupabaseServiceRole } from "../lib/supabase.js";

/**
 * Microsoft Graph change-notification subscription renewal.
 *
 * Runs every 2 hours. For every row in `graph_subscriptions` that expires in
 * the next 6 hours, PATCH the subscription with an expirationDateTime of
 * now + 3 days. Graph caps most Mail/Calendar subscriptions at ~3 days; the
 * exact cap varies by resource so we let the response tell us the real
 * expiry and store that back.
 *
 * Error handling:
 *   - 404 -> the subscription was deleted upstream; remove the local row so
 *            we don't keep re-trying it forever.
 *   - 401 -> invalidate the app token cache and retry the PATCH once.
 *
 * Schedule: cron `0 *\/2 * * *`, id `graph-webhook-renewal`.
 */

const RENEWAL_WINDOW_MS = 6 * 60 * 60 * 1000; // 6 hours
const NEW_EXPIRY_MS = 3 * 24 * 60 * 60 * 1000; // 3 days

interface SubscriptionRow {
  id: string;
  subscription_id: string | null;
  resource: string;
  expires_at: string;
}

interface PatchResponse {
  id?: string;
  expirationDateTime?: string;
  resource?: string;
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

async function patchSubscription(
  subscriptionId: string,
  newExpiry: string,
  token: string,
): Promise<PatchResponse> {
  const url = `https://graph.microsoft.com/v1.0/subscriptions/${encodeURIComponent(
    subscriptionId,
  )}`;
  const response = await fetch(url, {
    method: "PATCH",
    headers: {
      Authorization: `Bearer ${token}`,
      "Content-Type": "application/json",
      Accept: "application/json",
    },
    body: JSON.stringify({ expirationDateTime: newExpiry }),
  });

  if (response.status === 401) {
    throw new GraphAuthError(
      `graph-webhook-renewal: 401 for subscription ${subscriptionId}`,
    );
  }
  if (response.status === 404) {
    throw new SubscriptionNotFoundError(
      `graph-webhook-renewal: subscription ${subscriptionId} not found (404)`,
    );
  }
  if (!response.ok) {
    const text = await response.text().catch(() => "<unreadable>");
    throw new Error(
      `graph-webhook-renewal: Graph ${response.status} ${response.statusText}: ${text}`,
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
      invalidateGraphAppToken();
      token = await getGraphAppToken();
      return await patchSubscription(subscriptionId, newExpiry, token);
    }
    throw err;
  }
}

async function loadExpiringSubscriptions(): Promise<SubscriptionRow[]> {
  const sb = getSupabaseServiceRole();
  const threshold = new Date(Date.now() + RENEWAL_WINDOW_MS).toISOString();
  const { data, error } = await sb
    .from("graph_subscriptions")
    .select("id, subscription_id, resource, expires_at")
    .lt("expires_at", threshold);
  if (error) {
    throw new Error(
      `graph-webhook-renewal: subscriptions query failed: ${error.message}`,
    );
  }
  return (data ?? []) as SubscriptionRow[];
}

async function updateExpiryLocal(
  rowId: string,
  newExpiry: string,
): Promise<void> {
  const sb = getSupabaseServiceRole();
  const nowIso = new Date().toISOString();
  const { error } = await sb
    .from("graph_subscriptions")
    .update({ expires_at: newExpiry, updated_at: nowIso })
    .eq("id", rowId);
  if (error) {
    throw new Error(
      `graph-webhook-renewal: expires_at update failed for ${rowId}: ${error.message}`,
    );
  }
}

async function deleteLocal(rowId: string): Promise<void> {
  const sb = getSupabaseServiceRole();
  const { error } = await sb
    .from("graph_subscriptions")
    .delete()
    .eq("id", rowId);
  if (error) {
    throw new Error(
      `graph-webhook-renewal: row delete failed for ${rowId}: ${error.message}`,
    );
  }
}

export const graphWebhookRenewal = schedules.task({
  id: "graph-webhook-renewal",
  cron: "0 */2 * * *",
  maxDuration: 120,
  run: async () => {
    const expiring = await loadExpiringSubscriptions();
    if (expiring.length === 0) {
      logger.info("graph-webhook-renewal: no subscriptions need renewal");
      return { renewed: 0, deleted: 0 };
    }

    let renewed = 0;
    let deleted = 0;

    for (const row of expiring) {
      if (!row.subscription_id) {
        logger.warn(
          "graph-webhook-renewal: row has null subscription_id, skipping",
          { rowId: row.id },
        );
        continue;
      }
      const requestedExpiry = new Date(Date.now() + NEW_EXPIRY_MS).toISOString();

      try {
        const patched = await patchSubscriptionWithRetry(
          row.subscription_id,
          requestedExpiry,
        );
        const effectiveExpiry =
          patched.expirationDateTime ?? requestedExpiry;
        await updateExpiryLocal(row.id, effectiveExpiry);
        renewed += 1;
        logger.info("graph-webhook-renewal: renewed subscription", {
          rowId: row.id,
          subscriptionId: row.subscription_id,
          resource: row.resource,
          effectiveExpiry,
        });
      } catch (err) {
        if (err instanceof SubscriptionNotFoundError) {
          await deleteLocal(row.id);
          deleted += 1;
          logger.warn(
            "graph-webhook-renewal: subscription gone upstream, deleted local row",
            {
              rowId: row.id,
              subscriptionId: row.subscription_id,
            },
          );
          continue;
        }
        const message =
          err instanceof Error ? err.message : JSON.stringify(err);
        logger.error("graph-webhook-renewal: subscription renewal failed", {
          rowId: row.id,
          subscriptionId: row.subscription_id,
          error: message,
        });
      }
    }

    return { renewed, deleted };
  },
});
