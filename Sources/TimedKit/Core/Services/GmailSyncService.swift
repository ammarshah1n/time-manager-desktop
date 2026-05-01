// GmailSyncService.swift — Timed Core
// Background actor that polls Gmail's history API for new messages,
// upserts them to the same `email_messages` Supabase table the
// Microsoft pipeline uses, and triggers the classify-email Edge
// Function. Mirror of EmailSyncService but for Gmail.
//
// Gmail's historyId cursor is the analogue of Microsoft Graph's deltaLink.
// On first run we fetch the user profile (which includes the seed
// historyId) and run a 30-day backfill via messages.list. On subsequent
// runs we call /history?startHistoryId=X for incremental updates.
//
// What's intentionally simpler than EmailSyncService for v1:
//   - No folder-move detection (Gmail uses labels; semantics differ).
//   - No reply-latency social graph (Microsoft path covers this signal).
//   - Same Tier 0 observation emission and classify-email trigger so
//     the downstream intelligence engine treats Gmail messages identically.

import Foundation
import CryptoKit
import Dependencies
import os

// MARK: - Insert payload (mirrors EmailMessageInsert from EmailSyncService)

private struct GmailMessageInsert: Encodable, Sendable {
    let id: UUID
    let workspaceId: UUID
    let emailAccountId: UUID
    /// Stuffs the Gmail message ID into the existing graph_message_id column.
    /// Gmail and Microsoft IDs don't collide in practice (different formats);
    /// when a `provider` column lands later, this struct grows a field.
    let graphMessageId: String
    let graphThreadId: String?
    let fromAddress: String
    let fromName: String?
    let subject: String
    let snippet: String?
    let receivedAt: String
    let isCcFyi: Bool

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
        case isCcFyi = "is_cc_fyi"
    }
}

// MARK: - GmailSyncService

