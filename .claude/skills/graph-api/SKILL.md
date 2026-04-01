---
name: graph-api
description: Microsoft Graph API patterns for Timed email + calendar integration
trigger: When working with Microsoft Graph, MSAL, OAuth, email sync, or Outlook calendar
---

# Microsoft Graph API Patterns

## Authentication — MSAL Only

Never implement custom OAuth. Always use MSAL:

```swift
import MSAL

class GraphAuthProvider {
    private let application: MSALPublicClientApplication

    init() throws {
        let config = MSALPublicClientApplicationConfig(
            clientId: ProcessInfo.processInfo.environment["GRAPH_CLIENT_ID"] ?? "",
            redirectUri: "msauth.com.timeblock.app://auth",
            authority: try MSALAADAuthority(
                url: URL(string: "https://login.microsoftonline.com/\(tenantId)")!
            )
        )
        application = try MSALPublicClientApplication(configuration: config)
    }

    func acquireToken() async throws -> String {
        let parameters = MSALInteractiveTokenParameters(
            scopes: ["Mail.ReadWrite", "Calendars.ReadWrite", "offline_access"]
        )
        let result = try await application.acquireToken(with: parameters)
        return result.accessToken
    }

    func acquireTokenSilently(account: MSALAccount) async throws -> String {
        let parameters = MSALSilentTokenParameters(scopes: scopes, account: account)
        let result = try await application.acquireTokenSilent(with: parameters)
        return result.accessToken
    }
}
```

## Delta Queries — Email Sync

Always use delta queries, not full list:

```swift
// First call: no deltaLink
let url = "https://graph.microsoft.com/v1.0/me/mailFolders/inbox/messages/delta"
    + "?$select=subject,from,receivedDateTime,bodyPreview,isRead,toRecipients,ccRecipients,hasAttachments"
    + "&$top=50"

// Subsequent calls: use stored deltaLink
let url = storedDeltaLink // Returns only changes since last sync

// ALWAYS store the @odata.deltaLink from the response
// Store in Supabase: email_accounts.delta_link
```

## Error Handling

```swift
// 429 Throttling — MUST respect Retry-After header
case 429:
    let retryAfter = response.value(forHTTPHeaderField: "Retry-After") ?? "60"
    try await Task.sleep(for: .seconds(Int(retryAfter) ?? 60))
    return try await retry(request)

// 401 Token Expired — refresh silently
case 401:
    let newToken = try await authProvider.acquireTokenSilently(account: account)
    return try await retry(request, token: newToken)

// 503 Service Unavailable — exponential backoff
case 503:
    try await Task.sleep(for: .seconds(pow(2, Double(attempt))))
    return try await retry(request, attempt: attempt + 1)
```

## Security Rules
- Tokens stored in **Keychain only** — never UserDefaults, never plain files
- Request minimum scopes (Mail.ReadWrite, Calendars.ReadWrite, offline_access)
- Refresh tokens proactively (10 min before expiry)
- Never log access tokens — log "token refreshed" events only
- All Graph calls go through `GraphClient.swift` — no inline HTTP calls

## Calendar Operations

```swift
// Read calendar view (events in time range)
GET /me/calendarView?startDateTime=2026-03-28T00:00:00Z&endDateTime=2026-03-29T00:00:00Z

// Create event (write task block)
POST /me/events
{
    "subject": "Task: Review Q1 report",
    "start": { "dateTime": "2026-03-28T14:00:00", "timeZone": "Australia/Adelaide" },
    "end": { "dateTime": "2026-03-28T14:30:00", "timeZone": "Australia/Adelaide" },
    "categories": ["Timed-Action"]
}
```

## NEVER DO
- Never implement custom OAuth flow — always MSAL
- Never poll full mailbox — always delta queries
- Never store tokens outside Keychain
- Never call Graph API outside `GraphClient.swift`
- Never request more scopes than needed
