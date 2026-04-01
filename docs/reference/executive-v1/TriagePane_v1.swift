// TriagePane.swift — Timed macOS
// Unclassified email queue. Classify each item into a task bucket or archive it.

import SwiftUI

struct TriagePane: View {
    @Binding var items: [TriageItem]
    @Binding var tasks: [TimedTask]
    @State private var selected: TriageItem.ID?

    var selectedItem: TriageItem? { items.first(where: { $0.id == selected }) }

    var body: some View {
        HSplitView {
            // Left — queue
            VStack(spacing: 0) {
                triageHeader
                Divider()
                if items.isEmpty {
                    emptyState
                } else {
                    List(selection: $selected) {
                        ForEach(items) { item in
                            TriageRow(item: item)
                                .tag(item.id)
                                .contextMenu { contextMenu(for: item) }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .frame(minWidth: 300, idealWidth: 360, maxWidth: 460)

            // Right — preview
            if let item = selectedItem {
                TriageDetail(item: item) { action in
                    apply(action, to: item)
                }
            } else {
                TriageDetailEmpty()
            }
        }
        .navigationTitle("Triage")
    }

    // MARK: - Header

    private var triageHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(items.count) to process")
                    .font(.system(size: 13, weight: .semibold))
                Text("Classify each email into a work bucket")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                for item in items { archiveItem(item) }
            } label: {
                Text("Archive All")
                    .font(.system(size: 11))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(items.isEmpty)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(.secondary)
            Text("All clear")
                .font(.system(size: 15, weight: .medium))
            Text("Nothing left to triage")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Context menu

    @ViewBuilder
    private func contextMenu(for item: TriageItem) -> some View {
        Section("Move to bucket") {
            ForEach(TaskBucket.allCases, id: \.self) { bucket in
                Button {
                    classify(item, as: bucket)
                } label: {
                    Label(bucket.rawValue, systemImage: bucket.icon)
                }
            }
        }
        Divider()
        Button("Archive", role: .destructive) { archiveItem(item) }
    }

    // MARK: - Actions

    private func apply(_ action: TriageAction, to item: TriageItem) {
        switch action {
        case .classify(let bucket): classify(item, as: bucket)
        case .archive:              archiveItem(item)
        }
    }

    private func classify(_ item: TriageItem, as bucket: TaskBucket) {
        let task = TimedTask(
            id: UUID(),
            title: item.subject,
            sender: item.sender,
            estimatedMinutes: bucket == .reply ? 2 : 15,
            bucket: bucket,
            emailCount: 1,
            receivedAt: item.receivedAt
        )
        tasks.append(task)
        removeItem(item)
    }

    private func archiveItem(_ item: TriageItem) { removeItem(item) }

    private func removeItem(_ item: TriageItem) {
        items.removeAll { $0.id == item.id }
        if selected == item.id { selected = items.first?.id }
    }
}

// MARK: - Triage action

enum TriageAction {
    case classify(TaskBucket)
    case archive
}

// MARK: - Row

struct TriageRow: View {
    let item: TriageItem

    var body: some View {
        HStack(spacing: 10) {
            // Avatar
            ZStack {
                Circle()
                    .fill(item.avatarColor.opacity(0.18))
                    .frame(width: 34, height: 34)
                Text(item.initials)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(item.avatarColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(item.sender)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                    Spacer()
                    Text(item.relativeTime)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                Text(item.subject)
                    .font(.system(size: 12))
                    .lineLimit(1)
                Text(item.preview)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Detail

struct TriageDetail: View {
    let item: TriageItem
    let onAction: (TriageAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    ZStack {
                        Circle().fill(item.avatarColor.opacity(0.15)).frame(width: 42, height: 42)
                        Text(item.initials)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(item.avatarColor)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.sender).font(.system(size: 14, weight: .semibold))
                        Text(item.relativeTime).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Text(item.subject)
                    .font(.system(size: 16, weight: .semibold))
                    .padding(.top, 4)
                Text(item.preview)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(20)

            Divider()

            // Action buttons
            VStack(alignment: .leading, spacing: 10) {
                Text("MOVE TO BUCKET")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .tracking(1)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(TaskBucket.allCases, id: \.self) { bucket in
                        Button {
                            onAction(.classify(bucket))
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: bucket.icon)
                                    .font(.system(size: 11))
                                    .foregroundStyle(bucket.color)
                                Text(bucket.rawValue)
                                    .font(.system(size: 12))
                                Spacer()
                            }
                            .padding(.horizontal, 10).padding(.vertical, 7)
                            .background(bucket.color.opacity(0.07), in: RoundedRectangle(cornerRadius: 7))
                        }
                        .buttonStyle(.plain)
                    }
                }

                Divider().padding(.top, 4)

                Button(role: .destructive) {
                    onAction(.archive)
                } label: {
                    HStack {
                        Image(systemName: "archivebox")
                        Text("Archive — no action needed")
                    }
                    .font(.system(size: 12))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background(Color(.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            .padding(20)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct TriageDetailEmpty: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "hand.point.up.left")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(.secondary)
            Text("Select an email to triage")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
