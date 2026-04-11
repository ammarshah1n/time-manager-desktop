// GraphClient.swift — Timed Core
// ============================================================
// ALL Microsoft Graph API calls go through this file.
// NOWHERE ELSE. Not in features. Not in services. Not in views.
// If you need Graph data, add a method here and call it through
// the GraphClientDependency. No exceptions.
// ============================================================
// See: CLAUDE.md → Architecture Rules
// See: docs/runbooks/graph-oauth-setup.md

import Foundation
import MSAL
import Dependencies
import os

// MARK: - Graph Base URL

private let graphBaseURL = "https://graph.microsoft.com/v1.0"

// MARK: - Graph Response Types

struct DeltaResult: Sendable {
    let messages: [GraphEmailMessage]
    let nextDeltaLink: String?
    let hasMore: Bool
}

struct GraphEmailMessage: Codable, Identifiable, Sendable {
    let id: String
    let conversationId: String?
    let subject: String?
    let from: GraphRecipientWrapper?
    let receivedDateTime: String?
    let bodyPreview: String?
    let toRecipients: [GraphRecipientWrapper]
    let ccRecipients: [GraphRecipientWrapper]
    let parentFolderId: String?
    let isDraft: Bool?

    enum CodingKeys: String, CodingKey {
        case id
        case conversationId
        case subject
        case from
        case receivedDateTime
        case bodyPreview
        case toRecipients
        case ccRecipients
        case parentFolderId
        case isDraft
    }
}

struct GraphRecipientWrapper: Codable, Sendable {
    let emailAddress: GraphRecipient
}

struct GraphRecipient: Codable, Sendable {
    let address: String
    let name: String?
}

struct GraphSubscription: Codable, Identifiable, Sendable {
    let id: String
    let expirationDateTime: String
    let notificationUrl: String
}

struct GraphCalendarEvent: Codable, Identifiable, Sendable {
    let id: String
    let subject: String?
    let start: GraphDateTimeTimeZone
    let end: GraphDateTimeTimeZone
    let isAllDay: Bool
    let isCancelled: Bool
    let location: GraphLocation?
    let attendees: [GraphCalendarAttendee]?
    let isOrganizer: Bool?
    let responseStatus: GraphResponseStatus?
}

struct GraphDateTimeTimeZone: Codable, Sendable {
    let dateTime: String
    let timeZone: String
}

struct GraphLocation: Codable, Sendable {
    let displayName: String?
}

struct GraphCalendarAttendee: Codable, Sendable {
    let emailAddress: GraphRecipient?
}

struct GraphResponseStatus: Codable, Sendable {
    let response: String?
    let time: String?
}

// MARK: - Error Types

struct NotImplementedError: Error, LocalizedError {
    let methodName: String
    var errorDescription: String? {
        "GraphClient.\(methodName) is not yet implemented. Keys pending."
    }
}

// MARK: - Dependency Client

struct GraphClientDependency: Sendable {
    /// Authenticates via MSAL and returns an access token.
    var authenticate: @Sendable (String, String) async throws -> String = { _, _ in
        throw NotImplementedError(methodName: "authenticate")
    }

    /// Fetches new/changed messages using Graph delta query.
    /// Pass nil deltaLink on first call; pass returned nextDeltaLink on subsequent calls.
    var fetchDeltaMessages: @Sendable (String, String?, String) async throws -> DeltaResult = { _, _, _ in
        throw NotImplementedError(methodName: "fetchDeltaMessages")
    }

    /// Moves a message to the specified folder.
    var moveMessage: @Sendable (String, String, String) async throws -> Void = { _, _, _ in
        throw NotImplementedError(methodName: "moveMessage")
    }

    /// Creates a mail folder and returns the new folderId.
    var createFolder: @Sendable (String, String) async throws -> String = { _, _ in
        throw NotImplementedError(methodName: "createFolder")
    }

    /// Registers a Graph change notification webhook. Returns the subscription.
    var registerWebhook: @Sendable (String, String) async throws -> GraphSubscription = { _, _ in
        throw NotImplementedError(methodName: "registerWebhook")
    }

    /// Renews an existing webhook subscription before it expires.
    var renewWebhook: @Sendable (String, String) async throws -> Void = { _, _ in
        throw NotImplementedError(methodName: "renewWebhook")
    }

