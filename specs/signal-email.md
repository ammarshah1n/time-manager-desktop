# Timed — Email Signal Ingestion Spec

**Status:** Implementation-ready
**Last updated:** 2026-04-02
**Layer:** L1 — Signal Ingestion
**Implements:** `EmailSyncService.swift`, writes to signal queue via `DataStore.swift`
**Dependencies:** `GraphClient.swift` (MSAL OAuth), `TimedLogger.swift`

---

## 1. Overview

Email is the highest-volume signal source for Timed. The email ingestion pipeline reads from Microsoft Graph, extracts metadata and body text, computes derived fields, and writes structured signals to the local signal queue. It never sends, modifies, deletes, or marks emails as read. Observation only.

---

## 2. Microsoft Graph Endpoints

### 2.1 Primary Endpoints

| Operation | Method | Endpoint | Scope Required |
|-----------|--------|----------|----------------|
| List messages | GET | `/me/messages` | `Mail.Read` |
| Delta sync | GET | `/me/messages/delta` | `Mail.Read` |
| Get message | GET | `/me/messages/{id}` | `Mail.Read` |
| List thread | GET | `/me/messages?$filter=conversationId eq '{id}'` | `Mail.Read` |

### 2.2 Query Parameters

Initial sync (no delta token):
```
GET /me/messages/delta
  ?$select=id,subject,from,toRecipients,ccRecipients,receivedDateTime,
           sentDateTime,isRead,importance,categories,conversationId,
           conversationIndex,hasAttachments,bodyPreview,body,
           inferenceClassification,parentFolderId,isDraft,
           internetMessageHeaders
  &$top=50
  &$orderby=receivedDateTime desc
  &$filter=isDraft eq false
```

Delta sync (with token):
```
GET /me/messages/delta
  ?$deltatoken={stored_token}
  &$select=<same fields>
  &$top=50
```

### 2.3 Delta Sync Mechanics

1. **First sync**: No delta token. Fetch all messages (paginated, `$top=50`). Follow `@odata.nextLink` until exhausted. Store `@odata.deltaLink` token.
2. **Subsequent syncs**: Use stored delta token. Receive only new/modified messages since last sync.
3. **Token expiry**: If Graph returns HTTP 410 (Gone), discard delta token and perform full re-sync.
4. **Sync trigger**: Every 5 minutes via `TimedScheduler`, or on-demand when app comes to foreground after > 10 minutes in background.

---

## 3. Captured Data

### 3.1 Direct Metadata (from Graph response)

| Field | Graph Property | Type | Notes |
|-------|---------------|------|-------|
| `messageId` | `id` | String | Graph unique ID |
| `subject` | `subject` | String | Raw subject line |
| `sender` | `from.emailAddress` | `{name, address}` | Display name + email |
| `toRecipients` | `toRecipients` | `[{name, address}]` | All To: addresses |
| `ccRecipients` | `ccRecipients` | `[{name, address}]` | All Cc: addresses |
| `threadId` | `conversationId` | String | Groups messages in same thread |
| `receivedAt` | `receivedDateTime` | ISO8601 Date | When message arrived |
| `sentAt` | `sentDateTime` | ISO8601 Date | When sender sent it |
| `isRead` | `isRead` | Bool | Read/unread state at sync time |
| `importance` | `importance` | `low\|normal\|high` | Sender-set importance |
| `categories` | `categories` | `[String]` | Outlook categories (color tags) |
| `isReply` | derived | Bool | True if `subject` starts with `Re:` or `conversationIndex` indicates reply |
| `hasAttachments` | `hasAttachments` | Bool | Flag only — attachment content never fetched |
| `inferenceClassification` | `inferenceClassification` | `focused\|other` | Outlook Focused Inbox classification |
| `parentFolderId` | `parentFolderId` | String | Inbox, Sent, Archive, etc. |

### 3.2 Captured Content

