# Timed — Email Signal Ingestion Spec: Microsoft Graph Mail

**Layer 1 Signal Ingestion | Signal Type: Email | Version: 1.0**
**Scope:** Microsoft 365 / Exchange Online mailboxes. Observation-only. No write operations.

***

## 1. Overview and Architecture

The email signal pipeline for Timed ingests structured metadata and body text from a user's Microsoft 365 mailbox via the Microsoft Graph REST API (v1.0). The architecture follows a three-phase model:

1. **Initial Full Sync** — page through all historical messages per folder using delta queries to bootstrap the local signal store.
2. **Incremental Sync** — webhook change notifications trigger targeted delta calls to fetch only new/changed/deleted messages.
3. **Downstream Enrichment** — the signal queue feeds a classification and intelligence layer that derives relationship health, response patterns, and avoidance signals.

The pipeline is **observation-only**: the required scope is `Mail.Read` (application or delegated), no write permissions are requested or granted.

***

## 2. Required Permissions

| Scenario | Permission | Consent Required |
|---|---|---|
| Observe one signed-in user | `Mail.Read` (Delegated) | User |
| Observe user's mailbox without sign-in | `Mail.Read` (Application) | Admin |
| Access all mailboxes tenant-wide | `Mail.Read` (Application) | Admin |

For Timed's macOS context (single-user cognitive layer), **delegated `Mail.Read`** is the appropriate choice — it observes only the consenting user's mailbox. The app must be registered in Microsoft Entra ID (formerly Azure AD); the user grants consent once via OAuth 2.0 authorization code flow. Admin-level application permissions can be scoped to specific mailboxes using application access policies even when the broader `Mail.Read` application permission is granted.[^1][^2]

**Important (2026 update):** Microsoft is implementing a breaking change effective 31 December 2026 that restricts modification of sensitive properties (subject, body, recipients) on non-draft messages to apps holding `Mail-Advanced.ReadWrite`. Since Timed is read-only, this change does not apply, but it is worth noting for any future write-adjacent features.[^3]

***

## 3. Exact API Endpoints

### 3.1 Folder Discovery

```
GET https://graph.microsoft.com/v1.0/me/mailFolders/delta
```

Run this before message sync to build a complete map of all mail folders and obtain a `deltaLink` per folder. Store the `parentFolderId` → folder name mapping for signal enrichment.[^4]

### 3.2 Initial Full Message Sync (per folder)

```
GET https://graph.microsoft.com/v1.0/me/mailFolders/{folderId}/messages/delta
    ?$select=id,conversationId,conversationIndex,subject,from,sender,
             toRecipients,ccRecipients,bccRecipients,replyTo,
             receivedDateTime,sentDateTime,lastModifiedDateTime,
             hasAttachments,isRead,importance,categories,parentFolderId,
             internetMessageId,isDraft,inferenceClassification,
             body,internetMessageHeaders
    &changeType=created
```

Header: `Prefer: odata.maxpagesize=50`

**Do not** use `$top` with delta queries; instead control page size via the `Prefer` header. The response streams pages via `@odata.nextLink` until a final `@odata.deltaLink` is returned, signalling sync completion.[^5][^6]

### 3.3 Incremental Delta (webhook-triggered or backstop)

```
GET {stored @odata.deltaLink URL}
```

The stored `@odata.deltaLink` is opaque — use it verbatim. Microsoft Graph encodes all query parameters into the token itself; do not modify or reconstruct the URL.[^7]

### 3.4 Folder-Level Incremental Sync

```
GET https://graph.microsoft.com/v1.0/me/mailFolders/delta
    ?$deltatoken={stored_folder_delta_token}
```

Detects when the user creates or deletes mail folders, allowing the message delta map to be updated accordingly.[^4]

### 3.5 Get Single Message (on-demand enrichment)

```
GET https://graph.microsoft.com/v1.0/me/messages/{messageId}
    ?$select=body,internetMessageHeaders
```

Used to retrieve body text or internet headers for a specific message when not captured during initial sync (e.g., very old messages or re-enrichment passes).[^8]

### 3.6 Change Notification Subscription

```
POST https://graph.microsoft.com/v1.0/subscriptions
Content-Type: application/json

{
  "changeType": "created,updated,deleted",
  "notificationUrl": "https://{timed-agent-endpoint}/graph/notify",
  "lifecycleNotificationUrl": "https://{timed-agent-endpoint}/graph/lifecycle",
  "resource": "/me/mailfolders('inbox')/messages",
  "expirationDateTime": "{now + 4319 minutes}",
  "clientState": "{secure-random-uuid}"
}
```

A separate subscription is required per folder observed. The standard subscription maximum is approximately 3 days (4320 minutes); your agent must renew before expiry.[^9][^10][^11]

***

## 4. Captured Metadata

The following table defines every field captured from the Graph API message object, its Graph property name, and its purpose in the Timed signal model.

