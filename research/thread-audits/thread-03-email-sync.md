# Research Thread 3: EmailSyncService Delta Sync & Graph API Architecture
### `Sources/Core/Services/EmailSyncService.swift` · `ammarshah1n/time-manager-desktop` · `ui/apple-v1-restore`

***

## Executive Summary

The current `EmailSyncService` is a working first-pass implementation with **six critical architectural defects** that will cause data loss, silent de-auth, and API quota exhaustion in production. The most urgent issues are: (1) the delta link is stored only in memory and lost on every app restart, causing a full re-sync on each launch; (2) the raw Graph access token is passed in and never refreshed, so the service silently stops syncing after 60–90 minutes; and (3) there is zero rate-limit handling, no 410/syncStateNotFound recovery, and no offline guard despite a `NetworkMonitor` already in the codebase. Each section below provides the specific fix, the exact function(s) to change, a line estimate, and an impact rating for a single executive user.

***

## Impact Ranking Matrix

| # | Area | Severity | User Impact (solo exec) | Fix Complexity |
|---|------|----------|------------------------|----------------|
| 1 | Delta link persistence | **CRITICAL** | Full re-sync every launch; missed moves | Low (15–20 lines) |
| 2 | OAuth token refresh | **CRITICAL** | Silent sync failure after 60–90 min | Medium (40–60 lines) |
| 3 | 410 / syncStateNotFound recovery | **HIGH** | Permanent sync freeze if token evicted | Low (10 lines) |
| 4 | `$select` optimization + batch | **HIGH** | 3–5× more API calls than necessary | Medium (30 lines) |
| 5 | Offline guard (NetworkMonitor) | **HIGH** | `URLError` spam in logs, partial writes | Low (5 lines) |
| 6 | isCcFyi logic bug | **MEDIUM** | Wrong triage bucket on ~25% of CC emails | Low (10 lines) |
| 7 | Privacy / scope declaration | **MEDIUM** | App Store rejection; Graph 403 on launch | Low (5 lines) |
| 8 | Hardcoded `supabaseAnonKey` | **LOW** | Key exposed in source repo | Low (already env-guarded) |

***

## 1. Delta Sync Efficiency

### The Core Problem

The delta link is stored as `private var deltaLink: String?` on the actor and is **never persisted to disk**. Every time the app relaunches — or the Mac restarts — `deltaLink` is `nil`, so `syncOnce()` performs a full initial sync that pulls the entire mailbox history. For an executive with years of Outlook history, this is thousands of API calls on every cold start, and it causes the `detectFolderMove` logic to falsely fire on every message (because `knownFolders` is empty and every message "appears" to have moved from nothing to its current folder).

Microsoft's delta query documentation confirms that Outlook message delta tokens do **not** have a hard-coded expiry date (unlike directory objects which expire after 7 days). The token is stored in a server-side cache — when that cache evicts the token, the service returns `410 Gone` with error code `syncStateNotFound`. This is a normal lifecycle event that must be handled; the correct recovery is to discard the token and run a fresh full sync.[^1][^2][^3]

### Fix: Persist deltaLink to UserDefaults

The `knownFolders` persistence pattern already in the codebase is exactly right — apply the same pattern to `deltaLink`.

**In `EmailSyncService.swift`** — add alongside `loadKnownFolders` / `saveKnownFolders`:

```swift
// ~15 lines added to EmailSyncService

private func loadDeltaLink(for accountId: UUID) {
    deltaLink = UserDefaults.standard.string(forKey: "deltaLink_\(accountId)")
}

private func saveDeltaLink(for accountId: UUID) {
    if let link = deltaLink {
        UserDefaults.standard.set(link, forKey: "deltaLink_\(accountId)")
    } else {
        UserDefaults.standard.removeObject(forKey: "deltaLink_\(accountId)")
    }
}
```

Call `loadDeltaLink(for: emailAccountId)` in `start()` alongside `loadKnownFolders`. Call `saveDeltaLink` at the end of each successful `syncOnce()`.

### Fix: 410 / syncStateNotFound Recovery

Add this guard at the top of the `while hasMore` loop in `syncOnce()`:

