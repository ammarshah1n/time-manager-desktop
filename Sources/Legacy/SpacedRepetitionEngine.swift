import Foundation

enum RecallRating: Int, CaseIterable, Identifiable {
    case again = 1
    case hard = 2
    case good = 4
    case easy = 5

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .again:
            return "Again"
        case .hard:
            return "Hard"
        case .good:
            return "Good"
        case .easy:
            return "Easy"
        }
    }
}

enum SpacedRepetitionEngine {
    static let defaultEaseFactor = 2.5
    static let defaultInterval = 1

    static func review(_ question: QuizQuestion, quality: Int, now: Date = .now, calendar: Calendar = .current) -> QuizQuestion {
        let clampedQuality = max(0, min(5, quality))
        let currentEaseFactor = max(1.3, question.easeFactor)
        let penalty = Double(5 - clampedQuality)
        let nextEaseFactor = max(
            1.3,
            currentEaseFactor + 0.1 - penalty * (0.08 + penalty * 0.02)
        )

        let nextInterval: Int
        if clampedQuality >= 3 {
            if question.interval <= 1 {
                nextInterval = 6
            } else {
                nextInterval = max(1, Int((Double(question.interval) * currentEaseFactor).rounded()))
            }
        } else {
            nextInterval = 1
        }

        let reviewDate = calendar.date(byAdding: .day, value: nextInterval, to: now) ?? now
        return question.updated(
            easeFactor: nextEaseFactor,
            interval: nextInterval,
            nextDue: calendar.startOfDay(for: reviewDate)
        )
    }

    static func isDue(_ question: QuizQuestion, now: Date = .now, calendar: Calendar = .current) -> Bool {
        calendar.startOfDay(for: question.nextDue) <= calendar.startOfDay(for: now)
    }

    static func daysUntilDue(_ question: QuizQuestion, now: Date = .now, calendar: Calendar = .current) -> Int {
        let startOfToday = calendar.startOfDay(for: now)
        let startOfDueDate = calendar.startOfDay(for: question.nextDue)
        let days = calendar.dateComponents([.day], from: startOfToday, to: startOfDueDate).day ?? 0
        return max(0, days)
    }
}
