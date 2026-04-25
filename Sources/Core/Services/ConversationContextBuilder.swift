import Dependencies
import Foundation

struct ConversationSystemBlock {
    let text: String
    let cache: Bool

    var payload: [String: Any] {
        var block: [String: Any] = [
            "type": "text",
            "text": text,
        ]
        if cache {
            block["cache_control"] = ["type": "ephemeral"]
        }
        return block
    }
}

struct ConversationContextBuilder {
    @Dependency(\.supabaseClient) private var supabase

    func build(
        tasks: [TimedTask],
        blocks: [CalendarBlock],
        freeTimeSlots: [FreeTimeSlot]
    ) async -> [ConversationSystemBlock] {
        let acb = (try? await MemoryStoreActor.shared.activeContextBuffer(variant: .light))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "No active context buffer available."
        let observations = (try? await supabase.recentObservations(24)) ?? []
        let records = (try? await DataStore.shared.loadCompletionRecords()) ?? []
        let bucketAccuracy = InsightsEngine.accuracyByBucket(records)

        return [
            ConversationSystemBlock(text: personaBlock, cache: true),
            ConversationSystemBlock(text: "ACB-light:\n\(acb)", cache: true),
            ConversationSystemBlock(text: todayStateBlock(tasks: tasks, blocks: blocks, freeTimeSlots: freeTimeSlots, bucketAccuracy: bucketAccuracy), cache: false),
            ConversationSystemBlock(text: recentObservationsBlock(observations), cache: false),
        ]
    }

    private var personaBlock: String {
        """
        You are Timed, an executive operating system for Yasser Shahin. You observe, reflect, and recommend. You do not act on the outside world — never send mail, schedule, delegate, or contact anyone. You speak in calm, short British English sentences (Lily TTS). You never appease. You don't call ideas 'great'. You push back when warranted — including pointing out avoidance patterns the data shows. You surface what you've learned only when it's useful in this moment, not to impress. You never strain to appear clever. You are confident, dry, and short.
        """
    }

    private func todayStateBlock(
        tasks: [TimedTask],
        blocks: [CalendarBlock],
        freeTimeSlots: [FreeTimeSlot],
        bucketAccuracy: [TaskBucket: (avgEstimated: Double, avgActual: Double)]
    ) -> String {
        var lines: [String] = ["Today's state:"]
        for bucket in TaskBucket.allCases {
            let bucketTasks = tasks.filter { $0.bucket == bucket && !$0.isDone }
            guard !bucketTasks.isEmpty else { continue }
            lines.append("\n\(bucket.rawValue):")
            for task in bucketTasks.sorted(by: { ($0.planScore ?? 0) > ($1.planScore ?? 0) }) {
                lines.append("- \(task.id.uuidString): \(task.title) | \(task.estimatedMinutes)m | do_first=\(task.isDoFirst) | stale=\(task.isStale) | score=\(task.planScore ?? 0) | urgency=\(task.urgency) | importance=\(task.importance)")
            }
        }

        lines.append("\nCalendar blocks:")
        if blocks.isEmpty {
            lines.append("- none")
        } else {
            for block in blocks.sorted(by: { $0.startTime < $1.startTime }) {
                lines.append("- \(time(block.startTime))-\(time(block.endTime)): \(block.title) (\(block.category.rawValue))")
            }
        }

        lines.append("\nFree-time slots:")
        if freeTimeSlots.isEmpty {
            lines.append("- none")
        } else {
            for slot in freeTimeSlots {
                lines.append("- \(time(slot.start))-\(time(slot.end)): \(slot.durationMinutes)m")
            }
        }

        lines.append("\nBucket accuracy:")
        if bucketAccuracy.isEmpty {
            lines.append("- insufficient completion data")
        } else {
            for bucket in TaskBucket.allCases {
                if let accuracy = bucketAccuracy[bucket] {
                    lines.append("- \(bucket.rawValue): estimated avg \(Int(accuracy.avgEstimated))m, actual avg \(Int(accuracy.avgActual))m")
                }
            }
        }

        lines.append("\nActive Dish Me Up plan: not available in this pane state.")
        return lines.joined(separator: "\n")
    }

    private func recentObservationsBlock(_ observations: [Tier0Row]) -> String {
        var lines: [String] = ["Recent Tier 0 observations, last 24h:"]
        if observations.isEmpty {
            lines.append("- none available")
        } else {
            for observation in observations.prefix(30) {
                lines.append("- \(time(observation.occurredAt)): \(observation.eventType) — \(observation.summary ?? "no summary")")
            }
        }
        return lines.joined(separator: "\n")
    }

    private func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }
}
