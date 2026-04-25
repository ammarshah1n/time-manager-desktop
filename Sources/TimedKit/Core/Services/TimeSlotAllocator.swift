// TimeSlotAllocator.swift — Timed Core
// Calendar-aware time-slot allocation. Takes calendar blocks + scored tasks,
// produces a time-slotted day plan with energy-tier matching and incremental repair.
// Pure Swift. No I/O. No async.

import Foundation

// MARK: - Supporting Types

struct TimeSlot: Sendable {
    let start: Date
    let end: Date
    var durationMinutes: Int { Int(end.timeIntervalSince(start) / 60) }
    let energyTier: EnergyTier

    enum EnergyTier: Sendable {
        case high, medium, low

        /// Preferred tier for a given bucket type.
        static func preferred(for bucketType: String) -> EnergyTier {
            switch bucketType {
            case "action":  return .high
            case "calls":   return .high
            case "reply":   return .medium
            case "read":    return .low
            case "transit": return .low
            default:        return .medium
            }
        }
    }
}

struct ScheduleConfig: Sendable {
    var minGapMinutes: Int = 15
    var preMeetingBufferMinutes: Int = 5
    var postMeetingBufferMinutes: Int = 10
    var utilizationCap: Double = 0.75  // 75% of free time
    var deepWorkMinGap: Int = 45
    var contextSwitchTaxMinutes: Int = 10

    static let `default` = ScheduleConfig()
}

struct SlotAssignment: Sendable {
    let taskId: UUID
    let slotStart: Date
    let slotEnd: Date
    let isSuggested: Bool  // false = user-locked
    let priorityScore: Double
}

struct AllocationResult: Sendable {
    let scheduled: [SlotAssignment]
    let deferred: [UUID]  // task IDs that didn't fit
    let totalFreeMinutes: Int
    let totalScheduledMinutes: Int
    let utilizationPercent: Double
    let warningMessage: String?
}

// MARK: - Task Input

struct SlotTaskInput: Sendable {
    let id: UUID
    let estimatedMinutes: Int
    let bucketType: String
    let priorityScore: Double
    let isLocked: Bool
    let lockedStartTime: Date?
    let prepForMeetingId: UUID?
}

// MARK: - Disruption / Repair Types

enum DisruptionType: Sendable {
    case meetingOverrun(meetingId: UUID, extraMinutes: Int)
    case newUrgentTask(taskId: UUID, estimatedMinutes: Int, priorityScore: Double)
    case taskRanLong(taskId: UUID, extraMinutes: Int)
}

struct RepairResult: Sendable {
    let updatedSchedule: [SlotAssignment]
    let deferredTasks: [UUID]
    let notifications: [RepairNotification]
}

enum RepairNotification: Sendable, Equatable {
    case shifted(taskId: UUID, byMinutes: Int)
    case deferredToTomorrow(taskId: UUID)
    case urgentInserted(taskId: UUID, at: Date)
    case extendedIntoBuffer(taskId: UUID)
}

// MARK: - TimeSlotAllocator

enum TimeSlotAllocator {

    // MARK: - Main Entry Point

