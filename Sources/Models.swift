import CryptoKit
import Foundation

enum TaskSource: String, CaseIterable, Identifiable, Codable {
    case codexMem = "codex-mem"
    case tickTick = "TickTick"
    case seqta = "Seqta"
    case transcript = "Transcript"
    case chat = "Chat"

    var id: String { rawValue }
}

enum TaskEnergy: String, CaseIterable, Identifiable, Codable {
    case low = "Low"
    case medium = "Medium"
    case high = "High"

    var id: String { rawValue }
}

enum ImportSource: String, CaseIterable, Identifiable, Codable {
    case tickTick = "TickTick"
    case transcript = "Transcript"
    case seqta = "Seqta"
    case chat = "Chat"

    var id: String { rawValue }

    var taskSource: TaskSource {
        switch self {
        case .tickTick:
            return .tickTick
        case .seqta:
            return .seqta
        case .transcript:
            return .transcript
        case .chat:
            return .chat
        }
    }
}

enum PromptRole: String, Codable, CaseIterable {
    case user
    case assistant
    case tutor
    case student

    var displayName: String {
        switch self {
        case .user:
            return "You"
        case .assistant:
            return "Timed"
        case .tutor:
            return "Tutor"
        case .student:
            return "Student"
        }
    }
}

struct TaskItem: Identifiable, Hashable, Codable {
    let id: String
    var title: String
    var list: String
    var source: TaskSource
    var subject: String
    var estimateMinutes: Int
    var confidence: Int
    var importance: Int
    var dueDate: Date?
    var notes: String
    var energy: TaskEnergy
    var isCompleted: Bool
    var completedAt: Date?
    var isAutoDiscovered: Bool

    init(
        id: String,
        title: String,
        list: String,
        source: TaskSource,
        subject: String,
        estimateMinutes: Int,
        confidence: Int,
        importance: Int,
        dueDate: Date?,
        notes: String,
        energy: TaskEnergy,
        isCompleted: Bool,
        completedAt: Date?,
        isAutoDiscovered: Bool = false
    ) {
        self.id = id
        self.title = title
        self.list = list
        self.source = source
        self.subject = subject
        self.estimateMinutes = estimateMinutes
        self.confidence = confidence
        self.importance = importance
        self.dueDate = dueDate
        self.notes = notes
        self.energy = energy
        self.isCompleted = isCompleted
        self.completedAt = completedAt
        self.isAutoDiscovered = isAutoDiscovered
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case list
        case source
        case subject
        case estimateMinutes
        case confidence
        case importance
        case dueDate
        case notes
        case energy
        case isCompleted
        case completedAt
        case isAutoDiscovered
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        list = try container.decode(String.self, forKey: .list)
        source = try container.decode(TaskSource.self, forKey: .source)
        subject = try container.decode(String.self, forKey: .subject)
        estimateMinutes = try container.decode(Int.self, forKey: .estimateMinutes)
        confidence = try container.decode(Int.self, forKey: .confidence)
        importance = try container.decode(Int.self, forKey: .importance)
        dueDate = try container.decodeIfPresent(Date.self, forKey: .dueDate)
        notes = try container.decode(String.self, forKey: .notes)
        energy = try container.decode(TaskEnergy.self, forKey: .energy)
        isCompleted = try container.decode(Bool.self, forKey: .isCompleted)
        completedAt = try container.decodeIfPresent(Date.self, forKey: .completedAt)
        isAutoDiscovered = try container.decodeIfPresent(Bool.self, forKey: .isAutoDiscovered) ?? false
    }
}

struct ContextItem: Identifiable, Hashable, Codable {
    let id: String
    var title: String
    var kind: String
    var subject: String
    var summary: String
    var detail: String
    var createdAt: Date
}

struct ScheduleBlock: Identifiable, Hashable, Codable {
    let id: String
    var taskID: String
    var title: String
    var start: Date
    var end: Date
    var timeRange: String
    var note: String
    var isApproved: Bool
}

struct PromptMessage: Identifiable, Hashable, Codable {
    let id: UUID
    var role: PromptRole
    var text: String
    var createdAt: Date
    var isQuiz: Bool

    init(
        id: UUID = UUID(),
        role: PromptRole,
        text: String,
        createdAt: Date = .now,
        isQuiz: Bool = false
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.createdAt = createdAt
        self.isQuiz = isQuiz
    }
}

struct RankedTask: Identifiable, Hashable {
    let task: TaskItem
    let score: Int
    let band: String
    let reasons: [String]
    let suggestedNextAction: String

    var id: String { task.id }
}

struct PlannerSnapshot: Codable {
    let tasks: [TaskItem]
    let contexts: [ContextItem]
    let schedule: [ScheduleBlock]
    let selectedTaskID: String?
    let selectedContextID: String?
    let promptText: String
    let chat: [PromptMessage]
    let studyChat: [PromptMessage]
    let promptBoostSubject: String?
    let dismissedScheduleTaskIDs: [String]
}

struct ImportTaskDraft: Identifiable, Hashable {
    let id: UUID
    let originalID: String
    var title: String
    var list: String
    var source: TaskSource
    var subject: String
    var estimateMinutes: Int
    var confidence: Int
    var importance: Int
    var dueDate: Date
    var notes: String
    var energy: TaskEnergy