    /// Fetches a mail folder's display name by its ID.
    /// params: (folderId, accessToken) → displayName
    var fetchFolderName: @Sendable (String, String) async throws -> String = { _, _ in
        throw NotImplementedError(methodName: "fetchFolderName")
    }

    /// Fetches all mail folders. Returns array of (id, displayName) tuples.
    /// params: (accessToken) → [(id, displayName)]
    var fetchMailFolders: @Sendable (String) async throws -> [(id: String, displayName: String)] = { _ in
        throw NotImplementedError(methodName: "fetchMailFolders")
    }

    /// Fetches calendar events within the given date range.
    var fetchCalendarEvents: @Sendable (Date, Date, String) async throws -> [GraphCalendarEvent] = { _, _, _ in
        throw NotImplementedError(methodName: "fetchCalendarEvents")
    }
}

// MARK: - DependencyKey

extension GraphClientDependency: DependencyKey {
    static let liveValue: GraphClientDependency = .live()
    static let testValue: GraphClientDependency = .init()
}

extension DependencyValues {
    var graphClient: GraphClientDependency {
        get { self[GraphClientDependency.self] }
        set { self[GraphClientDependency.self] = newValue }
    }
}

// MARK: - Azure App Config

private enum AzureConfig {
    static let clientId  = ProcessInfo.processInfo.environment["GRAPH_CLIENT_ID"]
                        ?? "89e8f1c6-3cc4-47fb-83ae-f7e0528eb860"
    static let tenantId  = ProcessInfo.processInfo.environment["GRAPH_TENANT_ID"]
                        ?? "d20d9117-7f0f-45e9-87b3-2bb194f6be6b"
    static let redirectUri = "msauth.com.timed.app://auth"
    static let scopes    = ["Mail.Read", "Mail.ReadWrite", "Mail.Send",
                            "Calendars.Read", "Calendars.ReadWrite", "offline_access", "User.Read"]
}

// MARK: - Sendable box for ObjC types

/// Wraps a non-Sendable ObjC type that is documented as thread-safe.
private struct SendableBox<T>: @unchecked Sendable {
    let value: T
}

// MARK: - Live Implementation