    static func buildDayPlan(
        calendarBlocks: [CalendarBlock],
        tasks: [SlotTaskInput],
        workStart: Date,
        workEnd: Date,
        config: ScheduleConfig = .default
    ) -> AllocationResult {

        // Phase 1 — Extract usable gaps
        var gaps = extractUsableGaps(
            calendarBlocks: calendarBlocks,
            workStart: workStart,
            workEnd: workEnd,
            config: config
        )

        let totalFreeMinutes = gaps.reduce(0) { $0 + $1.durationMinutes }

        // Phase 2 — Over-scheduling check
        let lockedTasks = tasks.filter { $0.isLocked }
        let freeTasks = tasks.filter { !$0.isLocked }
        let totalDemanded = freeTasks.reduce(0) { $0 + $1.estimatedMinutes }

        var warningMessage: String?
        if totalFreeMinutes > 0 {
            let ratio = Double(totalDemanded) / Double(totalFreeMinutes)
            if ratio > config.utilizationCap {
                let overMinutes = totalDemanded - Int(Double(totalFreeMinutes) * config.utilizationCap)
                warningMessage = "Over-scheduled by ~\(overMinutes) min. \(Int(ratio * 100))% utilisation vs \(Int(config.utilizationCap * 100))% cap."
            }
        } else if totalDemanded > 0 {
            warningMessage = "No free time available. \(totalDemanded) min of tasks cannot be scheduled."
        }

        // Phase 3 — Place locked tasks first
        var scheduled: [SlotAssignment] = []
        for task in lockedTasks {
            guard let lockTime = task.lockedStartTime else { continue }
            let lockEnd = lockTime.addingTimeInterval(Double(task.estimatedMinutes) * 60)
            scheduled.append(SlotAssignment(
                taskId: task.id,
                slotStart: lockTime,
                slotEnd: lockEnd,
                isSuggested: false,
                priorityScore: task.priorityScore
            ))
            gaps = consumeGapTime(gaps: gaps, start: lockTime, end: lockEnd)
        }

        // Phase 4 — Place free tasks (scored greedy with energy matching)
        let sortedFreeTasks = freeTasks.sorted { $0.priorityScore > $1.priorityScore }
        var deferredIds: [UUID] = []
        // Build meeting lookup for prepForMeetingId matching
        let meetingLookup = Dictionary(uniqueKeysWithValues:
            calendarBlocks.filter { $0.category == .meeting }.map { ($0.id, $0) }
        )

        for task in sortedFreeTasks {
            let bestResult = findBestGap(
                for: task,
                in: gaps,
                meetingLookup: meetingLookup,
                workStart: workStart,
                workEnd: workEnd
            )

            guard let (_, placement) = bestResult else {
                deferredIds.append(task.id)
                continue
            }

            let taskEnd = placement.addingTimeInterval(Double(task.estimatedMinutes) * 60)
            scheduled.append(SlotAssignment(
                taskId: task.id,
                slotStart: placement,
                slotEnd: taskEnd,
                isSuggested: true,
                priorityScore: task.priorityScore
            ))
            gaps = consumeGapTime(gaps: gaps, start: placement, end: taskEnd)
            // Re-filter gaps below min threshold after consumption
            gaps = gaps.filter { $0.durationMinutes >= config.minGapMinutes }
        }

        // Phase 5 — Trim to utilization cap (hard enforcement)
        let capMinutes = Int(Double(totalFreeMinutes) * config.utilizationCap)
        var totalScheduled = scheduled.reduce(0) { $0 + Int($1.slotEnd.timeIntervalSince($1.slotStart) / 60) }

        if totalScheduled > capMinutes {
            // Drop lowest-priority suggested tasks until under cap
            let suggestedSorted = scheduled
                .filter { $0.isSuggested }
                .sorted { $0.priorityScore < $1.priorityScore }

            for assignment in suggestedSorted {
                guard totalScheduled > capMinutes else { break }
                let taskMinutes = Int(assignment.slotEnd.timeIntervalSince(assignment.slotStart) / 60)
                scheduled.removeAll { $0.taskId == assignment.taskId }
                deferredIds.append(assignment.taskId)
                totalScheduled -= taskMinutes
            }
        }

        // Phase 6 — Build result
        let finalScheduledMinutes = scheduled.reduce(0) {
            $0 + Int($1.slotEnd.timeIntervalSince($1.slotStart) / 60)
        }
        let utilization = totalFreeMinutes > 0
            ? Double(finalScheduledMinutes) / Double(totalFreeMinutes)
            : 0.0

        return AllocationResult(
            scheduled: scheduled.sorted { $0.slotStart < $1.slotStart },
            deferred: deferredIds,
            totalFreeMinutes: totalFreeMinutes,
            totalScheduledMinutes: finalScheduledMinutes,
            utilizationPercent: utilization,
            warningMessage: warningMessage
        )
    }

    // MARK: - Incremental Repair

