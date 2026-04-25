import Foundation

struct MorningBriefing: Codable, Sendable, Identifiable {
    let id: UUID
    let profileId: UUID
    let date: String // YYYY-MM-DD
    let content: BriefingContent
    let generatedAt: Date
    let wordCount: Int
    var wasViewed: Bool
    var firstViewedAt: Date?
    var engagementDurationSeconds: Int?
    var sectionsInteracted: [String]

    enum CodingKeys: String, CodingKey {
        case id
        case profileId = "profile_id"
        case date
        case content
        case generatedAt = "generated_at"
        case wordCount = "word_count"
        case wasViewed = "was_viewed"
        case firstViewedAt = "first_viewed_at"
        case engagementDurationSeconds = "engagement_duration_seconds"
        case sectionsInteracted = "sections_interacted"
    }
}

struct BriefingContent: Codable, Sendable {
    let sections: [BriefingSection]
    let wordCount: Int?
    let generatedBy: String?

    enum CodingKeys: String, CodingKey {
        case sections
        case wordCount = "word_count"
        case generatedBy = "generated_by"
    }
}

struct BriefingSection: Codable, Sendable, Identifiable {
    var id: String { section }
    let section: String
    let insight: String
    let supportingData: String?
    let confidence: BriefingConfidence
    let category: String
    let sourceSignals: [String]
    let historicalAccuracy: Double?
    let trackRecord: String?

    enum CodingKeys: String, CodingKey {
        case section
        case insight
        case supportingData = "supporting_data"
        case confidence
        case category
        case sourceSignals = "source_signals"
        case historicalAccuracy = "historical_accuracy"
        case trackRecord = "track_record"
    }
}

enum BriefingConfidence: String, Codable, Sendable {
    case high
    case moderate
    // .low NEVER appears in morning brief — held for strengthening
}
