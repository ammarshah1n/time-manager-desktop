// InboxView.swift — Timed iOS Mockup
// Screen 1: Email inbox with swipe actions and time-block sheet.

import SwiftUI

struct InboxView: View {
    @State private var emails = MockEmail.samples
    @State private var blockTarget: MockEmail?
    @State private var showBlockSheet = false

    var unreadCount: Int { emails.filter { !$0.isRead }.count }

    var body: some View {
        NavigationStack {
            List {
                ForEach($emails) { $email in
                    EmailRow(email: $email) {
                        blockTarget = email
                        showBlockSheet = true
                    }
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                    .listRowSeparator(.hidden)
                    // Leading: time-block (primary) + snooze
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        Button {
                            blockTarget = email
                            showBlockSheet = true
                        } label: {
                            Label("Block", systemImage: "calendar.badge.plus")
                        }
                        .tint(.blue)

                        Button {
                            withAnimation { email.isSnoozed = true }
                        } label: {
                            Label("Snooze", systemImage: "moon.fill")
                        }
                        .tint(.indigo)
                    }
                    // Trailing: archive (destructive)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            withAnimation {
                                emails.removeAll { $0.id == email.id }
                            }
                        } label: {
                            Label("Archive", systemImage: "archivebox.fill")
                        }
                        .tint(Color(.systemGray))
                    }
                }
            }
            .listStyle(.plain)
            .navigationTitle("Inbox")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if unreadCount > 0 {
                        Text("\(unreadCount) unread")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { } label: {
                        Image(systemName: "square.and.pencil")
                            .fontWeight(.medium)
                    }
                }
            }
            .refreshable {
                try? await Task.sleep(for: .milliseconds(800))
            }
            .sheet(isPresented: $showBlockSheet) {
                if let email = blockTarget {
                    TimeBlockSheet(email: email)
                        .presentationDetents([.medium])
                        .presentationDragIndicator(.visible)
                        .presentationCornerRadius(20)
                }
            }
        }
    }
}

// MARK: - Email Row

struct EmailRow: View {
    @Binding var email: MockEmail
    var onBlock: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            AvatarView(initials: email.initials, color: email.avatarColor)

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .center) {
                    Text(email.sender)
                        .font(.system(size: 15, weight: email.isRead ? .regular : .semibold))
                    Spacer()
                    Text(email.relativeTime)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    if !email.isRead {
                        Circle().fill(.blue).frame(width: 7, height: 7)
                    }
                }

                Text(email.subject)
                    .font(.system(size: 14, weight: email.isRead ? .regular : .medium))
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Text(email.preview)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    Spacer(minLength: 0)
                    if email.hasTimeBlock {
                        Image(systemName: "calendar.badge.checkmark")
                            .font(.system(size: 12))
                            .foregroundStyle(.blue)
                    }
                    if email.isSnoozed {
                        Image(systemName: "moon.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.indigo)
                    }
                }
            }
        }
        .padding(.vertical, 11)
        .contentShape(Rectangle())
        .onTapGesture { email.isRead = true }
    }
}

// MARK: - Avatar

struct AvatarView: View {
    let initials: String
    let color: Color
    var size: CGFloat = 42

    var body: some View {
        Circle()
            .fill(color.opacity(0.12))
            .frame(width: size, height: size)
            .overlay {
                Text(initials)
                    .font(.system(size: size * 0.33, weight: .semibold))
                    .foregroundStyle(color)
            }
    }
}

// MARK: - Time Block Sheet

struct TimeBlockSheet: View {
    let email: MockEmail
    @Environment(\.dismiss) private var dismiss
    @State private var selectedDate = Date()
    @State private var durationMinutes: Double = 60

    private let durations: [(String, Double)] = [
        ("30m", 30), ("1h", 60), ("90m", 90), ("2h", 120), ("3h", 180)
    ]

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 24) {
                // Email card
                HStack(spacing: 12) {
                    AvatarView(initials: email.initials, color: email.avatarColor, size: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(email.subject)
                            .font(.subheadline).fontWeight(.semibold)
                            .lineLimit(1)
                        Text(email.sender)
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))

                // Date + time
                VStack(alignment: .leading, spacing: 8) {
                    Label("When", systemImage: "calendar")
                        .font(.subheadline).fontWeight(.semibold)
                        .foregroundStyle(.primary)
                    DatePicker("", selection: $selectedDate, displayedComponents: [.date, .hourAndMinute])
                        .labelsHidden()
                        .datePickerStyle(.compact)
                }

                // Duration chips
                VStack(alignment: .leading, spacing: 8) {
                    Label("Duration", systemImage: "clock")
                        .font(.subheadline).fontWeight(.semibold)
                        .foregroundStyle(.primary)
                    HStack(spacing: 8) {
                        ForEach(durations, id: \.0) { label, value in
                            Button {
                                durationMinutes = value
                            } label: {
                                Text(label)
                                    .font(.system(size: 14, weight: .medium))
                                    .padding(.horizontal, 18).padding(.vertical, 9)
                                    .background(durationMinutes == value ? Color.blue : Color(.tertiarySystemBackground),
                                                in: Capsule())
                                    .foregroundStyle(durationMinutes == value ? .white : .primary)
                                    .animation(.easeInOut(duration: 0.15), value: durationMinutes)
                            }
                        }
                    }
                }

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Text("Add to Calendar")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(.blue, in: RoundedRectangle(cornerRadius: 14))
                        .foregroundStyle(.white)
                }
            }
            .padding(20)
            .navigationTitle("Block Time")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }.foregroundStyle(.secondary)
                }
            }
        }
    }
}

#Preview {
    InboxView()
}
