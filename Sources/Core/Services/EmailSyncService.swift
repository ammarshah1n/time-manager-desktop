// EmailSyncService.swift — Timed Core
// Background actor that polls Graph delta API for new emails,
// upserts them to Supabase, and triggers the classify-email Edge Function.

import Foundation
import Dependencies
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

    /// Default polling interval in seconds.
    var pollInterval: TimeInterval = 60

    // MARK: - Folder-move tracking (in-memory, lost on restart — fine for v1)

    /// Maps graphMessageId → parentFolderId last seen for that message.
    private var knownFolders: [String: String] = [:]

    /// Caches folderId → displayName to avoid repeated Graph API calls.
    private var folderNameCache: [String: String] = [:]

    // MARK: - Reply latency social graph (in-memory, persisted to Supabase)

    /// sender_address → [latency_minutes] for all observed outbound replies.
    private var senderReplyLatencies: [String: [Double]] = [:]

    /// conversationId → (fromAddress, receivedDateTime) of the most recent inbound message.
    /// Used to compute reply latency when an outbound message appears in the same thread.
    private var inboundMessagesByThread: [String: (fromAddress: String, receivedAt: Date)] = [:]

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

    // MARK: - Start / Stop

    /// Starts the background sync loop. Idempotent — calling while already running is a no-op.
    func start(accessToken: String, workspaceId: UUID, emailAccountId: UUID, profileId: UUID? = nil) {
        guard !isRunning else {
            TimedLogger.graph.info("EmailSyncService.start called but already running — skipping")
            return
        }
        isRunning = true
        TimedLogger.graph.info("EmailSyncService starting (interval: \(self.pollInterval)s)")

        syncTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                do {
                    let count = try await self.syncOnce(
                        accessToken: accessToken,
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
        syncTask?.cancel()
        syncTask = nil
        isRunning = false
    }

    // MARK: - Single sync pass

    /// Performs one delta sync pass. Returns the number of messages processed.
    func syncOnce(
        accessToken: String,
        workspaceId: UUID,
        emailAccountId: UUID,
        profileId: UUID? = nil
    ) async throws -> Int {
        var totalProcessed = 0
        var currentDeltaLink = deltaLink
        var hasMore = true

        while hasMore {
            let result = try await graphClient.fetchDeltaMessages(
                "",               // accountId — not used by the live implementation
                currentDeltaLink, // nil on first call → full delta
                accessToken
            )

            for message in result.messages {
                do {
                    // Detect folder moves before upserting
                    if let profileId, let folderId = message.parentFolderId {
                        await detectFolderMove(
                            message: message,
                            currentFolderId: folderId,
                            accessToken: accessToken,
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

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fallbackFormatter = ISO8601DateFormatter()

        let messageDate: Date? = {
            guard let raw = message.receivedDateTime else { return nil }
            return formatter.date(from: raw) ?? fallbackFormatter.date(from: raw)
        }()

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

        // Detect CC/FYI: if the user's address isn't in the to: list, they were CC'd
        let ccRecipientCount = message.ccRecipients.count
        let isCcFyi = ccRecipientCount > 0 && message.toRecipients.isEmpty

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
}
