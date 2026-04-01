import Foundation

protocol TimedScheduling: Sendable {
    func suggestBlocks(for emails: [EmailMessage]) -> [CalendarBlock]
}

struct TimedSchedulerService: TimedScheduling {
    func suggestBlocks(for emails: [EmailMessage]) -> [CalendarBlock] {
        let classifier = EmailClassifierService()
        var blocks: [CalendarBlock] = []
        var currentTime = Date()

        for email in emails {
            let category = classifier.classify(email, senderRules: [])
            guard category == .actionRequired else { continue }

            let block = CalendarBlock(
                id: UUID(),
                title: "Focus: \(email.subject)",
                startTime: currentTime,
                endTime: currentTime.addingTimeInterval(30 * 60),
                sourceEmailId: email.id,
                category: .focus
            )
            blocks.append(block)
            currentTime = block.endTime
        }

        return blocks
    }
}