| Signal Field | Graph Property | Type | Notes |
|---|---|---|---|
| Message ID | `id` | string | Graph-internal ID; changes on folder move unless `ImmutableId` header sent[^12] |
| Internet Message ID | `internetMessageId` | string | RFC5322 ID; stable across providers; use for cross-provider dedup[^12] |
| Thread ID | `conversationId` | string | Exchange conversation ID; may change if subject edited[^13] |
| Thread Position | `conversationIndex` | binary (base64) | MAPI binary; encodes thread position and depth[^14] |
| Subject | `subject` | string | Redact before LLM if needed; used for topic clustering |
| Sender | `from.emailAddress` | {name, address} | Mailbox owner and sender — differs from `sender` in delegation[^12] |
| From (actual account) | `sender.emailAddress` | {name, address} | Account used to send; important for delegate detection[^12] |
| To Recipients | `toRecipients[]` | recipient[] | Primary recipients |
| CC Recipients | `ccRecipients[]` | recipient[] | CC'd parties |
| BCC Recipients | `bccRecipients[]` | recipient[] | Available to sender's mailbox only |
| Received Time | `receivedDateTime` | ISO8601 UTC | When message landed in mailbox[^12] |
| Sent Time | `sentDateTime` | ISO8601 UTC | When message was sent |
| Last Modified | `lastModifiedDateTime` | ISO8601 UTC | Tracks read/flag updates[^12] |
| Read State | `isRead` | boolean | Changes on read; delta will surface updated record[^12] |
| Importance | `importance` | enum | `low` / `normal` / `high`[^15] |
| Categories | `categories[]` | string[] | User-defined Outlook categories[^12] |
| Folder | `parentFolderId` | string | Resolved to folder name via folder map[^12] |
| Has Attachments | `hasAttachments` | boolean | True only for file attachments, not inline images[^12] |
| Is Draft | `isDraft` | boolean | Exclude drafts from relationship analysis |
| Is Reply Requested | `isReadReceiptRequested` | boolean | Signal of sender intent/formality[^12] |
| Inference Class | `inferenceClassification` | enum | `focused` / `other` (Outlook AI)[^15] |
| Internet Headers | `internetMessageHeaders[]` | [{name, value}] | Must use `$select`; contains `In-Reply-To`, `References`, routing hops; read-only[^16] |
| Reply-To | `replyTo[]` | recipient[] | Addresses for replies if different from sender |
| Unsubscribe | `unsubscribeEnabled` | boolean | Newsletter/list detection signal |

### 4.1 Body Content Capture

```
body: {
  contentType: "html" | "text",
  content: "..."
}
```

The `body` field returns HTML or plain text. For LLM classification, strip HTML tags to extract plain text content. Use `uniqueBody` (`?$select=uniqueBody`) as an alternative — it returns only the content unique to the current message, excluding quoted prior messages — which reduces token consumption in downstream LLM calls.[^12]

**Strip before queuing:** HTML tags, inline `<img src="cid:...">` references, and email signature blocks identified via heuristic (HR tag, `--` delimiter). Store stripped plain text only.

***

## 5. What Is NOT Captured

| Excluded Signal | Reason |
|---|---|
| Attachment binary content | Privacy boundary; use `hasAttachments` flag only |
| Inline image content | Embedded as CID references in body; excluded from capture |
| Attachment metadata (filename, size) | Requires separate `GET .../attachments` call; excluded in v1 scope |
| Calendar invite bodies | Separate resource type (`eventMessage`); out of scope for Layer 1 Email |
| MIME raw source | Requires `GET /messages/{id}/$value`; contains headers already captured via `internetMessageHeaders` |
| Encryption keys / S/MIME certificates | Never captured |
| Read receipts as message content | Read state is captured as `isRead` flag only |
| Full conversation thread history on delta | Delta only surfaces changed messages; historical thread context is reconstructed from local store via `conversationId` |

***

## 6. Computed Metadata

These fields are computed by the ingestion pipeline at write time, before the signal enters the queue.

### 6.1 Is-Reply Detection

```python
def is_reply(msg: dict) -> bool:
    # Method 1: conversationIndex length > 22 bytes = at least one reply hop
    ci = base64.b64decode(msg.get('conversationIndex', ''))
    if len(ci) > 22:
        return True
    # Method 2: In-Reply-To header present
    for h in msg.get('internetMessageHeaders', []):
        if h['name'].lower() == 'in-reply-to':
            return True
    return False
```

The `conversationIndex` is a binary MAPI property. Its structure:[^14][^17]
- Bytes 0–4: reserved (0x01)
- Bytes 5–20: 16-byte GUID (conversation root)
- Bytes 21+: 5-byte child blocks, one per reply hop

`is_reply = len(conversationIndex_bytes) > 22`

### 6.2 Thread Depth

