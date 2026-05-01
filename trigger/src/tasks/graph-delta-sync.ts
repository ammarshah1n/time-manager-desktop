import { logger, schedules } from "@trigger.dev/sdk";

import {
  getGraphAppToken,
  invalidateGraphAppToken,
} from "../lib/graph-app-auth.js";
import { getSupabaseServiceRole } from "../lib/supabase.js";

/**
 * Server-side Microsoft Graph email delta sync.
 *
 * Runs every minute. For each executive whose `email_sync_driver = 'server'`
 * the task walks /users/{email}/messages/delta, upserts new messages into
 * `email_messages`, advances the @odata.deltaLink stored in `email_sync_state`,
 * and caps each run at MAX_MESSAGES_PER_EXEC so a slow executive can't starve
 * the rest of the tenant.
 *
 * Error handling:
 *   - 410 Gone -> delta token expired. Reset to null, re-enter the loop with a
 *                 bounded $filter on receivedDateTime >= now - 30 days to avoid
 *                 re-paging years of mail on the next schedule tick.
 *   - 401     -> invalidate the app token cache, refresh once, retry once.
 *
 * Schedule: cron `*\/1 * * * *`, id `graph-delta-sync`.
 */

const MAX_MESSAGES_PER_EXEC = 500;

interface ExecutiveRow {
  id: string;
  email: string;
}

interface EmailAccountRow {
  id: string;
  workspace_id: string;
  email_address: string;
}

interface EmailSyncStateRow {
  delta_link: string | null;
}

interface GraphRecipient {
  emailAddress?: {
    address?: string;
    name?: string;
  };
}

interface GraphMessage {
  id?: string;
  conversationId?: string | null;
  subject?: string | null;
  bodyPreview?: string | null;
  receivedDateTime?: string | null;
  from?: GraphRecipient | null;
  toRecipients?: GraphRecipient[] | null;
  ccRecipients?: GraphRecipient[] | null;
  "@removed"?: unknown;
}

interface GraphDeltaResponse {
  value?: GraphMessage[];
  "@odata.nextLink"?: string;
  "@odata.deltaLink"?: string;
}

interface EmailMessageUpsert {
  workspace_id: string;
  email_account_id: string;
  graph_message_id: string;
  graph_thread_id: string | null;
  from_address: string;
  from_name: string | null;
  to_addresses: string[];
  cc_addresses: string[];
  subject: string | null;
  snippet: string | null;
  received_at: string;
}

class GraphAuthError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "GraphAuthError";
  }
}

class GraphDeltaExpiredError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "GraphDeltaExpiredError";
  }
}

function initialDeltaUrl(email: string): string {
  return `https://graph.microsoft.com/v1.0/users/${encodeURIComponent(
    email,
  )}/messages/delta`;
}

function boundedInitialDeltaUrl(email: string): string {
  // 410 recovery: clamp the re-sync to the last 30 days so a one-minute
  // schedule doesn't blow through decades of inbox history in one tick.
  const thirtyDaysAgo = new Date(
    Date.now() - 30 * 24 * 60 * 60 * 1000,
  ).toISOString();
  const base = initialDeltaUrl(email);
  return `${base}?$filter=receivedDateTime%20ge%20${encodeURIComponent(
    thirtyDaysAgo,
  )}`;
}

async function graphGet(
  url: string,
  token: string,
): Promise<GraphDeltaResponse> {
  const response = await fetch(url, {
    method: "GET",
    headers: {
      Authorization: `Bearer ${token}`,
      Accept: "application/json",
    },
  });

  if (response.status === 401) {
    throw new GraphAuthError(
      `graph-delta-sync: Graph returned 401 for ${url}`,
    );
  }
  if (response.status === 410) {
    throw new GraphDeltaExpiredError(
      `graph-delta-sync: delta token expired (410) for ${url}`,
    );
  }
  if (!response.ok) {
    const text = await response.text().catch(() => "<unreadable>");
    throw new Error(
      `graph-delta-sync: Graph ${response.status} ${response.statusText}: ${text}`,
    );
  }

  return (await response.json()) as GraphDeltaResponse;
}

