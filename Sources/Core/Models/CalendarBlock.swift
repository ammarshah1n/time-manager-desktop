import Foundation

enum BlockCategory: String, Codable, Sendable {
    case focus
    case meeting
    case admin
    case `break`
    case transit
}

struct CalendarBlock: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var title: String
    var startTime: Date
    var endTime: Date
    var sourceEmailId: UUID?
    var category: BlockCategory
}
