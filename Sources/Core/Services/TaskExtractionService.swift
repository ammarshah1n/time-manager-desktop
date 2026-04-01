// TaskExtractionService.swift — Timed Core
// Groups related triage emails by thread and extracts task bundles.
// FR-03: Real Task Extraction from Email.

import Foundation
import os

// MARK: - Extracted task bundle

struct ExtractedTaskBundle: Identifiable, Sendable {
    let id: UUID
    let emails: [TriageItem]
    var suggestedTitle: String
    var suggestedBucket: TaskBucket
    var suggestedMinutes: Int

    var emailCount: Int { emails.count }
}

// MARK: - Service

actor TaskExtractionService {
    static let shared = TaskExtractionService()
    private let log = Logger(subsystem: "com.timed.app", category: "taskExtraction")

    // MARK: - Public API

    /// Groups emails by conversation thread and extracts task bundles.
    func extractTasks(from emails: [TriageItem]) -> [ExtractedTaskBundle] {
        let groups = groupByThread(emails)
        log.info("Grouped \(emails.count) emails into \(groups.count) bundles")
        return groups.map { bundle(from: $0) }
    }

    /// Merges multiple triage items into a single TimedTask.
    func mergeItems(_ items: [TriageItem], bucket: TaskBucket, title: String, minutes: Int) -> TimedTask {
        let mostRecent = items.max(by: { $0.receivedAt < $1.receivedAt }) ?? items[0]
        return TimedTask(
            id: UUID(),
            title: title,
            sender: mostRecent.sender,
            estimatedMinutes: minutes,
            bucket: bucket,
            emailCount: items.count,
            receivedAt: mostRecent.receivedAt
        )
    }

    // MARK: - Thread grouping

    private func groupByThread(_ emails: [TriageItem]) -> [[TriageItem]] {
        var groups: [[TriageItem]] = []
        var assigned = Set<UUID>()

        let sorted = emails.sorted { $0.receivedAt > $1.receivedAt }

        for email in sorted {
            guard !assigned.contains(email.id) else { continue }

            var thread = [email]
            assigned.insert(email.id)
            let cleanSubject = email.subject.cleanedEmailSubject.lowercased()

            for other in sorted where !assigned.contains(other.id) {
                if matchesThread(email, other, cleanSubject: cleanSubject) {
                    thread.append(other)
                    assigned.insert(other.id)
                }
            }

            // Sort thread chronologically (oldest first)
            thread.sort { $0.receivedAt < $1.receivedAt }
            groups.append(thread)
        }

        return groups
    }

    private func matchesThread(_ a: TriageItem, _ b: TriageItem, cleanSubject: String) -> Bool {
        // Same sender
        if a.sender == b.sender {
            let otherClean = b.subject.cleanedEmailSubject.lowercased()
            // Exact cleaned subject match
            if cleanSubject == otherClean { return true }
            // One contains the other (catches partial subject matches)
            if cleanSubject.contains(otherClean) || otherClean.contains(cleanSubject) {
                return true
            }
        }

        // Different sender but same cleaned subject — likely same thread
        let otherClean = b.subject.cleanedEmailSubject.lowercased()
        if cleanSubject == otherClean && !cleanSubject.isEmpty {
            return true
        }

        return false
    }

    // MARK: - Bundle construction

    private func bundle(from emails: [TriageItem]) -> ExtractedTaskBundle {
        let mostRecent = emails.last ?? emails[0]
        let title = mostRecent.subject.cleanedEmailSubject
        let bucket = detectBucket(from: emails)
        let minutes = estimateMinutes(emailCount: emails.count, bucket: bucket)

        return ExtractedTaskBundle(
            id: UUID(),
            emails: emails,
            suggestedTitle: title.isEmpty ? mostRecent.subject : title,
            suggestedBucket: bucket,
            suggestedMinutes: minutes
        )
    }

    // MARK: - Bucket detection

    private func detectBucket(from emails: [TriageItem]) -> TaskBucket {
        let combined = emails.map { "\($0.subject) \($0.preview)" }.joined(separator: " ").lowercased()

        // Calls keywords
        let callKeywords = ["call", "phone", "ring", "dial", "speak with", "talk to", "return call"]
        if callKeywords.contains(where: { combined.contains($0) }) {
            return .calls
        }

        // Question / reply patterns
        let questionPatterns = ["?", "quick question", "could you", "can you", "would you",
                                "please reply", "please respond", "let me know", "get back to"]
        if questionPatterns.contains(where: { combined.contains($0) }) {
            return .reply
        }

        // Read patterns
        let readPatterns = ["fyi", "for your information", "no action needed", "newsletter",
                            "billing statement", "monthly report", "weekly digest"]
        if readPatterns.contains(where: { combined.contains($0) }) {
            return .readToday
        }

        // CC / notification patterns
        let ccPatterns = ["sign-in", "new sign-in", "notification", "automated", "noreply",
                          "do not reply", "unsubscribe"]
        if ccPatterns.contains(where: { combined.contains($0) }) {
            return .ccFyi
        }

        // Waiting patterns
        let waitingPatterns = ["waiting for", "pending", "awaiting", "follow up", "following up"]
        if waitingPatterns.contains(where: { combined.contains($0) }) {
            return .waiting
        }

        // Default to action
        return .action
    }

    // MARK: - Time estimation

    private func estimateMinutes(emailCount: Int, bucket: TaskBucket) -> Int {
        let base: Int
        switch bucket {
        case .reply:        base = 5
        case .action:       base = 15
        case .calls:        base = 10
        case .readToday:    base = 10
        case .readThisWeek: base = 15
        case .transit:      base = 20
        case .waiting:      base = 5
        case .ccFyi:        base = 2
        }

        if emailCount <= 1 { return base }
        if emailCount <= 3 { return Int(Double(base) * 1.5) }
        return base * 2
    }
}