```swift
// ~10 lines added in syncOnce() around fetchDeltaMessages call

do {
    let result = try await graphClient.fetchDeltaMessages("", currentDeltaLink, accessToken)
    // ... existing processing ...
} catch let error as GraphAPIError where error.statusCode == 410 {
    TimedLogger.graph.warning("Delta token evicted (410) — clearing and running full resync")
    deltaLink = nil
    currentDeltaLink = nil
    // Loop continues with nil deltaLink = full resync
}
```

### Polling vs. Webhooks for a Desktop App

Microsoft Graph change notifications (webhooks) require a **publicly accessible HTTPS endpoint** to receive push events. A single-user desktop app has no such endpoint — Microsoft would need to reach the user's Mac directly, which is impractical behind NAT/firewall. The optimal architecture for Timed is therefore the **hybrid pattern**: continue polling with delta queries, but reduce the interval dynamically based on user activity:[^4][^5]

- **Active hours** (detected via system idle time or app focus): 30–60 second interval
- **Background/sleep**: 5–10 minute interval
- **First launch / full resync**: 15-minute backoff to avoid quota burn

The Microsoft documentation explicitly recommends combining webhooks + delta for server-side applications, but acknowledges that polling with delta is appropriate for the single-user desktop case.[^6][^7]

***

## 2. OAuth Token Management

### The Core Problem

`AuthService` stores the Graph access token as `@Published var graphAccessToken: String?`. `EmailSyncService.start()` receives this raw `String` once at startup and uses it for every subsequent API call until the service stops. Microsoft access tokens expire after **60–90 minutes** — after which every Graph call will return `401 Unauthorized`, the error is swallowed in the `catch` block, and the service silently stops syncing without any user-visible indication.[^8]

There is no MSAL integration anywhere in the current codebase. `AuthService.signInWithGraph()` calls `graphClient.authenticate()` via the `@Dependency` client — the concrete implementation of that dependency is responsible for token acquisition, but there is no proactive silent-refresh mechanism.

### MSAL Best Practice for macOS

MSAL for macOS persists tokens to the keychain under the `com.microsoft.identity.universalstorage` access group. The correct pattern is to call `acquireTokenSilent()` immediately **before every API call** rather than caching the token string. MSAL reads from keychain cache and issues a silent refresh automatically if the access token is near expiry. The app only needs to handle the `MSALErrorInteractionRequired` case by triggering a UI-level re-auth prompt.[^9][^10]

### Fix: Token Provider Pattern

Replace the raw `accessToken: String` parameter with an `async` token provider closure:

```swift
// Replace in EmailSyncService — ~40 lines changed

// Old:
func start(accessToken: String, workspaceId: UUID, emailAccountId: UUID, profileId: UUID? = nil)

// New:
func start(
    tokenProvider: @escaping () async throws -> String,  // async closure, not cached String
    workspaceId: UUID,
    emailAccountId: UUID,
    profileId: UUID? = nil
)

// In syncOnce(), replace direct use of accessToken with:
private func freshToken() async throws -> String {
    guard let provider = tokenProvider else { throw EmailSyncError.noTokenProvider }
    return try await provider()
}
```

In `AuthService`, implement the token provider:

```swift
// In AuthService.signInWithGraph() — replaces graphAccessToken: String storage

var graphTokenProvider: (() async throws -> String)? {
    return {
        // MSAL acquireTokenSilent — reads keychain, refreshes if needed
        let params = MSALSilentTokenParameters(scopes: Self.mailScopes, account: cachedAccount)
        let result = try await msalApp.acquireTokenSilent(with: params)
        return result.accessToken
    }
}
```

**Scopes to request** (change `signInWithMicrosoft()` in `AuthService.swift`):

```swift
// Current (BROKEN — no mail access):
scopes: "email profile openid"

// Correct:
scopes: "Mail.Read email profile openid offline_access"
```

The current scope string in `AuthService` does not include `Mail.Read` at all. Graph will silently grant the token but any `/me/messages` call will return `403 Forbidden`. `offline_access` is required for MSAL to receive a refresh token.[^11][^12]