| Field | Source | Type | Notes |
|-------|--------|------|-------|
| `bodyText` | `body.content` where `body.contentType == "text"` | String | Plain text body. If `contentType == "html"`, strip all HTML tags, decode entities, extract text only. |
| `bodyPreview` | `bodyPreview` | String | First 255 chars, provided by Graph. Used for quick display, not analysis. |

### 3.3 NOT Captured (observation-only boundary)

| Data | Reason |
|------|--------|
| Attachment content (files, images, PDFs) | Privacy. Not needed for cognitive signal. Binary data bloats store. |
| Inline images | Stripped during HTML → text conversion. |
| Email headers beyond standard fields | Noise. `internetMessageHeaders` fetched only if needed for reply detection fallback. |
| Draft emails | Filtered out (`isDraft eq false`). Incomplete signal. |

---

## 4. Computed Fields

Computed after raw data is captured, before writing to signal queue.

### 4.1 Response Latency

```swift
/// Time between receiving an email and the user's reply in the same thread.
/// Nil if the user has not replied.
func computeResponseLatency(
    incomingMessage: EmailSignal,
    threadMessages: [EmailSignal]
) -> TimeInterval? {
    // Find the first message FROM the user AFTER incomingMessage.receivedAt
    // in the same thread (matching conversationId).
    guard let reply = threadMessages
        .filter({ $0.sender.address == userEmail })
        .filter({ $0.sentAt > incomingMessage.receivedAt })
        .sorted(by: { $0.sentAt < $1.sentAt })
        .first
    else { return nil }
    
    return reply.sentAt.timeIntervalSince(incomingMessage.receivedAt)
}
```

**Notes:**
- Latency is computed retroactively — when a reply appears in a delta sync, we update the original message's signal.
- Latency > 7 days is capped at 7 days (signal value diminishes).
- Latency is stored in seconds.

### 4.2 Thread Depth

```swift
/// Number of messages in a conversation thread.
func computeThreadDepth(conversationId: String) -> Int {
    return signalStore.count(where: .conversationId == conversationId)
}
```

Updated on every sync. Depth > 20 is capped at 20 (display only, raw count preserved).

### 4.3 Sender Frequency

```swift
/// Rolling 30-day count of emails from a given sender address.
func computeSenderFrequency(senderAddress: String) -> Int {
    let thirtyDaysAgo = Date().addingTimeInterval(-30 * 86400)
    return signalStore.count(
        where: .sender.address == senderAddress 
            && .receivedAt >= thirtyDaysAgo
    )
}
```

**Frequency tiers** (for L2/L3 consumption):
| Tier | Emails/30d | Label |
|------|-----------|-------|
| VIP | >= 20 | `frequent` |
| Regular | 5-19 | `regular` |
| Occasional | 2-4 | `occasional` |
| One-off | 1 | `oneOff` |

---

## 5. Signal Queue Write Path

### 5.1 Signal Schema

```swift
struct EmailSignal: Codable, Identifiable {
    let id: UUID                        // Local signal ID
    let messageId: String               // Graph message ID
    let subject: String
    let sender: EmailContact
    let toRecipients: [EmailContact]
    let ccRecipients: [EmailContact]
    let threadId: String
    let receivedAt: Date
    let sentAt: Date
    let isRead: Bool
    let importance: EmailImportance     // .low, .normal, .high
    let categories: [String]
    let isReply: Bool
    let hasAttachments: Bool
    let inferenceClassification: InboxClassification  // .focused, .other
    let parentFolderId: String
    let bodyText: String
    let bodyPreview: String
    
    // Computed (populated post-capture)
    var responseLatency: TimeInterval?
    var threadDepth: Int
    var senderFrequency: Int
    var senderTier: SenderTier
    
    // Metadata
    let capturedAt: Date                // When Timed ingested this
    let syncBatchId: UUID               // Groups signals from same sync
    let signalSource: SignalSource       // .email
}
```

