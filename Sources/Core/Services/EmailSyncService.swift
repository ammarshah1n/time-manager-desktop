// EmailSyncService.swift — Timed Core
// Background actor that polls Graph delta API for new emails,
// upserts them to Supabase, and triggers the classify-email Edge Function.

import Foundation
import CryptoKit
import Dependencies
import Network
import os

// MARK: - Insert payload (mutable fields for initial insert)

/// Encodable payload for inserting a new email message row.
/// Unlike `EmailMessageRow` (which is the read model), this sets classification
/// fields to nil/defaults so the Edge Function can fill them.
private struct EmailMessageInsert: Encodable, Sendable {
    let id: UUID
    let workspaceId: UUID
    let emailAccountId: UUID
    let graphMessageId: String
    let graphThreadId: String?
    let fromAddress: String
    let fromName: String?
    let subject: String
    let snippet: String?
    let receivedAt: String
    let triageBucket: String?
    let triageConfidence: Float?
    let triageSource: String?
    let isQuestion: Bool
    let isCcFyi: Bool
    let isQuickReply: Bool
    let parsedPriority: Int?
    let parsedEstimateMinutes: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case workspaceId = "workspace_id"
        case emailAccountId = "email_account_id"
        case graphMessageId = "graph_message_id"
        case graphThreadId = "graph_thread_id"
        case fromAddress = "from_address"
        case fromName = "from_name"
        case subject
        case snippet
        case receivedAt = "received_at"
        case triageBucket = "triage_bucket"
        case triageConfidence = "triage_confidence"
        case triageSource = "triage_source"
        case isQuestion = "is_question"
        case isCcFyi = "is_cc_fyi"
        case isQuickReply = "is_quick_reply"
        case parsedPriority = "parsed_priority"
        case parsedEstimateMinutes = "parsed_estimate_minutes"
    }
}

// MARK: - EmailSyncService