extension GraphClientDependency {
    static func live() -> GraphClientDependency {
        // Build MSAL public client once — shared across all @Sendable closures.
        let msalApp: MSALPublicClientApplication? = {
            guard let authorityURL = URL(string: "https://login.microsoftonline.com/\(AzureConfig.tenantId)"),
                  let authority = try? MSALAADAuthority(url: authorityURL) else {
                return nil
            }
            let config = MSALPublicClientApplicationConfig(
                clientId: AzureConfig.clientId,
                redirectUri: AzureConfig.redirectUri,
                authority: authority
            )
            config.multipleCloudsSupported = false
            return try? MSALPublicClientApplication(configuration: config)
        }()

        // Box the ObjC app instance once so all @Sendable closures can capture it safely.
        guard let msalApp else {
            TimedLogger.graph.error("MSAL initialisation failed — Graph API unavailable")
            return GraphClientDependency()
        }
        let appBox = SendableBox(value: msalApp)

        return GraphClientDependency(

            // MARK: authenticate
            // params: (accountId: String, loginHint: String) → accessToken
            // accountId: persisted MSAL account identifier (pass "" on first sign-in)
            // loginHint: UPN / email hint shown in the picker (pass "" if unknown)
            authenticate: { accountId, loginHint in
                let accounts = (try? appBox.value.allAccounts()) ?? []

                // 1. Try silent with a matching stored account.
                let candidateAccount = accounts.first(where: { $0.identifier == accountId })
                    ?? accounts.first

                if let account = candidateAccount {
                    let silentParams = MSALSilentTokenParameters(
                        scopes: AzureConfig.scopes,
                        account: account
                    )
                    silentParams.forceRefresh = false
                    if let result = try? await appBox.value.acquireTokenSilent(with: silentParams) {
                        return result.accessToken
                    }
                    // Silent failed — fall through to interactive.
                }

                // 2. Interactive — all MSAL UI work runs on MainActor via Task continuation.
                return try await withCheckedThrowingContinuation { continuation in
                    Task { @MainActor in
                        do {
                            let webviewParams = MSALWebviewParameters(
                                authPresentationViewController: NSApp.keyWindow?.contentViewController
                                    ?? NSViewController()
                            )
                            let params = MSALInteractiveTokenParameters(
                                scopes: AzureConfig.scopes,
                                webviewParameters: webviewParams
                            )
                            params.promptType = .selectAccount
                            if !loginHint.isEmpty { params.loginHint = loginHint }
                            let result = try await appBox.value.acquireToken(with: params)
                            continuation.resume(returning: result.accessToken)
                        } catch {
                            continuation.resume(throwing: error)
                        }
                    }
                }
            },

            // MARK: fetchDeltaMessages
            // params: (accountId, deltaLink?, accessToken)
            fetchDeltaMessages: { _, deltaLink, accessToken in
                let urlString = deltaLink
                    ?? "\(graphBaseURL)/me/messages/delta"
                    + "?$select=id,subject,from,receivedDateTime,parentFolderId,bodyPreview,conversationId,toRecipients,ccRecipients,isDraft"
                    + "&$top=50"

                guard let url = URL(string: urlString) else {
                    TimedLogger.graph.error("Invalid delta messages URL: \(urlString, privacy: .public)")
                    throw GraphError.httpError(0)
                }
                var request = URLRequest(url: url)
                request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

                let (data, response) = try await URLSession.shared.data(for: request)
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
                if statusCode == 410 {
                    throw GraphError.syncStateNotFound
                }
                guard statusCode == 200 else {
                    throw GraphError.httpError(statusCode)
                }

                let decoded = try JSONDecoder().decode(GraphDeltaResponse.self, from: data)
                return DeltaResult(
                    messages: decoded.value,
                    nextDeltaLink: decoded.odataNextLink ?? decoded.odataDeltaLink,
                    hasMore: decoded.odataNextLink != nil
                )
            },

            // MARK: moveMessage
            // params: (messageId, destinationFolderId, accessToken)
            moveMessage: { messageId, destinationFolderId, accessToken in
                let request = graphRequest(
                    path: "/me/messages/\(messageId)/move",
                    method: "POST",
                    accessToken: accessToken,
                    body: try JSONEncoder().encode(["destinationId": destinationFolderId])
                )
                let (_, response) = try await URLSession.shared.data(for: request)
                guard (response as? HTTPURLResponse)?.statusCode == 201 else {
                    throw GraphError.httpError((response as? HTTPURLResponse)?.statusCode ?? 0)
                }
            },

            // MARK: createFolder
            // params: (displayName, accessToken) → folderId
            createFolder: { displayName, accessToken in
                let request = graphRequest(
                    path: "/me/mailFolders",
                    method: "POST",
                    accessToken: accessToken,
                    body: try JSONEncoder().encode(["displayName": displayName])
                )
                let (data, response) = try await URLSession.shared.data(for: request)
                guard (response as? HTTPURLResponse)?.statusCode == 201 else {
                    throw GraphError.httpError((response as? HTTPURLResponse)?.statusCode ?? 0)
                }
                let decoded = try JSONDecoder().decode(GraphFolder.self, from: data)
                return decoded.id
            },

            // MARK: registerWebhook
            // params: (notificationUrl, accessToken) → GraphSubscription
            registerWebhook: { notificationUrl, accessToken in
                let expiry = ISO8601DateFormatter()
                    .string(from: Date().addingTimeInterval(3 * 24 * 3600))
                let bodyDict: [String: String] = [
                    "changeType": "created,updated",
                    "notificationUrl": notificationUrl,
                    "resource": "me/mailFolders/inbox/messages",
                    "expirationDateTime": expiry,
                    "clientState": "timed-\(UUID().uuidString)"
                ]
                let request = graphRequest(
                    path: "/subscriptions",
                    method: "POST",
                    accessToken: accessToken,
                    body: try JSONEncoder().encode(bodyDict)
                )
                let (data, response) = try await URLSession.shared.data(for: request)
                guard (response as? HTTPURLResponse)?.statusCode == 201 else {
                    throw GraphError.httpError((response as? HTTPURLResponse)?.statusCode ?? 0)
                }
                return try JSONDecoder().decode(GraphSubscription.self, from: data)
            },

            // MARK: renewWebhook
            // params: (subscriptionId, accessToken)
            renewWebhook: { subscriptionId, accessToken in
                let newExpiry = ISO8601DateFormatter()
                    .string(from: Date().addingTimeInterval(3 * 24 * 3600))
                let request = graphRequest(
                    path: "/subscriptions/\(subscriptionId)",
                    method: "PATCH",
                    accessToken: accessToken,
                    body: try JSONEncoder().encode(["expirationDateTime": newExpiry])
                )
                let (_, response) = try await URLSession.shared.data(for: request)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                    throw GraphError.httpError((response as? HTTPURLResponse)?.statusCode ?? 0)
                }
            },

            // MARK: fetchFolderName
            // params: (folderId, accessToken) → displayName
            fetchFolderName: { folderId, accessToken in
                let request = graphRequest(
                    path: "/me/mailFolders/\(folderId)",
                    method: "GET",
                    accessToken: accessToken
                )
                let (data, response) = try await URLSession.shared.data(for: request)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                    throw GraphError.httpError((response as? HTTPURLResponse)?.statusCode ?? 0)
                }
                let decoded = try JSONDecoder().decode(GraphFolder.self, from: data)
                return decoded.displayName
            },

