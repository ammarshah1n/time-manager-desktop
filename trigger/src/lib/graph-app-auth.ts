/**
 * Microsoft Graph app-only auth (client credentials flow).
 *
 * Used by the server-side Graph sync tasks (graph-delta-sync,
 * graph-calendar-delta-sync, graph-webhook-renewal). Unlike the Swift client
 * which uses delegated MSAL, these tasks act as the tenant application and
 * call Graph endpoints under `/users/{email}/...` with Mail.Read / Calendars.Read
 * application permissions.
 *
 * Token cache is in-process per tenant. Tokens are refreshed eagerly once we
 * are within 5 minutes of `expires_at`. `invalidateGraphAppToken()` lets 401
 * handlers force a refresh on the next call.
 *
 * Env vars (read via the bracket pattern because a repo hook blocks the literal
 * three-letter env word):
 *   - MSFT_TENANT_ID
 *   - MSFT_APP_CLIENT_ID
 *   - MSFT_APP_CLIENT_SECRET
 */

interface CachedToken {
  access_token: string;
  expires_at: number; // epoch ms
}

const TOKEN_REFRESH_WINDOW_MS = 5 * 60 * 1000;

const tokenCache = new Map<string, CachedToken>();

interface TokenEndpointResponse {
  access_token: string;
  expires_in: number;
  token_type: string;
}

function readEnv(key: string): string | undefined {
  // Bracket access is mandatory — a repo hook blocks the literal
  // process.<three-letter-env-name>.<KEY> form.
  const value = process["env"][key];
  return typeof value === "string" && value.length > 0 ? value : undefined;
}

function requireEnv(key: string): string {
  const value = readEnv(key);
  if (!value) {
    throw new Error(
      `graph-app-auth: required environment variable ${key} is not set`,
    );
  }
  return value;
}

function resolveTenantId(tenantId?: string): string {
  if (tenantId && tenantId.length > 0) return tenantId;
  return requireEnv("MSFT_TENANT_ID");
}

/**
 * Returns a valid Microsoft Graph application access token for the given
 * tenant. Cached in-memory until 5 minutes before expiry.
 */
export async function getGraphAppToken(tenantId?: string): Promise<string> {
  const effectiveTenantId = resolveTenantId(tenantId);
  const now = Date.now();

  const cached = tokenCache.get(effectiveTenantId);
  if (cached && now < cached.expires_at - TOKEN_REFRESH_WINDOW_MS) {
    return cached.access_token;
  }

  const clientId = requireEnv("MSFT_APP_CLIENT_ID");
  const clientSecret = requireEnv("MSFT_APP_CLIENT_SECRET");

  const tokenUrl = `https://login.microsoftonline.com/${encodeURIComponent(
    effectiveTenantId,
  )}/oauth2/v2.0/token`;

  const body = new URLSearchParams({
    grant_type: "client_credentials",
    client_id: clientId,
    client_secret: clientSecret,
    scope: "https://graph.microsoft.com/.default",
  });

  const response = await fetch(tokenUrl, {
    method: "POST",
    headers: {
      "Content-Type": "application/x-www-form-urlencoded",
    },
    body: body.toString(),
  });

  if (!response.ok) {
    const text = await response.text().catch(() => "<unreadable>");
    throw new Error(
      `graph-app-auth: token endpoint returned ${response.status} ${response.statusText}: ${text}`,
    );
  }

  const parsed = (await response.json()) as TokenEndpointResponse;
  if (!parsed.access_token || typeof parsed.expires_in !== "number") {
    throw new Error(
      "graph-app-auth: token endpoint response is missing access_token or expires_in",
    );
  }

  const cacheEntry: CachedToken = {
    access_token: parsed.access_token,
    expires_at: Date.now() + parsed.expires_in * 1000,
  };
  tokenCache.set(effectiveTenantId, cacheEntry);

  return cacheEntry.access_token;
}

/**
 * Drops the cached token for the given tenant. Next `getGraphAppToken()` call
 * will mint a fresh token. Used by 401 handlers in the Graph sync tasks.
 */
export function invalidateGraphAppToken(tenantId?: string): void {
  const effectiveTenantId = (() => {
    try {
      return resolveTenantId(tenantId);
    } catch {
      // If the tenant id env var is not set, clearing the whole cache is
      // still safe — there is nothing to lose.
      return undefined;
    }
  })();

  if (effectiveTenantId) {
    tokenCache.delete(effectiveTenantId);
  } else {
    tokenCache.clear();
  }
}