actor EmailSyncService {
    static let shared = EmailSyncService()

    private var deltaLink: String?
    private var syncTask: Task<Void, Never>?
    private var isRunning = false
    private var currentEmailAccountId: UUID?

    /// Default polling interval in seconds.
    var pollInterval: TimeInterval = 60

    // MARK: - Folder-move tracking (in-memory, lost on restart — fine for v1)

    /// Maps graphMessageId → parentFolderId last seen for that message.
    private var knownFolders: [String: String] = [:]

    /// Tracks when each knownFolders entry was last updated.
    private var knownFoldersTimestamps: [String: Date] = [:]

    /// Caches folderId → displayName to avoid repeated Graph API calls.
    private var folderNameCache: [String: String] = [:]

    /// Whether the folder cache has been pre-warmed this session.
    private var folderCacheWarmed = false

    // MARK: - Reply latency social graph (in-memory, persisted to Supabase)

    /// sender_address → [latency_minutes] for all observed outbound replies.
    private var senderReplyLatencies: [String: [Double]] = [:]

    /// conversationId → (fromAddress, receivedDateTime) of the most recent inbound message.
    /// Used to compute reply latency when an outbound message appears in the same thread.
    private var inboundMessagesByThread: [String: (fromAddress: String, receivedAt: Date)] = [:]

    /// conversationId → number of messages seen during this app session.
    private var observedThreadDepths: [String: Int] = [:]

    // MARK: - Dependencies

    @Dependency(\.graphClient) private var graphClient
    @Dependency(\.supabaseClient) private var supabaseClient

    private let supabaseURL: String = {
        ProcessInfo.processInfo.environment["SUPABASE_URL"]
            ?? "https://fpmjuufefhtlwbfinxlx.supabase.co"
    }()

    private let supabaseAnonKey: String = {
        ProcessInfo.processInfo.environment["SUPABASE_ANON_KEY"]
            ?? "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImZwbWp1dWZlZmh0bHdiZmlueGx4Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzQ5MTMxMDEsImV4cCI6MjA5MDQ4OTEwMX0.VUtjezhFMpwrcVMXltyYmU2n0Xazi9lvhuwAQlKOTO4"
    }()

    // MARK: - DeltaLink Persistence

    private func loadDeltaLink(for accountId: UUID) {
        deltaLink = UserDefaults.standard.string(forKey: "deltaLink_\(accountId)")
    }

    private func saveDeltaLink(for accountId: UUID) {
        if let deltaLink {
            UserDefaults.standard.set(deltaLink, forKey: "deltaLink_\(accountId)")
        } else {
            UserDefaults.standard.removeObject(forKey: "deltaLink_\(accountId)")
        }
    }

    // MARK: - Known Folders Persistence

    private func loadKnownFolders(for accountId: UUID) {
        if let data = UserDefaults.standard.data(forKey: "knownFolders_\(accountId)"),
           let dict = try? JSONDecoder().decode([String: String].self, from: data) {
            knownFolders = dict
        }
        if let tsData = UserDefaults.standard.data(forKey: "knownFoldersTS_\(accountId)"),
           let dict = try? JSONDecoder().decode([String: Date].self, from: tsData) {
            knownFoldersTimestamps = dict
        }
    }

    private func saveKnownFolders(for accountId: UUID) {
        // Prune: cap at 5000 entries, removing oldest by timestamp
        if knownFolders.count > 5000 {
            let sorted = knownFoldersTimestamps.sorted { $0.value < $1.value }
            let toRemove = sorted.prefix(knownFolders.count - 5000)
            for (key, _) in toRemove {
                knownFolders.removeValue(forKey: key)
                knownFoldersTimestamps.removeValue(forKey: key)
            }
        }
        if let data = try? JSONEncoder().encode(knownFolders) {
            UserDefaults.standard.set(data, forKey: "knownFolders_\(accountId)")
        }
        if let tsData = try? JSONEncoder().encode(knownFoldersTimestamps) {
            UserDefaults.standard.set(tsData, forKey: "knownFoldersTS_\(accountId)")
        }
    }

    // MARK: - Folder Cache Pre-warm

    /// Fetches all mail folders from Graph and populates folderNameCache.
    /// Called once per session on first sync to avoid per-message folder lookups.
    private func preWarmFolderCache(accessToken: String) async {
        guard !folderCacheWarmed else { return }
        do {
            let folders = try await graphClient.fetchMailFolders(accessToken)
            for folder in folders {
                folderNameCache[folder.id] = folder.displayName
            }
            folderCacheWarmed = true
            TimedLogger.graph.info("Pre-warmed folder cache with \(folders.count) folder(s)")
        } catch {
            TimedLogger.graph.warning(
                "Failed to pre-warm folder cache: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    // MARK: - Start / Stop

    /// Starts the background sync loop. Idempotent — calling while already running is a no-op.
    ///
    /// - Parameter tokenProvider: Closure that returns a fresh Graph access token on each call.
    ///   Handles MSAL silent refresh + interactive fallback internally.
    func start(
        tokenProvider: @escaping @Sendable () async throws -> String,
        workspaceId: UUID,
        emailAccountId: UUID,
        profileId: UUID? = nil
    ) async {
        guard !isRunning else {
            TimedLogger.graph.info("EmailSyncService.start called but already running — skipping")
            return
        }

        // Wave 2 B1 — check the server-side sync gate. When the executive's
        // `email_sync_driver` column is `server`, Trigger.dev owns Graph
        // polling and the Swift client must no-op to avoid double writes.
        // We fail-open (proceed as `client`) on any error so an auth or
        // network blip doesn't silently stop local sync.
        if !(await shouldSyncLocally(profileId: profileId)) {
            TimedLogger.graph.info("EmailSyncService: sync_driver=server, Swift polling disabled")
            return
        }

        isRunning = true
        currentEmailAccountId = emailAccountId
        loadDeltaLink(for: emailAccountId)
        loadKnownFolders(for: emailAccountId)
        TimedLogger.graph.info("EmailSyncService starting (interval: \(self.pollInterval)s)")

        syncTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                do {
                    let count = try await self.syncOnce(
                        tokenProvider: tokenProvider,
                        workspaceId: workspaceId,
                        emailAccountId: emailAccountId,
                        profileId: profileId
                    )
                    if count > 0 {
                        TimedLogger.graph.info("EmailSyncService synced \(count) message(s)")
                    }
                } catch {
                    TimedLogger.graph.error("EmailSyncService sync error: \(error.localizedDescription, privacy: .public)")
                }
                try? await Task.sleep(for: .seconds(self.pollInterval))
            }
        }
    }

    /// Stops the background sync loop.
    func stop() {
        TimedLogger.graph.info("EmailSyncService stopping")
        if let accountId = currentEmailAccountId {
            saveDeltaLink(for: accountId)
            saveKnownFolders(for: accountId)
        }
        syncTask?.cancel()
        syncTask = nil
        isRunning = false
    }

    // MARK: - Wave 2 B1: server-side sync gate

    /// Returns `true` when the Swift `EmailSyncService` should drive Graph
    /// polling locally, `false` when Trigger.dev's `graph-delta-sync` task
    /// owns it (executive row has `email_sync_driver = 'server'`).
    ///
    /// Fail-open: any error path returns `true` so a transient Supabase
    /// blip never silently halts local sync.
    private func shouldSyncLocally(profileId: UUID?) async -> Bool {
        // No signed-in executive → local-only mode, nothing to consult.
        guard let profileId else { return true }
        let driver = await fetchEmailSyncDriver(executiveId: profileId)
        return driver != "server"
    }

    /// Reads `public.executives.email_sync_driver` via the Supabase REST API
    /// using the anon key. We don't go through `supabaseClient` here because
    /// the B1 file boundary for this wave doesn't allow extending that
    /// dependency's surface, and the existing `supabaseURL` /
    /// `supabaseAnonKey` wiring on this actor is already plumbed.
    ///
    /// Returns `"client"`, `"server"`, or a best-effort default of
    /// `"client"` on any failure so the caller fails-open.
    private func fetchEmailSyncDriver(executiveId: UUID) async -> String {
        guard var components = URLComponents(
            string: "\(supabaseURL)/rest/v1/executives"
        ) else {
            return "client"
        }
        components.queryItems = [
            URLQueryItem(name: "id", value: "eq.\(executiveId.uuidString.lowercased())"),
            URLQueryItem(name: "select", value: "email_sync_driver"),
            URLQueryItem(name: "limit", value: "1")
        ]
        guard let url = components.url else { return "client" }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(supabaseAnonKey)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode) else {
                TimedLogger.graph.warning(
                    "fetchEmailSyncDriver: non-2xx, defaulting to client"
                )
                return "client"
            }
            guard
                let decoded = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
                let row = decoded.first,
                let driver = row["email_sync_driver"] as? String
            else {
                return "client"
            }
            return driver
        } catch {
            TimedLogger.graph.warning(
                "fetchEmailSyncDriver failed: \(error.localizedDescription, privacy: .public); defaulting to client"
            )
            return "client"
        }
    }

    // MARK: - Single sync pass

    /// Performs one delta sync pass. Returns the number of messages processed.
    ///
    /// - Parameter tokenProvider: Closure that returns a fresh Graph access token on each call.
    func syncOnce(
        tokenProvider: @escaping @Sendable () async throws -> String,
        workspaceId: UUID,
        emailAccountId: UUID,
        profileId: UUID? = nil
    ) async throws -> Int {
        // Skip sync if offline
        let isConnected = await NetworkMonitor.shared.isConnected
        guard isConnected else {
            TimedLogger.graph.info("EmailSyncService skipping sync — offline")
            return 0
        }

        // Acquire a fresh token at the start of each sync pass
        let accessToken = try await tokenProvider()

        // Pre-warm the folder name cache on first sync
        await preWarmFolderCache(accessToken: accessToken)

        var totalProcessed = 0
        var currentDeltaLink = deltaLink
        var hasMore = true

        while hasMore {
            let result: DeltaResult
            do {
                result = try await graphClient.fetchDeltaMessages(
                    "",               // accountId — not used by the live implementation
                    currentDeltaLink, // nil on first call → full delta
                    accessToken
                )
            } catch GraphError.syncStateNotFound {
                // 410 Gone — delta token expired or invalid. Reset to full re-sync.
                TimedLogger.graph.warning("Delta token expired (410 syncStateNotFound) — resetting to full sync")
                deltaLink = nil
                if let accountId = currentEmailAccountId {
                    saveDeltaLink(for: accountId)
                }
                currentDeltaLink = nil
                continue
            }

            for message in result.messages {
                do {
                    // Detect folder moves before upserting
                    if let profileId, let folderId = message.parentFolderId {
                        // Fetch a fresh token for folder-move detection (may be long-running)
                        let moveToken = try await tokenProvider()
                        await detectFolderMove(
                            message: message,
                            currentFolderId: folderId,
                            accessToken: moveToken,
                            workspaceId: workspaceId,
                            profileId: profileId
                        )
                    }

                    // Track reply latency for the social graph
                    trackReplyLatency(message: message, workspaceId: workspaceId, profileId: profileId)

                    let row = Self.makeInsertPayload(
                        from: message,
                        workspaceId: workspaceId,
                        emailAccountId: emailAccountId
                    )
                    try await upsertMessage(row)
                    await emitEmailObservationsIfPossible(
                        for: message,
                        emailMessageId: row.id,
                        explicitProfileId: profileId
                    )

                    // Compute sender importance from reply latency before classifying
                    let senderAddress = message.from?.emailAddress.address ?? "unknown"
                    let senderImportance = senderImportanceScore(senderAddress)

                    await triggerClassification(
                        messageId: row.id,
                        workspaceId: workspaceId,
                        senderImportance: senderImportance
                    )
                    totalProcessed += 1
                } catch {
                    TimedLogger.graph.error(
                        "Failed to process message \(message.id, privacy: .public): \(error.localizedDescription, privacy: .public)"
                    )
                }
            }

            hasMore = result.hasMore
            currentDeltaLink = result.nextDeltaLink
        }

        // Persist the delta link for the next call
        deltaLink = currentDeltaLink
        if let accountId = currentEmailAccountId {
            saveDeltaLink(for: accountId)
        }

        // Save known folders after each sync pass
        if let accountId = currentEmailAccountId {
            saveKnownFolders(for: accountId)
        }

        return totalProcessed
    }

    // MARK: - Supabase upsert

    private func upsertMessage(_ payload: EmailMessageInsert) async throws {
        // Convert insert payload to EmailMessageRow for the dependency client
        let row = EmailMessageRow(
            id: payload.id,
            workspaceId: payload.workspaceId,
            emailAccountId: payload.emailAccountId,
            graphMessageId: payload.graphMessageId,
            graphThreadId: payload.graphThreadId,
            fromAddress: payload.fromAddress,
            fromName: payload.fromName,
            subject: payload.subject,
            snippet: payload.snippet,
            receivedAt: ISO8601DateFormatter().date(from: payload.receivedAt) ?? Date(),
            triageBucket: payload.triageBucket,
            triageConfidence: payload.triageConfidence,
            triageSource: payload.triageSource,
            isQuestion: payload.isQuestion,
            isQuickReply: payload.isQuickReply,
            isCcFyi: payload.isCcFyi
        )
        try await supabaseClient.upsertEmailMessage(row)
    }

    // MARK: - Tier 0 observation emission

    private func emitEmailObservationsIfPossible(
        for message: GraphEmailMessage,
        emailMessageId: UUID,
        explicitProfileId: UUID?
    ) async {
        guard let profileId = await resolvedExecutiveId(explicitProfileId) else { return }
        let occurredAt = Self.parseGraphTimestamp(message.receivedDateTime) ?? Date()
        let eventType = emailEventType(for: message)
        let threadDepth = recordThreadDepth(for: message.conversationId)
        let recipientCount = message.toRecipients.count + message.ccRecipients.count
        let responseLatencySeconds = responseLatencySeconds(for: message, occurredAt: occurredAt)
        let senderCategory = senderCategory(for: message)
        let senderAddress = message.from?.emailAddress.address
        let senderName = message.from?.emailAddress.name
        let summary = emailSummary(
            for: message,
            eventType: eventType,
            senderName: senderName,
            senderAddress: senderAddress,
            recipientCount: recipientCount
        )
        let rawData = makeEmailRawData(
            senderCategory: senderCategory,
            responseLatencySeconds: responseLatencySeconds,
            threadDepth: threadDepth,
            recipientCount: recipientCount
        )

        let observation = Tier0Observation(
            profileId: profileId,
            occurredAt: occurredAt,
            source: .email,
            eventType: eventType,
            entityId: emailMessageId,
            entityType: "email_message",
            summary: summary,
            rawData: rawData,
            importanceScore: 0.5
        )
        do {
            try await Tier0Writer.shared.recordObservation(observation)
        } catch {
            TimedLogger.graph.error("Tier0 observation write failed: \(error.localizedDescription)")
        }

        let counterpartyAddress = observationCounterpartyAddress(for: message)
        let importance = importanceLabel(for: senderImportanceScore(counterpartyAddress ?? senderAddress ?? ""))
        let emailObservation = EmailObservationRow(
            id: UUID(),
            executiveId: profileId,
            observedAt: occurredAt,
            graphMessageId: message.id,
            senderAddress: senderAddress,
            senderName: senderName,
            recipientCount: recipientCount,
            subjectHash: subjectHash(for: message.subject),
            folder: folderName(for: message.parentFolderId),
            importance: importance,
            isReply: isReply(message.subject),
            isForward: isForward(message.subject),
            responseLatencySeconds: responseLatencySeconds,
            threadDepth: threadDepth,
            categories: [senderCategory]
        )
        do {
            try await persistEmailObservation(emailObservation)
        } catch {
            TimedLogger.graph.error("Email observation persist failed: \(error.localizedDescription)")
        }
    }

    private func resolvedExecutiveId(_ explicitProfileId: UUID?) async -> UUID? {
        if let explicitProfileId {
            return explicitProfileId
        }
        return await MainActor.run { AuthService.shared.executiveId }
    }

    private func emailEventType(for message: GraphEmailMessage) -> String {
        let userEmail = OnboardingUserPrefs.email.lowercased()
        let fromAddress = message.from?.emailAddress.address.lowercased() ?? ""
        let isSent = !userEmail.isEmpty && fromAddress == userEmail
        if isSent {
            return isReply(message.subject) ? "email.response_sent" : "email.sent"
        }
        return "email.received"
    }

    private func emailSummary(
        for message: GraphEmailMessage,
        eventType: String,
        senderName: String?,
        senderAddress: String?,
        recipientCount: Int
    ) -> String {
        if eventType == "email.sent" {
            if recipientCount > 0 {
                let label = recipientCount == 1 ? "recipient" : "recipients"
                return "Email sent to \(recipientCount) \(label)"
            }
            return "Email sent"
        }
        let senderLabel = senderName?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let senderLabel, !senderLabel.isEmpty {
            return "Email received from \(senderLabel)"
        }
        if let senderAddress, !senderAddress.isEmpty {
            return "Email received from \(senderAddress)"
        }
        return "Email received"
    }

    private func makeEmailRawData(
        senderCategory: String,
        responseLatencySeconds: Int?,
        threadDepth: Int?,
        recipientCount: Int
    ) -> [String: AnyCodable] {
        var rawData: [String: AnyCodable] = [
            "sender_category": AnyCodable(senderCategory),
            "recipient_count": AnyCodable(recipientCount)
        ]

        if let responseLatencySeconds {
            rawData["response_time_sec"] = AnyCodable(responseLatencySeconds)
        }
        if let threadDepth {
            rawData["thread_depth"] = AnyCodable(threadDepth)
        }

        return rawData
    }

    private func recordThreadDepth(for conversationId: String?) -> Int? {
        guard let conversationId, !conversationId.isEmpty else { return nil }
        observedThreadDepths[conversationId, default: 0] += 1
        return observedThreadDepths[conversationId]
    }

    private func responseLatencySeconds(for message: GraphEmailMessage, occurredAt: Date) -> Int? {
        guard emailEventType(for: message) == "email.sent",
              let conversationId = message.conversationId,
              let inbound = inboundMessagesByThread[conversationId] else {
            return nil
        }

        let latency = Int(occurredAt.timeIntervalSince(inbound.receivedAt))
        return latency > 0 ? latency : nil
    }

    private func senderCategory(for message: GraphEmailMessage) -> String {
        let userEmail = OnboardingUserPrefs.email.lowercased()
        let address = message.from?.emailAddress.address.lowercased() ?? ""
        let name = message.from?.emailAddress.name ?? ""

        if !userEmail.isEmpty, address == userEmail {
            return "self"
        }
        if name.isFamilyMember(surname: OnboardingUserPrefs.familySurname) {
            return "family"
        }

        let addressDomain = address.split(separator: "@").last.map(String.init)
        let userDomain = userEmail.split(separator: "@").last.map(String.init)
        if let addressDomain, let userDomain, !addressDomain.isEmpty, addressDomain == userDomain {
            return "internal"
        }

        return "external"
    }

    private func observationCounterpartyAddress(for message: GraphEmailMessage) -> String? {
        if emailEventType(for: message) == "email.sent" {
            return message.toRecipients.first?.emailAddress.address
        }
        return message.from?.emailAddress.address
    }

    private func importanceLabel(for score: Double) -> String {
        if score >= 0.8 { return "high" }
        if score <= 0.2 { return "low" }
        return "normal"
    }

    private func folderName(for folderId: String?) -> String? {
        guard let folderId else { return nil }
        return folderNameCache[folderId] ?? folderId
    }

    private func isReply(_ subject: String?) -> Bool {
        guard let subject else { return false }
        return subject.lowercased().hasPrefix("re:")
    }

    private func isForward(_ subject: String?) -> Bool {
        guard let subject else { return false }
        return subject.lowercased().hasPrefix("fw:") || subject.lowercased().hasPrefix("fwd:")
    }

    private func subjectHash(for subject: String?) -> String? {
        guard let subject, !subject.isEmpty else { return nil }
        let digest = SHA256.hash(data: Data(subject.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func persistEmailObservation(_ observation: EmailObservationRow) async throws {
        let isConnected = await NetworkMonitor.shared.isConnected
        guard isConnected, supabaseClient.rawClient != nil else {
            try await enqueueEmailObservationOffline(observation)
            return
        }

        try await supabaseClient.insertEmailObservation(observation)
    }

    private func enqueueEmailObservationOffline(_ observation: EmailObservationRow) async throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let payload = try encoder.encode(observation)
        try await OfflineSyncQueue.shared.enqueue(
            operationType: "email_observations.insert",
            payload: payload
        )
    }

    // MARK: - Edge Function: classify-email

    private func triggerClassification(messageId: UUID, workspaceId: UUID, senderImportance: Double = 0.5) async {
        guard let url = URL(string: "\(supabaseURL)/functions/v1/classify-email") else {
            TimedLogger.graph.error("Invalid classify-email URL")
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(supabaseAnonKey)", forHTTPHeaderField: "Authorization")

        let body: [String: Any] = [
            "message_id": messageId.uuidString,
            "workspace_id": workspaceId.uuidString,
            "sender_importance": senderImportance,
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            if statusCode < 200 || statusCode >= 300 {
                TimedLogger.graph.warning(
                    "classify-email returned \(statusCode) for message \(messageId.uuidString, privacy: .public)"
                )
            }
        } catch {
            TimedLogger.graph.error(
                "classify-email request failed for \(messageId.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    // MARK: - Reply latency social graph

    /// Detects outbound replies and computes reply latency against the original inbound message.
    /// Outbound = message.from matches user's email. Reply = same conversationId as a tracked inbound.
    private func trackReplyLatency(message: GraphEmailMessage, workspaceId: UUID, profileId: UUID?) {
        let fromAddress = message.from?.emailAddress.address.lowercased() ?? ""
        let userEmail = OnboardingUserPrefs.email.lowercased()

        guard !fromAddress.isEmpty, !userEmail.isEmpty else { return }
        guard let conversationId = message.conversationId, !conversationId.isEmpty else { return }

        let messageDate = Self.parseGraphTimestamp(message.receivedDateTime)

        if fromAddress == userEmail {
            // Outbound message — check if we have an inbound in this thread
            if let inbound = inboundMessagesByThread[conversationId],
               let sentDate = messageDate {
                let latencyMinutes = sentDate.timeIntervalSince(inbound.receivedAt) / 60.0
                guard latencyMinutes > 0 else { return }

                let sender = inbound.fromAddress.lowercased()
                senderReplyLatencies[sender, default: []].append(latencyMinutes)

                TimedLogger.triage.info(
                    "Reply latency to \(sender, privacy: .public): \(String(format: "%.1f", latencyMinutes)) min"
                )

                // Persist to Supabase
                if let profileId {
                    let avgLatency = {
                        let latencies = senderReplyLatencies[sender] ?? [latencyMinutes]
                        return latencies.reduce(0, +) / Double(latencies.count)
                    }()
                    Task {
                        await persistSenderLatency(
                            workspaceId: workspaceId,
                            profileId: profileId,
                            fromAddress: sender,
                            avgLatencyMinutes: avgLatency,
                            sampleSize: senderReplyLatencies[sender]?.count ?? 1
                        )
                    }
                }
            }
        } else {
            // Inbound message — track it for future outbound matching.
            // Only store the latest inbound per thread.
            if let receivedDate = messageDate {
                inboundMessagesByThread[conversationId] = (fromAddress: fromAddress, receivedAt: receivedDate)
            }
        }
    }

    /// Computes sender importance from average reply latency.
    /// < 2 min = very important (1.0), < 10 min = important (0.8),
    /// < 60 min = normal (0.5), > 60 min = low (0.2), no data = neutral (0.5).
    private func senderImportanceScore(_ address: String) -> Double {
        guard let latencies = senderReplyLatencies[address.lowercased()],
              !latencies.isEmpty else { return 0.5 }
        let avgLatency = latencies.reduce(0, +) / Double(latencies.count)
        if avgLatency < 2 { return 1.0 }
        if avgLatency < 10 { return 0.8 }
        if avgLatency < 60 { return 0.5 }
        return 0.2
    }

    /// Persists the rolling average reply latency for a sender to Supabase.
    private func persistSenderLatency(
        workspaceId: UUID,
        profileId: UUID,
        fromAddress: String,
        avgLatencyMinutes: Double,
        sampleSize: Int
    ) async {
        do {
            try await supabaseClient.upsertSenderLatency(
                workspaceId, profileId, fromAddress, avgLatencyMinutes, sampleSize
            )
        } catch {
            TimedLogger.triage.error(
                "Failed to persist sender latency for \(fromAddress, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    // MARK: - Folder-move detection → sender rule learning

    /// Compares the current parentFolderId against what we last saw.
    /// If it changed, the user moved the email — learn a sender rule.
    private func detectFolderMove(
        message: GraphEmailMessage,
        currentFolderId: String,
        accessToken: String,
        workspaceId: UUID,
        profileId: UUID
    ) async {
        let previousFolderId = knownFolders[message.id]
        knownFolders[message.id] = currentFolderId
        knownFoldersTimestamps[message.id] = Date()

        // No previous record → first time seeing this message, nothing to compare
        guard let previousFolderId, previousFolderId != currentFolderId else { return }

        let fromAddress = message.from?.emailAddress.address ?? ""
        guard !fromAddress.isEmpty else { return }

        // Resolve the destination folder name
        let folderName: String
        if let cached = folderNameCache[currentFolderId] {
            folderName = cached
        } else {
            do {
                let name = try await graphClient.fetchFolderName(currentFolderId, accessToken)
                folderNameCache[currentFolderId] = name
                folderName = name
            } catch {
                TimedLogger.triage.error(
                    "Failed to resolve folder \(currentFolderId, privacy: .public): \(error.localizedDescription, privacy: .public)"
                )
                return
            }
        }

        // Map folder display name → triage bucket rule type
        guard let ruleType = Self.folderNameToRuleType(folderName) else {
            TimedLogger.triage.info(
                "Folder move to '\(folderName, privacy: .public)' has no rule mapping — ignoring"
            )
            return
        }

        TimedLogger.triage.info(
            "Folder move detected: \(fromAddress, privacy: .public) → '\(folderName, privacy: .public)' → rule '\(ruleType, privacy: .public)'"
        )

        do {
            try await supabaseClient.upsertSenderRule(workspaceId, profileId, fromAddress, ruleType)
        } catch {
            TimedLogger.triage.error(
                "Failed to upsert sender rule for \(fromAddress, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    /// Maps an Outlook folder display name to a sender rule type.
    /// Returns nil for folders that don't map to a triage action.
    private static func folderNameToRuleType(_ folderName: String) -> String? {
        switch folderName.lowercased().trimmingCharacters(in: .whitespaces) {
        case "black hole", "blackhole", "junk email", "junk", "deleted items", "trash":
            return "black_hole"
        case "inbox", "focused", "important":
            return "inbox_always"
        case "later", "read later", "someday":
            return "later"
        case "delegate", "delegated", "forwarded":
            return "delegate"
        default:
            return nil
        }
    }

    // MARK: - GraphEmailMessage → Insert payload

    private static func makeInsertPayload(
        from message: GraphEmailMessage,
        workspaceId: UUID,
        emailAccountId: UUID
    ) -> EmailMessageInsert {
        let fromAddress = message.from?.emailAddress.address ?? "unknown"
        let fromName = message.from?.emailAddress.name
        let receivedAt = message.receivedDateTime ?? ISO8601DateFormatter().string(from: Date())
        let isFamilySender = (fromName ?? "").isFamilyMember(surname: OnboardingUserPrefs.familySurname)

        // Detect CC/FYI: user is in CC but not in To recipients
        let userEmail = OnboardingUserPrefs.email.lowercased()
        let isInTo = message.toRecipients.contains {
            $0.emailAddress.address.lowercased() == userEmail
        }
        let isInCc = message.ccRecipients.contains {
            $0.emailAddress.address.lowercased() == userEmail
        }
        let isCcFyi = isInCc && !isInTo

        return EmailMessageInsert(
            id: UUID(),
            workspaceId: workspaceId,
            emailAccountId: emailAccountId,
            graphMessageId: message.id,
            graphThreadId: message.conversationId,
            fromAddress: fromAddress,
            fromName: fromName,
            subject: message.subject ?? "(no subject)",
            snippet: message.bodyPreview,
            receivedAt: receivedAt,
            triageBucket: nil,
            triageConfidence: nil,
            triageSource: nil,
            isQuestion: false,
            isCcFyi: isCcFyi,
            isQuickReply: false,
            parsedPriority: isFamilySender ? 10 : nil,
            parsedEstimateMinutes: nil
        )
    }

    private static func parseGraphTimestamp(_ raw: String?) -> Date? {
        guard let raw else { return nil }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fallbackFormatter = ISO8601DateFormatter()

        return formatter.date(from: raw) ?? fallbackFormatter.date(from: raw)
    }
}
