// GmailClient.swift — Timed Core
// ============================================================
// ALL Gmail API + Google Calendar v3 calls go through this file.
// NOWHERE ELSE. Mirrors the architectural rule on GraphClient.swift.
// If you need Google data, add a method here and call it through
// the GmailClientDependency. No exceptions.
// ============================================================
//
// Auth tokens come in as a parameter (not fetched here). Caller
// (GmailSyncService / GmailCalendarSyncService) acquires the token
// via the AuthService.makeGoogleTokenProvider() closure, which wraps
// GoogleAuth.freshAccessToken() (silent refresh).

import Foundation
import Dependencies
import os

// MARK: - Base URLs

private let gmailBaseURL    = "https://gmail.googleapis.com/gmail/v1"
private let calendarBaseURL = "https://www.googleapis.com/calendar/v3"

// MARK: - Response shapes

/// Single message returned by Gmail's metadata endpoint.
struct GoogleEmailMessage: Codable, Identifiable, Sendable {
    let id: String
    let threadId: String?
    let labelIds: [String]?
    let snippet: String?
    /// Milliseconds since epoch as a string. Gmail returns it as string.
    let internalDate: String?
    let payload: GmailPayload?

    /// Subject extracted from headers, nil if absent.
    var subject: String? { headerValue("Subject") }

    /// "Display Name <addr@host>" raw From header, nil if absent.
    var fromHeader: String? { headerValue("From") }

    /// To header (may be a comma-separated list), nil if absent.
    var toHeader: String? { headerValue("To") }

    /// Cc header (may be a comma-separated list), nil if absent.
    var ccHeader: String? { headerValue("Cc") }

    /// RFC 2822 date string, nil if absent. Prefer internalDate for parsing.
    var dateHeader: String? { headerValue("Date") }

    /// Parses internalDate (epoch ms) as a Swift Date.
    var receivedAt: Date? {
        guard let raw = internalDate, let ms = Double(raw) else { return nil }
        return Date(timeIntervalSince1970: ms / 1000.0)
    }

    private func headerValue(_ name: String) -> String? {
        guard let headers = payload?.headers else { return nil }
        return headers.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame })?.value
    }
}

struct GmailPayload: Codable, Sendable {
    let headers: [GmailHeader]?
}

struct GmailHeader: Codable, Sendable {
    let name: String
    let value: String
}

/// `messages.list` page result.
struct GmailMessageList: Codable, Sendable {
    let messages: [GmailMessageRef]?
    let nextPageToken: String?
    let resultSizeEstimate: Int?
}

struct GmailMessageRef: Codable, Sendable {
    let id: String
    let threadId: String?
}

/// `users.getProfile` result.
struct GmailProfile: Codable, Sendable {
    let emailAddress: String
    let messagesTotal: Int?
    let historyId: String
}

/// `users.history.list` page result.
struct GmailHistoryPage: Codable, Sendable {
    let history: [GmailHistoryRecord]?
    let nextPageToken: String?
    let historyId: String?
}

struct GmailHistoryRecord: Codable, Sendable {
    let id: String?
    let messagesAdded: [GmailHistoryMessageEnvelope]?
}

struct GmailHistoryMessageEnvelope: Codable, Sendable {
    let message: GmailMessageRef
}

/// Outcome of a single Gmail delta pass — analogous to DeltaResult on the
/// Microsoft side.
struct GmailDeltaResult: Sendable {
    let messages: [GoogleEmailMessage]
    /// Next historyId to use as the cursor for the following sync. nil only
    /// when caller should fall back to a full re-sync (HTTP 404 from /history).
    let nextHistoryId: String?
    /// True if the page indicated more pages remain.
    let hasMore: Bool
    /// True iff Gmail returned 404 from /history → cursor expired,
    /// caller must reset and run a full backfill.
    let expired: Bool
}

// MARK: - Calendar v3 shapes

struct GoogleCalendarEvent: Codable, Identifiable, Sendable {
    let id: String
    let status: String?
    let summary: String?
    let location: String?
    let start: GoogleCalendarTime
    let end: GoogleCalendarTime
    let attendees: [GoogleCalendarAttendee]?
    let organizer: GoogleCalendarOrganizer?
    let hangoutLink: String?
}

struct GoogleCalendarTime: Codable, Sendable {
    /// Set when the event has a precise time. ISO8601 with timezone offset.
    let dateTime: String?
    /// Set when the event is all-day. Date only ("YYYY-MM-DD").
    let date: String?
    /// IANA timezone, present alongside dateTime for floating times.
    let timeZone: String?

