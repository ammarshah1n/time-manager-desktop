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
                        onDismiss()
                        dismiss()
                    }
                }
            }
        }
        .frame(minWidth: 500, minHeight: 600)
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

            // Sender (read-only style)
            LabeledContent("Sender") {
                HStack(spacing: 6) {
                    if !task.sender.isEmpty {
                        Image(systemName: "person.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Text(task.sender.isEmpty ? "—" : task.sender)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
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

            // Waiting On
            TextField("Waiting On", text: waitingOnBinding, prompt: Text("Person or team…"))

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
