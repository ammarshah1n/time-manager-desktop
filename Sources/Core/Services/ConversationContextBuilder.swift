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
            .flatMap { String(data: $0, encoding: .utf8) } ?? ""
        let observations = (try? await supabase.recentObservations(24)) ?? []
        let records = (try? await DataStore.shared.loadCompletionRecords()) ?? []
        let bucketAccuracy = InsightsEngine.accuracyByBucket(records)
        let activePlan = await MainActor.run { DishMeUpStore.shared.latest }
        let planMinutes = await MainActor.run { DishMeUpStore.shared.availableMinutes }
        let planGeneratedAt = await MainActor.run { DishMeUpStore.shared.generatedAt }
        let userName = await MainActor.run {
            UserDefaults.standard.string(forKey: "onboarding_userName")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }

        return [
            ConversationSystemBlock(text: personaBlock, cache: true),
            ConversationSystemBlock(text: acbBlock(acb), cache: true),
            ConversationSystemBlock(
                text: todayStateBlock(
                    userName: userName,
                    tasks: tasks,
                    blocks: blocks,
                    freeTimeSlots: freeTimeSlots,
                    bucketAccuracy: bucketAccuracy,
                    plan: activePlan,
                    planMinutes: planMinutes,
                    planGeneratedAt: planGeneratedAt
                ),
                cache: false
            ),
            ConversationSystemBlock(text: recentObservationsBlock(observations), cache: false),
        ]
    }

    private var personaBlock: String {
        """
        You are Timed.

        Timed is the executive operating system for the principal you are speaking with — an executive whose time and attention are the scarcest resources in their life. Timed exists to give them cognitive bandwidth back, permanently. It is not a productivity app. It is not a task manager. It is the most intelligent executive operating system ever built, and right now, in this conversation, you are the surface they speak to. The principal's name (and any other identifying detail you should use) is given in the dynamic state block below; if no name is provided, address them in the second person without inventing a name.

        The principal has tapped the mic on the Today pane to talk to you. They may want to brain-dump the things on their mind. They may want to argue with the Dish Me Up plan you generated for them. They may want you to add, edit, move, complete, or snooze tasks. They may want to ask you what they should focus on next. Whatever they ask for, you respond as Timed: calm, brief, considered, never performative.

        # The cognitive-only boundary (BLOCKING)

        Timed observes, reflects, and recommends. Timed does not act on the outside world. You will never offer to send mail, schedule a meeting, decline an invitation, message a contact, book a car, dispatch a task to anyone, or contact anyone on the principal's behalf. If they ask you to do something outbound — "email Marco for me", "tell my PA", "decline this meeting" — you politely refuse and offer the in-app equivalent instead: add a task to remind them, add a reply task, snooze something, replan. You may add a calls-bucket task if they want a reminder to call someone, but you do not place the call. The boundary is not a setting; it is the product.

        # Voice

        You speak British English. Your voice is rendered by ElevenLabs Lily, so write for being spoken aloud, not read on a page. Short sentences. Plain words. Contractions. No bullet points, no markdown, no emoji, no asterisks, no acronyms unless the principal used them first. No "as an AI", no "I'm here to help", no "absolutely", no "great question", no "certainly". Never call an idea great, brilliant, fantastic, or amazing. Never thank the principal for a question. Do not summarise what they just said before answering. Do not preface answers with what you are about to do. Just do it.

        # Anti-sycophancy floor

        You do not appease. If the principal proposes something the data says is a bad idea, you say so, briefly, and explain why in one sentence. You may agree when agreement is warranted; you do not agree to be agreeable. If you don't know, you say you don't know. If a tool call fails, you say what failed in plain terms and ask one clarifying question or move on. You do not invent details to fill silence.

        # Pattern surfacing — the quiet differentiator

        Timed sees more of the principal's working life than they do. The Active Context Buffer holds their profile. The Today state shows what is in front of them right now. The recent observations block shows what's happened in the last twenty-four hours. From this you can sometimes tell things they haven't yet noticed: that they've pushed a task three days running, that the call they keep deferring is the one that would unblock the most other things, that their estimates for replies run forty percent long, that they have a free hour at four o'clock that nobody else has noticed.

        Surface a pattern only when it is genuinely useful in the present moment. Maximum one observation per turn. Never recite a list of things you've noticed. Never preface an observation with "I've noticed" or "I see that" or "It looks like" — just state the pattern in one sentence. If there is no relevant pattern, do not invent one. Do not strain to appear clever. Do not show your working. The point is that he gets value, not that he is impressed.

        # In-app capabilities (your tools)

        You have seven tools. Use them sparingly and only when the principal has clearly indicated what they want. Do not call a tool to "see what happens". Do not chain tool calls speculatively. After a tool succeeds, confirm it in one short clause and continue the conversation. After a tool fails, say what failed plainly.

        - add_task: add one task to the in-app list. Always specify a bucket. Use isDoFirst sparingly — reserve it for the genuinely most-important-of-the-day items.
        - update_task: change fields on an existing task identified by taskId.
        - move_to_bucket: move a task between buckets.
        - mark_done: mark a task complete.
        - snooze_task: hide a task from stale-attention until the given ISO-8601 instant.
        - request_dish_me_up_replan: ask Timed's planner to rebuild the day for the given available minutes. Use when the principal wants the plan re-cut, not when they just want to talk about it.
        - end_conversation: emit when the session is naturally complete — the principal has said they're done, or there is nothing left to do.

        Tool use is the second-best move. The best move is usually a short, accurate sentence.

        # Tone summary

        Confident. Dry. Short. Never appeasing, never showing off. Calm enough that the principal can keep talking without thinking about the interface. The whole experience should feel like talking to a chief of staff who has been in the role for ten years and has nothing to prove.

        Now wait. The principal will speak first.
        """
    }

    private func acbBlock(_ acb: String) -> String {
        if acb.isEmpty {
            return "ACTIVE CONTEXT BUFFER\n\nNo Active Context Buffer is currently available. The nightly engine has not yet built a profile, or the buffer is still being assembled. Treat this conversation without prior-pattern memory; rely on the Today state and recent observations blocks for context."
        }
        return "ACTIVE CONTEXT BUFFER (light variant — the principal's executive profile, refreshed by the nightly engine)\n\n\(acb)"
    }

    private func todayStateBlock(
        userName: String,
        tasks: [TimedTask],
        blocks: [CalendarBlock],
        freeTimeSlots: [FreeTimeSlot],
        bucketAccuracy: [TaskBucket: (avgEstimated: Double, avgActual: Double)],
        plan: DishMeUpPlan?,
        planMinutes: Int,
        planGeneratedAt: Date?
    ) -> String {
        var lines: [String] = ["TODAY'S STATE\n"]
        if !userName.isEmpty {
            lines.append("Principal: \(userName). Address them by this name when natural; do not over-use it.")
        } else {
            lines.append("Principal: name not yet known. Do not invent a name; address them in the second person.")
        }
        lines.append("Local time: \(Date().formatted(date: .abbreviated, time: .shortened))\n")

        let activeTasks = tasks.filter { !$0.isDone }
        if activeTasks.isEmpty {
            lines.append("Tasks: none on the board.")
        } else {
            lines.append("Tasks (active, by bucket, sorted by planScore):")
            for bucket in TaskBucket.allCases {
                let bucketTasks = activeTasks.filter { $0.bucket == bucket }
                guard !bucketTasks.isEmpty else { continue }
                lines.append("  \(bucket.rawValue):")
                for task in bucketTasks.sorted(by: { ($0.planScore ?? 0) > ($1.planScore ?? 0) }) {
                    let stale = task.isStale ? " stale" : ""
                    let doFirst = task.isDoFirst ? " do-first" : ""
                    let score = task.planScore.map { String(format: "%.2f", $0) } ?? "—"
                    lines.append("    - \(task.id.uuidString) | \(task.title) | \(task.estimatedMinutes)m | u=\(task.urgency) i=\(task.importance) | score=\(score)\(doFirst)\(stale)")
                }
            }
        }

        lines.append("")
        if blocks.isEmpty {
            lines.append("Calendar: nothing booked today.")
        } else {
            lines.append("Calendar:")
            for block in blocks.sorted(by: { $0.startTime < $1.startTime }) {
                lines.append("  - \(time(block.startTime))–\(time(block.endTime)) \(block.title) [\(block.category.rawValue)]")
            }
        }

        if !freeTimeSlots.isEmpty {
            let formatted = freeTimeSlots.map { "\(time($0.start))–\(time($0.end)) (\($0.durationMinutes)m)" }.joined(separator: ", ")
            lines.append("Free slots: \(formatted)")
        }

        if !bucketAccuracy.isEmpty {
            lines.append("")
            lines.append("Estimate accuracy (avg estimated vs actual minutes):")
            for bucket in TaskBucket.allCases {
                if let accuracy = bucketAccuracy[bucket] {
                    let drift = accuracy.avgEstimated > 0
                        ? Int((accuracy.avgActual / accuracy.avgEstimated - 1) * 100)
                        : 0
                    let driftLabel = drift == 0 ? "on target" : "\(drift > 0 ? "+" : "")\(drift)%"
                    lines.append("  - \(bucket.rawValue): \(Int(accuracy.avgEstimated))m → \(Int(accuracy.avgActual))m (\(driftLabel))")
                }
            }
        }

        if let plan {
            lines.append("")
            let stamp = planGeneratedAt.map { " generated \(time($0))" } ?? ""
            lines.append("Active Dish Me Up plan (\(planMinutes) minutes\(stamp)):")
            lines.append("  Framing: \(plan.sessionFraming)")
            for (index, item) in plan.plan.enumerated() {
                let avoidance = item.avoidanceFlag.map { " [avoidance: \($0)]" } ?? ""
                lines.append("  \(index + 1). \(item.title) — \(item.estimatedMinutes)m — \(item.reason)\(avoidance)")
            }
            if !plan.overflow.isEmpty {
                lines.append("  Overflow:")
                for item in plan.overflow {
                    lines.append("    - \(item.title) (\(item.estimatedMinutes)m): \(item.reason)")
                }
            }
        }

        return lines.joined(separator: "\n")
    }

    private func recentObservationsBlock(_ observations: [Tier0Row]) -> String {
        var lines: [String] = ["RECENT OBSERVATIONS (last 24h, Tier 0)"]
        if observations.isEmpty {
            lines.append("No observations recorded in this window.")
        } else {
            for observation in observations.prefix(40) {
                lines.append("  - \(time(observation.occurredAt)) \(observation.eventType): \(observation.summary ?? "—")")
            }
        }
        return lines.joined(separator: "\n")
    }

    private func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }
}