    var isAllDay: Bool { dateTime == nil && date != nil }
}

struct GoogleCalendarAttendee: Codable, Sendable {
    let email: String?
    let displayName: String?
    let responseStatus: String?
    let optional: Bool?
    let organizer: Bool?
    let `self`: Bool?
}

struct GoogleCalendarOrganizer: Codable, Sendable {
    let email: String?
    let displayName: String?
    let `self`: Bool?
}

struct GoogleCalendarEventList: Codable, Sendable {
    let items: [GoogleCalendarEvent]?
    let nextPageToken: String?
    let nextSyncToken: String?
}

// MARK: - Errors

enum GmailError: Error, LocalizedError {
    case httpError(Int)
    case historyExpired
    case malformedResponse
    case rateLimited

    var errorDescription: String? {
        switch self {
        case .httpError(let code): return "Gmail API HTTP \(code)"
        case .historyExpired: return "Gmail history cursor expired (HTTP 404) — full re-sync required"
        case .malformedResponse: return "Gmail API response could not be decoded"
        case .rateLimited: return "Gmail API rate-limited (HTTP 429)"
        }
    }
}

// MARK: - Dependency Client

struct GmailClientDependency: Sendable {
    /// Returns the user's Gmail profile. Used to seed the initial historyId
    /// cursor and confirm authorization.
    var fetchProfile: @Sendable (String) async throws -> GmailProfile = { _ in
        throw NotImplementedError(methodName: "fetchProfile")
    }

    /// Lists message IDs matching `query`. Pass nil pageToken on first call.
    /// Default query string in caller is `newer_than:30d`.
    var listMessages: @Sendable (String, String?, String) async throws -> GmailMessageList = { _, _, _ in
        throw NotImplementedError(methodName: "listMessages")
    }

    /// Fetches a single message in `metadata` format with Subject/From/To/Cc/Date headers.
    var fetchMessage: @Sendable (String, String) async throws -> GoogleEmailMessage = { _, _ in
        throw NotImplementedError(methodName: "fetchMessage")
    }

    /// Delta sync via /history — returns new messages added since the cursor.
    /// Throws GmailError.historyExpired (404) when the cursor is too old.
    var fetchHistory: @Sendable (String, String) async throws -> GmailDeltaResult = { _, _ in
        throw NotImplementedError(methodName: "fetchHistory")
    }

    /// Returns calendar events between `start` and `end` from the primary calendar.
    var fetchCalendarEvents: @Sendable (Date, Date, String) async throws -> [GoogleCalendarEvent] = { _, _, _ in
        throw NotImplementedError(methodName: "fetchCalendarEvents")
    }
}

extension GmailClientDependency: DependencyKey {
    static let liveValue: GmailClientDependency = .live()
    static let testValue: GmailClientDependency = .init()
}

extension DependencyValues {
    var gmailClient: GmailClientDependency {
        get { self[GmailClientDependency.self] }
        set { self[GmailClientDependency.self] = newValue }
    }
}

// MARK: - Live implementation

