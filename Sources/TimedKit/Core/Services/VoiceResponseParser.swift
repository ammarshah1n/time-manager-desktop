// VoiceResponseParser.swift — Timed Core
// Interprets spoken responses during the morning interview.
// Handles affirmative/negative, numbers, and hours-to-minutes conversion.

import Foundation

enum VoiceResponse: Sendable {
    case affirmative                // yes, yeah, sure, go, confirm, lock it in, sounds good
    case negative                   // no, nah, skip, remove, nope
    case number(Int)                // "three hours" → 180, "about 2" → 120, "45 minutes" → 45
    case removeItem(Int)            // "remove the last one" → index, "remove the second" → 2
    case swapItems(Int, Int)        // "swap the first two" → (1, 2)
    case estimateOverride(ordinal: Int, minutes: Int)  // "make the third one 20 minutes"
    case skip                       // "skip", "next", "pass"
    case done                       // "done", "finished", "that's it", "that's all"
    case noMore                     // "no more", "nothing else"
    case repeat_                    // "repeat", "say again", "what?"
    case goBack                     // "go back", "previous", "back"
    case moveToTomorrow(Int?)       // "move to tomorrow", "defer", "tomorrow" (optional item number)
    case addTask(String)            // "add [task description]"
    case undo                       // "undo", "take that back", "cancel that"
    case adjustEndTime(Int)         // "I'm leaving at 3" → 15, "finishing at 5" → 17
    case subtractTime(Int)          // "I have a call not on my calendar" → manual subtract minutes
    case unknown(String)            // anything we can't parse

    // MARK: - Parse

    static func parse(_ transcript: String) -> VoiceResponse {
        let cleaned = transcript
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        guard !cleaned.isEmpty else { return .unknown("") }

        // 1. Check undo (before affirmative/negative to avoid "cancel" collisions)
        if isUndo(cleaned) { return .undo }

        // 2. Check affirmative
        if isAffirmative(cleaned) { return .affirmative }

        // 3. Check done / no-more (before negative — "that's it" is not negative)
        if isDone(cleaned) { return .done }
        if isNoMore(cleaned) { return .noMore }

        // 4. Check negative
        if isNegative(cleaned) { return .negative }

        // 5. Check skip
        if isSkip(cleaned) { return .skip }

        // 6. Check repeat
        if isRepeat(cleaned) { return .repeat_ }

        // 7. Check go back
        if isGoBack(cleaned) { return .goBack }

        // 8. Check add task ("add [description]")
        if let addTask = parseAddTask(cleaned) { return addTask }

        // 9. Check move to tomorrow / defer
        if let move = parseMoveToTomorrow(cleaned) { return move }

        // 10. Check estimate override ("make the third one 20 minutes")
        if let override_ = parseEstimateOverride(cleaned) { return override_ }

        // 11. Check swap
        if let swap = parseSwap(cleaned) { return swap }

        // 12. Check remove
        if let remove = parseRemove(cleaned) { return remove }

        // 13. Check adjust end time ("I'm leaving at 3", "finishing at 5pm")
        if let endTime = parseAdjustEndTime(cleaned) { return endTime }

        // 14. Check subtract time ("I have a call not on my calendar for 30 minutes")
        if let subtract = parseSubtractTime(cleaned) { return subtract }

        // 15. Check number (with hours/minutes handling)
        if let mins = parseMinutes(cleaned) { return .number(mins) }

        return .unknown(transcript)
    }

    // MARK: - Affirmative

    private static let affirmativeWords: Set<String> = [
        "yes", "yeah", "yep", "yup", "sure", "go", "confirm", "confirmed",
        "lock it in", "sounds good", "sounds right", "that's right", "correct",
        "absolutely", "do it", "let's go", "all good", "okay", "ok", "good",
        "perfect", "great", "fine", "keep them", "keep all", "keep it"
    ]

    private static func isAffirmative(_ text: String) -> Bool {
        if affirmativeWords.contains(text) { return true }
        return affirmativeWords.contains { text.hasPrefix($0) || text.hasSuffix($0) }
    }

    // MARK: - Negative

    private static let negativeWords: Set<String> = [
        "no", "nah", "nope", "remove", "don't", "not", "none",
        "remove all", "clear", "nothing"
    ]

    private static func isNegative(_ text: String) -> Bool {
        if negativeWords.contains(text) { return true }
        return negativeWords.contains { text.hasPrefix($0) }
    }

    // MARK: - Number / Minutes parsing