async function graphGetWithRetry(
  url: string,
): Promise<GraphDeltaResponse> {
  let token = await getGraphAppToken();
  try {
    return await graphGet(url, token);
  } catch (err) {
    if (err instanceof GraphAuthError) {
      invalidateGraphAppToken();
      token = await getGraphAppToken();
      return await graphGet(url, token);
    }
    throw err;
  }
}

function addressOf(recipient: GraphRecipient | null | undefined): string {
  return recipient?.emailAddress?.address ?? "";
}

function mapMessage(
  message: GraphMessage,
  workspaceId: string,
  emailAccountId: string,
): EmailMessageUpsert | null {
  if (!message.id) return null;
  if (message["@removed"] !== undefined) {
    // Deletions signalled by the delta feed — we don't remove rows here
    // (Wave 2 keeps the audit trail), so skip.
    return null;
  }

  const fromAddr = addressOf(message.from);
  const fromName = message.from?.emailAddress?.name ?? null;
  const toAddresses = (message.toRecipients ?? [])
    .map(addressOf)
    .filter((addr) => addr.length > 0);
  const ccAddresses = (message.ccRecipients ?? [])
    .map(addressOf)
    .filter((addr) => addr.length > 0);

  const receivedAt = message.receivedDateTime ?? new Date().toISOString();

  return {
    workspace_id: workspaceId,
    email_account_id: emailAccountId,
    graph_message_id: message.id,
    graph_thread_id: message.conversationId ?? null,
    from_address: fromAddr.length > 0 ? fromAddr : "unknown",
    from_name: fromName,
    to_addresses: toAddresses,
    cc_addresses: ccAddresses,
    subject: message.subject ?? null,
    snippet: message.bodyPreview ?? null,
    received_at: receivedAt,
  };
}

async function loadExecutives(): Promise<ExecutiveRow[]> {
  const sb = getSupabaseServiceRole();
  const { data, error } = await sb
    .from("executives")
    .select("id, email")
    .eq("email_sync_driver", "server");
  if (error) {
    throw new Error(
      `graph-delta-sync: executives query failed: ${error.message}`,
    );
  }
  return (data ?? []) as ExecutiveRow[];
}

async function loadSyncState(execId: string): Promise<string | null> {
  const sb = getSupabaseServiceRole();
  const { data, error } = await sb
    .from("email_sync_state")
    .select("delta_link")
    .eq("exec_id", execId)
    .maybeSingle<EmailSyncStateRow>();
  if (error) {
    throw new Error(
      `graph-delta-sync: email_sync_state read failed for ${execId}: ${error.message}`,
    );
  }
  return data?.delta_link ?? null;
}

async function persistSyncState(
  execId: string,
  deltaLink: string | null,
): Promise<void> {
  const sb = getSupabaseServiceRole();
  const nowIso = new Date().toISOString();
  const { error } = await sb.from("email_sync_state").upsert(
    {
      exec_id: execId,
      delta_link: deltaLink,
      last_synced_at: nowIso,
      updated_at: nowIso,
    },
    { onConflict: "exec_id" },
  );
  if (error) {
    throw new Error(
      `graph-delta-sync: email_sync_state upsert failed for ${execId}: ${error.message}`,
    );
  }
}

async function resolveEmailAccount(
  exec: ExecutiveRow,
): Promise<EmailAccountRow | null> {
  const sb = getSupabaseServiceRole();
  const { data, error } = await sb
    .from("email_accounts")
    .select("id, workspace_id, email_address")
    .eq("id", exec.id)
    .eq("provider", "outlook")
    .eq("sync_enabled", true)
    .limit(1)
    .maybeSingle<EmailAccountRow>();
  if (error) {
    throw new Error(
      `graph-delta-sync: email_accounts lookup failed for ${exec.id}: ${error.message}`,
    );
  }
  return data ?? null;
}