```python
def thread_depth(conv_index_b64: str) -> int:
    ci = base64.b64decode(conv_index_b64)
    if len(ci) < 22:
        return 0
    return (len(ci) - 22) // 5 + 1
```

This is the zero-indexed depth of the message within its conversation thread.[^14]

### 6.3 Response Latency

```python
def response_latency_seconds(reply_msg: dict, parent_msg: dict) -> float | None:
    if not is_reply(reply_msg):
        return None
    reply_time = datetime.fromisoformat(reply_msg['receivedDateTime'])
    sent_time = datetime.fromisoformat(parent_msg['sentDateTime'])
    return (reply_time - sent_time).total_seconds()
```

Computed by matching on `conversationId` within the local signal store. The parent message is the most recent prior message in the same thread where `from.address` matches the current message's `toRecipients`. A rolling median latency per sender is maintained as a relationship health baseline.

### 6.4 Sender Frequency

```python
# Rolling 30-day window, updated on each new message ingested
sender_freq[sender_address] = count of messages from sender in last 30 days
```

Computed from the local store. A sliding window per sender address gives contact frequency rank. Frequency drops trigger "relationship cooling" signals downstream.

***

## 7. Write Path to Signal Queue

```
Graph API Response
       │
       ▼
[Message Normalization]
  - Strip HTML from body
  - Decode conversationIndex
  - Resolve parentFolderId → folderName
  - Compute is_reply, thread_depth
       │
       ▼
[Signal Envelope Construction]
  {
    signal_type: "email",
    source: "microsoft_graph",
    ingested_at: ISO8601 UTC,
    message_id: internetMessageId,
    graph_id: id,
    conversation_id: conversationId,
    thread_depth: int,
    is_reply: bool,
    folder: string,
    sender: { name, address },
    recipients: { to[], cc[], bcc[] },
    subject: string,
    received_at: ISO8601 UTC,
    sent_at: ISO8601 UTC,
    read: bool,
    importance: enum,
    categories: [],
    has_attachments: bool,
    body_text: string (HTML-stripped),
    computed: {
      response_latency_s: float | null,
      sender_frequency_30d: int,
    }
  }
       │
       ▼
[Signal Queue]
  Append-only log (SQLite WAL / Redis Stream / local file queue)
  - Keyed by internetMessageId for idempotent writes
  - Delta deletions published as { signal_type: "email_deleted", id: ... }
       │
       ▼
[Downstream Intelligence Layer]
```

**Idempotency:** Use `internetMessageId` (RFC5322) as the idempotent key, not Graph's `id`, because Graph's `id` changes when a message is moved between folders (unless the `Prefer: IdType="ImmutableId"` request header is used).[^12]

***

## 8. Delta Sync Deep Dive

### 8.1 Initial Full Sync Procedure

The initial sync bootstraps the local signal store. Because `message:delta` operates per folder, the procedure is:[^18]

**Step 1 — Sync folder structure:**
```
GET /me/mailFolders/delta
```
Page through all results; store folder ID → name map and `deltaLink` for folders.

**Step 2 — Determine target folders:**
Timed should sync at minimum: Inbox, Sent Items, Drafts (excluded from analysis), Archive, and any user-defined folders. Exclude Junk Email and Deleted Items unless avoidance analysis requires sent-to-junk signals.

**Step 3 — Per-folder message delta (initial round):**
```
GET /me/mailFolders/{folderId}/messages/delta
    ?$select={field list}
Header: Prefer: odata.maxpagesize=50
```
Page through all `@odata.nextLink` responses until `@odata.deltaLink` is received. Store the `deltaLink` in persistent storage keyed by `folderId`.

**Known limitation:** Some Exchange Online tenants cap the initial delta traversal at 5,000 messages per folder. If a user has a large mailbox, set `$top` to a value exceeding the message count (e.g., 10,000) — this bypasses the 5,000 item limit but changes page size to 512. Test against your target tenant.[^19][^20]

### 8.2 Incremental Polling

The recommended production pattern combines webhooks with delta queries:[^21]

```
Webhook notification arrives
    │
    ▼
Trigger: GET {stored deltaLink for affected folder}
    │
    ├──▶ @odata.nextLink → continue paging
    │
    └──▶ @odata.deltaLink → store new token; processing complete
```

Microsoft explicitly recommends this hybrid: "use webhook notifications as the trigger to make delta query calls. You should also ensure that your application has a backstop polling threshold, in case no notifications are triggered."[^21]

**Backstop polling interval:** Poll each folder's deltaLink every 15 minutes regardless of webhook activity. This catches any missed notifications and handles cases where the webhook subscription has silently expired.[^22]

### 8.3 Token Management

| Token | Location | Meaning |
|---|---|---|
| `$skiptoken` | `@odata.nextLink` | More pages in current sync round; keep paging[^7] |
| `$deltatoken` | `@odata.deltaLink` | Sync round complete; use this URL next time[^7] |