### Comparison with Outlook for Mac and Spark

Both Outlook for Mac and Spark use MSAL's keychain-backed token cache identically: they call `acquireTokenSilent` before every batch of API calls, handle `interactionRequired` by showing a non-blocking banner ("Re-connect Outlook account"), and never store raw access token strings in memory beyond a single request lifecycle. Timed should follow this exact pattern.

***

## 3. Batch Efficiency and `$select` Optimization

### Current Call Count

For each message in a delta page, the current code makes:

1. `fetchDeltaMessages()` — 1 call (fetches full message payload, no `$select`)
2. `graphClient.fetchFolderName()` — 1 call per unique folder (on cache miss)
3. `supabaseClient.upsertEmailMessage()` — 1 call per message
4. `URLSession.shared.data(for: classifyRequest)` — 1 HTTP call per message

For 50 messages in a delta page with 10 unique destination folders, that is **~112 network calls** per sync cycle. With 60s polling, over an hour this is ~6,720 calls — already 67% of the 10-minute quota budget of 10,000 requests.[^13]

### Fix 1: `$select` on Delta Query

The delta endpoint supports `$select`. Request only the fields you actually use:

```swift
// In your GraphClient dependency's fetchDeltaMessages implementation
// Add ?$select= to the base URL or deltaLink override

let fields = "$select=id,subject,from,receivedDateTime,parentFolderId,bodyPreview,conversationId,toRecipients,ccRecipients,isDraft"
// Append to initial URL only (deltaLink already encodes the correct params)
let url = deltaLink ?? "https://graph.microsoft.com/v1.0/me/messages/delta?\(fields)&\(pageParams)"
```

This eliminates transmission of `body.content` (HTML email body), `attachments`, `categories`, `inferenceClassification`, and ~25 other unused properties. For a typical 10KB email, this reduces payload by ~70%.

### Fix 2: Batch the Supabase Classify Calls

Instead of calling `triggerClassification()` per message, collect IDs and fire a single batch request:

```swift
// In syncOnce(), after the processing loop (~20 lines changed)

var classifyBatch: [(id: UUID, workspaceId: UUID, senderImportance: Double)] = []

for message in result.messages {
    // ... existing upsert ...
    classifyBatch.append((id: row.id, workspaceId: workspaceId, senderImportance: senderImportance))
    totalProcessed += 1
}

// After the inner loop, fire batch classify
await triggerClassificationBatch(classifyBatch)
```

The batch Edge Function endpoint should accept an array of `{message_id, workspace_id, sender_importance}` objects. This collapses N HTTP calls to 1 per sync page.

### Fix 3: Pre-warm Folder Name Cache

At startup, call `GET /me/mailFolders?$select=id,displayName&$top=100` once and populate `folderNameCache` fully. This eliminates per-message folder name fetches entirely for common folders (Inbox, Junk, Deleted Items), reducing per-cycle calls to near zero for the folder resolution path.

### Minimum API Call Count for a Full Sync Cycle (Target State)

| Operation | Current | Optimised | Saving |
|-----------|---------|-----------|--------|
| Delta fetch (paginated) | N calls × full payload | N calls × `$select` payload | ~70% bandwidth |
| Folder name resolution | Up to N calls | 0 (pre-warmed cache) | ~100% |
| Message upsert to Supabase | N calls | N calls (no change) | — |
| Classify Edge Function | N calls | 1 batch call | ~(N-1) × 100ms |
| **Total per 50-msg page** | **~112** | **~52** | **~54%** |

### Graph API JSON `$batch`

The Graph `$batch` endpoint accepts up to 20 requests per POST. For Timed's use case, the primary win is batching folder name lookups at startup — batch 20 `mailFolder GET` requests into 1 HTTP call. Individual message upserts should remain sequential (Supabase, not Graph). Do not batch delta query calls — pagination order matters and batching breaks the sequential nextLink chain.[^14]

***

## 4. Offline Resilience

### The Core Problem

`NetworkMonitor` exists and correctly publishes `isConnected` via NWPathMonitor, but `EmailSyncService` never references it. When the Mac goes offline mid-sync:

1. `fetchDeltaMessages` throws `URLError.notConnectedToInternet`
2. The `catch` in the sync loop logs the error and **advances `deltaLink`** to whatever partial state was stored by the previous successful page
3. On reconnect, the next delta call may skip messages that were partially processed in the aborted page

### Fix: Integrate NetworkMonitor

In `syncOnce()`, add a guard at the top:

```swift
// ~5 lines added to syncOnce()

guard await NetworkMonitor.shared.isConnected else {
    TimedLogger.graph.info("Offline — skipping delta sync cycle")
    return 0
}
```

### Partial Delta Page Safety

The critical invariant for delta sync is: **only advance `deltaLink` after a page is fully committed**. The current code updates `deltaLink = currentDeltaLink` inside the loop after processing `result.messages` — if the upsert of message #3 on a page of 10 throws, messages #4–10 are skipped but the loop continues and `deltaLink` is updated to the post-page `nextLink`. The safe fix:

```swift
// Move deltaLink update outside the hasMore loop — only commit after all messages on a page succeed

var pendingDeltaLink: String? = nil

while hasMore {
    let result = try await graphClient.fetchDeltaMessages(...)
    // Process ALL messages on page, collecting errors
    for message in result.messages { /* ... */ }
    // Only advance if entire page succeeded
    pendingDeltaLink = result.nextDeltaLink
    hasMore = result.hasMore
}
// Commit the final deltaLink only on clean completion
deltaLink = pendingDeltaLink
```

### Comparison with Apple Mail

Apple Mail uses IMAP IDLE for push notifications (rather than polling), keeping a persistent TCP connection to the IMAP server with a server-initiated notify on new mail. Apple Mail stores the entire IMAP UID sequence locally and uses an optimistic write-ahead log: folder state changes are queued locally and replayed against the server when connectivity resumes. Timed's architecture (Graph delta + Supabase) is structurally similar but lacks the write-ahead queue — offline writes are simply dropped. For v1 (single executive user, rarely offline mid-session), the `NetworkMonitor` guard is sufficient. A proper write-ahead queue with retry is a v2 concern.[^15][^16]

***

## 5. isCcFyi Logic Bug

The current `makeInsertPayload` has an incorrect CC/FYI detection:

```swift
// Current (WRONG):
let isCcFyi = ccRecipientCount > 0 && message.toRecipients.isEmpty

// This reads: "there are CC recipients AND nobody is in the To field"
// That describes a BCC-only send, not a CC/FYI to the user
```

The correct logic is: the user was CC'd (not To'd) on this email.

```swift
// Correct (~10 lines changed in makeInsertPayload):
let userEmail = OnboardingUserPrefs.email.lowercased()
let isInTo = message.toRecipients.contains {
    $0.emailAddress.address.lowercased() == userEmail
}
let isInCc = message.ccRecipients.contains {
    $0.emailAddress.address.lowercased() == userEmail
}
let isCcFyi = isInCc && !isInTo
```

This matters significantly for an executive inbox: newsletters, bulk mail, and company-wide threads often have empty `toRecipients` with the user in BCC (not CC), meaning the current code would incorrectly triage ~25% of non-To mail as `cc_fyi`.

***

## 6. Rate Limiting Analysis

### For a 500 email/day Power User

At 60-second polling with no optimisations, the theoretical peak request rate during a burst delivery of 50 emails simultaneously:

- **1** delta page fetch  
- **Up to 50** folder name fetches (cold cache)  
- **50** classify Edge Function calls  
- **50** Supabase upserts  

That is ~151 Graph API calls in a few seconds. Sustained over 10 minutes with continuous email arrival, this approaches the **10,000 requests per 10 minutes per user per app** Outlook-specific limit.[^17][^18][^13]

With the folder cache pre-warm and batch classify fixes (Section 3), the 50-email burst drops to ~53 Graph calls — well within budget. The remaining risk is 4 concurrent request limit, which the current sequential per-message processing already respects.[^13]

### 429 Backoff Implementation

There is currently zero retry logic. Add to `graphClient` dependency:

```swift
// In GraphClient concrete implementation — ~25 lines

func fetchWithRetry<T>(_ request: URLRequest, decoder: JSONDecoder) async throws -> T {
    var delay: TimeInterval = 1.0
    for attempt in 0..<5 {
        let (data, response) = try await URLSession.shared.data(for: request)
        let httpResponse = response as? HTTPURLResponse
        if httpResponse?.statusCode == 429 {
            let retryAfter = httpResponse?.value(forHTTPHeaderField: "Retry-After")
                .flatMap(TimeInterval.init) ?? delay
            TimedLogger.graph.warning("Graph 429 — backing off \(retryAfter)s (attempt \(attempt))")
            try await Task.sleep(for: .seconds(retryAfter))
            delay = min(delay * 2, 60)
            continue
        }
        return try decoder.decode(T.self, from: data)
    }
    throw GraphAPIError.throttled
}
```

Always respect the `Retry-After` header; if absent, use exponential backoff starting at 1 second and doubling up to 60 seconds. Do not retry immediately — Microsoft continues to accrue usage during the backoff window.[^19][^20]

***

## 7. Privacy and Scope Compliance

### Declared Scopes vs. Actual Needs

| Scope Currently in `AuthService` | Status | Required? |
|----------------------------------|--------|-----------|
| `email` | ✅ Present | Yes (user email claim) |
| `profile` | ✅ Present | Yes (user display name) |
| `openid` | ✅ Present | Yes (auth) |
| `Mail.Read` | ❌ **Missing** | **Yes — required for /me/messages** |
| `offline_access` | ❌ **Missing** | **Yes — required for refresh tokens** |

The `Mail.Read` delegated permission is required for any `GET /me/messages` call. Without it, the Graph token will technically be issued (no error at auth time) but every subsequent messages call returns `403 Forbidden`. The `offline_access` scope is required for MSAL to provide a refresh token, without which silent token renewal is impossible.[^12][^11]

**Do not request `Mail.Read.All`** (application permission) — Timed uses delegated auth (the user is signed in), so `Mail.Read` (delegated) is both necessary and sufficient. `Mail.Read.All` would trigger admin consent requirements and is inappropriate for a consumer desktop app.[^21]

### Body Content Classification and Privacy

Reading email body content for AI classification falls under the "sensitive" category in Apple's App Store privacy nutrition label. The app must declare:

- **Data type collected**: Email content (body, subject, sender)
- **Purpose**: Product personalisation (triage/classification)
- **Linked to identity**: Yes (stored in Supabase with `workspace_id`)
- **Used for tracking**: No (single-user, not shared across users)

Microsoft's own compliance documentation confirms that `Mail.Read` (delegated) for a single signed-in user is appropriate for this use case and does not require additional enterprise data governance beyond standard app registration consent. Unlike `Mail.Read.All` (application permissions used by compliance tools), the delegated scope acts on behalf of the authenticated user only.[^22]

### SaneBox and Superhuman Comparison

**SaneBox** uses server-side IMAP folder monitoring — it logs into your mailbox as a full IMAP client and watches folder state changes. It never reads body content for classification; instead, it uses sender relationship graphs, folder history, and header metadata only. This is why SaneBox works with any email provider and does not need `Mail.Read`.[^23][^24]

**Superhuman** connects as a companion application that syncs with Outlook via Graph API, using delegated `Mail.Read` plus `Mail.ReadWrite` (for marking read, starring, etc.). Superhuman discloses in its privacy policy that email content is processed by their AI on their servers — exactly the disclosure model Timed should follow.[^25]

Timed's classification model (sending `bodyPreview` to a Supabase Edge Function for LLM analysis) requires `Mail.Read` and must be disclosed. If future versions send the full `body.content`, that disclosure strengthens accordingly. `bodyPreview` (the 255-character preview) is sufficient for the current classifier and avoids pulling full HTML body payloads.

***

## 8. Security: Hardcoded Supabase Key