    static func repairPlan(
        currentPlan: [SlotAssignment],
        calendarBlocks: [CalendarBlock],
        disruption: DisruptionType,
        currentTime: Date,
        workEnd: Date,
        config: ScheduleConfig = .default
    ) -> RepairResult {
        var plan = currentPlan.sorted { $0.slotStart < $1.slotStart }
        var deferred: [UUID] = []
        var notifications: [RepairNotification] = []

        switch disruption {

        case .meetingOverrun(let meetingId, let extraMinutes):
            guard let meeting = calendarBlocks.first(where: { $0.id == meetingId }) else {
                return RepairResult(updatedSchedule: plan, deferredTasks: [], notifications: [])
            }
            let shiftAmount = Double(extraMinutes) * 60

            // Shift all uncommitted tasks that start after the meeting's original end
            var updated: [SlotAssignment] = []
            for assignment in plan {
                guard assignment.slotStart >= meeting.endTime else {
                    updated.append(assignment)
                    continue
                }

                let newStart = assignment.slotStart.addingTimeInterval(shiftAmount)
                let newEnd = assignment.slotEnd.addingTimeInterval(shiftAmount)

                if newEnd > workEnd {
                    deferred.append(assignment.taskId)
                    notifications.append(.deferredToTomorrow(taskId: assignment.taskId))
                } else {
                    notifications.append(.shifted(taskId: assignment.taskId, byMinutes: extraMinutes))
                    updated.append(SlotAssignment(
                        taskId: assignment.taskId,
                        slotStart: newStart,
                        slotEnd: newEnd,
                        isSuggested: assignment.isSuggested,
                        priorityScore: assignment.priorityScore
                    ))
                }
            }
            plan = updated

        case .newUrgentTask(let taskId, let estimatedMinutes, let priorityScore):
            let taskDuration = Double(estimatedMinutes) * 60
            let futurePlan = plan.filter { $0.slotEnd > currentTime }.sorted { $0.slotStart < $1.slotStart }
            var inserted = false

            // Try to find a gap between existing tasks
            var searchStart = currentTime
            for assignment in futurePlan {
                let gapDuration = assignment.slotStart.timeIntervalSince(searchStart)
                if gapDuration >= taskDuration {
                    let urgentEnd = searchStart.addingTimeInterval(taskDuration)
                    plan.append(SlotAssignment(
                        taskId: taskId,
                        slotStart: searchStart,
                        slotEnd: urgentEnd,
                        isSuggested: true,
                        priorityScore: priorityScore
                    ))
                    notifications.append(.urgentInserted(taskId: taskId, at: searchStart))
                    inserted = true
                    break
                }
                searchStart = assignment.slotEnd
            }

            // Try gap after last task
            if !inserted {
                let lastEnd = futurePlan.last?.slotEnd ?? currentTime
                let gapToWorkEnd = workEnd.timeIntervalSince(lastEnd)
                if gapToWorkEnd >= taskDuration {
                    plan.append(SlotAssignment(
                        taskId: taskId,
                        slotStart: lastEnd,
                        slotEnd: lastEnd.addingTimeInterval(taskDuration),
                        isSuggested: true,
                        priorityScore: priorityScore
                    ))
                    notifications.append(.urgentInserted(taskId: taskId, at: lastEnd))
                    inserted = true
                }
            }

            // Still no room — bump lowest-priority suggested task
            if !inserted {
                if let lowestIdx = plan
                    .enumerated()
                    .filter({ $0.element.isSuggested && $0.element.slotStart > currentTime })
                    .min(by: { $0.element.priorityScore < $1.element.priorityScore })?.offset
                {
                    let bumped = plan[lowestIdx]
                    deferred.append(bumped.taskId)
                    notifications.append(.deferredToTomorrow(taskId: bumped.taskId))
                    plan[lowestIdx] = SlotAssignment(
                        taskId: taskId,
                        slotStart: bumped.slotStart,
                        slotEnd: bumped.slotStart.addingTimeInterval(taskDuration),
                        isSuggested: true,
                        priorityScore: priorityScore
                    )
                    notifications.append(.urgentInserted(taskId: taskId, at: bumped.slotStart))
                }
            }

        case .taskRanLong(let taskId, let extraMinutes):
            guard let taskIdx = plan.firstIndex(where: { $0.taskId == taskId }) else {
                return RepairResult(updatedSchedule: plan, deferredTasks: [], notifications: [])
            }

            let task = plan[taskIdx]
            let extensionSeconds = Double(extraMinutes) * 60
            let newEnd = task.slotEnd.addingTimeInterval(extensionSeconds)

            // Find the next task in chronological order
            let sortedPlan = plan.sorted { $0.slotStart < $1.slotStart }
            let taskInSorted = sortedPlan.firstIndex(where: { $0.taskId == taskId })
            let nextTask = taskInSorted.flatMap { idx in
                idx + 1 < sortedPlan.count ? sortedPlan[idx + 1] : nil
            }

            if let next = nextTask, newEnd > next.slotStart {
                // Check if shifting subsequent tasks keeps them within workEnd
                let lastSubsequent = sortedPlan.last { $0.slotStart >= next.slotStart }
                let lastSubsequentNewEnd = (lastSubsequent?.slotEnd ?? next.slotEnd).addingTimeInterval(extensionSeconds)

                if lastSubsequentNewEnd <= workEnd {
                    // Extend current task
                    plan[taskIdx] = SlotAssignment(
                        taskId: taskId,
                        slotStart: task.slotStart,
                        slotEnd: newEnd,
                        isSuggested: task.isSuggested,
                        priorityScore: task.priorityScore
                    )
                    notifications.append(.extendedIntoBuffer(taskId: taskId))

                    // Shift subsequent tasks
                    for i in plan.indices where plan[i].slotStart >= next.slotStart && plan[i].taskId != taskId {
                        let shifted = plan[i]
                        let newStart = shifted.slotStart.addingTimeInterval(extensionSeconds)
                        let newEndShifted = shifted.slotEnd.addingTimeInterval(extensionSeconds)
                        plan[i] = SlotAssignment(
                            taskId: shifted.taskId,
                            slotStart: newStart,
                            slotEnd: newEndShifted,
                            isSuggested: shifted.isSuggested,
                            priorityScore: shifted.priorityScore
                        )
                        notifications.append(.shifted(taskId: shifted.taskId, byMinutes: extraMinutes))
                    }
                } else {
                    // Can't shift everything — defer the lowest-priority subsequent task
                    let subsequent = plan.filter { $0.slotStart >= next.slotStart && $0.taskId != taskId }
                    if let lowest = subsequent.min(by: { $0.priorityScore < $1.priorityScore }) {
                        deferred.append(lowest.taskId)
                        notifications.append(.deferredToTomorrow(taskId: lowest.taskId))
                        plan.removeAll { $0.taskId == lowest.taskId }

                        plan[plan.firstIndex(where: { $0.taskId == taskId })!] = SlotAssignment(
                            taskId: taskId,
                            slotStart: task.slotStart,
                            slotEnd: newEnd,
                            isSuggested: task.isSuggested,
                            priorityScore: task.priorityScore
                        )
                        notifications.append(.extendedIntoBuffer(taskId: taskId))
                    }
                }
            } else {
                // No overlap — just extend
                plan[taskIdx] = SlotAssignment(
                    taskId: taskId,
                    slotStart: task.slotStart,
                    slotEnd: newEnd,
                    isSuggested: task.isSuggested,
                    priorityScore: task.priorityScore
                )
                notifications.append(.extendedIntoBuffer(taskId: taskId))
            }
        }

        plan.removeAll { deferred.contains($0.taskId) }
        return RepairResult(
            updatedSchedule: plan.sorted { $0.slotStart < $1.slotStart },
            deferredTasks: deferred,
            notifications: notifications
        )
    }

