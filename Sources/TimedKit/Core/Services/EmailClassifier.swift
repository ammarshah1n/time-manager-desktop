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
    /// Server-side `classify-email` Edge Function (called from `EmailSyncService.triggerClassification`)
    /// is the canonical AI path; this struct just wraps the sender-rules pass for the few
    /// hot loops that cannot await.
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
}