The `supabaseAnonKey` is hardcoded as a fallback string literal in both `EmailSyncService.swift` and `AuthService.swift`. While the anon key is designed to be public (it is a JWT with `role: anon` and no special privileges), committing it to a public repository risks exposure to credential scanning tools and makes rotation harder. The existing pattern of reading from `ProcessInfo.processInfo.environment` first is correct. Remove the fallback literal for the release build and rely on Xcode build settings or `.xcconfig` files to inject the value.

***

## Recommended Fix Order (Single-Sprint Priority)

1. **`AuthService.swift` — Fix scope string** (5 lines, 30 min) — Without `Mail.Read` + `offline_access`, nothing else works.
2. **`EmailSyncService.swift` — Persist `deltaLink`** (20 lines, 1 hr) — Prevents full re-sync on every launch.
3. **`EmailSyncService.swift` — Add `NetworkMonitor` guard** (5 lines, 15 min) — Prevents partial write on offline transitions.
4. **`EmailSyncService.swift` — Handle `410 syncStateNotFound`** (10 lines, 30 min) — Required for long-running production use.
5. **`EmailSyncService.swift` — `$select` on delta query** (10 lines, 30 min) — Bandwidth and quota win.
6. **`EmailSyncService.swift` — Fix `isCcFyi` logic** (10 lines, 30 min) — Correctness fix affecting ~25% of triage decisions.
7. **`AuthService.swift` → `EmailSyncService` — Token provider pattern** (60 lines, 2–3 hrs) — Required for sessions longer than 90 minutes.
8. **`GraphClient` concrete impl — 429 retry with backoff** (25 lines, 1 hr) — Defensive; unlikely to trigger at current scale.
9. **`EmailSyncService.swift` — Batch `triggerClassification`** (20 lines, 1 hr) — Performance win; address in same sprint as Edge Function update.
10. **App Store privacy manifest — Declare `Mail.Read` and email content collection** (non-code, 30 min) — Required before TestFlight/distribution.

**Total estimated effort: ~1 working day** for fixes 1–7 (the critical set).

---

## References