    // MARK: - Free Time Helper

    /// Computes available free time from calendar blocks within a work window.
    /// Replaces the "how many hours today?" question.
    static func computeFreeTime(
        calendarBlocks: [CalendarBlock],
        workStart: Date,
        workEnd: Date,
        config: ScheduleConfig = .default
    ) -> (totalFreeMinutes: Int, gapCount: Int, meetingMinutes: Int) {
        let gaps = extractUsableGaps(
            calendarBlocks: calendarBlocks,
            workStart: workStart,
            workEnd: workEnd,
            config: config
        )

        let totalFree = gaps.reduce(0) { $0 + $1.durationMinutes }
        let meetingMinutes = calendarBlocks
            .filter { $0.category == .meeting }
            .filter { $0.startTime < workEnd && $0.endTime > workStart }
            .reduce(0) { total, block in
                let effectiveStart = max(block.startTime, workStart)
                let effectiveEnd = min(block.endTime, workEnd)
                return total + max(0, Int(effectiveEnd.timeIntervalSince(effectiveStart) / 60))
            }

        return (totalFreeMinutes: totalFree, gapCount: gaps.count, meetingMinutes: meetingMinutes)
    }

    // MARK: - Private Helpers

    /// Phase 1: Extract usable gaps from calendar blocks within the work window.
    private static func extractUsableGaps(
        calendarBlocks: [CalendarBlock],
        workStart: Date,
        workEnd: Date,
        config: ScheduleConfig
    ) -> [TimeSlot] {
        // Sort blocks by start time, only those overlapping the work window
        let sorted = calendarBlocks
            .filter { $0.endTime > workStart && $0.startTime < workEnd }
            .sorted { $0.startTime < $1.startTime }

        // Add pre/post buffers around meeting, admin, transit blocks
        var buffered: [(start: Date, end: Date)] = sorted.map { block in
            let needsBuffer = block.category == .meeting
                || block.category == .admin
                || block.category == .transit
            let bufferPre = needsBuffer ? Double(config.preMeetingBufferMinutes) * 60 : 0
            let bufferPost = needsBuffer ? Double(config.postMeetingBufferMinutes) * 60 : 0
            return (
                start: max(workStart, block.startTime.addingTimeInterval(-bufferPre)),
                end: min(workEnd, block.endTime.addingTimeInterval(bufferPost))
            )
        }

        // Merge overlapping buffered blocks
        buffered = mergeIntervals(buffered)

        // Walk from workStart to workEnd, collect uncovered intervals as TimeSlots
        var gaps: [TimeSlot] = []
        var cursor = workStart

        for block in buffered {
            if cursor < block.start {
                gaps.append(makeTimeSlot(start: cursor, end: block.start))
            }
            cursor = max(cursor, block.end)
        }

        // Final gap after last block
        if cursor < workEnd {
            gaps.append(makeTimeSlot(start: cursor, end: workEnd))
        }

        // Filter out gaps below minimum threshold
        return gaps.filter { $0.durationMinutes >= config.minGapMinutes }
    }

