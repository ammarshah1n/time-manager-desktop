// WaitingPane.swift — Timed macOS
// Waiting on Others (WOO) tracker.
// Expanded PRD: "Executives spend 10–40% of their time chasing things they already asked for."

import SwiftUI
import AppKit

struct WaitingPane: View {
    @Binding var items: [WOOItem]
    @Binding var tasks: [TimedTask]
    @State private var selected: WOOItem.ID?
    @State private var showFollowUpFor: WOOItem?
    @State private var showAddSheet = false

    private var overdue: [WOOItem]      { items.filter { $0.isOverdue && !$0.hasReplied } }
    private var active: [WOOItem]       { items.filter { !$0.isOverdue && !$0.hasReplied } }
    private var replied: [WOOItem]      { items.filter { $0.hasReplied } }
    private var waitingTasks: [TimedTask] { tasks.filter { $0.bucket == .waiting && !$0.isDone } }

    private var totalWaiting: Int  { items.filter { !$0.hasReplied }.count + waitingTasks.count }
    private var overdueCount: Int  { overdue.count }

    var body: some View {
        VStack(spacing: 0) {
            wooHeader
            Divider()
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {

                    if !overdue.isEmpty {
                        wooSection("OVERDUE", items: overdue, accent: .red)
                    }

                    if !active.isEmpty {
                        wooSection("WAITING", items: active, accent: .teal)
                    }

                    if !replied.isEmpty {
                        wooSection("RESPONDED", items: replied, accent: .secondary)
                    }

                    if !waitingTasks.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("FROM TASKS")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .tracking(1.2)

                            VStack(spacing: 4) {
                                ForEach(waitingTasks) { task in
                                    HStack(spacing: 12) {
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(task.title)
                                                .font(.system(size: 13))
                                                .lineLimit(1)
                                            if let wo = task.waitingOn {
                                                Text("Waiting on \(wo)")
                                                    .font(.system(size: 11))
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                        Spacer()
                                        Button("Responded") {
                                            if let idx = tasks.firstIndex(where: { $0.id == task.id }) {
                                                tasks[idx].isDone = true
                                            }
                                        }
                                        .buttonStyle(.bordered)
                                        .controlSize(.mini)
                                        .tint(.teal)
                                    }
                                    .padding(.horizontal, 14).padding(.vertical, 10)
                                    .background(Color(.controlBackgroundColor),
                                                in: RoundedRectangle(cornerRadius: 10))
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 24).padding(.vertical, 20)
            }
        }
        .navigationTitle("Waiting")
        .sheet(item: $showFollowUpFor) { item in
            FollowUpSheet(item: item) { showFollowUpFor = nil }
        }
        .sheet(isPresented: $showAddSheet) {
            AddWaitingItemSheet { newItem in
                items.insert(newItem, at: 0)
                showAddSheet = false
            }
        }
    }

    // MARK: - Header

    private var wooHeader: some View {
        HStack(spacing: 24) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Waiting on Others")
                    .font(.system(size: 14, weight: .semibold))
                Text("\(totalWaiting) outstanding")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if overdueCount > 0 {
                HStack(spacing: 5) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.red)
                    Text("\(overdueCount) overdue")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.red)
                }
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Color.red.opacity(0.08), in: Capsule())
            }

            Button {
                showAddSheet = true
            } label: {
                Label("Add", systemImage: "plus")
                    .font(.system(size: 12))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
    }

    // MARK: - Section

    @ViewBuilder
    private func wooSection(_ title: String, items: [WOOItem], accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(accent == Color.secondary ? .secondary : accent)
                    .tracking(1.2)
                Text("·  \(items.count)")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 2) {
                ForEach(items) { item in
                    WOORow(item: item) {
                        showFollowUpFor = item
                    } onMarkReplied: {
                        if let idx = self.items.firstIndex(where: { $0.id == item.id }) {
                            self.items[idx].hasReplied = true
                        }
                    }
                }
            }
        }
    }
}

// MARK: - WOO Row

struct WOORow: View {
    let item: WOOItem
    let onFollowUp: () -> Void
    let onMarkReplied: () -> Void

    private var askedLabel: String {
        let f = DateFormatter(); f.dateFormat = "d MMM yy"
        return f.string(from: item.askedDate)
    }

    private var ageLabel: String {
        let d = item.daysWaiting
        if d == 0 { return "today" }
        if d == 1 { return "1 day" }
        return "\(d) days"
    }

    private var overdueDays: Int? {
        guard let exp = item.expectedByDate, Date() > exp else { return nil }
        return max(1, Int(Date().timeIntervalSince(exp) / 86_400))
    }

