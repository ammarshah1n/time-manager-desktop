# Spec: Microsoft Graph Integration

> Layer: Signal Ingestion
> Status: Implementation-ready
> Dependencies: MSAL.framework, GraphClient.swift (existing), Keychain, NetworkMonitor
> Swift target: 5.9+ / macOS 14+

---

## 1. Purpose

Microsoft Graph is Timed's primary external data source. It provides read-only access to the executive's Outlook email and calendar — the two richest signals for building a cognitive model. This spec defines the complete integration: OAuth lifecycle, API patterns, rate limit handling, delta sync, error recovery, and the hard read-only enforcement boundary.

---

## 2. OAuth 2.0 via MSAL on macOS

### 2.1 Flow: Authorization Code + PKCE

Timed is a native macOS public client. It uses MSAL (Microsoft Authentication Library) for macOS with the authorization code flow + PKCE (Proof Key for Code Exchange). No client secret is used in the native app — the client secret exists only in the Supabase Edge Functions for server-side webhook renewal.

**Existing implementation:** `GraphClient.swift` already has a working MSAL integration. This spec codifies the contract and adds missing lifecycle management.

### 2.2 Scopes

```
Mail.Read
Calendars.Read
offline_access
User.Read
```

**HARD RULE: NEVER request write scopes.** The current codebase (`AzureConfig.scopes`) includes `Mail.ReadWrite`, `Mail.Send`, and `Calendars.ReadWrite`. These MUST be removed before production. Timed's design principle is observation-only. Write scopes create both a liability and a trust violation.

| Scope | Purpose | Why needed |
|-------|---------|------------|
| `Mail.Read` | Read email messages, metadata, folders | Email triage, signal extraction |
| `Calendars.Read` | Read calendar events | Calendar sync, gap extraction, meeting analysis |
| `offline_access` | Obtain refresh tokens | Silent token renewal without re-auth |
| `User.Read` | Read user profile (display name, email) | Account display, workspace bootstrap |

### 2.3 Azure App Registration

**Existing:** Client ID `89e8f1c6-3cc4-47fb-83ae-f7e0528eb860`, Tenant `d20d9117-7f0f-45e9-87b3-2bb194f6be6b`.

**Redirect URI:** `msauth.com.timed.app://auth` (custom URL scheme registered in Info.plist).

**Platform:** Mobile and desktop applications (macOS native).

**Admin consent:** Not required for the read-only scopes above. Users consent at first sign-in.

---

## 3. Token Lifecycle

### 3.1 Token Types

| Token | Lifetime | Storage | Purpose |
|-------|----------|---------|---------|
| Access token | ~60-90 min (Microsoft default) | In-memory only | Bearer auth for Graph API calls |
| Refresh token | 90 days (rolling) | MSAL token cache (Keychain) | Obtain new access tokens silently |
| Account identifier | Permanent until sign-out | UserDefaults | Locate cached account for silent auth |

### 3.2 Keychain Storage

MSAL manages its own token cache, which defaults to macOS Keychain on native apps. Timed does not manually read or write tokens to Keychain.

