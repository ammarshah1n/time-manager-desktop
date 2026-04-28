import Foundation
import Dependencies

enum EmailCategory: String, Codable, Sendable {
    case actionRequired
    case informational
    case newsletter
    case spam
    case blackHole
    case inbox
}

protocol EmailClassifying: Sendable {
    func classify(_ email: EmailMessage, senderRules: [SenderRuleRow]) -> EmailCategory
}

struct EmailClassifierService: EmailClassifying {
    /// Synchronous rule-based pass — sender rules first, default `informational`.
    /// Use this when you can't await (e.g. hot loops). For real classification
    /// quality, prefer `classifyLive(_:senderRules:)`.
    func classify(_ email: EmailMessage, senderRules: [SenderRuleRow]) -> EmailCategory {
        let senderAddress = email.sender.lowercased()
        if let rule = senderRules.first(where: { $0.fromAddress.lowercased() == senderAddress }) {
            switch rule.ruleType {
            case "black_hole":   return .blackHole
            case "inbox_always": return .inbox
            case "later":        return .informational
            case "delegate":     return .actionRequired
            default:             break
            }
        }
        return .informational
    }

    /// Live classification via `anthropic-relay` Edge Function (Claude Haiku 4.5).
    /// Falls back to sync `classify` if the network is unreachable.
    @MainActor
    func classifyLive(_ email: EmailMessage, senderRules: [SenderRuleRow]) async -> EmailCategory {
        // Sender rules win unconditionally — they're learned from real folder moves.
        let ruleBased = classify(email, senderRules: senderRules)
        if ruleBased != .informational { return ruleBased }

        let prompt = """
        Classify this email into exactly one of: actionRequired, informational, newsletter, spam, blackHole, inbox.
        Reply with JSON: {"category":"<one of the categories>"}.
        Subject: \(email.subject.prefix(200))
        From: \(email.sender)
        Body: \(email.body.prefix(800))
        """
        let body: [String: Any] = [
            "model": "claude-haiku-4-5",
            "max_tokens": 50,
            "messages": [["role": "user", "content": prompt]]
        ]
        do {
            let data = try await EdgeFunctions.shared.anthropicRelay(body: body)
            return Self.parseCategory(from: data) ?? ruleBased
        } catch {
            TimedLogger.triage.warning("classifyLive fell back to rule-based: \(error.localizedDescription, privacy: .private)")
            return ruleBased
        }
    }

    private static func parseCategory(from data: Data) -> EmailCategory? {
        // Anthropic Messages response shape: { content: [{ type: "text", text: "..." }] }
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let content = json["content"] as? [[String: Any]],
            let firstText = content.first?["text"] as? String
        else { return nil }
        // Pull the first {"category":"..."} match out of the response.
        if let range = firstText.range(of: #"\"category\"\s*:\s*\"([a-zA-Z]+)\""#, options: .regularExpression) {
            let match = String(firstText[range])
            if let valueRange = match.range(of: #"\"([a-zA-Z]+)\"\s*$"#, options: .regularExpression) {
                let raw = match[valueRange].trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                return EmailCategory(rawValue: raw)
            }
        }
        return nil
    }
}