    var body: some View {
        HStack(spacing: 12) {
            // Contact avatar
            ZStack {
                Circle()
                    .fill(item.isOverdue ? Color.red.opacity(0.12) : Color.teal.opacity(0.1))
                    .frame(width: 36, height: 36)
                Text(item.contact.prefix(2).uppercased())
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(item.isOverdue ? .red : .teal)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(item.contact)
                        .font(.system(size: 13, weight: .semibold))
                    Text("·")
                        .foregroundStyle(.secondary)
                    Text(item.category)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    if let days = overdueDays {
                        Text("overdue by \(days) day\(days == 1 ? "" : "s")")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.red, in: Capsule())
                    }
                }
                Text(item.description)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                Text("Asked \(askedLabel)")
                    .font(.system(size: 11))
                    .foregroundStyle(item.isOverdue ? .red : .secondary)
                Text("\(ageLabel) ago")
                    .font(.system(size: 10))
                    .foregroundStyle(item.isOverdue ? Color.red.opacity(0.8) : Color(.tertiaryLabelColor))
            }

            HStack(spacing: 6) {
                Button {
                    onFollowUp()
                } label: {
                    Text("Follow up")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .tint(item.isOverdue ? .red : .teal)

                Button {
                    onMarkReplied()
                } label: {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11))
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .help("Mark as replied")
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(
            item.isOverdue ? Color.red.opacity(0.04) : Color(.controlBackgroundColor),
            in: RoundedRectangle(cornerRadius: 10)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(item.isOverdue ? Color.red.opacity(0.15) : Color.clear, lineWidth: 1)
        )
    }
}

// MARK: - Follow Up Sheet

struct FollowUpSheet: View {
    let item: WOOItem
    let onDismiss: () -> Void

    @State private var message = ""

    private var defaultMessage: String {
        "Hi \(item.contact), just following up on my previous message regarding \(item.description.lowercased()). Happy to jump on a call if easier."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Follow Up")
                        .font(.headline)
                    Text("to \(item.contact) re: \(item.description)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            Divider()

            TextEditor(text: $message)
                .font(.system(size: 13))
                .frame(height: 100)
                .padding(8)
                .background(Color(.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))

            HStack(spacing: 8) {
                Button("Use template") {
                    message = defaultMessage
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button {
                    // voice dictate placeholder
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "mic.fill")
                        Text("Dictate")
                    }
                    .font(.system(size: 12))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Spacer()
            }

            HStack {
                Button("Cancel", role: .cancel) { onDismiss() }
                    .keyboardShortcut(.escape)
                Spacer()
                Button("Send via Email") {
                    let encodedSubject = "Following up".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                    let encodedBody    = message.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                    if let url = URL(string: "mailto:\(item.contact)?subject=\(encodedSubject)&body=\(encodedBody)") {
                        NSWorkspace.shared.open(url)
                    }
                    onDismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(.teal)
                .keyboardShortcut(.return)
                Button("Copy to Clipboard") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(message, forType: .string)
                    onDismiss()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(24)
        .frame(width: 460)
        .onAppear { message = defaultMessage }
    }
}

// MARK: - Add Waiting Item Sheet

struct AddWaitingItemSheet: View {
    let onAdd: (WOOItem) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var contact     = ""
    @State private var description = ""
    @State private var category    = "Business"
    @State private var hasDeadline = false
    @State private var deadline    = Date().addingTimeInterval(7 * 86_400)

    private let categories = ["Personal", "Business", "PFF"]

    private var canSubmit: Bool {
        !contact.trimmingCharacters(in: .whitespaces).isEmpty &&
        !description.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Add Waiting Item")
                .font(.headline)

            Divider()

            VStack(alignment: .leading, spacing: 14) {
                labeledField("Waiting on") {
                    TextField("Name or organisation", text: $contact)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .padding(8)
                        .background(Color(.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 7))
                }

                labeledField("Regarding") {
                    TextField("Brief description of what you're waiting for", text: $description)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .padding(8)
                        .background(Color(.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 7))
                }

                labeledField("Category") {
                    Picker("Category", selection: $category) {
                        ForEach(categories, id: \.self) { c in
                            Text(c).tag(c)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Toggle("Expected by a specific date", isOn: $hasDeadline)
                        .font(.system(size: 13))

                    if hasDeadline {
                        DatePicker("", selection: $deadline, displayedComponents: .date)
                            .labelsHidden()
                    }
                }
            }

            Divider()

            HStack {
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.escape)
                Spacer()
                Button("Add to Waiting") {
                    let item = WOOItem(
                        id: UUID(),
                        contact: contact.trimmingCharacters(in: .whitespaces),
                        description: description.trimmingCharacters(in: .whitespaces),
                        category: category,
                        askedDate: Date(),
                        expectedByDate: hasDeadline ? deadline : nil
                    )
                    onAdd(item)
                }
                .buttonStyle(.borderedProminent)
                .tint(.teal)
                .keyboardShortcut(.return)
                .disabled(!canSubmit)
            }
        }
        .padding(24)
        .frame(width: 420)
    }

    @ViewBuilder
    private func labeledField<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)
            content()
        }
    }
}
