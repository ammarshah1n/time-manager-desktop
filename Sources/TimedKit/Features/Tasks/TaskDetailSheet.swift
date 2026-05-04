// TaskDetailSheet.swift — Timed macOS
// Full edit sheet for a TimedTask. Opens when a task row is tapped.
// Accepts a Binding<TimedTask> — changes apply immediately.

import SwiftUI

struct TaskDetailSheet: View {
    @Binding var task: TimedTask
    let onDelete: () -> Void
    let onDismiss: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var notes: String = ""
    @State private var originalEstimatedMinutes: Int?
    @State private var originalBucket: TaskBucket?
    @State private var isEditingWaitingOn = false

    var body: some View {
        NavigationStack {
            Form {
                taskInfoSection
                schedulingSection
                statusSection
                notesSection
                deleteSection
            }
            .formStyle(.grouped)
            .navigationTitle("Task Detail")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        logCorrectionsAndDismiss()
                    }
                }
            }
        }
        .frame(minWidth: 500, minHeight: 600)
        .onAppear {
            if originalEstimatedMinutes == nil {
                originalEstimatedMinutes = task.estimatedMinutes
                originalBucket = task.bucket
            }
        }
    }

    // MARK: - Task Info

    @ViewBuilder
    private var taskInfoSection: some View {
        Section("Task Info") {
            // Title (read-only since it's a let)
            LabeledContent("Title") {
                Text(task.title)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Sender — hidden entirely when the task has no sender (manually
            // added, voice-captured, etc.). A row showing "—" is cognitive
            // bloat for an executive scanning a task; the source pill on the
            // TaskRow already conveys provenance for AI/Manual/Voice/Email.
            // See docs/UI-RULES.md § "No empty rows".
            if !task.sender.isEmpty {
                LabeledContent("Sender") {
                    HStack(spacing: 6) {
                        Image(systemName: "person.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Text(task.sender)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            // Bucket picker
            Picker("Bucket", selection: bucketBinding) {
                ForEach(TaskBucket.allCases, id: \.self) { bucket in
                    Label(bucket.rawValue, systemImage: bucket.icon)
                        .tag(bucket)
                }
            }

            // Estimated minutes
            Stepper(
                "Estimated time: \(formatMins(task.estimatedMinutes))",
                value: $task.estimatedMinutes,
                in: 5...240,
                step: 5
            )

            // Reply medium — only show if bucket is .reply
            if task.bucket == .reply {
                Picker("Reply Medium", selection: replyMediumBinding) {
                    Text("None").tag(Optional<ReplyMedium>.none)
                    ForEach(ReplyMedium.allCases, id: \.self) { medium in
                        Label(medium.rawValue, systemImage: medium.icon)
                            .tag(Optional(medium))
                    }
                }
            }

            // Email count (read-only)
            if task.emailCount > 0 {
                LabeledContent("Emails") {
                    Label("\(task.emailCount)", systemImage: "envelope.stack")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
            }

            // Received date (read-only)
            LabeledContent("Received") {
                Text(task.receivedAt.formatted(date: .abbreviated, time: .shortened))
                    .foregroundStyle(.secondary)
            }

            // Days in queue (read-only)
            if task.daysInQueue > 0 {
                LabeledContent("In queue") {
                    Text("\(task.daysInQueue) day\(task.daysInQueue == 1 ? "" : "s")")
                        .foregroundStyle(task.daysInQueue > 7 ? .red : .secondary)
                }
            }
        }
    }

    // MARK: - Scheduling

    @ViewBuilder
    private var schedulingSection: some View {
        Section("Scheduling") {
            Toggle("Due Today", isOn: $task.dueToday)
            Toggle("Do First", isOn: $task.isDoFirst)
            Toggle("Transit Safe", isOn: $task.isTransitSafe)

            waitingOnRow

            // Expected By Date
            Toggle("Has expected date", isOn: hasExpectedDateBinding)
            if task.expectedByDate != nil {
                DatePicker(
                    "Expected By",
                    selection: expectedByDateBinding,
                    displayedComponents: [.date]
                )
            }
        }
    }

    @ViewBuilder
    private var waitingOnRow: some View {
        if isEditingWaitingOn {
            TextField("Waiting On", text: waitingOnBinding, prompt: Text("Person or team…"))
                .onSubmit { isEditingWaitingOn = false }
        } else {
            HStack(spacing: 8) {
                Text("Waiting On")
                Spacer()
                Text(waitingOnDisplay)
                    .foregroundStyle(task.waitingOn == nil ? .tertiary : .secondary)
                Image(systemName: "pencil")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
            .onTapGesture { isEditingWaitingOn = true }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .help("Edit who this task is waiting on")
        }
    }

    private var waitingOnDisplay: String {
        guard let waitingOn = task.waitingOn?.trimmingCharacters(in: .whitespacesAndNewlines), !waitingOn.isEmpty else {
            return "Not waiting"
        }
        return waitingOn
    }

    // MARK: - Status

    @ViewBuilder
    private var statusSection: some View {
        Section("Status") {
            Toggle("Done", isOn: $task.isDone)
        }
    }

    // MARK: - Notes

    @ViewBuilder
    private var notesSection: some View {
        Section("Notes") {
            TextEditor(text: $notes)
                .frame(minHeight: 80)
                .scrollContentBackground(.hidden)
        }
    }

    // MARK: - Delete

    @ViewBuilder
    private var deleteSection: some View {
        Section {
            Button(role: .destructive) {
                onDelete()
                dismiss()
            } label: {
                HStack {
                    Spacer()
                    Label("Delete Task", systemImage: "trash")
                    Spacer()
                }
            }
        }
    }

    // MARK: - Bindings

    /// Bucket is a `let` on TimedTask, so we rebuild the task when it changes.
    private var bucketBinding: Binding<TaskBucket> {
        Binding(
            get: { task.bucket },
            set: { newBucket in
                task = TimedTask(
                    id: task.id,
                    title: task.title,
                    sender: task.sender,
                    estimatedMinutes: task.estimatedMinutes,
                    bucket: newBucket,
                    emailCount: task.emailCount,
                    receivedAt: task.receivedAt,
                    sectionId: task.sectionId,
                    parentTaskId: task.parentTaskId,
                    sortOrder: task.sortOrder,
                    manualImportance: task.manualImportance,
                    notes: task.notes,
                    isPlanningUnit: task.isPlanningUnit,
                    replyMedium: task.replyMedium,
                    dueToday: task.dueToday,
                    isDoFirst: task.isDoFirst,
                    isTransitSafe: task.isTransitSafe,
                    waitingOn: task.waitingOn,
                    askedDate: task.askedDate,
                    expectedByDate: task.expectedByDate,
                    isDone: task.isDone,
                    estimateUncertainty: task.estimateUncertainty,
                    planScore: task.planScore,
                    scheduledStartTime: task.scheduledStartTime,
                    urgency: task.urgency,
                    importance: task.importance,
                    energyRequired: task.energyRequired,
                    context: task.context,
                    skipCount: task.skipCount,
                    snoozedUntil: task.snoozedUntil
                )
            }
        )
    }

    private var replyMediumBinding: Binding<ReplyMedium?> {
        Binding(
            get: { task.replyMedium },
            set: { task.replyMedium = $0 }
        )
    }

    private func logCorrectionsAndDismiss() {
        if let oldMinutes = originalEstimatedMinutes, oldMinutes != task.estimatedMinutes {
            let updatedTask = task
            let eventContext = TaskBehaviourEventContext.current()
            if let eventContext {
                Task {
                    try? await DataBridge.shared.logEstimateOverride(
                        task: updatedTask,
                        oldMinutes: oldMinutes,
                        newMinutes: updatedTask.estimatedMinutes,
                        context: eventContext
                    )
                }
            }
        }

        if let oldBucket = originalBucket, oldBucket != task.bucket {
            let updatedTask = task
            let eventContext = TaskBehaviourEventContext.current()
            if let eventContext {
                Task {
                    try? await DataBridge.shared.logTaskBucketChanged(
                        task: updatedTask,
                        oldBucket: oldBucket,
                        context: eventContext
                    )
                }
            }
        }

        onDismiss()
        dismiss()
    }

    private var waitingOnBinding: Binding<String> {
        Binding(
            get: { task.waitingOn ?? "" },
            set: { task.waitingOn = $0.isEmpty ? nil : $0 }
        )
    }

    private var hasExpectedDateBinding: Binding<Bool> {
        Binding(
            get: { task.expectedByDate != nil },
            set: { enabled in
                task.expectedByDate = enabled ? Date() : nil
            }
        )
    }

    private var expectedByDateBinding: Binding<Date> {
        Binding(
            get: { task.expectedByDate ?? Date() },
            set: { task.expectedByDate = $0 }
        )
    }

    // MARK: - Helpers

    private func formatMins(_ m: Int) -> String {
        m < 60 ? "\(m) min" : (m % 60 == 0 ? "\(m / 60)h" : "\(m / 60)h \(m % 60)m")
    }
}