    /// Merge overlapping time intervals.
    private static func mergeIntervals(_ intervals: [(start: Date, end: Date)]) -> [(start: Date, end: Date)] {
        guard !intervals.isEmpty else { return [] }
        let sorted = intervals.sorted { $0.start < $1.start }
        var merged: [(start: Date, end: Date)] = [sorted[0]]

        for interval in sorted.dropFirst() {
            if interval.start <= merged[merged.count - 1].end {
                merged[merged.count - 1] = (
                    start: merged[merged.count - 1].start,
                    end: max(merged[merged.count - 1].end, interval.end)
                )
            } else {
                merged.append(interval)
            }
        }
        return merged
    }

    /// Create a TimeSlot with energy tier based on time of day.
    private static func makeTimeSlot(start: Date, end: Date) -> TimeSlot {
        let hour = Calendar.current.component(.hour, from: start)
        let tier: TimeSlot.EnergyTier
        switch hour {
        case 8..<12:  tier = .high
        case 12..<15: tier = .medium
        default:      tier = .low  // 15–18 and outside standard hours
        }
        return TimeSlot(start: start, end: end, energyTier: tier)
    }

    /// Find the best gap for a task using energy-matching scoring.
    private static func findBestGap(
        for task: SlotTaskInput,
        in gaps: [TimeSlot],
        meetingLookup: [UUID: CalendarBlock],
        workStart: Date,
        workEnd: Date
    ) -> (gapIndex: Int, placementStart: Date)? {
        let taskDuration = task.estimatedMinutes
        let preferredTier = TimeSlot.EnergyTier.preferred(for: task.bucketType)
        let workDuration = workEnd.timeIntervalSince(workStart)
        guard workDuration > 0 else { return nil }

        var bestScore = Int.min
        var bestResult: (gapIndex: Int, placementStart: Date)?

        for (index, gap) in gaps.enumerated() {
            guard gap.durationMinutes >= taskDuration else { continue }

            // If task has prepForMeetingId, only consider gaps ending within 60min before that meeting
            if let meetingId = task.prepForMeetingId,
               let meeting = meetingLookup[meetingId] {
                let gapEndToMeeting = meeting.startTime.timeIntervalSince(gap.end)
                if gapEndToMeeting < 0 || gapEndToMeeting > 3600 {
                    continue
                }
            }

            var score = 0

            // Energy tier match: +30 exact, +15 one tier off
            let tierDistance = tierDelta(gap.energyTier, preferredTier)
            if tierDistance == 0 {
                score += 30
            } else if tierDistance == 1 {
                score += 15
            }

            // Earlier-in-day preference (normalized 0–1)
            let normalizedStart = gap.start.timeIntervalSince(workStart) / workDuration
            score += Int(10.0 * (1.0 - normalizedStart))

            // Tight fit bonus: gap - task duration < 30min
            if gap.durationMinutes - taskDuration < 30 {
                score += 5
            }

            if score > bestScore {
                bestScore = score
                bestResult = (gapIndex: index, placementStart: gap.start)
            }
        }

        return bestResult
    }

    /// Compute distance between two energy tiers (0 = same, 1 = adjacent, 2 = opposite).
    private static func tierDelta(_ a: TimeSlot.EnergyTier, _ b: TimeSlot.EnergyTier) -> Int {
        let order: [TimeSlot.EnergyTier] = [.high, .medium, .low]
        guard let ai = order.firstIndex(of: a), let bi = order.firstIndex(of: b) else { return 2 }
        return abs(ai - bi)
    }

    /// Consume a time range from the gap list, splitting gaps as needed.
    private static func consumeGapTime(gaps: [TimeSlot], start: Date, end: Date) -> [TimeSlot] {
        var result: [TimeSlot] = []
        for gap in gaps {
            // No overlap — keep gap as-is
            if gap.end <= start || gap.start >= end {
                result.append(gap)
                continue
            }
            // Portion before consumed range
            if gap.start < start {
                result.append(makeTimeSlot(start: gap.start, end: start))
            }
            // Portion after consumed range
            if gap.end > end {
                result.append(makeTimeSlot(start: end, end: gap.end))
            }
        }
        return result
    }
}
