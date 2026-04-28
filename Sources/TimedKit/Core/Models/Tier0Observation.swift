import Foundation

/// A raw observation from any signal source, mirroring the `tier0_observations` Supabase table.
struct Tier0Observation: Codable, Sendable, Identifiable {
    let id: UUID
    let profileId: UUID
    let occurredAt: Date
    let source: SignalSource
    let eventType: String
    var entityId: UUID?
    var entityType: String?
    var summary: String?
    var rawData: [String: AnyCodable]?
    var importanceScore: Double
    var baselineDeviation: Double?
    var isProcessed: Bool
    var processedAt: Date?
    let createdAt: Date

    init(
        id: UUID = UUID(),
        profileId: UUID,
        occurredAt: Date = Date(),
        source: SignalSource,
        eventType: String,
        entityId: UUID? = nil,
        entityType: String? = nil,
        summary: String? = nil,
        rawData: [String: AnyCodable]? = nil,
        importanceScore: Double = 0.5,
        baselineDeviation: Double? = nil,
        isProcessed: Bool = false,
        processedAt: Date? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.profileId = profileId
        self.occurredAt = occurredAt
        self.source = source
        self.eventType = eventType
        self.entityId = entityId
        self.entityType = entityType
        self.summary = summary
        self.rawData = rawData
        self.importanceScore = importanceScore
        self.baselineDeviation = baselineDeviation
        self.isProcessed = isProcessed
        self.processedAt = processedAt
        self.createdAt = createdAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case profileId = "profile_id"
        case occurredAt = "occurred_at"
        case source
        case eventType = "event_type"
        case entityId = "entity_id"
        case entityType = "entity_type"
        case summary
        case rawData = "raw_data"
        case importanceScore = "importance_score"
        case baselineDeviation = "baseline_deviation"
        case isProcessed = "is_processed"
        case processedAt = "processed_at"
        case createdAt = "created_at"
    }
}

enum SignalSource: Codable, Sendable, Equatable {
    case email
    case calendar
    case appUsage
    case system
    case keystroke
    case voice
    case healthkit
    case oura
    case composite
    case engagement
    case unknown(String)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        switch raw {
        case "email": self = .email
        case "calendar": self = .calendar
        case "app_usage": self = .appUsage
        case "system": self = .system
        case "keystroke": self = .keystroke
        case "voice": self = .voice
        case "healthkit": self = .healthkit
        case "oura": self = .oura
        case "composite": self = .composite
        case "engagement": self = .engagement
        default: self = .unknown(raw)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawString)
    }

    /// String form matching the database `source` column. Used when handing a
    /// source identifier to non-Codable callers (e.g. `AlertEngine.evaluateRTScore`).
    var rawString: String {
        switch self {
        case .email: return "email"
        case .calendar: return "calendar"
        case .appUsage: return "app_usage"
        case .system: return "system"
        case .keystroke: return "keystroke"
        case .voice: return "voice"
        case .healthkit: return "healthkit"
        case .oura: return "oura"
        case .composite: return "composite"
        case .engagement: return "engagement"
        case .unknown(let raw): return raw
        }
    }
}

/// Type-erased Codable wrapper for JSONB raw_data field.
struct AnyCodable: Codable, @unchecked Sendable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let int = try? container.decode(Int.self) { value = int }
        else if let double = try? container.decode(Double.self) { value = double }
        else if let string = try? container.decode(String.self) { value = string }
        else if let bool = try? container.decode(Bool.self) { value = bool }
        else if let dict = try? container.decode([String: AnyCodable].self) { value = dict }
        else if let array = try? container.decode([AnyCodable].self) { value = array }
        else if container.decodeNil() { value = NSNull() }
        else { throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported type") }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case let int as Int: try container.encode(int)
        case let double as Double: try container.encode(double)
        case let string as String: try container.encode(string)
        case let bool as Bool: try container.encode(bool)
        case let dict as [String: AnyCodable]: try container.encode(dict)
        case let array as [AnyCodable]: try container.encode(array)
        case is NSNull: try container.encodeNil()
        default: throw EncodingError.invalidValue(value, .init(codingPath: [], debugDescription: "Unsupported type"))
        }
    }
}
