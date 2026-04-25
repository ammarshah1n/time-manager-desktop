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
    func classify(_ email: EmailMessage, senderRules: [SenderRuleRow]) -> EmailCategory {
        // Check sender rules first (learned from Outlook folder moves)
        let senderAddress = email.sender.lowercased()
        if let rule = senderRules.first(where: { $0.fromAddress.lowercased() == senderAddress }) {
            switch rule.ruleType {
            case "black_hole":
                return .blackHole
            case "inbox_always":
                return .inbox
            case "later":
                return .informational
            case "delegate":
                return .actionRequired
            default:
                break
            }
        }

        // Stub: real implementation will call Edge Function → Claude Sonnet
        return .informational
    }
}
