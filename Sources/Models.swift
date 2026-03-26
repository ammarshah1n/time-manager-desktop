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
    var pomodoroCount: Int

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
        isAutoDiscovered: Bool = false,
        pomodoroCount: Int = 0
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
        self.pomodoroCount = max(0, pomodoroCount)
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
        case pomodoroCount
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
        pomodoroCount = try container.decodeIfPresent(Int.self, forKey: .pomodoroCount) ?? 0
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

struct ContextDocument: Identifiable, Hashable, Codable {
    let id: String
    var subject: String
    var title: String
    var content: String
    var path: String
    var importedAt: Date
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
    var isPinned: Bool

    init(
        id: UUID = UUID(),
        role: PromptRole,
        text: String,
        createdAt: Date = .now,
        isQuiz: Bool = false,
        isPinned: Bool = false
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.createdAt = createdAt
        self.isQuiz = isQuiz
        self.isPinned = isPinned
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case role
        case text
        case createdAt
        case isQuiz
        case isPinned
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        role = try container.decode(PromptRole.self, forKey: .role)
        text = try container.decode(String.self, forKey: .text)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? .now
        isQuiz = try container.decodeIfPresent(Bool.self, forKey: .isQuiz) ?? false
        isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
    }
}

struct PromptErrorState: Identifiable, Equatable {
    let id: UUID
    var message: String

    init(id: UUID = UUID(), message: String) {
        self.id = id
        self.message = message
    }
}

struct SettingsIssueState: Equatable {
    var message: String
}

enum ToastTone: String, Equatable {
    case info
    case error
}

struct ToastState: Identifiable, Equatable {
    let id: UUID
    var title: String
    var message: String
    var systemImage: String
    var tone: ToastTone