extension GmailClientDependency {
    static func live() -> GmailClientDependency {
        GmailClientDependency(
            fetchProfile: { token in
                try await getJSON(
                    url: "\(gmailBaseURL)/users/me/profile",
                    accessToken: token,
                    type: GmailProfile.self
                )
            },
            listMessages: { query, pageToken, token in
                var components = URLComponents(string: "\(gmailBaseURL)/users/me/messages")!
                var items: [URLQueryItem] = [
                    .init(name: "q", value: query),
                    .init(name: "maxResults", value: "100"),
                    // Skip Spam + Trash — Gmail's bulk list otherwise returns them.
                    .init(name: "labelIds", value: "INBOX")
                ]
                if let pageToken { items.append(.init(name: "pageToken", value: pageToken)) }
                components.queryItems = items
                let url = components.url!.absoluteString
                return try await getJSON(url: url, accessToken: token, type: GmailMessageList.self)
            },
            fetchMessage: { messageId, token in
                var components = URLComponents(
                    string: "\(gmailBaseURL)/users/me/messages/\(messageId)"
                )!
                components.queryItems = [
                    .init(name: "format", value: "metadata"),
                    .init(name: "metadataHeaders", value: "Subject"),
                    .init(name: "metadataHeaders", value: "From"),
                    .init(name: "metadataHeaders", value: "To"),
                    .init(name: "metadataHeaders", value: "Cc"),
                    .init(name: "metadataHeaders", value: "Date")
                ]
                let url = components.url!.absoluteString
                return try await getJSON(url: url, accessToken: token, type: GoogleEmailMessage.self)
            },
            fetchHistory: { startHistoryId, token in
                var components = URLComponents(string: "\(gmailBaseURL)/users/me/history")!
                components.queryItems = [
                    .init(name: "startHistoryId", value: startHistoryId),
                    .init(name: "historyTypes", value: "messageAdded"),
                    .init(name: "labelId", value: "INBOX"),
                    .init(name: "maxResults", value: "100")
                ]
                let url = components.url!
                var request = URLRequest(url: url)
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                request.setValue("application/json", forHTTPHeaderField: "Accept")
                let (data, response) = try await URLSession.shared.data(for: request)
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                if status == 404 {
                    googleFileLog("GmailClient.fetchHistory: 404 — historyId expired (\(startHistoryId))")
                    throw GmailError.historyExpired
                }
                if status == 429 { throw GmailError.rateLimited }
                guard (200..<300).contains(status) else {
                    googleFileLog("GmailClient.fetchHistory: HTTP \(status)")
                    throw GmailError.httpError(status)
                }
                let page = try JSONDecoder().decode(GmailHistoryPage.self, from: data)
                // Hydrate each new message via fetchMessage.
                var hydrated: [GoogleEmailMessage] = []
                let added = (page.history ?? [])
                    .flatMap { $0.messagesAdded ?? [] }
                    .map { $0.message.id }
                for messageId in added {
                    do {
                        let msg = try await fetchSingleMetadata(id: messageId, token: token)
                        hydrated.append(msg)
                    } catch {
                        googleFileLog("GmailClient.fetchHistory: hydrate \(messageId) FAILED: \(error.localizedDescription)")
                    }
                }
                return GmailDeltaResult(
                    messages: hydrated,
                    nextHistoryId: page.historyId,
                    hasMore: page.nextPageToken != nil,
                    expired: false
                )
            },
            fetchCalendarEvents: { start, end, token in
                var components = URLComponents(
                    string: "\(calendarBaseURL)/calendars/primary/events"
                )!
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime]
                components.queryItems = [
                    .init(name: "timeMin", value: formatter.string(from: start)),
                    .init(name: "timeMax", value: formatter.string(from: end)),
                    .init(name: "singleEvents", value: "true"),
                    .init(name: "orderBy", value: "startTime"),
                    .init(name: "maxResults", value: "250")
                ]
                let url = components.url!.absoluteString
                let page = try await getJSON(
                    url: url,
                    accessToken: token,
                    type: GoogleCalendarEventList.self
                )
                return page.items ?? []
            }
        )
    }
}

// MARK: - Private helpers

/// Hydrates a single message by id. Used inside fetchHistory's loop.
private func fetchSingleMetadata(id: String, token: String) async throws -> GoogleEmailMessage {
    var components = URLComponents(string: "\(gmailBaseURL)/users/me/messages/\(id)")!
    components.queryItems = [
        .init(name: "format", value: "metadata"),
        .init(name: "metadataHeaders", value: "Subject"),
        .init(name: "metadataHeaders", value: "From"),
        .init(name: "metadataHeaders", value: "To"),
        .init(name: "metadataHeaders", value: "Cc"),
        .init(name: "metadataHeaders", value: "Date")
    ]
    let url = components.url!.absoluteString
    return try await getJSON(url: url, accessToken: token, type: GoogleEmailMessage.self)
}

/// Generic JSON GET with bearer auth. Throws GmailError on non-2xx.
private func getJSON<T: Decodable>(
    url: String,
    accessToken: String,
    type: T.Type
) async throws -> T {
    guard let parsed = URL(string: url) else {
        throw GmailError.malformedResponse
    }
    var request = URLRequest(url: parsed)
    request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    let (data, response) = try await URLSession.shared.data(for: request)
    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
    if status == 429 { throw GmailError.rateLimited }
    guard (200..<300).contains(status) else {
        if let body = String(data: data, encoding: .utf8) {
            googleFileLog("GmailClient: HTTP \(status) for \(parsed.path) — \(body.prefix(240))")
        }
        throw GmailError.httpError(status)
    }
    do {
        return try JSONDecoder().decode(T.self, from: data)
    } catch {
        googleFileLog("GmailClient: decode failed \(parsed.path): \(error.localizedDescription)")
        throw GmailError.malformedResponse
    }
}