    private static let wordToNumber: [String: Int] = [
        "one": 1, "two": 2, "three": 3, "four": 4, "five": 5,
        "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10,
        "eleven": 11, "twelve": 12, "fifteen": 15, "twenty": 20,
        "thirty": 30, "forty": 40, "forty five": 45, "forty-five": 45,
        "fifty": 50, "sixty": 60, "ninety": 90,
        "half": 30, "half an": 30, "a half": 30,
        "an": 1, "a": 1
    ]

    static func parseMinutes(_ text: String) -> Int? {
        // Try regex for digit patterns: "3 hours", "45 minutes", "2.5 hours"
        if let mins = extractDigitDuration(text) { return mins }

        // Try word patterns: "about three hours", "two and a half hours"
        if let mins = extractWordDuration(text) { return mins }

        // Bare number: "3" or "three"
        if let n = bareNumber(text), n > 0 && n <= 12 {
            // Assume hours if small number with no unit
            return n * 60
        }

        return nil
    }

    private static func extractDigitDuration(_ text: String) -> Int? {
        // Match: "2.5 hours", "3 hours", "45 minutes", "90 min"
        let pattern = #"(\d+(?:\.\d+)?)\s*(hours?|hrs?|h\b|minutes?|mins?|m\b)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range) else { return nil }

        guard let numRange = Range(match.range(at: 1), in: text),
              let unitRange = Range(match.range(at: 2), in: text),
              let number = Double(text[numRange]) else { return nil }

        let unit = String(text[unitRange]).lowercased()
        if unit.hasPrefix("hour") || unit.hasPrefix("hr") || unit == "h" {
            return Int(number * 60)
        }
        return Int(number)
    }

    private static func extractWordDuration(_ text: String) -> Int? {
        let isHours = text.contains("hour") || text.contains("hr")
        let isMinutes = text.contains("minute") || text.contains("min")

        // "two and a half hours"
        if text.contains("and a half") || text.contains("and half") {
            for (word, val) in wordToNumber {
                if text.contains(word) && val >= 1 && val <= 12 {
                    let base = isMinutes ? val : val * 60
                    return base + 30
                }
            }
        }

        // "about three hours", "three hours"
        for (word, val) in wordToNumber {
            if text.contains(word) {
                if isHours { return val * 60 }
                if isMinutes { return val }
            }
        }

        return nil
    }