            // MARK: fetchMailFolders
            // params: (accessToken) → [(id, displayName)]
            fetchMailFolders: { accessToken in
                let request = graphRequest(
                    path: "/me/mailFolders?$top=100",
                    method: "GET",
                    accessToken: accessToken
                )
                let (data, response) = try await URLSession.shared.data(for: request)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                    throw GraphError.httpError((response as? HTTPURLResponse)?.statusCode ?? 0)
                }
                let decoded = try JSONDecoder().decode(GraphFoldersResponse.self, from: data)
                return decoded.value.map { ($0.id, $0.displayName) }
            },

            // MARK: fetchCalendarEvents
            // params: (startDate, endDate, accessToken) → [GraphCalendarEvent]
            fetchCalendarEvents: { startDate, endDate, accessToken in
                let formatter = ISO8601DateFormatter()
                let start = formatter.string(from: startDate)
                let end   = formatter.string(from: endDate)
                let raw = "\(graphBaseURL)/me/calendarView"
                    + "?startDateTime=\(start)"
                    + "&endDateTime=\(end)"
                    + "&$select=id,subject,start,end,isAllDay,isCancelled,location,attendees,isOrganizer,responseStatus"
                    + "&$top=100"
                guard let url = URL(string: raw.addingPercentEncoding(
                    withAllowedCharacters: .urlQueryAllowed) ?? raw
                ) else {
                    throw GraphError.httpError(0)
                }
                var request = URLRequest(url: url)
                request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

                let (data, response) = try await URLSession.shared.data(for: request)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                    throw GraphError.httpError((response as? HTTPURLResponse)?.statusCode ?? 0)
                }
                let decoded = try JSONDecoder().decode(GraphCalendarResponse.self, from: data)
                return decoded.value
            }
        )
    }
}

// MARK: - Helpers

private extension GraphClientDependency {
    /// Builds a bearer-authenticated URLRequest against the Graph v1.0 API.
    /// Returns nil if the URL is invalid — callers must handle this case.
    static func graphRequest(
        path: String,
        method: String = "GET",
        accessToken: String,
        body: Data? = nil
    ) -> URLRequest {
        guard let url = URL(string: "\(graphBaseURL)\(path)") else {
            TimedLogger.graph.error("Invalid Graph API path: \(path, privacy: .public)")
            // Return a request with an empty URL — it will fail at the network layer.
            // This preserves the existing return type without breaking the API.
            var fallback = URLRequest(url: URL(string: graphBaseURL)!)
            fallback.httpMethod = method
            return fallback
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let body {
            request.httpBody = body
        }
        return request
    }
}

// MARK: - Graph API Response Types (private decoding contracts)

private struct GraphDeltaResponse: Decodable {
    let value: [GraphEmailMessage]
    let odataNextLink: String?
    let odataDeltaLink: String?

    enum CodingKeys: String, CodingKey {
        case value
        case odataNextLink  = "@odata.nextLink"
        case odataDeltaLink = "@odata.deltaLink"
    }
}

private struct GraphFolder: Decodable {
    let id: String
    let displayName: String
}

private struct GraphFoldersResponse: Decodable {
    let value: [GraphFolder]
}

private struct GraphCalendarResponse: Decodable {
    let value: [GraphCalendarEvent]
}

// MARK: - Graph Error

enum GraphError: Error, Sendable {
    case httpError(Int)
    case noAccount
    case tokenExpired
    case syncStateNotFound
}
