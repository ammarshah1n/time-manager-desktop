// String+EmailSubject.swift — Timed Core
// Utility extension for cleaning email subject prefixes (Re:, Fwd:, etc.)

import Foundation

extension String {
    /// Strips common email reply/forward prefixes and trims whitespace.
    var cleanedEmailSubject: String {
        var s = self
        let prefixes = ["Re: ", "RE: ", "Fwd: ", "FW: ", "re: ", "fwd: ",
                        "Re:", "RE:", "Fwd:", "FW:", "re:", "fwd:"]
        var changed = true
        while changed {
            changed = false
            for prefix in prefixes {
                if s.hasPrefix(prefix) {
                    s = String(s.dropFirst(prefix.count))
                    changed = true
                }
            }
        }
        return s.trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Subject metadata parsing

    /// Extract priority level (1-3) from subject like "P1" or "Priority 2" (case insensitive).
    var extractedPriority: Int? {
        // Match "P1", "P2", "P3" or "Priority 1", "Priority 2", "Priority 3"
        let pattern = #"(?i)\b(?:P([1-3])\b|Priority\s*([1-3])\b)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: self, range: NSRange(startIndex..., in: self))
        else { return nil }

        // Either capture group 1 (P1 form) or group 2 (Priority 1 form) will have a value
        for group in 1...2 {
            let range = match.range(at: group)
            if range.location != NSNotFound,
               let swiftRange = Range(range, in: self) {
                return Int(self[swiftRange])
            }
        }
        return nil
    }

    /// Extract time estimate in minutes from subject like "30 mins" or "1 hour" (case insensitive).
    var extractedTimeEstimate: Int? {
        // Minutes: "30 mins", "30m", "30 minutes", "30 min"
        let minutePattern = #"(?i)\b(\d+)\s*(?:mins?|minutes?|m)\b"#
        if let regex = try? NSRegularExpression(pattern: minutePattern),
           let match = regex.firstMatch(in: self, range: NSRange(startIndex..., in: self)),
           let range = Range(match.range(at: 1), in: self),
           let value = Int(self[range]) {
            return value
        }

        // Hours: "2 hours", "1hr", "2 hrs", "1h"
        let hourPattern = #"(?i)\b(\d+)\s*(?:hrs?|hours?|h)\b"#
        if let regex = try? NSRegularExpression(pattern: hourPattern),
           let match = regex.firstMatch(in: self, range: NSRange(startIndex..., in: self)),
           let range = Range(match.range(at: 1), in: self),
           let value = Int(self[range]) {
            return value * 60
        }

        return nil
    }

    /// Parse both priority and time estimate from a subject line.
    var parsedSubjectMetadata: (priority: Int?, estimatedMinutes: Int?) {
        (priority: extractedPriority, estimatedMinutes: extractedTimeEstimate)
    }

    /// Returns `true` if this string (typically a sender name) contains the given surname.
    /// Used to detect family emails — same surname -> isDoFirst.
    func isFamilyMember(surname: String) -> Bool {
        guard !surname.isEmpty else { return false }
        return self.localizedCaseInsensitiveContains(surname)
    }
}