    init(
        id: UUID = UUID(),
        title: String,
        message: String,
        systemImage: String,
        tone: ToastTone
    ) {
        self.id = id
        self.title = title
        self.message = message
        self.systemImage = systemImage
        self.tone = tone
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
    let subjectConfidences: [String: Int]
    let selectedTaskID: String?
    let selectedContextID: String?
    let promptText: String
    let chat: [PromptMessage]
    let studyChat: [PromptMessage]
    let promptBoostSubject: String?
    let dismissedScheduleTaskIDs: [String]
    let obsidianDocuments: [ContextDocument]

    init(
        tasks: [TaskItem],
        contexts: [ContextItem],
        schedule: [ScheduleBlock],
        subjectConfidences: [String: Int],
        selectedTaskID: String?,
        selectedContextID: String?,
        promptText: String,
        chat: [PromptMessage],
        studyChat: [PromptMessage],
        promptBoostSubject: String?,
        dismissedScheduleTaskIDs: [String],
        obsidianDocuments: [ContextDocument] = []
    ) {
        self.tasks = tasks
        self.contexts = contexts
        self.schedule = schedule
        self.subjectConfidences = subjectConfidences
        self.selectedTaskID = selectedTaskID
        self.selectedContextID = selectedContextID
        self.promptText = promptText
        self.chat = chat
        self.studyChat = studyChat
        self.promptBoostSubject = promptBoostSubject
        self.dismissedScheduleTaskIDs = dismissedScheduleTaskIDs
        self.obsidianDocuments = obsidianDocuments
    }

    private enum CodingKeys: String, CodingKey {
        case tasks
        case contexts
        case schedule
        case subjectConfidences
        case selectedTaskID
        case selectedContextID
        case promptText
        case chat
        case studyChat
        case promptBoostSubject
        case dismissedScheduleTaskIDs
        case obsidianDocuments
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tasks = try container.decode([TaskItem].self, forKey: .tasks)
        contexts = try container.decode([ContextItem].self, forKey: .contexts)
        schedule = try container.decode([ScheduleBlock].self, forKey: .schedule)
        subjectConfidences = try container.decodeIfPresent([String: Int].self, forKey: .subjectConfidences) ?? [:]
        selectedTaskID = try container.decodeIfPresent(String.self, forKey: .selectedTaskID)
        selectedContextID = try container.decodeIfPresent(String.self, forKey: .selectedContextID)
        promptText = try container.decode(String.self, forKey: .promptText)
        chat = try container.decode([PromptMessage].self, forKey: .chat)
        studyChat = try container.decode([PromptMessage].self, forKey: .studyChat)
        promptBoostSubject = try container.decodeIfPresent(String.self, forKey: .promptBoostSubject)
        dismissedScheduleTaskIDs = try container.decodeIfPresent([String].self, forKey: .dismissedScheduleTaskIDs) ?? []
        obsidianDocuments = try container.decodeIfPresent([ContextDocument].self, forKey: .obsidianDocuments) ?? []
    }
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

    private static let aliasRules: [(subject: String, patterns: [String])] = [
        ("Society and Culture", [
            "society and culture",
            "soc and culture",
            "society culture",
            "soc",
            "so c",
            "s and c"
        ]),
        ("Economics", [
            "sace economics",
            "economics",
            "economic",
            "eco",
            "microeconomics",
            "macroeconomics",
            "markets"
        ]),
        ("English", [
            "eng stds",
            "eng standards",
            "english studies",
            "english",
            "essay",
            "quote",
            "literature",
            "text response"
        ]),
        ("Maths", [
            "specialist mathematics",
            "specialist maths",
            "mathematical methods",
            "general mathematics",
            "general maths",
            "mathematics",
            "specialist",
            "methods",
            "maths",
            "math",
            "calculus",
            "algebra",
            "statistics"
        ]),
        ("Chemistry", ["chemistry", "chemical", "stoichiometry", "molecule", "equilibrium", "chem"]),
        ("Physics", ["physics", "kinematics", "forces", "motion", "electricity"]),
        ("Biology", ["biology", "cell", "genetics", "ecosystem", "photosynthesis"]),
        ("Legal Studies", ["legal studies", "legal", "law", "court", "rights", "constitution"]),
        ("Modern History", ["modern history", "history", "source analysis", "historian", "war"]),
        ("Geography", ["geography", "geographic", "climate", "urban", "population"]),
        ("PE", ["physical education", "pe", "sport", "exercise", "training"]),
        ("Languages", ["language", "french", "japanese", "spanish", "german", "vocabulary"])
    ]

    static func matchingSubject(in text: String) -> String? {
        let normalizedText = normalizedSubjectText(text)
        guard !normalizedText.isEmpty else { return nil }

        for rule in aliasRules {
            if rule.patterns.contains(where: { matches(pattern: $0, in: normalizedText) }) {
                return rule.subject
            }
        }

        return nil
    }

    static func keywords(for subject: String) -> [String] {
        if let rule = aliasRules.first(where: { $0.subject.caseInsensitiveCompare(subject) == .orderedSame }) {
            return Array(Set(rule.patterns + [rule.subject])).sorted()
        }

        return [subject]
    }

    static func normalizedSubjectText(_ text: String) -> String {
        let lowered = text
            .lowercased()
            .replacingOccurrences(of: "&", with: " and ")
            .replacingOccurrences(of: "/", with: " ")
        let components = lowered.components(separatedBy: CharacterSet.alphanumerics.inverted)
        return components
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func matches(pattern: String, in normalizedText: String) -> Bool {
        let normalizedPattern = normalizedSubjectText(pattern)
        guard !normalizedPattern.isEmpty else { return false }

        if normalizedText == normalizedPattern {
            return true
        }

        if normalizedText.hasPrefix("\(normalizedPattern) ") || normalizedText.hasSuffix(" \(normalizedPattern)") {
            return true
        }

        let paddedText = " \(normalizedText) "
        let paddedPattern = " \(normalizedPattern) "
        if paddedText.contains(paddedPattern) {
            return true
        }

        return normalizedText.contains(normalizedPattern)
    }
}

enum StableID {
    static func makeTaskID(source: TaskSource, title: String) -> String {
        let seed = normalizedTaskIdentityTitle(from: title)
        return hashedID(prefix: "task", seed: seed)
    }

    static func makeSeqtaTaskID(remoteID: String?, title: String, subject: String) -> String {
        let trimmedRemoteID = remoteID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmedRemoteID.isEmpty {
            return hashedID(prefix: "seqta", seed: "seqta-id|\(trimmedRemoteID)")
        }

        let seed = [
            "seqta",
            normalizedTaskIdentityTitle(from: title),
            normalizedSubjectIdentity(from: subject)
        ].joined(separator: "|")
        return hashedID(prefix: "seqta", seed: seed)
    }

    static func normalizedTaskIdentityTitle(from title: String) -> String {
        title
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func normalizedSubjectIdentity(from subject: String) -> String {
        SubjectCatalog.normalizedSubjectText(subject)
    }

    static func makeContextID(source: ImportSource, title: String, createdAt: Date) -> String {
        let seed = "\(source.rawValue)-\(title)-\(createdAt.timeIntervalSince1970)"
        return hashedID(prefix: "ctx", seed: seed)
    }

    private static func hashedID(prefix: String, seed: String) -> String {
        let digest = SHA256.hash(data: Data(seed.utf8))
        let hash = digest.prefix(12).map { String(format: "%02x", $0) }.joined()
        return "\(prefix)-\(hash)"
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