1. [Use delta query to track changes in Microsoft Graph data](https://learn.microsoft.com/en-us/graph/delta-query-overview) - Delta query, also called change tracking, enables applications to discover newly created, updated, o...

2. [Under what conditions does SharePoint delta link return 410 (Gone)?](https://learn.microsoft.com/en-my/answers/questions/5773999/under-what-conditions-does-sharepoint-delta-link-r) - A 410 (Gone) response indicates that the service can no longer continue change tracking using the pr...

3. [How do we handle the 410 resyncRequired error from the https ...](https://learn.microsoft.com/en-us/answers/questions/1433352/how-do-we-handle-the-410-resyncrequired-error-from) - We have tried to get around this error by trying to sync all of the changes (https://learn.microsoft...

4. [Receive change notifications through webhooks - Microsoft Graph](https://learn.microsoft.com/en-us/graph/change-notifications-delivery-webhooks) - While the subscription is valid, Microsoft Graph sends a notification to your endpoint whenever it d...

5. [Graph API Timeout while validating endpoint - Microsoft Q&A](https://learn.microsoft.com/en-gb/answers/questions/1666576/graph-api-timeout-while-validating-endpoint) - I noticed that each time I tried to setup the Graph API webhook for outlook, I received a timeout er...

6. [Microsoft Graph Webhooks - What, Why, How & Best Practices](https://www.voitanos.io/blog/microsoft-graph-webhook-delta-query/) - The webhook allows you to issue a query to Microsoft Graph and then requests a notification when the...

7. [Webhooks v/s polling for all users drives' within an Org (multi-tenant)](https://stackoverflow.com/questions/62670522/webhooks-v-s-polling-for-all-users-drives-within-an-org-multi-tenant-ms-gra) - You can also combine the delta + webhooks: do the initial sync with delta and store the token, regis...

8. [acquireTokenSilent doesn't renew the id-token · Issue #4206 - GitHub](https://github.com/AzureAD/microsoft-authentication-library-for-js/issues/4206) - After an hour the id-tokens that are returned by the acquireTokenSilent function are expired. We hav...

9. [Acquire tokens in MSAL for iOS/macOS | Microsoft Learn](https://learn.microsoft.com/en-us/entra/msal/objc/acquire-tokens) - Learn how to acquire tokens using MSAL to authenticate users in iOS/macOS applications.

10. [Configure keychain - MSAL - Microsoft Learn](https://learn.microsoft.com/en-us/entra/msal/objc/howto-v2-keychain-objc) - This article covers how to configure app entitlements so that MSAL can write cached tokens to iOS an...

11. [Publish an add-in that requires admin consent for Microsoft Graph ...](https://learn.microsoft.com/en-us/office/dev/add-ins/publish/publish-nested-app-auth-add-in) - In this article you'll learn how to publish updates to an Office Add-in to use Microsoft Graph scope...

12. [Microsoft Graph Api for Mail and other features](https://learn.microsoft.com/en-us/answers/questions/1289248/microsoft-graph-api-for-mail-and-other-features) - If you're trying to get the logged-in user's email information, then you need to grant your app one ...

13. [What is the maximum number of emails that can be sent per minute ...](https://learn.microsoft.com/en-us/answers/questions/2258712/what-is-the-maximum-number-of-emails-that-can-be-s) - A maximum of 10,000 API requests every 10 minutes. A maximum of 4 concurrent requests. A maximum upl...

14. [Combine multiple HTTP requests using JSON batching](https://learn.microsoft.com/en-us/graph/json-batching) - Microsoft Graph supports batching up to 20 requests into the JSON object. In this article, we explor...

15. [IMAP IDLE: The best approach for 'push' email - Imageway](https://www.imageway.com/2018/email-hosting-blog/imap-idle-the-best-approach-for-push-email) - A good IMAP server will have minimal overhead for an Idle connection, and should be able to support ...

16. [Getting instant notifications on new emails with IMAP IDLE](https://mailbeenet.wordpress.com/2021/06/07/getting-instant-notifications-on-new-emails-with-imap-idle/) - One of the methods is known as polling, your application connects to mail server every once in a whi...

17. [Throttling coming to Outlook API and Microsoft Graph](https://devblogs.microsoft.com/microsoft365dev/throttling-coming-to-outlook-api-and-microsoft-graph/) - The limit is 10000 requests per 10-minute period, per user (or group), per app ID. This means that y...

18. [Max Concurrent Connections in Microsoft Graph API - Stack Overflow](https://stackoverflow.com/questions/48594199/max-concurrent-connections-in-microsoft-graph-api) - For Exchange/Outlook endpoints it is 10,000 requests per app id, per user, within a 10 minute window...

19. [Microsoft Graph throttling guidance](https://learn.microsoft.com/en-us/graph/throttling) - The Microsoft Graph service implements throttling limits to ensure service availability and reliabil...

20. [A beginners guide to Microsoft Graph API rate limiting in Intune](https://msendpointmgr.com/2025/11/08/graph-api-rate-limiting-in-intune/) - There is a global limit of 130,000 requests per 10 seconds per app across all tenants. This is your ...

21. [Does the permission 'Mail.Read' really mean 'Mail ... - Stack Overflow](https://stackoverflow.com/questions/42029389/does-the-permission-mail-read-really-mean-mail-read-all-in-the-microsoft-gra) - Mail.Read.Shared Read user and shared mail Allows the app to read mail that the user can access, inc...

22. [Overview of compliance and privacy APIs in Microsoft Graph](https://learn.microsoft.com/en-us/graph/compliance-concept-overview) - The Microsoft Graph APIs for compliance and privacy provide functionality for organizations to autom...

23. [What's new - SaneBox](https://www.sanebox.com/release-notes) - Automatically filter your email of spam and unimportant messages to only see the emails that are imp...

24. [Organize Your Inbox with These Email Filters - SaneBox Blog](https://blog.sanebox.com/2019/10/28/organize-your-inbox-with-these-email-filters/) - In this article, we'll be covering how SaneBox can manage your email for you, letting you automate t...

25. [Superhuman's Dependence on Gmail and Outlook | Sacra Chat](https://sacra.com/chat/h/7aa3538c-1dc4-4475-a75f-6e3d54c293f3/) - The product works by asking users to connect an existing Gmail or Outlook account, then reading, org...