async function upsertMessages(rows: EmailMessageUpsert[]): Promise<void> {
  if (rows.length === 0) return;
  const sb = getSupabaseServiceRole();
  const { error } = await sb.from("email_messages").upsert(rows, {
    onConflict: "email_account_id,graph_message_id",
    ignoreDuplicates: false,
  });
  if (error) {
    throw new Error(
      `graph-delta-sync: email_messages upsert failed: ${error.message}`,
    );
  }
}

interface SyncResult {
  processed: number;
  nextDeltaLink: string | null;
  hitCap: boolean;
}

async function runSyncPass(
  execEmail: string,
  workspaceId: string,
  emailAccountId: string,
  startUrl: string,
): Promise<SyncResult> {
  let processed = 0;
  let cursor: string | undefined = startUrl;
  let finalDeltaLink: string | null = null;
  let hitCap = false;

  while (cursor !== undefined) {
    const page: GraphDeltaResponse = await graphGetWithRetry(cursor);
    const rows: EmailMessageUpsert[] = [];
    for (const message of page.value ?? []) {
      const mapped = mapMessage(message, workspaceId, emailAccountId);
      if (mapped) rows.push(mapped);
    }
    if (rows.length > 0) {
      await upsertMessages(rows);
      processed += rows.length;
    }

    if (processed >= MAX_MESSAGES_PER_EXEC) {
      hitCap = true;
      // We must have a cursor to resume on the next tick. If we hit the cap
      // but only have a nextLink, persist it as the deltaLink so the next
      // run picks up from the same page — nextLink is delta-compatible.
      if (page["@odata.deltaLink"]) {
        finalDeltaLink = page["@odata.deltaLink"];
      } else if (page["@odata.nextLink"]) {
        finalDeltaLink = page["@odata.nextLink"];
      }
      break;
    }

    if (page["@odata.nextLink"]) {
      cursor = page["@odata.nextLink"];
    } else {
      cursor = undefined;
      if (page["@odata.deltaLink"]) {
        finalDeltaLink = page["@odata.deltaLink"];
      }
    }
  }

  logger.info("graph-delta-sync: pass complete", {
    execEmail,
    processed,
    hitCap,
    hasDeltaLink: finalDeltaLink !== null,
  });

  return { processed, nextDeltaLink: finalDeltaLink, hitCap };
}

export const graphDeltaSync = schedules.task({
  id: "graph-delta-sync",
  cron: "*/1 * * * *",
  maxDuration: 60,
  run: async () => {
    const executives = await loadExecutives();
    if (executives.length === 0) {
      logger.info("graph-delta-sync: no server-driven executives");
      return { executives_processed: 0 };
    }

    let totalProcessed = 0;

    for (const exec of executives) {
      try {
        const account = await resolveEmailAccount(exec);
        if (!account) {
          logger.warn(
            "graph-delta-sync: no email_accounts row for exec, skipping",
            {
              execId: exec.id,
              execEmail: exec.email,
            },
          );
          continue;
        }

        const storedDelta = await loadSyncState(exec.id);
        const syncEmail = account.email_address || exec.email;
        const startUrl = storedDelta ?? initialDeltaUrl(syncEmail);

        let result: SyncResult;
        try {
          result = await runSyncPass(
            syncEmail,
            account.workspace_id,
            account.id,
            startUrl,
          );
        } catch (err) {
          if (err instanceof GraphDeltaExpiredError) {
            logger.warn(
              "graph-delta-sync: delta expired, resetting to bounded 30-day window",
              { execId: exec.id },
            );
            await persistSyncState(exec.id, null);
            const recoveryUrl = boundedInitialDeltaUrl(syncEmail);
            result = await runSyncPass(
              syncEmail,
              account.workspace_id,
              account.id,
              recoveryUrl,
            );
          } else {
            throw err;
          }
        }

        await persistSyncState(exec.id, result.nextDeltaLink);
        totalProcessed += result.processed;
      } catch (err) {
        const message =
          err instanceof Error ? err.message : JSON.stringify(err);
        logger.error("graph-delta-sync: exec failed", {
          execId: exec.id,
          execEmail: exec.email,
          error: message,
        });
      }
    }

    return {
      executives_processed: executives.length,
      messages_upserted: totalProcessed,
    };
  },
});