**Storage:** Persist the full `@odata.deltaLink` URL (not just the token portion) per folder ID. The URL is opaque and Microsoft may change its format; never parse it.[^7]

**Delta token expiry:** Microsoft does not publish an official delta token expiry window for mail folders. If a delta token becomes stale (HTTP 410 Gone response), perform a full re-sync for that folder and obtain a new `deltaLink`.

### 8.4 Webhook Subscription Lifecycle

```
POST /subscriptions → subscriptionId + expirationDateTime
    │
    ▼ (before expiry)
PATCH /subscriptions/{id}
  { "expirationDateTime": "{extended_time}" }
```

- Standard email webhook maximum: ~3 days (4,320 minutes)[^11]
- Rich notification email webhooks may cap at 1 day in practice despite documentation suggesting 7 days[^23]
- Renew subscriptions on a schedule (e.g., every 60 minutes with a 30-minute safety buffer)
- On subscription expiry, the agent must `POST /subscriptions` to create a new one and immediately run a delta sync to catch any missed changes during the gap[^24]

***

## 9. Rate Limit Handling

### 9.1 Throttling Limits for Outlook/Mail

| Limit | Scope | Value |
|---|---|---|
| Requests per 10-min period | Per app per mailbox | 10,000[^25] |
| Concurrent requests | Per app per mailbox | 4[^26] |
| Global requests per 10 seconds | Per app, all tenants | 130,000[^27] |
| Batch max requests | Per batch payload | 20 (max 4 per mailbox within batch)[^28] |

### 9.2 429 Handling and Exponential Backoff

```python
import time
import random

MAX_RETRIES = 7
BASE_DELAY_S = 1.0
MAX_DELAY_S = 120.0

def graph_request_with_retry(url: str, headers: dict) -> dict:
    for attempt in range(MAX_RETRIES):
        response = requests.get(url, headers=headers)
        
        if response.status_code == 429:
            retry_after = int(response.headers.get('Retry-After', BASE_DELAY_S * (2 ** attempt)))
            jitter = random.uniform(0, retry_after * 0.1)
            wait = min(retry_after + jitter, MAX_DELAY_S)
            time.sleep(wait)
            continue
        
        if response.status_code == 200:
            return response.json()
        
        if response.status_code in (500, 502, 503, 504):
            # Transient server error
            wait = min(BASE_DELAY_S * (2 ** attempt) + random.uniform(0, 1), MAX_DELAY_S)
            time.sleep(wait)
            continue
        
        response.raise_for_status()
    
    raise Exception(f"Max retries exceeded for {url}")
```

Key principles:[^29][^30][^31]
- **Always respect `Retry-After`** — it is returned in seconds; ignoring it extends the throttle window
- **Add jitter** — prevents synchronized retry storms in multi-folder sync workers
- **Prioritize user-initiated requests** — use `x-ms-throttle-priority: high` header for any request triggered by direct user action; background delta polls should use `normal` or `low`
- **Monitor `x-ms-throttle-limit-percentage`** response header — at 0.8+ begin backing off proactively

### 9.3 Concurrent Request Control

Maintain a semaphore limiting concurrent Graph calls to 3 (leaving one slot buffer below the 4-request limit):[^26]

```python
import asyncio

_graph_semaphore = asyncio.Semaphore(3)

async def safe_graph_get(url: str) -> dict:
    async with _graph_semaphore:
        return await graph_request_with_retry(url)
```

### 9.4 JSON Batching

Use `POST /$batch` when enriching multiple messages in a single pass (e.g., fetching `internetMessageHeaders` for a batch of messages). Batch up to 20 requests, with a maximum of 4 targeting the same mailbox per batch. Each sub-request in the batch still counts against per-mailbox throttle limits.[^28][^32]

***

## 10. Access Token Lifecycle

| Token | TTL | Notes |
|---|---|---|
| Access token | ~1 hour | Short-lived; used in Bearer header[^33] |
| Refresh token | ~90 days (with activity) | 14 days inactivity = expiry[^34] |

**MSAL integration:**

```python
from msal import PublicClientApplication

app = PublicClientApplication(
    client_id=CLIENT_ID,
    authority=f"https://login.microsoftonline.com/{TENANT_ID}"
)

def get_access_token() -> str:
    accounts = app.get_accounts()
    if accounts:
        result = app.acquire_token_silent(
            scopes=["Mail.Read"],
            account=accounts
        )
        if result and "access_token" in result:
            return result["access_token"]
    # Fall back to interactive or device code flow
    raise TokenExpiredError("Re-authentication required")
```

MSAL's `acquire_token_silent` transparently refreshes the access token using the cached refresh token without user interaction. On a macOS app, token cache should be persisted to the system Keychain via MSAL's `SerializableTokenCache` to survive process restarts.[^34]

