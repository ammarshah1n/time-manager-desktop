import Foundation

struct EmailMessage: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var subject: String
    var sender: String
    var receivedAt: Date
    var body: String
    var isRead: Bool
}