### 5.2 Write Path

```
Graph API Response
  → JSON deserialization (Codable)
  → HTML stripping (if body is HTML)
  → Deduplication check (messageId exists in store?)
    → If exists and modified: update signal
    → If exists and unchanged: skip
    → If new: create signal
  → Computed field derivation
  → CoreData write (DataStore.saveEmailSignal)
  → Post-write: update sender frequency cache
  → Post-write: update thread depth for conversation
```

### 5.3 Deduplication

Primary key: `messageId` (Graph unique ID). If a delta sync returns a message already in the store:
- Compare `isRead`, `importance`, `categories`, `parentFolderId` for changes.
- If changed: update the existing signal. Set `updatedAt`. Do not create a duplicate.
- If unchanged: skip entirely. Log at `.debug` level.

---

## 6. Rate Limits and Throttling

### 6.1 Microsoft Graph Rate Limits

| Limit | Value | Source |
|-------|-------|--------|
| Per-app per-mailbox | 10,000 requests / 10 minutes | Graph docs |
| Per-app tenant-wide | 150,000 requests / 5 minutes | Graph docs |
| Mail-specific | 4 concurrent requests per mailbox | Observed |

Timed's usage pattern (single user, delta sync every 5 minutes) is well within limits. Defensive handling still required.

### 6.2 Throttle Response Handling

```swift
func handleThrottling(_ response: HTTPURLResponse) async throws {
    guard response.statusCode == 429 else { return }
    
    let retryAfter = response.value(forHTTPHeaderField: "Retry-After")
        .flatMap(TimeInterval.init) ?? 60.0
    
    let jitter = TimeInterval.random(in: 0...5)
    let delay = retryAfter + jitter
    
    TimedLogger.network.warning("Graph API throttled. Retrying in \(delay)s")
    
    try await Task.sleep(for: .seconds(delay))
    // Retry is handled by the caller's retry loop (max 3 retries)
}
```

### 6.3 Retry Policy

| Condition | Action | Max Retries |
|-----------|--------|-------------|
| HTTP 429 | Wait `Retry-After` + jitter, retry | 3 |
| HTTP 500, 502, 503 | Exponential backoff (2s, 4s, 8s) | 3 |
| HTTP 401 | Trigger MSAL token refresh, retry | 1 |
| HTTP 410 (delta expired) | Discard delta token, full re-sync | 1 |
| Network timeout (30s) | Retry with same request | 2 |
| Other errors | Log error, skip this sync cycle | 0 |

After max retries exhausted: log error via `TimedLogger.network.error()`, skip this sync cycle, retry on next scheduled cycle. Never crash. Never lose local data.

---

## 7. Error Handling

### 7.1 Error Categories

```swift
enum EmailSyncError: Error {
    case authenticationFailed(underlying: Error)
    case deltaTokenExpired
    case rateLimited(retryAfter: TimeInterval)
    case serverError(statusCode: Int)
    case networkUnavailable
    case deserializationFailed(messageId: String?, underlying: Error)
    case coreDataWriteFailed(underlying: Error)
}
```

### 7.2 Error Handling Matrix

| Error | User Impact | Action |
|-------|-------------|--------|
| `authenticationFailed` | No new email signals | Trigger re-auth flow. Show "Reconnect email" in settings. |
| `deltaTokenExpired` | Brief delay during full re-sync | Automatic full re-sync. No user action needed. |
| `rateLimited` | Delayed sync (usually < 60s) | Automatic retry. No user action needed. |
| `serverError` | Delayed sync | Automatic retry with backoff. Log for diagnostics. |
| `networkUnavailable` | No sync while offline | Queue sync for when network returns (`NetworkMonitor`). |
| `deserializationFailed` | Single email skipped | Log the messageId. Skip this email. Continue sync. Never fail the entire batch for one bad message. |
| `coreDataWriteFailed` | Signal not persisted | Retry write once. If fails again, log and move to next signal. Investigate on next app launch. |