    init(
        id: UUID = UUID(),
        originalID: String,
        title: String,
        list: String,
        source: TaskSource,
        subject: String,
        estimateMinutes: Int,
        confidence: Int,
        importance: Int,
        dueDate: Date,
        notes: String,
        energy: TaskEnergy
    ) {
        self.id = id
        self.originalID = originalID
        self.title = title
        self.list = list
        self.source = source
        self.subject = subject
        self.estimateMinutes = estimateMinutes
        self.confidence = confidence
        self.importance = importance
        self.dueDate = dueDate
        self.notes = notes
        self.energy = energy
    }

    func resolvedSubject() -> String {
        let trimmed = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? SubjectCatalog.supported.first ?? "General" : trimmed
    }

    func makeTask() -> TaskItem {
        TaskItem(
            id: originalID,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            list: list,
            source: source,
            subject: resolvedSubject(),
            estimateMinutes: max(5, estimateMinutes),
            confidence: max(1, min(5, confidence)),
            importance: max(1, min(5, importance)),
            dueDate: dueDate,
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
            energy: energy,
            isCompleted: false,
            completedAt: nil
        )
    }
}

struct ImportBatch {
    var context: ContextItem?
    var taskDrafts: [ImportTaskDraft]
    var messages: [String]
}

struct AddTaskDraft {
    var title = ""
    var subject = SubjectCatalog.supported.first ?? "English"
    var estimateMinutes = 30
    var importance = 3.0
    var confidence = 3.0
    var dueDate = Calendar.current.date(byAdding: .day, value: 1, to: .now) ?? .now
    var energy: TaskEnergy = .medium
    var source: TaskSource = .chat
    var notes = ""

    func makeTask() -> TaskItem {
        TaskItem(
            id: StableID.makeTaskID(source: source, title: title),
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            list: source.rawValue,
            source: source,
            subject: subject,
            estimateMinutes: max(5, estimateMinutes),
            confidence: Int(confidence.rounded()),
            importance: Int(importance.rounded()),
            dueDate: dueDate,
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
            energy: energy,
            isCompleted: false,
            completedAt: nil
        )
    }
}

enum SubjectCatalog {
    static let supported = [
        "English",
        "Maths",
        "Economics",
        "Chemistry",
        "Physics",
        "Biology",
        "Legal Studies",
        "Society and Culture",
        "Modern History",
        "Geography",
        "PE",
        "Languages"
    ]

    static func matchingSubject(in text: String) -> String? {
        let lowered = text.lowercased()

        let rules: [(String, [String])] = [
            ("English", ["english", "essay", "quote", "literature", "text response"]),
            ("Maths", ["math", "maths", "mathematics", "calculus", "algebra", "statistics"]),
            ("Economics", ["economics", "economic", "markets", "microeconomics", "macroeconomics"]),
            ("Chemistry", ["chemistry", "chemical", "stoichiometry", "molecule", "equilibrium"]),
            ("Physics", ["physics", "kinematics", "forces", "motion", "electricity"]),
            ("Biology", ["biology", "cell", "genetics", "ecosystem", "photosynthesis"]),
            ("Legal Studies", ["legal", "law", "court", "rights", "constitution"]),
            ("Society and Culture", ["society", "culture", "social", "identity", "community"]),
            ("Modern History", ["modern history", "history", "source analysis", "historian", "war"]),
            ("Geography", ["geography", "geographic", "climate", "urban", "population"]),
            ("PE", ["pe", "physical education", "sport", "exercise", "training"]),
            ("Languages", ["language", "french", "japanese", "spanish", "german", "vocabulary"])
        ]

        for (subject, keywords) in rules where keywords.contains(where: lowered.contains) {
            return subject
        }

        return nil
    }
}

enum StableID {
    static func makeTaskID(source: TaskSource, title: String) -> String {
        let seed = normalizedTaskIdentityTitle(from: title)
        let digest = SHA256.hash(data: Data(seed.utf8))
        let hash = digest.prefix(12).map { String(format: "%02x", $0) }.joined()
        return "task-\(hash)"
    }

    static func normalizedTaskIdentityTitle(from title: String) -> String {
        title
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func makeContextID(source: ImportSource, title: String, createdAt: Date) -> String {
        let seed = "\(source.rawValue)-\(title)-\(createdAt.timeIntervalSince1970)"
        let digest = SHA256.hash(data: Data(seed.utf8))
        let hash = digest.prefix(12).map { String(format: "%02x", $0) }.joined()
        return "ctx-\(hash)"
    }
}

struct ShellData: Codable {
    let tasks: [TaskItem]
    let contexts: [ContextItem]
    let schedule: [ScheduleBlock]
    let chat: [PromptMessage]
    let studyChat: [PromptMessage]
}

extension ShellData {
    static let empty = ShellData(
        tasks: [],
        contexts: [],
        schedule: [],
        chat: [PromptMessage(role: .assistant, text: "Timed is ready. Import your real tasks, transcript context, or ask it to find a file.")],
        studyChat: [PromptMessage(role: .assistant, text: "Study mode is ready. Pick a task and ask for a quiz, practice questions, or formative-style drills.")]
    )
}

extension JSONEncoder {
    static var pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

extension JSONDecoder {
    convenience init(iso8601: Bool = true) {
        self.init()
        if iso8601 {
            dateDecodingStrategy = .iso8601
        }
    }
}