    private static func bareNumber(_ text: String) -> Int? {
        // Strip filler: "about", "around", "roughly", "like"
        let stripped = text
            .replacingOccurrences(of: "about ", with: "")
            .replacingOccurrences(of: "around ", with: "")
            .replacingOccurrences(of: "roughly ", with: "")
            .replacingOccurrences(of: "like ", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let n = Int(stripped) { return n }
        return wordToNumber[stripped]
    }

    // MARK: - Skip / Done / NoMore / Repeat / GoBack / Undo

    private static let skipWords: Set<String> = ["skip", "next", "pass", "skip it", "next one"]

    private static func isSkip(_ text: String) -> Bool {
        skipWords.contains(text)
    }

    private static let doneWords: Set<String> = [
        "done", "finished", "that's it", "thats it", "that's all", "thats all",
        "i'm done", "im done", "all done", "we're done", "were done"
    ]

    private static func isDone(_ text: String) -> Bool {
        doneWords.contains(text) || doneWords.contains { text.hasPrefix($0) }
    }

    private static let noMoreWords: Set<String> = [
        "no more", "nothing else", "nothing more", "that's everything", "thats everything"
    ]

    private static func isNoMore(_ text: String) -> Bool {
        noMoreWords.contains(text) || noMoreWords.contains { text.hasPrefix($0) }
    }

    private static let repeatWords: Set<String> = [
        "repeat", "say again", "say that again", "what", "what?", "pardon",
        "come again", "repeat that", "one more time", "huh"
    ]

    private static func isRepeat(_ text: String) -> Bool {
        repeatWords.contains(text) || repeatWords.contains { text.hasPrefix($0) }
    }

    private static let goBackWords: Set<String> = [
        "go back", "previous", "back", "go back one", "previous step",
        "previous question", "back up"
    ]

    private static func isGoBack(_ text: String) -> Bool {
        goBackWords.contains(text) || goBackWords.contains { text.hasPrefix($0) }
    }

    private static let undoWords: Set<String> = [
        "undo", "take that back", "cancel that", "undo that", "revert",
        "never mind", "nevermind", "scratch that"
    ]

    private static func isUndo(_ text: String) -> Bool {
        undoWords.contains(text) || undoWords.contains { text.hasPrefix($0) }
    }

    // MARK: - Add task parsing

    private static func parseAddTask(_ text: String) -> VoiceResponse? {
        // "add call John", "add review the deck"
        let prefixes = ["add ", "add a ", "add task ", "new task "]
        for prefix in prefixes {
            if text.hasPrefix(prefix) {
                let description = String(text.dropFirst(prefix.count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !description.isEmpty else { return nil }
                return .addTask(description)
            }
        }
        return nil
    }

    // MARK: - Move to tomorrow / defer parsing

    private static func parseMoveToTomorrow(_ text: String) -> VoiceResponse? {
        let triggers = ["move to tomorrow", "defer", "push to tomorrow", "tomorrow",
                        "move it to tomorrow", "do it tomorrow", "defer that"]
        guard triggers.contains(where: { text.contains($0) }) else { return nil }
        // Check for item number: "move the third to tomorrow", "defer number 2"
        for (word, idx) in ordinalToIndex {
            if text.contains(word) { return .moveToTomorrow(idx) }
        }
        // Check bare digit: "defer 3"
        let pattern = #"(\d+)"#
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let range = Range(match.range(at: 1), in: text),
           let num = Int(text[range]) {
            return .moveToTomorrow(num)
        }
        return .moveToTomorrow(nil)
    }

    // MARK: - Remove parsing

    private static let ordinalToIndex: [String: Int] = [
        "first": 1, "second": 2, "third": 3, "fourth": 4, "fifth": 5,
        "last": -1, "1st": 1, "2nd": 2, "3rd": 3, "4th": 4, "5th": 5
    ]

    private static func parseEstimateOverride(_ text: String) -> VoiceResponse? {
        // "make the third one 20 minutes", "change the second to 45 minutes"
        guard text.contains("make") || text.contains("change") || text.contains("set") else { return nil }
        var ordinal: Int?
        for (word, idx) in ordinalToIndex {
            if text.contains(word) { ordinal = idx; break }
        }
        guard let ord = ordinal else { return nil }
        // Extract minutes: look for a number followed by optional min/minutes
        let pattern = #"(\d+)\s*(?:min|mins|minutes|m\b)?"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text),
              let mins = Int(text[range]) else { return nil }
        return .estimateOverride(ordinal: ord, minutes: mins)
    }

    private static func parseRemove(_ text: String) -> VoiceResponse? {
        guard text.contains("remove") || text.contains("drop") || text.contains("delete") else { return nil }
        for (word, idx) in ordinalToIndex {
            if text.contains(word) { return .removeItem(idx) }
        }
        return nil
    }

    // MARK: - Adjust end time parsing

    private static func parseAdjustEndTime(_ text: String) -> VoiceResponse? {
        // "I'm leaving at 3", "leaving at 3pm", "finishing at 5", "done at 4", "wrapping up at 2"
        let triggers = ["leaving at", "leave at", "finishing at", "done at", "wrapping up at",
                        "stopping at", "stop at", "out at", "going at", "heading out at"]
        guard triggers.contains(where: { text.contains($0) }) else { return nil }

        // Extract hour: "3", "3pm", "15", "3:00"
        let pattern = #"at\s+(\d{1,2})(?::(\d{2}))?\s*(?:pm|p\.m\.?)?"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let hourRange = Range(match.range(at: 1), in: text),
              var hour = Int(text[hourRange]) else { return nil }

        // Normalise to 24h: if 1-12 and contains "pm" or hour < 7 (likely afternoon), add 12
        let isPM = text.contains("pm") || text.contains("p.m")
        if isPM && hour < 12 { hour += 12 }
        else if hour >= 1 && hour <= 6 { hour += 12 } // "leaving at 3" means 15:00
        guard hour >= 7 && hour <= 23 else { return nil }
        return .adjustEndTime(hour)
    }

    // MARK: - Subtract time parsing

    private static func parseSubtractTime(_ text: String) -> VoiceResponse? {
        // "I have a call not on my calendar for 30 minutes", "subtract 45 minutes"
        let triggers = ["not on my calendar", "subtract", "minus", "take off", "remove time"]
        guard triggers.contains(where: { text.contains($0) }) else { return nil }
        if let mins = parseMinutes(text) { return .subtractTime(mins) }
        return nil
    }

    // MARK: - Swap parsing

    private static func parseSwap(_ text: String) -> VoiceResponse? {
        guard text.contains("swap") || text.contains("switch") || text.contains("flip") else { return nil }
        if text.contains("first two") || text.contains("top two") {
            return .swapItems(1, 2)
        }
        // "swap 1 and 3"
        let pattern = #"(\d+)\s*(?:and|with)\s*(\d+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let r1 = Range(match.range(at: 1), in: text), let a = Int(text[r1]),
              let r2 = Range(match.range(at: 2), in: text), let b = Int(text[r2])
        else { return nil }
        return .swapItems(a, b)
    }
}