### 7.3 Logging

All sync operations log to `TimedLogger.emailSync` subsystem:
- `.debug`: Individual message processing, skip reasons.
- `.info`: Sync started, sync completed (count, duration), delta token refreshed.
- `.warning`: Throttled, retrying. Deserialization skipped for individual message.
- `.error`: Sync cycle failed after retries. Auth failure. CoreData write failure.

---

## 8. Privacy

### 8.1 Data Minimisation

- Only `Mail.Read` scope — never `Mail.ReadWrite`, `Mail.Send`, or any write scope.
- Attachment content is never fetched. Only the `hasAttachments` boolean flag.
- Email body is stored as stripped plain text. No HTML, no images, no formatting.
- No data leaves the device except to Supabase (encrypted, user's own workspace, authenticated).

### 8.2 Observation-Only Enforcement

The `GraphClient` email methods are restricted at the code level:

```swift
// GraphClient.swift — Email methods
// OBSERVATION ONLY: These methods use GET requests exclusively.
// No POST, PATCH, PUT, or DELETE methods exist for email.
// This is enforced by code review and by ObservationOnlyTests.

func fetchMessages(deltaToken: String?) async throws -> MessageDeltaResponse { ... }
func fetchMessage(id: String) async throws -> GraphMessage { ... }
// No sendMessage(), no updateMessage(), no deleteMessage().
```

### 8.3 Data Retention

- Email signals are retained locally for 180 days.
- After 180 days, signals are archived (metadata retained, bodyText purged).
- After 365 days, archived signals are hard-deleted.
- User can trigger immediate purge of all email data from Settings.

---

## 9. Acceptance Criteria

### 9.1 Functional

- [ ] Initial sync fetches all non-draft emails from inbox, paginated correctly.
- [ ] Delta sync fetches only new/modified emails since last sync.
- [ ] All 16 direct metadata fields are correctly extracted and stored.
- [ ] Body text is extracted as plain text regardless of source format (text or HTML).
- [ ] HTML bodies are stripped of all tags, entities decoded, images removed.
- [ ] Response latency is computed retroactively when reply appears in a thread.
- [ ] Thread depth is updated on every sync for affected conversations.
- [ ] Sender frequency is computed on a rolling 30-day window.
- [ ] Sender tier is derived correctly from frequency count.
- [ ] Duplicate messages (same `messageId`) are updated, not duplicated.
- [ ] Delta token is persisted and reused across app launches.
- [ ] Delta token expiry (410) triggers automatic full re-sync.

### 9.2 Observation-Only

- [ ] No POST, PATCH, PUT, or DELETE requests are ever made to Graph Mail endpoints.
- [ ] Read status of emails is never modified by Timed.
- [ ] No attachment content is ever downloaded.
- [ ] `GraphClient` contains no write methods for email.

### 9.3 Error Handling

- [ ] HTTP 429 triggers retry with `Retry-After` header + jitter.
- [ ] HTTP 401 triggers MSAL token refresh and single retry.
- [ ] HTTP 5xx triggers exponential backoff (3 retries max).
- [ ] A single malformed email does not fail the entire sync batch.
- [ ] Network unavailability queues sync for reconnection.
- [ ] All errors are logged with appropriate severity.

### 9.4 Performance

- [ ] Delta sync of 100 new emails completes in < 5 seconds (network + processing).
- [ ] Initial sync of 1,000 emails completes in < 60 seconds.
- [ ] CoreData write for a single sync batch (50 emails) completes in < 1 second.
- [ ] Sync does not block the main thread.

### 9.5 Privacy

- [ ] Only `Mail.Read` scope is requested during OAuth.
- [ ] Email body is stored as plain text only.
- [ ] No attachment binary data is ever present in local storage.
- [ ] Data retention policy is enforced (180-day archive, 365-day purge).