**Keychain access group:** `com.timed.app` (matches the app's bundle ID).

**Security attributes:**
- `kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlock` — tokens available after device unlock, even if app launched at login.
- Keychain items are sandboxed to the app. No other process can read them.

### 3.3 Token Acquisition Flow

```
1. App launch
   └─ Read stored accountId from UserDefaults
   └─ Call MSALPublicClientApplication.acquireTokenSilent(account:)
      ├─ Success → return access token, proceed
      └─ Failure (interaction_required / token expired beyond refresh)
         └─ Call acquireToken(interactive:) → MSAL opens system browser
            ├─ User authenticates → return access token
            └─ User cancels → surface error, no retry
```

### 3.4 Silent Refresh

- Before every Graph API call, `GraphClient` checks token expiry.
- If the access token expires within 5 minutes, trigger a silent refresh proactively (not at the point of failure).
- If silent refresh fails with `MSALError.interactionRequired`, queue an interactive auth prompt. Do not block the current operation — return a typed error (`GraphError.authRequired`) so the caller can show UI.

### 3.5 Sign-Out

- Call `MSALPublicClientApplication.remove(account:)` to clear the MSAL token cache.
- Clear stored `accountId` from UserDefaults.
- Clear all locally cached Graph data (delta links, email cache, calendar cache).
- Do NOT delete Supabase data — that persists independently.

---

## 4. Rate Limit Handling

### 4.1 Microsoft Graph Rate Limits

Graph applies per-app and per-user throttling. Documented limits for Mail and Calendar:

| Resource | Limit | Window |
|----------|-------|--------|
| Mail (per mailbox) | 10,000 requests | 10 minutes |
| Calendar (per user) | 10,000 requests | 10 minutes |
| Application-wide | Varies by tenant | Rolling |

For a single-user desktop app, these limits are effectively unreachable under normal operation. The concern is burst scenarios (initial sync, recovery after extended offline).

### 4.2 HTTP 429 Handling

When Graph returns `429 Too Many Requests`:

1. Read the `Retry-After` header (value in seconds).
2. If `Retry-After` is present, wait exactly that duration before retrying.
3. If `Retry-After` is absent, use exponential backoff: `min(2^attempt * 1000ms, 60_000ms)` + random jitter (0-500ms).
4. Maximum retry attempts: 5. After 5 failures, surface `GraphError.rateLimited` to the caller.
5. Log every 429 via `TimedLogger.graph` at `.warning` level with the endpoint and retry-after value.

### 4.3 Backoff Implementation

```swift
struct RetryPolicy: Sendable {
    let maxAttempts: Int = 5
    let baseDelayMs: UInt64 = 1_000
    let maxDelayMs: UInt64 = 60_000
    let jitterRangeMs: UInt64 = 500

    func delay(for attempt: Int, retryAfter: Int?) -> UInt64 {
        if let retryAfter {
            return UInt64(retryAfter) * 1_000
        }
        let exponential = min(baseDelayMs * (1 << UInt64(attempt)), maxDelayMs)
        let jitter = UInt64.random(in: 0...jitterRangeMs)
        return exponential + jitter
    }
}
```

### 4.4 Request Budgeting

To stay well under limits during burst operations:

- **Initial mail sync (delta with no prior link):** Cap at 50 messages per page (`$top=50`), max 20 pages per sync cycle (1000 messages). If more exist, continue in the next cycle.
- **Calendar sync:** Fetch 30-day windows. One request per window.
- **Polling interval (when not using webhooks):** Minimum 60 seconds between delta queries. In practice, 5-minute intervals are sufficient for near-real-time.

---

## 5. Delta Query for Mail

### 5.1 How Delta Works

Delta query (`/me/mailFolders/inbox/messages/delta`) returns only messages that have changed since the last query. On the first call, it returns all messages (initial sync). Subsequent calls with the `deltaLink` return only new, modified, or deleted messages.

### 5.2 Implementation

```
First sync:
  GET /me/mailFolders/inbox/messages/delta?$top=50&$select=id,conversationId,subject,from,receivedDateTime,bodyPreview,toRecipients,ccRecipients,parentFolderId,isDraft

  Response includes @odata.nextLink (more pages) or @odata.deltaLink (caught up)
  
  ├─ If nextLink: fetch next page, accumulate messages
  └─ If deltaLink: store the deltaLink, process accumulated messages

Subsequent syncs:
  GET {stored deltaLink}
  
  Response includes changed messages since last deltaLink was issued
  - New messages: present with full fields
  - Modified messages: present with changed fields only
  - Deleted messages: present with @removed annotation
```

### 5.3 Delta Link Persistence

- Store the latest `deltaLink` in DataStore: `func saveDeltaLink(_ link: String, for resource: String) throws`
- Key: `delta_mail_inbox` (or `delta_calendar` for calendar)
- On sign-out, delete all delta links.
- If a delta link returns `410 Gone` (expired, typically after 30 days), discard it and perform a full initial sync.

### 5.4 Fields Selected

Only request the fields Timed actually uses. This reduces payload size and improves performance.

**Mail:**
```
$select=id,conversationId,subject,from,receivedDateTime,bodyPreview,toRecipients,ccRecipients,parentFolderId,isDraft
```

**Never request:** `body` (full HTML body). The `bodyPreview` (255 chars) is sufficient for classification. Full body fetch is a separate, explicit operation if the user opens an email detail view (future feature, not in current scope).

---

## 6. Delta Query for Calendar

### 6.1 Calendar View vs Delta

Calendar supports delta queries on the events collection:
```
GET /me/calendarView/delta?startDateTime={start}&endDateTime={end}
```

For Timed's use case (scheduling around existing events), use `calendarView` with explicit date ranges rather than open-ended delta queries.

### 6.2 Implementation

```
Daily sync (runs at app launch and every 30 minutes):
  GET /me/calendarView?startDateTime={today_start_utc}&endDateTime={today_end_utc + 7d}&$select=id,subject,start,end,isAllDay,isCancelled,location&$top=100

  - Fetch today + 7 days forward (planning window)
  - Store results in DataStore (calendarBlocks)
  - Diff against previous fetch to detect additions/cancellations/reschedules
  - Emit calendar signals for changes (separate signal spec)
```

### 6.3 Calendar Change Detection

Compare fetched events against locally stored `CalendarBlock` entries:

| Change | Detection | Signal emitted |
|--------|-----------|----------------|
| New event | `id` not in local store | `calendar.eventAdded` |
| Cancelled event | `isCancelled == true` or `id` missing from new fetch but present locally | `calendar.eventCancelled` |
| Rescheduled event | Same `id`, different `start`/`end` | `calendar.eventRescheduled` |
| No change | All fields match | No signal |

---

## 7. Webhook vs Polling for Desktop App

### 7.1 Analysis

| Approach | Pros | Cons |
|----------|------|------|
| **Webhooks** | Near-instant notifications, no wasted requests | Requires a publicly reachable HTTPS endpoint. Desktop app has no fixed URL. Supabase Edge Function can receive, but adds a push notification relay hop. Subscriptions expire (max 3 days for mail, need renewal cron). |
| **Polling** | Simple, reliable, works offline then catches up. No infra dependency beyond Graph API. | Latency (minutes, not seconds). Wastes some requests when nothing changed. |
| **Hybrid** | Webhook for real-time signal when available, polling as fallback | Maximum complexity. Two code paths. |

### 7.2 Decision: Polling-First with Optional Webhook

**Primary:** Poll via delta queries every 5 minutes while the app is in the foreground. Every 15 minutes when in the background (menu bar only).

**Rationale:** Timed is a cognitive layer, not a real-time chat app. 5-minute latency on email arrival is acceptable — the executive is not watching for emails in Timed, they use Outlook for that. Timed processes email for intelligence extraction, which is not time-sensitive to the minute.

**Future:** The webhook infrastructure already exists (Edge Function `graph-webhook` is deployed, `renew-graph-subscriptions` cron is deployed). If sub-minute latency becomes a requirement, activate webhooks as an enhancement. The polling path remains as fallback regardless.

### 7.3 Polling Schedule

| App state | Mail poll interval | Calendar poll interval |
|-----------|-------------------|----------------------|
| Foreground (any pane active) | 5 min | 30 min |
| Background (menu bar only) | 15 min | 60 min |
| Focus timer active | 30 min (reduce noise) | 60 min |
| App just launched | Immediate | Immediate |
| Network restored after offline | Immediate | Immediate |

Polling is coordinated by `EmailSyncService` (existing) and `CalendarSyncService` (existing). Both use `Timer.publish` with Combine and respect `NetworkMonitor.isConnected`.

---

## 8. Read-Only Enforcement

### 8.1 Scope-Level Enforcement

The Azure App Registration MUST only have `Mail.Read`, `Calendars.Read`, `offline_access`, and `User.Read` in its API permissions. Remove `Mail.ReadWrite`, `Mail.Send`, `Calendars.ReadWrite` from both the app registration and the `AzureConfig.scopes` array.

**Action required:** Update `AzureConfig.scopes` in `GraphClient.swift`:
```swift
// BEFORE (current, WRONG):
static let scopes = ["Mail.Read", "Mail.ReadWrite", "Mail.Send",
                     "Calendars.Read", "Calendars.ReadWrite", "offline_access", "User.Read"]

// AFTER (correct):
static let scopes = ["Mail.Read", "Calendars.Read", "offline_access", "User.Read"]
```

### 8.2 Code-Level Enforcement

- `GraphClientDependency` must NOT expose any methods that perform POST, PATCH, PUT, or DELETE on mail or calendar resources.
- The existing `moveMessage` and `createFolder` methods violate this. They should be removed or gated behind a `#if DEBUG` flag for development only.
- Code review rule: any PR that adds a Graph API call must be verified as a GET request against a read-only resource.

### 8.3 Methods to Remove or Gate

| Method | Current state | Action |
|--------|--------------|--------|
| `moveMessage` | Exists, throws NotImplementedError | Remove entirely |
| `createFolder` | Exists, throws NotImplementedError | Remove entirely |
| `registerWebhook` | Exists, throws NotImplementedError | Keep — webhook registration is a POST but creates a subscription, not modifying user data |
| `renewWebhook` | Exists, throws NotImplementedError | Keep — same rationale |

---

## 9. Error Handling

### 9.1 Error Taxonomy

```swift
enum GraphError: Error, Sendable {
    // Auth
    case authRequired                    // Token expired, interactive auth needed
    case authCancelled                   // User dismissed auth prompt
    case authFailed(underlying: Error)   // MSAL error

    // Network
    case networkUnavailable              // No connection (from NetworkMonitor)
    case timeout                         // Request exceeded 30s timeout

    // Rate limits
    case rateLimited(retryAfterSeconds: Int?)  // 429, with optional Retry-After

    // API errors
    case badRequest(message: String)     // 400
    case forbidden(message: String)      // 403 — scope insufficient
    case notFound                        // 404 — resource deleted
    case gone                            // 410 — delta link expired
    case serverError(statusCode: Int)    // 500-599

    // Data
    case decodingFailed(underlying: Error)  // JSON parse failure
    case unexpectedResponse              // Response shape not matching expectation
}
```

### 9.2 Error Recovery Matrix

| Error | Recovery action | User-visible? |
|-------|----------------|---------------|
| `authRequired` | Queue interactive auth prompt. Pause sync until resolved. | Yes — show "Sign in to Outlook" banner |
| `authCancelled` | No retry. User chose not to authenticate. | No |
| `networkUnavailable` | Pause all Graph calls. Resume when `NetworkMonitor` reports connectivity. | Yes — show offline indicator |
| `rateLimited` | Exponential backoff per Section 4.2 | No (unless persists > 5 min, then show warning) |
| `gone` (410) | Discard delta link, full re-sync | No |
| `forbidden` (403) | Log scope mismatch. Prompt re-auth with correct scopes. | Yes — "Timed needs permission to read your email" |
| `serverError` | Retry 3 times with 5s delay. If persistent, pause sync for 15 min. | No (unless persistent > 30 min) |
| `decodingFailed` | Log full response body. Skip the malformed item. Continue processing. | No |

### 9.3 Logging

All Graph API calls are logged via `TimedLogger.graph`:

| Level | What |
|-------|------|
| `.debug` | Every request: method, URL (sanitized — no tokens), response status |
| `.info` | Sync cycle start/end, messages fetched count, delta link updated |
| `.warning` | 429 received, retry scheduled. Auth token refresh triggered. |
| `.error` | Auth failure, network failure, decode failure, unexpected response |

---

## 10. Request Construction

### 10.1 Base Headers

```swift
func graphRequest(endpoint: String, accessToken: String) -> URLRequest {
    var request = URLRequest(url: URL(string: "https://graph.microsoft.com/v1.0\(endpoint)")!)
    request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.setValue("Timed/1.0", forHTTPHeaderField: "User-Agent")
    request.timeoutInterval = 30
    return request
}
```

### 10.2 Prefer Headers for Delta

For delta queries, include the `Prefer` header to control page size:
```
Prefer: odata.maxpagesize=50
```

### 10.3 Pagination

All paginated responses follow the OData pattern:
- `@odata.nextLink` → more pages available. Fetch the next page.
- `@odata.deltaLink` → caught up. Store for next sync cycle.
- Never follow more than 20 `nextLink` pages in a single sync cycle (circuit breaker).

---

## 11. Acceptance Criteria

1. **Scopes are read-only** — `AzureConfig.scopes` contains only `Mail.Read`, `Calendars.Read`, `offline_access`, `User.Read`. No write scopes. Verified by unit test that asserts scope array contents.
2. **Silent auth works** — After initial interactive sign-in, subsequent app launches acquire tokens silently without user interaction.
3. **Token refresh works** — Simulate token expiry. Next Graph call triggers silent refresh. If refresh fails, interactive prompt appears. No crash, no data loss.
4. **Delta sync resumes** — Kill the app during a multi-page delta sync. On relaunch, sync resumes from the last stored delta link without data loss or duplication.
5. **410 recovery** — Expire a delta link (or mock a 410 response). System performs a full re-sync transparently.
6. **429 handling** — Mock a 429 response with `Retry-After: 10`. System waits exactly 10 seconds before retrying. After 5 consecutive 429s, `GraphError.rateLimited` is surfaced.
7. **Offline resilience** — Disconnect network. App continues functioning with cached data. Reconnect. Delta sync fires immediately and catches up.
8. **No write operations in production** — `moveMessage` and `createFolder` methods are removed or compile-gated. No Graph API call in the production binary performs POST/PATCH/PUT/DELETE on user mail or calendar resources.
9. **Calendar sync detects changes** — Add an event in Outlook. Within one poll cycle (5 min foreground), Timed reflects the new event in `calendarBlocks`.
10. **Logging coverage** — Every Graph API call produces at least one log entry. Errors produce entries at `.warning` or `.error` level with actionable context.
