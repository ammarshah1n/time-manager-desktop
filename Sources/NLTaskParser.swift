import Foundation

struct ParsedTask: Equatable {
    var title: String
    var subject: String?
    var dueDate: Date?
    var importance: Int?
}

struct NLTaskParser {
    private let calendar: Calendar

    init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    func parse(_ input: String, now: Date = .now) -> ParsedTask {
        let trimmedInput = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedInput.isEmpty else {
            return ParsedTask(title: "", subject: nil, dueDate: nil, importance: nil)
        }

        let subject = SubjectCatalog.matchingSubject(in: trimmedInput)
        let importanceMatch = firstMatch(
            pattern: #"\b(?:importance|priority|imp)\s*[:=]?\s*(\d{1,2})\b"#,
            in: trimmedInput
        )
        let dueMatch = duePhraseMatch(in: trimmedInput)

        var strippedTitle = trimmedInput

        let matchedRanges = [dueMatch?.range, importanceMatch?.range]
            .compactMap { $0 }
            .sorted { $0.location > $1.location }

        for range in matchedRanges {
            strippedTitle = replacingCharacters(in: strippedTitle, range: range, with: " ")
        }

        if let subject {
            strippedTitle = removingSubject(subject, from: strippedTitle)
        }

        let cleanedTitle = cleanTitle(strippedTitle, fallback: trimmedInput)
        let parsedImportance = importanceMatch.flatMap { match -> Int? in
            guard match.captures.count > 1, let value = Int(match.captures[1]) else { return nil }
            return max(1, min(10, value))
        }
        let parsedDueDate = dueMatch.flatMap { resolveDuePhrase($0.term, now: now) }

        return ParsedTask(
            title: cleanedTitle,
            subject: subject,
            dueDate: parsedDueDate,
            importance: parsedImportance
        )
    }

    private func duePhraseMatch(in text: String) -> RegexMatch? {
        let explicitPattern = #"\b(?:due|by|on)\s+(today|tomorrow|next week|monday|tuesday|wednesday|thursday|friday|saturday|sunday)\b"#
        if let match = firstMatch(pattern: explicitPattern, in: text) {
            return RegexMatch(range: match.range, captures: match.captures, termIndex: 1)
        }

        let standalonePattern = #"\b(today|tomorrow|next week|monday|tuesday|wednesday|thursday|friday|saturday|sunday)\b"#
        if let match = firstMatch(pattern: standalonePattern, in: text) {
            return RegexMatch(range: match.range, captures: match.captures, termIndex: 1)
        }

        return nil
    }

    private func resolveDuePhrase(_ phrase: String, now: Date) -> Date? {
        let normalized = phrase.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let startOfToday = calendar.startOfDay(for: now)

        switch normalized {
        case "today":
            return endOfDay(for: startOfToday)
        case "tomorrow":
            guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: startOfToday) else { return nil }
            return endOfDay(for: tomorrow)
        case "next week":
            guard let nextWeek = calendar.date(byAdding: .day, value: 7, to: startOfToday) else { return nil }
            return endOfDay(for: nextWeek)
        default:
            guard let targetWeekday = weekdayIndex(for: normalized) else { return nil }
            let currentWeekday = calendar.component(.weekday, from: now)
            // Natural-language weekdays resolve to the next occurrence, not "later today".
            var dayOffset = targetWeekday - currentWeekday
            if dayOffset <= 0 {
                dayOffset += 7
            }

            guard let targetDate = calendar.date(byAdding: .day, value: dayOffset, to: startOfToday) else {
                return nil
            }
            return endOfDay(for: targetDate)
        }
    }

    private func weekdayIndex(for value: String) -> Int? {
        switch value {
        case "sunday": return 1
        case "monday": return 2
        case "tuesday": return 3
        case "wednesday": return 4
        case "thursday": return 5
        case "friday": return 6
        case "saturday": return 7
        default: return nil
        }
    }

    private func endOfDay(for date: Date) -> Date? {
        var components = calendar.dateComponents([.year, .month, .day], from: date)
        components.hour = 23
        components.minute = 59
        components.second = 0
        return calendar.date(from: components)
    }

    private func removingSubject(_ subject: String, from text: String) -> String {
        let candidates = SubjectCatalog.keywords(for: subject)
            .sorted { $0.count > $1.count }

        for candidate in candidates where !candidate.isEmpty {
            if let range = text.range(of: candidate, options: [.caseInsensitive, .diacriticInsensitive]) {
                var copy = text
                copy.replaceSubrange(range, with: " ")
                return copy
            }
        }

        return text
    }

    private func cleanTitle(_ text: String, fallback: String) -> String {
        let collapsed = text
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))

        if !collapsed.isEmpty {
            return collapsed
        }

        return fallback.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func replacingCharacters(in text: String, range: NSRange, with replacement: String) -> String {
        guard let stringRange = Range(range, in: text) else { return text }
        var copy = text
        copy.replaceSubrange(stringRange, with: replacement)
        return copy
    }

    private func firstMatch(pattern: String, in text: String) -> RegexMatch? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }

        guard let match = regex.firstMatch(in: text, options: [], range: NSRange(text.startIndex..., in: text)) else {
            return nil
        }

        let captures = (0..<match.numberOfRanges).map { index in
            let captureRange = match.range(at: index)
            guard let stringRange = Range(captureRange, in: text) else { return "" }
            return String(text[stringRange])
        }

        return RegexMatch(range: match.range, captures: captures, termIndex: 0)
    }
}

private struct RegexMatch {
    let range: NSRange
    let captures: [String]
    let termIndex: Int

    var term: String {
        guard captures.indices.contains(termIndex) else { return "" }
        return captures[termIndex]
    }
}
