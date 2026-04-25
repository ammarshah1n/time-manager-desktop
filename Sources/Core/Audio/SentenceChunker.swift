import Foundation

struct SentenceChunker {
    var minimumCharacters = 10

    private var buffer = ""
    private var lastAppend = Date.distantPast

    mutating func append(_ delta: String) -> [String] {
        buffer += delta
        lastAppend = Date()

        var chunks: [String] = []
        while let range = sentenceRange(in: buffer) {
            let sentence = String(buffer[..<range.upperBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            buffer.removeSubrange(..<range.upperBound)
            if sentence.count >= minimumCharacters {
                chunks.append(sentence)
            }
        }
        return chunks
    }

    mutating func flushIfIdle(after interval: TimeInterval = 0.2, now: Date = Date()) -> String? {
        guard !buffer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              now.timeIntervalSince(lastAppend) >= interval else {
            return nil
        }
        return flush()
    }

    mutating func flush() -> String? {
        let sentence = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        buffer = ""
        return sentence.isEmpty ? nil : sentence
    }

    private func sentenceRange(in text: String) -> Range<String.Index>? {
        guard text.count >= minimumCharacters else { return nil }
        return text.rangeOfCharacter(from: CharacterSet(charactersIn: ".?!\n"))
    }
}