For unattended background operation, configure the app registration with **offline_access** scope at consent time to obtain a refresh token. Note: MSAL Node.js requires explicit `offline_access` scope in the consent request to receive a refresh token.[^35]

***

## 11. How Email Signals Feed Downstream Intelligence

### 11.1 Response Pattern Analysis

Using `conversationId` to group messages within the local signal store, the pipeline computes:

- **Reply rate per contact**: percentage of sent messages that received a response within 72 hours
- **Median response latency**: per sender/recipient pair, rolling 30-day window
- **Response time delta**: current latency vs. historical median — a Z-score of >2 triggers a "cooling" event
- **No-response detection**: threads where the user sent the last message > 7 days ago with no reply

### 11.2 Relationship Health Score

Built from a composite of:
- Sender frequency (messages exchanged per 30 days)[^36]
- Response reciprocity (does the relationship go both ways, or is the user always the initiator?)
- Thread depth (deep threads = engaged relationship)
- Importance signals (are messages marked `high` importance and going unanswered?)
- Inference classification (`focused` vs `other` — Outlook's own relevance signal)[^15]

### 11.3 Avoidance Detection

Avoidance signals are constructed from behavioral pattern shifts:[^37]

| Signal | Detection Method |
|---|---|
| Response latency increase | Current latency > 2× historical median for that sender |
| Read-without-reply | `isRead: true` on sent item + no reply within contact's normal window |
| Folder shift | Contact's emails begin landing in `other` inference class after `focused` |
| Subject-initiated cooling | User stops initiating new threads with a previously frequent contact |
| Silence window | N consecutive days with zero messages from/to a historically active contact |

### 11.4 LLM Classification Feed

Body text (HTML-stripped) and the computed metadata envelope are submitted to the downstream LLM layer for:

- **Topic clustering** — what subjects dominate threads with each contact
- **Sentiment drift** — tone shift over time within a relationship thread
- **Action item detection** — commitments, deadlines, and follow-ups in message bodies
- **Urgency classification** — combining `importance` flag, subject keywords, and body tone

The signal envelope should be sent to the LLM with `uniqueBody` where available (excludes quoted prior messages) to reduce token count and improve classification accuracy.[^12]

***

## 12. Error Handling

| Error | HTTP Code | Action |
|---|---|---|
| Throttled | 429 | Respect `Retry-After`; exponential backoff with jitter[^29] |
| Unauthorized | 401 | Attempt silent token refresh via MSAL; if fails, surface re-auth UI |
| Forbidden | 403 | Log permission error; alert user to re-consent with correct scope |
| Not Found | 404 | Message deleted between delta and fetch; mark as `deleted` in local store |
| Gone | 410 | Delta token expired; trigger full re-sync for that folder |
| Timeout / Server Error | 500/503/504 | Exponential backoff; max 7 retries; dead-letter after max retries |
| Subscription expired | — | `POST /subscriptions` to create new subscription; immediately run delta sync |
| Webhook validation failure | — | Return 200 with `validationToken` from Graph; failure kills the subscription[^24] |
| ConversationId mismatch | — | Subject changed mid-thread; correlate on `In-Reply-To` header instead[^13] |

**Dead letter queue:** Any message that fails enrichment after max retries should be written to a dead-letter log with the raw Graph response for manual inspection. Never silently discard signals.

***

## 13. Privacy Considerations

| Principle | Implementation |
|---|---|
| **Data minimisation** | Capture only the `$select` fields explicitly defined in this spec; never use `GET /me/messages` without `$select` (returns all fields by default)[^38] |
| **No attachment content** | `hasAttachments` flag only; attachment binary content is never fetched |
| **Body retention policy** | Store stripped body text in the signal queue; implement a configurable TTL (default: 90 days) after which body text is purged, retaining metadata only |
| **Local processing only** | Signal queue and intelligence layer must remain on-device; body text must not be transmitted to third-party LLM APIs without explicit user consent per message class |
| **Consent transparency** | Display a clear manifest of what is read, what is stored, and how long before OAuth consent is requested |
| **BCC confidentiality** | `bccRecipients` is only visible in the sender's own sent message; it is captured but must never be surfaced in relationship graphs involving third parties who were not BCC'd |
| **Folder exclusions** | Allow user to exclude specific folders (e.g., Personal, Health) from ingestion scope; implement via folder-level delta subscription opt-out |
| **Token storage** | MSAL token cache must be stored in macOS Keychain, not in plaintext files |
| **Audit log** | Maintain a local audit log of every API call made (endpoint, timestamp, response code) for user transparency and debugging |

***

## 14. Better Approaches: Recommendations with Evidence

### 14.1 Webhooks + Delta Query Hybrid (Recommended)

Pure polling introduces unnecessary API calls and risks throttling; pure webhooks risk missed events on subscription expiry. Microsoft's own documentation explicitly states: *"Webhooks and delta query are often used better together... use webhook notifications as the trigger to make delta query calls. You should also ensure that your application has a backstop polling threshold."* This hybrid is the production-grade pattern and is what Timed should implement.[^21]

### 14.2 Use `internetMessageId` as Primary Key, Not Graph `id`

Graph's `id` is folder-specific and changes on move. The RFC5322 `internetMessageId` is stable across moves, client changes, and providers. Use it as the idempotent signal key and for cross-referencing `In-Reply-To` / `References` headers to reconstruct thread continuity when `conversationId` breaks (e.g., subject changes).[^13][^12]

### 14.3 Use `uniqueBody` for LLM Input, Not `body`

The `body` field includes all quoted prior messages in a thread, consuming unnecessary LLM tokens and introducing duplicate content. `uniqueBody` returns only the new content in the current message. This is a significant cost optimization for high-volume mailboxes.[^12]

### 14.4 Immutable IDs for Folder-Agnostic Tracking

Add the `Prefer: IdType="ImmutableId"` request header to all delta calls. This makes Graph return stable message IDs that do not change when messages are moved between folders, eliminating the need to rekey signals on folder moves.[^12]

### 14.5 Skip IMAP

While IMAP IDLE offers near-zero latency push, it provides none of the rich metadata (conversationId, conversationIndex, inferenceClassification, categories) available from Graph, has no delta token mechanism for efficient incremental sync, requires a persistent TCP connection, and uses legacy basic-auth patterns. For a macOS intelligence layer targeting Microsoft 365 mailboxes, Graph is strictly superior.[^39][^40][^41]

***

## 15. Acceptance Criteria

### Initial Full Sync
- [ ] All mail folders discovered via `mailFolders/delta` before message sync begins
- [ ] Messages fetched with all fields in the `$select` list defined in §3.2
- [ ] `deltaLink` persisted per folder after initial sync completes
- [ ] Deduplication by `internetMessageId` enforced at write time
- [ ] Initial sync of a 10,000-message mailbox completes without 429 errors

### Incremental Sync
- [ ] Webhook subscription created for Inbox and Sent Items at minimum
- [ ] Webhook subscription renewed at least 60 minutes before expiry
- [ ] Delta query triggered within 30 seconds of webhook notification receipt
- [ ] Backstop delta poll runs every 15 minutes regardless of webhook activity
- [ ] 410 Gone response triggers full folder re-sync within 60 seconds
- [ ] Deleted messages produce a `email_deleted` signal event

### Signal Quality
- [ ] `is_reply` computed correctly for 100% of reply messages (validated against `In-Reply-To` header cross-check)
- [ ] `thread_depth` matches `conversationIndex` byte length formula for sampled messages
- [ ] `response_latency_s` is null for non-reply messages and non-null for all replies where parent message exists in local store
- [ ] HTML stripped from body text before queuing; no raw `<` characters in `body_text` field

### Rate Limit Compliance
- [ ] No more than 3 concurrent Graph calls at any time (semaphore enforced)
- [ ] All 429 responses result in a wait ≥ `Retry-After` seconds before retry
- [ ] No more than 10,000 requests to a single mailbox within any 10-minute window
- [ ] `x-ms-throttle-limit-percentage` header is read and logged; alert when > 0.8

### Reliability
- [ ] Token refresh handled silently via MSAL `acquire_token_silent` for access tokens within their 1-hour TTL[^34]
- [ ] Re-auth UI surface triggered correctly when refresh token expires (14-day inactivity)[^34]
- [ ] All API calls logged to local audit file with timestamp and response code
- [ ] Dead-letter queue populated for any message failing after 7 retries

### Privacy
- [ ] Attachment binary content never fetched or stored
- [ ] Signal queue body text purged after configurable TTL (default 90 days)
- [ ] Folder exclusion list respected; no signals ingested from excluded folders
- [ ] MSAL token cache stored exclusively in macOS Keychain

---

## References

1. [Mail.Read - Microsoft Graph Permissions Explorer](https://graphpermissions.merill.net/permission/Mail.Read) - This article lists all the Microsoft Graph APIs and your tenant data that can be accessed by the app...

2. [What is the Correct Microsoft Graph API Permission for Reading ...](https://stackoverflow.com/questions/74645702/what-is-the-correct-microsoft-graph-api-permission-for-reading-mailbox-to-specif) - Application permissions allows the app to read mail in all mailboxes without a signed-in user where ...

3. [Microsoft Graph API Sensitive Email Properties Update](https://devblogs.microsoft.com/microsoft365dev/graph-api-updates-to-sensitive-email-properties/) - Starting 12/31/2026, we'll restrict sensitive email properties updates on non-draft messages. Add Ma...

4. [mailFolder: delta - Microsoft Graph v1.0](https://learn.microsoft.com/en-us/graph/api/mailfolder-delta?view=graph-rest-1.0) - This allows you to maintain and synchronize a local store of a user's mail folders without having to...

5. [How can MS Graph API Get Message List, for a given user and ...](https://learn.microsoft.com/en-us/answers/questions/2074020/how-can-ms-graph-api-get-message-list-for-a-given) - How can MS Graph API Get Message List, for a given user and mailbox, using delta retrieve more than ...

6. [Use delta query to track changes in Microsoft Graph data](https://learn.microsoft.com/en-us/graph/delta-query-overview) - Delta query, also called change tracking, enables applications to discover newly created, updated, o...

7. [message: delta - Microsoft Graph v1.0](https://learn.microsoft.com/en-us/graph/api/message-delta?view=graph-rest-1.0) - Microsoft Graph automatically encodes any specified parameters into the token portion of the @odata....

8. [Get message - Microsoft Graph v1.0](https://learn.microsoft.com/en-us/graph/api/message-get?view=graph-rest-1.0) - Retrieve the properties and relationships of a message object. You can use the $value parameter to g...

9. [Microsoft Graph api webhook for emails](https://learn.microsoft.com/en-us/answers/questions/5733790/microsoft-graph-api-webhook-for-emails) - When using Microsoft Graph API webhooks for email subscriptions, it is possible to receive multiple ...

10. [Question About Renewing Microsoft Graph Outlook Message ...](https://learn.microsoft.com/en-us/answers/questions/5726066/question-about-renewing-microsoft-graph-outlook-me) - Renewing Microsoft Graph change notification subscriptions every 3 days is generally acceptable, as ...

11. [Microsoft Graph change notifications - YouTube](https://www.youtube.com/watch?v=IxAq40_pmlU) - ... notification lifecycle with Microsoft Graph by creating and managing, and renewing Microsoft Gra...

12. [message resource type - Microsoft Graph v1.0](https://learn.microsoft.com/en-us/graph/api/resources/message?view=graph-rest-1.0) - To get the headers of a message, apply the $select query parameter in a get message operation. Addin...

13. [Conversation id changes after editing subject? - Microsoft Q&A](https://learn.microsoft.com/en-us/answers/questions/1194303/conversation-id-changes-after-editing-subject) - If the subject of the email thread changes, Exchange applies a new ConversationTopic value and new C...

14. [Microsoft Graph send email api conversation Index is different](https://stackoverflow.com/questions/67723319/microsoft-graph-send-email-api-conversation-index-is-different) - ConversationIndex of mail sent via API is different than recipients' replies to the same mail. Due t...

15. [Update message - Microsoft Graph v1.0](https://learn.microsoft.com/en-us/graph/api/message-update?view=graph-rest-1.0) - Use the PATCH operation to add, update, or delete your own app-specific data in custom properties of...

16. [microsoft-graph-docs-contrib/api-reference/beta/resources/message ...](https://github.com/microsoftgraph/microsoft-graph-docs-contrib/blob/main/api-reference/beta/resources/message.md) - The set includes message headers indicating the network path taken by a message from the sender to t...

17. [ConversationIndex Property (Message Object) - Microsoft Learn](https://learn.microsoft.com/en-us/previous-versions/exchange-server/exchange-10/ms528174(v=exchg.10)) - ConversationIndex Property (Message Object). The ConversationIndex property specifies the index to t...

18. [How can we use message: delta to sync ALL folders and subfolders?](https://learn.microsoft.com/en-us/answers/questions/2085861/how-can-we-use-message-delta-to-sync-all-folders-a) - The message:delta endpoint in Microsoft Graph is designed to track changes in messages within a spec...

19. [MS Graph API Get Message List delta Pagination always return ...](https://learn.microsoft.com/en-us/answers/questions/643983/ms-graph-api-get-message-list-delta-pagination-alw) - The items that being returned is limited to 5000 records only. Even though we have more that 5000 re...

20. [Graph api /users/{id}/mailFolders/{id}/messages/delta only lists up to ...](https://learn.microsoft.com/en-us/answers/questions/622314/graph-api-users-((id))-mailfolders-((id))-messages) - We've met an issue that users/{id}/mailFolders/{id}/messages/delta in graph api lists only up to 500...

21. [Best practices for working with Microsoft Graph](https://learn.microsoft.com/en-us/graph/best-practices-concept) - Webhooks and delta query are often used better together, because if you use delta query alone, you n...

22. [Eliminate polling Microsoft Graph with delta query - YouTube](https://www.youtube.com/watch?v=Pa_p98ZrKE8) - In this video, you'll learn how the delta query can be used to help avoid Microsoft Graph requests f...

23. [Microsoft Graph email webhook subscriptions expiring in 1 day ...](https://learn.microsoft.com/en-us/answers/questions/5525734/microsoft-graph-email-webhook-subscriptions-expiri) - Expected Behavior (per documentation): Rich notification webhooks on emails should support up to 7 d...

24. [Receive change notifications through webhooks - Microsoft Graph](https://learn.microsoft.com/en-us/graph/change-notifications-delivery-webhooks) - You can create a subscription to the resource for which you want to be notified of changes. While th...

25. [Throttling Limit for get mail from office 365 using graph api](https://learn.microsoft.com/en-us/answers/questions/1284905/throttling-limit-for-get-mail-from-office-365-usin) - According to the documentation, the throttling limit threshold for the Microsoft Graph API is 10,000...

26. [What is the maximum number of emails that can be sent per minute ...](https://learn.microsoft.com/en-us/answers/questions/2258712/what-is-the-maximum-number-of-emails-that-can-be-s) - 30 messages per minute is the maximum allowed. Despite the Graph API's high request threshold, the E...

27. [Microsoft Graph service-specific throttling limits](https://learn.microsoft.com/en-us/graph/throttling-limits) - A maximum of four requests per second per app can be issued on a given team. A maximum of one reques...

28. [Graph API - Increase Rate Limiting/ Throttling - Microsoft Q&A](https://learn.microsoft.com/en-us/answers/questions/219222/graph-api-increase-rate-limiting-throttling) - Reduce the number of operations per request. · Reduce the frequency of calls. · Avoid immediate retr...

29. [Graph Api rate limits - Microsoft Q&A](https://learn.microsoft.com/en-us/answers/questions/5589984/graph-api-rate-limits) - Microsoft Graph returns an HTTP 429 Too Many Requests response when throttling occurs, along with a ...

30. [microsoft graph api - Using sendMail is regularly returning 429 error](https://stackoverflow.com/questions/41862194/using-sendmail-is-regularly-returning-429-error) - The problem is that there is no explanation for when the emails are suddenly no longer going to be s...

31. [A beginners guide to Microsoft Graph API rate limiting in Intune](https://msendpointmgr.com/2025/11/08/graph-api-rate-limiting-in-intune/) - Learn how to handle HTTP 429 rate limiting when working with Microsoft Graph API. Understand Retry-A...

32. [Improve Microsoft Graph PowerShell Performance with Batching](https://ourcloudnetwork.com/improve-microsoft-graph-powershell-performance-with-batching/) - Request batching enables applications to combine multiple requests to Microsoft Graph to improve per...

33. [Get access on behalf of a user - Microsoft Graph](https://learn.microsoft.com/en-us/graph/auth-v2-user) - Access tokens are short lived, and the app must refresh them after they expire to continue accessing...

34. [Handling refresh tokens in Azure (Microsoft graph) delegation flow](https://learn.microsoft.com/en-us/answers/questions/1622996/handling-refresh-tokens-in-azure-(microsoft-graph)) - MSAL provides the acquireTokenSilent method, which checks the expiration of the access token and att...

35. [Issue with Refresh Token Acquisition in MSAL Node.js Application](https://learn.microsoft.com/en-sg/answers/questions/2238370/issue-with-refresh-token-acquisition-in-msal-node) - Our application is unable to obtain a refresh token when authenticating with Microsoft Graph API usi...

36. [Detections - Understanding Relationship Strength – Mimecast](https://mimecastsupport.zendesk.com/hc/en-us/articles/33859968154515-Detections-Understanding-Relationship-Strength) - This score is derived from the AI graph and is used to surface whether there has been strong communi...

37. [Email Security Scoring: How Behavioral Analytics Work - Mailbird](https://www.getmailbird.com/email-behavioral-analytics-security-scoring/) - Behavioral analytics in email security examines your communication patterns to detect abnormal activ...

38. [List messages - Microsoft Graph v1.0](https://learn.microsoft.com/en-us/graph/api/user-list-messages?view=graph-rest-1.0) - This API uses the $skip value to keep count of all the items it has gone through in the user's mailb...

39. [Self-Hosted Email Threat Detection: Real-Time Monitoring, Multi ...](https://dev.to/kserude/self-hosted-email-threat-detection-real-time-monitoring-multi-stage-enrichment-and-llm-verdicts-2dlk) - Mechanistically, the LLM tokenizes input data, processes it through neural layers, and outputs proba...

40. [Microsoft Graph API vs. IMAP/POP3 - which is better for reading mails?](https://stackoverflow.com/questions/59253363/microsoft-graph-api-vs-imap-pop3-which-is-better-for-reading-mails) - So the point is how you want to read your email. If you are developing your own app, using Microsoft...

41. [Mail Handling via Graph API by Microsoft - Ex Libris Idea Exchange](https://ideas.exlibrisgroup.com/forums/308173-alma/suggestions/48710078-mail-handling-via-graph-api-by-microsoft) - I am writing to highlight the technical advantages of using Microsoft Graph API over SMTP for our em...