actor GmailSyncService {
    static let shared = GmailSyncService()

    private var historyId: String?
    private var syncTask: Task<Void, Never>?
    private var isRunning = false
    private var currentEmailAccountId: UUID?

    /// Default polling interval. Gmail history is cheap; 60s matches Microsoft.
    var pollInterval: TimeInterval = 60

    @Dependency(\.gmailClient) private var gmailClient
    @Dependency(\.supabaseClient) private var supabaseClient

    private let supabaseURL: String = {
        ProcessInfo.processInfo.environment["SUPABASE_URL"]
            ?? "https://fpmjuufefhtlwbfinxlx.supabase.co"
    }()

    // MARK: - History cursor persistence

    private func loadHistoryId(for accountId: UUID) {
        historyId = UserDefaults.standard.string(forKey: "gmailHistoryId_\(accountId)")
    }

    private func saveHistoryId(for accountId: UUID) {
        if let historyId {
            UserDefaults.standard.set(historyId, forKey: "gmailHistoryId_\(accountId)")
        } else {
            UserDefaults.standard.removeObject(forKey: "gmailHistoryId_\(accountId)")
        }
    }

    // MARK: - Start / Stop

    /// Idempotent start. `tokenProvider` returns a fresh Google access token —
    /// AuthService.makeGoogleTokenProvider() wraps GoogleAuth.freshAccessToken().
    func start(
        tokenProvider: @escaping @Sendable () async throws -> String,
        workspaceId: UUID,
        emailAccountId: UUID,
        profileId: UUID? = nil
    ) async {
        guard !isRunning else {
            googleFileLog("GmailSync.start: already running, skipping")
            return
        }
        isRunning = true
        currentEmailAccountId = emailAccountId
        loadHistoryId(for: emailAccountId)
        googleFileLog("GmailSync.start: ws=\(workspaceId) account=\(emailAccountId) profile=\(profileId?.uuidString ?? "nil") cursor=\(historyId ?? "nil")")

        syncTask = Task { [weak self] in
            guard let self else { return }
            var hasLinkedGmail = false
            var iteration = 0
            while !Task.isCancelled {
                iteration += 1
                googleFileLog("GmailSync.poll[\(iteration)]: starting syncOnce")
                do {
                    let count = try await self.syncOnce(
                        tokenProvider: tokenProvider,
                        workspaceId: workspaceId,
                        emailAccountId: emailAccountId,
                        profileId: profileId
                    )
                    googleFileLog("GmailSync.poll[\(iteration)]: synced \(count) message(s)")
                    if count > 0 {
                        TimedLogger.graph.info("GmailSyncService synced \(count) message(s)")
                    }
                    if !hasLinkedGmail, let pid = profileId {
                        hasLinkedGmail = true
                        await self.markGmailLinked(profileId: pid)
                        googleFileLog("GmailSync: stamped gmail_linked=true on exec \(pid)")
                    }
                } catch {
                    googleFileLog("GmailSync.poll[\(iteration)]: ERROR \(error.localizedDescription)")
                    TimedLogger.graph.error("GmailSyncService sync error: \(error.localizedDescription, privacy: .public)")
                }
                try? await Task.sleep(for: .seconds(self.pollInterval))
            }
        }
    }

    func stop() {
        googleFileLog("GmailSync.stop")
        if let accountId = currentEmailAccountId {
            saveHistoryId(for: accountId)
        }
        syncTask?.cancel()
        syncTask = nil
        isRunning = false
    }

    /// Stamps `executives.gmail_linked = true` on the first successful sync.
    /// Mirror of `markOutlookLinked` in EmailSyncService — orb gates on the
    /// OR of these two flags before claiming inbox knowledge.
    private func markGmailLinked(profileId: UUID) async {
        guard let supabase = SupabaseClientDependency.live().rawClient else { return }
        do {
            struct GmailLinkedUpdate: Encodable, Sendable { let gmail_linked: Bool }
            try await supabase
                .from("executives")
                .update(GmailLinkedUpdate(gmail_linked: true))
                .eq("id", value: profileId.uuidString)
                .execute()
            TimedLogger.graph.info("GmailSyncService stamped executives.gmail_linked = true")
        } catch {
            TimedLogger.graph.warning("Failed to stamp gmail_linked: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Single sync pass

    /// Returns the count of messages processed.
    func syncOnce(
        tokenProvider: @escaping @Sendable () async throws -> String,
        workspaceId: UUID,
        emailAccountId: UUID,
        profileId: UUID? = nil
    ) async throws -> Int {
        let isConnected = await NetworkMonitor.shared.isConnected
        guard isConnected else {
            TimedLogger.graph.info("GmailSyncService skipping sync — offline")
            return 0
        }

        let accessToken = try await tokenProvider()

        // Bootstrap: first run has no historyId. Run a 30-day backfill via
        // messages.list, then stash the profile's historyId as the cursor for
        // future delta calls.
        if historyId == nil {
            let processed = try await runInitialBackfill(
                accessToken: accessToken,
                workspaceId: workspaceId,
                emailAccountId: emailAccountId,
                profileId: profileId
            )
            // Seed cursor from /profile after backfill so we don't replay
            // anything when /history runs next.
            do {
                let profile = try await gmailClient.fetchProfile(accessToken)
                historyId = profile.historyId
                if let accountId = currentEmailAccountId { saveHistoryId(for: accountId) }
                googleFileLog("GmailSync.bootstrap: seeded historyId=\(profile.historyId) for \(profile.emailAddress)")
            } catch {
                googleFileLog("GmailSync.bootstrap: profile fetch FAILED \(error.localizedDescription)")
            }
            return processed
        }

        // Delta path.
        guard let cursor = historyId else { return 0 }
        let result: GmailDeltaResult
        do {
            result = try await gmailClient.fetchHistory(cursor, accessToken)
        } catch GmailError.historyExpired {
            // Cursor too old — drop it and rerun as initial backfill next pass.
            TimedLogger.graph.warning("Gmail history cursor expired — full re-sync next pass")
            historyId = nil
            if let accountId = currentEmailAccountId { saveHistoryId(for: accountId) }
            return 0
        } catch GmailError.httpError(let status) where status == 401 {
            // Token rejected — surface a reconnect notification.
            TimedLogger.graph.error("Gmail 401 — surfacing reconnect notification")
            Task { @MainActor in
                await PlatformNotifications.shared.deliver(
                    title: "Gmail reconnect needed",
                    body: "Tap to reconnect your Google account. Mail and calendar sync paused until you do.",
                    tier: .interrupt,
                    identifier: "gmail-reconnect",
                    userInfo: ["timed.action": "reconnect-google"]
                )
            }
            throw GmailError.httpError(401)
        }

        var processed = 0
        var hadFailures = false
        for msg in result.messages {
            do {
                try await persist(message: msg, workspaceId: workspaceId, emailAccountId: emailAccountId, profileId: profileId)
                processed += 1
            } catch {
                hadFailures = true
                TimedLogger.graph.error("GmailSync persist failed: \(error.localizedDescription, privacy: .public)")
            }
        }

        // Move cursor forward.
        if !hadFailures, let next = result.nextHistoryId {
            historyId = next
            if let accountId = currentEmailAccountId { saveHistoryId(for: accountId) }
        } else if hadFailures {
            TimedLogger.graph.warning("GmailSync: not advancing historyId after processing failures")
        }
        return processed
    }

    // MARK: - Initial backfill

    /// 30-day backfill via messages.list — mirrors the Microsoft 30-day
    /// initial clamp in GraphClient.fetchDeltaMessages's first pass.
    private func runInitialBackfill(
        accessToken: String,
        workspaceId: UUID,
        emailAccountId: UUID,
        profileId: UUID?
    ) async throws -> Int {
        var processed = 0
        var pageToken: String? = nil
        let query = "newer_than:30d"

        repeat {
            let page = try await gmailClient.listMessages(query, pageToken, accessToken)
            let refs = page.messages ?? []
            googleFileLog("GmailSync.backfill: page returned \(refs.count) refs")
            for ref in refs {
                do {
                    let msg = try await gmailClient.fetchMessage(ref.id, accessToken)
                    try await persist(message: msg, workspaceId: workspaceId, emailAccountId: emailAccountId, profileId: profileId)
                    processed += 1
                } catch {
                    googleFileLog("GmailSync.backfill: hydrate \(ref.id) FAILED: \(error.localizedDescription)")
                }
            }
            pageToken = page.nextPageToken
        } while pageToken != nil

        return processed
    }

    // MARK: - Persist + classify

    private func persist(
        message: GoogleEmailMessage,
        workspaceId: UUID,
        emailAccountId: UUID,
        profileId: UUID?
    ) async throws {
        let parsed = parseFromHeader(message.fromHeader)
        let receivedAtISO = ISO8601DateFormatter().string(
            from: message.receivedAt ?? Date()
        )
        let userEmail = OnboardingUserPrefs.email.lowercased()
        // Detect CC-FYI: user appears in Cc but not in To.
        let toAddrs = parseAddressList(message.toHeader).map { $0.lowercased() }
        let ccAddrs = parseAddressList(message.ccHeader).map { $0.lowercased() }
        let isInTo = !userEmail.isEmpty && toAddrs.contains(userEmail)
        let isInCc = !userEmail.isEmpty && ccAddrs.contains(userEmail)
        let isCcFyi = isInCc && !isInTo

        let row = EmailMessageRow(
            id: UUID(),
            workspaceId: workspaceId,
            emailAccountId: emailAccountId,
            graphMessageId: message.id,
            graphThreadId: message.threadId,
            fromAddress: parsed.address ?? "unknown",
            fromName: parsed.name,
            subject: message.subject ?? "(no subject)",
            snippet: message.snippet,
            receivedAt: ISO8601DateFormatter().date(from: receivedAtISO) ?? Date(),
            triageBucket: nil,
            triageConfidence: nil,
            triageSource: nil,
            isQuestion: false,
            isQuickReply: false,
            isCcFyi: isCcFyi
        )
        try await supabaseClient.upsertEmailMessage(row)

        // Tier 0 observation — same shape as EmailSyncService's path so the
        // downstream intelligence engine treats Gmail and Microsoft messages
        // identically.
        try await emitObservation(
            for: message,
            emailMessageId: row.id,
            fromAddress: parsed.address,
            fromName: parsed.name,
            recipientCount: toAddrs.count + ccAddrs.count,
            explicitProfileId: profileId
        )

        try await triggerClassification(messageId: row.id, workspaceId: workspaceId, profileId: profileId)
    }

    private func emitObservation(
        for message: GoogleEmailMessage,
        emailMessageId: UUID,
        fromAddress: String?,
        fromName: String?,
        recipientCount: Int,
        explicitProfileId: UUID?
    ) async throws {
        let profileId: UUID?
        if let explicitProfileId {
            profileId = explicitProfileId
        } else {
            profileId = await MainActor.run { AuthService.shared.executiveId }
        }
        guard let profileId else { return }

        let occurredAt = message.receivedAt ?? Date()
        let userEmail = OnboardingUserPrefs.email.lowercased()
        let isSent = !userEmail.isEmpty && (fromAddress?.lowercased() ?? "") == userEmail
        let eventType: String = isSent
            ? (isReply(message.subject) ? "email.response_sent" : "email.sent")
            : "email.received"

        var rawData: [String: AnyCodable] = [
            "sender_category": AnyCodable(senderCategory(fromAddress: fromAddress)),
            "recipient_count": AnyCodable(recipientCount)
        ]
        if let labels = message.labelIds {
            rawData["gmail_labels"] = AnyCodable(labels)
        }

        let observation = Tier0Observation(
            profileId: profileId,
            occurredAt: occurredAt,
            source: .email,
            eventType: eventType,
            entityId: emailMessageId,
            entityType: "email_message",
            summary: emailSummary(eventType: eventType, senderName: fromName, senderAddress: fromAddress, recipientCount: recipientCount),
            rawData: rawData,
            importanceScore: 0.5
        )
        try await Tier0Writer.shared.recordObservation(observation)
    }

    private func emailSummary(eventType: String, senderName: String?, senderAddress: String?, recipientCount: Int) -> String {
        if eventType == "email.sent" {
            if recipientCount > 0 {
                let label = recipientCount == 1 ? "recipient" : "recipients"
                return "Email sent to \(recipientCount) \(label)"
            }
            return "Email sent"
        }
        if let senderName, !senderName.isEmpty { return "Email received from \(senderName)" }
        if let senderAddress, !senderAddress.isEmpty { return "Email received from \(senderAddress)" }
        return "Email received"
    }

    private func senderCategory(fromAddress: String?) -> String {
        let userEmail = OnboardingUserPrefs.email.lowercased()
        let addr = (fromAddress ?? "").lowercased()
        if !userEmail.isEmpty, addr == userEmail { return "self" }
        let addrDomain = addr.split(separator: "@").last.map(String.init)
        let userDomain = userEmail.split(separator: "@").last.map(String.init)
        if let addrDomain, let userDomain, !addrDomain.isEmpty, addrDomain == userDomain {
            return "internal"
        }
        return "external"
    }

    private func isReply(_ subject: String?) -> Bool {
        guard let subject else { return false }
        return subject.lowercased().hasPrefix("re:")
    }

    // MARK: - Edge Function trigger (same one Microsoft uses)

    private func triggerClassification(messageId: UUID, workspaceId: UUID, profileId: UUID?) async throws {
        guard let url = URL(string: "\(supabaseURL)/functions/v1/classify-email") else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(try await EdgeFunctions.shared.authorizationHeader(), forHTTPHeaderField: "Authorization")
        let body: [String: Any] = [
            "emailMessageId": messageId.uuidString,
            "workspaceId": workspaceId.uuidString,
            "profileId": (profileId ?? workspaceId).uuidString,
            "sender_importance": 0.5
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (_, response) = try await URLSession.shared.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        if !(200..<300).contains(statusCode) {
            TimedLogger.graph.warning("classify-email returned \(statusCode) for Gmail message \(messageId.uuidString, privacy: .public)")
            throw NSError(
                domain: "Timed.GmailSyncService",
                code: statusCode,
                userInfo: [NSLocalizedDescriptionKey: "classify-email returned \(statusCode)"]
            )
        }
    }

    // MARK: - Header parsing

    /// Parses `From: "Display Name" <addr@host>` into (name?, address?).
    private func parseFromHeader(_ raw: String?) -> (name: String?, address: String?) {
        guard let raw, !raw.isEmpty else { return (nil, nil) }
        // Try "Name <addr>" form first.
        if let lt = raw.firstIndex(of: "<"), let gt = raw.firstIndex(of: ">"), lt < gt {
            let name = raw[..<lt].trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            let addr = raw[raw.index(after: lt)..<gt].trimmingCharacters(in: .whitespaces)
            return (name.isEmpty ? nil : name, addr.isEmpty ? nil : addr)
        }
        // Bare address.
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return (nil, trimmed.isEmpty ? nil : trimmed)
    }

    /// Parses a comma-separated address list, returning bare email addresses.
    private func parseAddressList(_ raw: String?) -> [String] {
        guard let raw, !raw.isEmpty else { return [] }
        return raw.split(separator: ",").compactMap { piece in
            let trimmed = String(piece).trimmingCharacters(in: .whitespacesAndNewlines)
            if let lt = trimmed.firstIndex(of: "<"), let gt = trimmed.firstIndex(of: ">"), lt < gt {
                return String(trimmed[trimmed.index(after: lt)..<gt]).trimmingCharacters(in: .whitespaces)
            }
            return trimmed.isEmpty ? nil : trimmed
        }
    }
}
