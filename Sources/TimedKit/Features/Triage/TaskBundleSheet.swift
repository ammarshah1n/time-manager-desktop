#if os(macOS)
// TaskBundleSheet.swift — Timed Features/Triage
// FR-03: Bundle preview sheet for extracted task bundles.
// Shows grouped emails with editable title, bucket, and time estimate.

import SwiftUI

struct TaskBundleSheet: View {
    @Binding var bundles: [ExtractedTaskBundle]
    @Binding var tasks: [TimedTask]
    @Binding var triageItems: [TriageItem]
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            sheetHeader
            Divider()

            if bundles.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach($bundles) { $bundle in
                            BundleRow(bundle: $bundle) {
                                acceptBundle(bundle)
                            }
                        }
                    }
                    .padding(20)
                }
            }

            Divider()
            sheetFooter
        }
        .frame(width: 620, height: 520)
    }

    // MARK: - Header

    private var sheetHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Smart Bundles")
                    .font(.system(size: 15, weight: .semibold))
                Text("\(bundles.count) bundle\(bundles.count == 1 ? "" : "s") from \(totalEmails) emails")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Close") { onDismiss() }
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
    }

    // MARK: - Footer

    private var sheetFooter: some View {
        HStack {
            Spacer()
            Button("Accept All") {
                acceptAll()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .disabled(bundles.isEmpty)
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
    }

    // MARK: - Empty

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 32, weight: .thin))
                .foregroundStyle(.secondary)
            Text("All bundles accepted")
                .font(.system(size: 14, weight: .medium))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions

    private func acceptBundle(_ bundle: ExtractedTaskBundle) {
        let task = TimedTask(
            id: UUID(),
            title: bundle.suggestedTitle,
            sender: bundle.emails.last?.sender ?? "",
            estimatedMinutes: bundle.suggestedMinutes,
            bucket: bundle.suggestedBucket,
            emailCount: bundle.emailCount,
            receivedAt: bundle.emails.last?.receivedAt ?? Date()
        )
        tasks.append(task)

        // Remove constituent emails from triage
        let emailIDs = Set(bundle.emails.map(\.id))
        triageItems.removeAll { emailIDs.contains($0.id) }

        // Remove from bundles list
        bundles.removeAll { $0.id == bundle.id }
    }

    private func acceptAll() {
        for bundle in bundles {
            let task = TimedTask(
                id: UUID(),
                title: bundle.suggestedTitle,
                sender: bundle.emails.last?.sender ?? "",
                estimatedMinutes: bundle.suggestedMinutes,
                bucket: bundle.suggestedBucket,
                emailCount: bundle.emailCount,
                receivedAt: bundle.emails.last?.receivedAt ?? Date()
            )
            tasks.append(task)

            let emailIDs = Set(bundle.emails.map(\.id))
            triageItems.removeAll { emailIDs.contains($0.id) }
        }
        bundles.removeAll()
    }

    private var totalEmails: Int {
        bundles.reduce(0) { $0 + $1.emailCount }
    }
}

// MARK: - Bundle row

struct BundleRow: View {
    @Binding var bundle: ExtractedTaskBundle
    let onAccept: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Title (editable)
            HStack(spacing: 8) {
                TextField("Title", text: $bundle.suggestedTitle)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14, weight: .semibold))

                // Email count badge
                Text("\(bundle.emailCount) email\(bundle.emailCount == 1 ? "" : "s")")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(Color(.controlBackgroundColor), in: Capsule())
            }

            HStack(spacing: 12) {
                // Bucket picker
                Picker("Bucket", selection: $bundle.suggestedBucket) {
                    ForEach(TaskBucket.allCases, id: \.self) { bucket in
                        Label(bucket.rawValue, systemImage: bucket.icon)
                            .tag(bucket)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 160)

                // Time stepper
                HStack(spacing: 4) {
                    Text("\(bundle.suggestedMinutes)m")
                        .font(.system(size: 12, weight: .medium))
                        .frame(width: 36, alignment: .trailing)
                    Stepper("", value: $bundle.suggestedMinutes, in: 1...480, step: 5)
                        .labelsHidden()
                }

                Spacer()

                Button("Accept") { onAccept() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }

            // Sender summary
            if !senderSummary.isEmpty {
                Text(senderSummary)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(Color(.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
    }

    private var senderSummary: String {
        let senders = Set(bundle.emails.map(\.sender))
        if senders.count == 1, let sender = senders.first {
            return "From: \(sender)"
        }
        return "From: \(senders.sorted().joined(separator: ", "))"
    }
}

#endif
