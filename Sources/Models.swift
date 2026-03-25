import Foundation

enum TaskSource: String, CaseIterable, Identifiable, Codable {
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
}

struct TaskItem: Identifiable, Hashable, Codable {
    let id: String
    let title: String
    let list: String
    let source: TaskSource
    let subject: String
    let estimateMinutes: Int
    let confidence: Int
    let importance: Int
    let dueDate: Date?
    let notes: String
    let energy: TaskEnergy
}

struct ContextItem: Identifiable, Hashable, Codable {
    let id: String
    let title: String
    let kind: String
    let subject: String
    let summary: String
    let detail: String
}

struct ScheduleBlock: Identifiable, Hashable, Codable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let timeRange: String
    let note: String
}

struct PromptMessage: Identifiable, Hashable, Codable {
    let id: UUID
    let role: String
    let text: String

    init(id: UUID = UUID(), role: String, text: String) {
        self.id = id
        self.role = role
        self.text = text
    }
}

struct ShellData: Codable {
    let tasks: [TaskItem]
    let contexts: [ContextItem]
    let schedule: [ScheduleBlock]
}

extension ShellData {
    static let sample = ShellData(
        tasks: [
            TaskItem(
                id: "task-english",
                title: "English revision - integrating quotes",
                list: "School",
                source: .seqta,
                subject: "English",
                estimateMinutes: 40,
                confidence: 2,
                importance: 5,
                dueDate: Date(),
                notes: "Use the essay framework pack before drafting.",
                energy: .medium
            ),
            TaskItem(
                id: "task-maths",
                title: "Maths investigation",
                list: "School",
                source: .seqta,
                subject: "Maths",
                estimateMinutes: 75,
                confidence: 2,
                importance: 5,
                dueDate: Date().addingTimeInterval(60 * 60 * 24),
                notes: "Break into method, calculation, and explanation.",
                energy: .high
            ),
            TaskItem(
                id: "task-time-manager",
                title: "Create the desktop time management tool",
                list: "Work",
                source: .tickTick,
                subject: "Systems",
                estimateMinutes: 90,
                confidence: 2,
                importance: 5,
                dueDate: nil,
                notes: "Build the planning layer before deeper integrations.",
                energy: .high
            )
        ],
        contexts: [
            ContextItem(
                id: "ctx-english",
                title: "English transcription pack",
                kind: "Transcript",
                subject: "English",
                summary: "Quote integration, evidence selection, and paragraph tightening.",
                detail: "Use this when the prompt asks for essay structure or better evidence use."
            ),
            ContextItem(
                id: "ctx-seqta",
                title: "Seqta export",
                kind: "Seqta",
                subject: "School",
                summary: "Tasks, due dates, and assessment pressure from Seqta.",
                detail: "Best context when deciding what school work should be time boxed first."
            ),
            ContextItem(
                id: "ctx-chat",
                title: "Planning chat memory",
                kind: "Chat",
                subject: "Personal",
                summary: "Past decisions and preferences from conversations with the tool.",
                detail: "Use this to keep the planner aligned with how the user actually works."
            )
        ],
        schedule: [
            ScheduleBlock(
                id: "slot-1",
                title: "Deep work",
                start: Date(),
                end: Date().addingTimeInterval(60 * 60),
                timeRange: "4:30 PM - 5:30 PM",
                note: "Maths investigation, high energy block."
            ),
            ScheduleBlock(
                id: "slot-2",
                title: "Recovery / admin",
                start: Date().addingTimeInterval(60 * 60),
                end: Date().addingTimeInterval(60 * 60 + 20 * 60),
                timeRange: "5:30 PM - 5:50 PM",
                note: "Short reset and paperwork."
            ),
            ScheduleBlock(
                id: "slot-3",
                title: "Essay sprint",
                start: Date().addingTimeInterval(80 * 60),
                end: Date().addingTimeInterval(120 * 60),
                timeRange: "6:00 PM - 6:40 PM",
                note: "English quote integration and cleanup."
            )
        ]
    )
}
