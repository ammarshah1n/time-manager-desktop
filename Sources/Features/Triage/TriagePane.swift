// TriagePane.swift — Timed macOS V2
// One-at-a-time keyboard-driven triage. Like SaneBox's drag-to-train — minimal effort, maximum learning.
// Transcript A1-A8: "All I have to do is drag any email I never want to see again into black hole"

import SwiftUI
import Dependencies

struct TriagePane: View {
    @Binding var items: [TriageItem]
    @Binding var tasks: [TimedTask]

    @State private var currentIndex = 0
    @State private var animatingOut = false
    @State private var slideDirection: SlideDirection = .left
    @State private var recentAction: String? = nil
    @State private var undoStack: [(item: TriageItem, index: Int)] = []
    @State private var showBundleSheet = false
    @State private var extractedBundles: [ExtractedTaskBundle] = []
    @State private var showBucketPicker = false

    private var current: TriageItem? {
        guard currentIndex < items.count else { return nil }
        return items[currentIndex]
    }

    private var processed: Int { currentIndex }
    private var remaining: Int { items.count - currentIndex }

    var body: some View {
        VStack(spacing: 0) {
            triageHeader
            Divider()

            if items.isEmpty {
                allClearView
            } else if remaining == 0 {
                sessionCompleteView
            } else {
                ZStack {
                    // Upcoming card preview
                    if currentIndex + 1 < items.count {
                        TriageCard(item: items[currentIndex + 1], isPreview: true)
                            .scaleEffect(0.95)
                            .offset(y: 12)
                    }

                    // Active card
                    if let item = current {
                        TriageCard(item: item, isPreview: false)
                            .offset(x: animatingOut ? (slideDirection == .left ? -600 : 600) : 0)
                            .opacity(animatingOut ? 0 : 1)
                            .animation(.easeIn(duration: 0.22), value: animatingOut)
                    }
                }
                .frame(maxWidth: 580, maxHeight: 280)
                .padding(.top, 16)
                .padding(.horizontal, 32)

                // Low-confidence nudge
                if let item = current, let conf = item.classificationConfidence, conf < 0.65,
                   let bucket = item.classifiedBucket {
                    lowConfidenceNudge(item: item, bucket: bucket)
                }

                Spacer().frame(height: 16)

                bucketButtons

                keyboardHints
                    .padding(.bottom, 24)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("Triage")
        .sheet(isPresented: $showBundleSheet) {
            TaskBundleSheet(
                bundles: $extractedBundles,
                tasks: $tasks,
                triageItems: $items,
                onDismiss: { showBundleSheet = false }
            )
        }
        .onKeyPress { key in
            handleKey(key)
        }
        .onChange(of: recentAction) { _, newVal in
            if newVal != nil {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    recentAction = nil
                }
            }
        }
    }

    // MARK: - Header
    // Progress bar shows how far through the queue the user is

    private var triageHeader: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text("\(processed) of \(items.count) processed")
                            .font(.system(size: 13, weight: .semibold))
                        if let action = recentAction {
                            Text("→ \(action)")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .transition(.opacity.combined(with: .move(edge: .leading)))
                        }
                    }
                    Text("\(remaining) remaining")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                HStack(spacing: 8) {
                    if !undoStack.isEmpty {
                        Button {
                            undoLast()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.uturn.backward")
                                    .font(.system(size: 11))
                                Text("Undo")
                                    .font(.system(size: 12))
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .keyboardShortcut("z", modifiers: .command)
                    }

                    Button {
                        smartBundle()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "rectangle.stack.fill")
                                .font(.system(size: 11))
                            Text("Smart Bundle")
                                .font(.system(size: 12))
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(items.count < 2)

                    Button {
                        archiveCurrent()
                    } label: {
                        Text("Skip All")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(remaining == 0)
                }
            }
            .frame(maxWidth: 580)
            .padding(.horizontal, 20).padding(.vertical, 12)
            .frame(maxWidth: .infinity)

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle().fill(Color(.separatorColor).opacity(0.5)).frame(height: 2)
                    Rectangle()
                        .fill(Color.blue)
                        .frame(width: items.isEmpty ? 0 : geo.size.width * CGFloat(processed) / CGFloat(items.count), height: 2)
                        .animation(.easeInOut(duration: 0.3), value: processed)
                }
            }
            .frame(height: 2)
        }
    }

    // MARK: - Bucket buttons

    private var bucketButtons: some View {
        VStack(spacing: 10) {
            // Row 1: do something
            HStack(spacing: 8) {
                ForEach([TaskBucket.reply, .action, .calls], id: \.self) { bucket in
                    BucketButton(bucket: bucket, key: keyFor(bucket)) {
                        classifyCurrent(as: bucket)
                    }
                }
            }

            // Row 2: defer
            HStack(spacing: 8) {
                ForEach([TaskBucket.readToday, .readThisWeek, .waiting], id: \.self) { bucket in
                    BucketButton(bucket: bucket, key: keyFor(bucket)) {
                        classifyCurrent(as: bucket)
                    }
                }
            }

            // Row 3: special classification
            HStack(spacing: 8) {
                ForEach([TaskBucket.transit, .ccFyi], id: \.self) { bucket in
                    BucketButton(bucket: bucket, key: keyFor(bucket)) {
                        classifyCurrent(as: bucket)
                    }
                }
            }

            // Archive
            Button {
                archiveCurrent()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "archivebox")
                        .font(.system(size: 12))
                    Text("Archive — no action needed")
                        .font(.system(size: 12, weight: .medium))
                    Spacer()
                    Text("space")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color(.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 4))
                }
                .padding(.horizontal, 14).padding(.vertical, 9)
                .frame(maxWidth: .infinity)
                .background(Color(.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 9))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: 580)
        .padding(.horizontal, 32)
        .padding(.bottom, 12)
    }

    // MARK: - Keyboard hints

    private var keyboardHints: some View {
        HStack(spacing: 4) {
            Text("Keyboard:")
                .font(.system(size: 10))
                .foregroundStyle(Color(.tertiaryLabelColor))
            Text("R")
                .keyHint(color: TaskBucket.reply.color)
            Text("Reply  ")
            Text("A")
                .keyHint(color: TaskBucket.action.color)
            Text("Action  ")
            Text("T")
                .keyHint(color: TaskBucket.transit.color)
            Text("Transit  ")
            Text("D")
                .keyHint(color: TaskBucket.readToday.color)
            Text("Read Today  ")
            Text("W")
                .keyHint(color: TaskBucket.readThisWeek.color)
            Text("This Week  ")
            Text("N")
                .keyHint(color: TaskBucket.waiting.color)
            Text("Waiting  ")
            Text("F")
                .keyHint(color: TaskBucket.ccFyi.color)
            Text("CC/FYI  ")
            Text("Space")
                .keyHint(color: .secondary)
            Text("Archive")
        }
        .font(.system(size: 10))
        .foregroundStyle(Color(.tertiaryLabelColor))
    }

    // MARK: - Empty/complete states

    private var allClearView: some View {
        VStack(spacing: 14) {
            Image(systemName: "tray")
                .font(.system(size: 40, weight: .thin))
                .foregroundStyle(.secondary)
            Text("Triage is empty")
                .font(.system(size: 17, weight: .medium))
            Text("Emails will appear here when they arrive from Outlook.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var sessionCompleteView: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 40, weight: .thin))
                .foregroundStyle(.green)
            Text("Triage complete")
                .font(.system(size: 17, weight: .medium))
            Text("All \(items.count) emails processed this session.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            Button("Start over") {
                currentIndex = 0
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Low-confidence nudge

    @ViewBuilder
    private func lowConfidenceNudge(item: TriageItem, bucket: String) -> some View {
        HStack(spacing: 8) {
            Text("AI classified this as **\(bucket)** (low confidence). Is this right?")
                .font(.system(size: 11))
            Spacer()
            if showBucketPicker {
                Picker("", selection: Binding<String>(
                    get: { bucket },
                    set: { newBucket in
                        logTriageCorrection(item: item, oldBucket: bucket, newBucket: newBucket)
                        showBucketPicker = false
                    }
                )) {
                    ForEach(TaskBucket.allCases, id: \.self) { b in
                        Text(b.rawValue).tag(b.rawValue)
                    }
                }
                .labelsHidden()
                .frame(width: 120)
                .controlSize(.small)
            } else {
                Button("Yes \u{2713}") {
                    logTriageCorrection(item: item, oldBucket: bucket, newBucket: bucket)
                }
                .controlSize(.small)
                Button("No, it's...") { showBucketPicker = true }
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 6)
        .frame(maxWidth: 580)
        .background(Color.yellow.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 32).padding(.top, 8)
    }

    private func logTriageCorrection(item: TriageItem, oldBucket: String, newBucket: String) {
        guard let emailId = item.emailMessageId,
              let wsId = AuthService.shared.workspaceId,
              let profileId = AuthService.shared.profileId else { return }
        Task {
            @Dependency(\.supabaseClient) var supa
            let row = TriageCorrectionRow(
                id: UUID(), workspaceId: wsId,
                emailMessageId: emailId, profileId: profileId,
                oldBucket: oldBucket, newBucket: newBucket, fromAddress: item.sender
            )
            try? await supa.insertTriageCorrection(row)
        }
        recentAction = oldBucket == newBucket ? "Confirmed \(oldBucket)" : "Corrected → \(newBucket)"
    }

    // MARK: - Actions

    private func classifyCurrent(as bucket: TaskBucket) {
        guard let item = current else { return }

        // CC/FYI: archive with no task created
        if bucket == .ccFyi {
            // Log correction if AI classification differs from user's CC/FYI choice
            if let emailId = item.emailMessageId,
               let aiClassification = item.classifiedBucket,
               aiClassification != bucket.rawValue {
                Task {
                    @Dependency(\.supabaseClient) var supa
                    let correction = TriageCorrectionRow(
                        id: UUID(), workspaceId: AuthService.shared.workspaceId ?? UUID(),
                        emailMessageId: emailId, profileId: AuthService.shared.profileId ?? UUID(),
                        oldBucket: aiClassification, newBucket: bucket.rawValue,
                        fromAddress: item.sender
                    )
                    try? await supa.insertTriageCorrection(correction)
                }
            }
            undoStack.append((item: item, index: currentIndex))
            recentAction = "CC/FYI — archived"
            animateOut(direction: .right) {
                items.remove(at: currentIndex)
            }
            return
        }

        undoStack.append((item: item, index: currentIndex))

        let parsed = item.subject.parsedSubjectMetadata
        let bucketDefault = bucket == .reply ? 2 : (bucket == .transit ? 20 : 15)
        let estimatedMinutes = parsed.estimatedMinutes ?? bucketDefault

        let isFamilySender = item.sender.isFamilyMember(surname: OnboardingUserPrefs.familySurname)

        let task = TimedTask(
            id: UUID(),
            title: item.subject,
            sender: item.sender,
            estimatedMinutes: estimatedMinutes,
            bucket: bucket,
            emailCount: 1,
            receivedAt: item.receivedAt,
            priority: parsed.priority,
            isDoFirst: isFamilySender
        )
        tasks.append(task)

        // Write back to Supabase if this came from a real email
        if let emailId = item.emailMessageId {
            Task {
                @Dependency(\.supabaseClient) var supa
                try? await supa.updateEmailBucket(emailId, bucket.rawValue, 1.0)

                // Log correction if AI classification differs from user choice
                if let aiClassification = item.classifiedBucket,
                   aiClassification != bucket.rawValue {
                    let correction = TriageCorrectionRow(
                        id: UUID(), workspaceId: AuthService.shared.workspaceId ?? UUID(),
                        emailMessageId: emailId, profileId: AuthService.shared.profileId ?? UUID(),
                        oldBucket: aiClassification, newBucket: bucket.rawValue,
                        fromAddress: item.sender
                    )
                    try? await supa.insertTriageCorrection(correction)
                }
            }
        }

        recentAction = bucket.rawValue
        animateOut(direction: .left) {
            items.remove(at: currentIndex)
            // currentIndex stays the same (next item slides into place)
        }
    }

    private func smartBundle() {
        Task {
            let bundles = await TaskExtractionService.shared.extractTasks(from: items)
            await MainActor.run {
                extractedBundles = bundles
                showBundleSheet = true
            }
        }
    }

    private func archiveCurrent() {
        guard let item = current else { return }
        // Log correction if AI had classified this into a bucket but user chose to archive
        if let emailId = item.emailMessageId,
           let aiClassification = item.classifiedBucket {
            Task {
                @Dependency(\.supabaseClient) var supa
                let correction = TriageCorrectionRow(
                    id: UUID(), workspaceId: AuthService.shared.workspaceId ?? UUID(),
                    emailMessageId: emailId, profileId: AuthService.shared.profileId ?? UUID(),
                    oldBucket: aiClassification, newBucket: "archive",
                    fromAddress: item.sender
                )
                try? await supa.insertTriageCorrection(correction)
            }
        }
        undoStack.append((item: item, index: currentIndex))
        recentAction = "Archived"
        animateOut(direction: .right) {
            items.remove(at: currentIndex)
        }
    }

    private func undoLast() {
        guard let last = undoStack.popLast() else { return }
        // Remove the task that was created if any
        tasks.removeAll { $0.title == last.item.subject && $0.sender == last.item.sender }
        // Re-insert triage item
        let insertAt = min(last.index, items.count)
        items.insert(last.item, at: insertAt)
        currentIndex = insertAt
        recentAction = "Undone"
    }

    private func animateOut(direction: SlideDirection, completion: @escaping () -> Void) {
        slideDirection = direction
        withAnimation(.easeIn(duration: 0.22)) {
            animatingOut = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            completion()
            animatingOut = false
        }
    }

    private func handleKey(_ key: KeyPress) -> KeyPress.Result {
        switch key.characters.lowercased() {
        case "r": classifyCurrent(as: .reply);        return .handled
        case "a": classifyCurrent(as: .action);       return .handled
        case "c": classifyCurrent(as: .calls);        return .handled
        case "t": classifyCurrent(as: .transit);      return .handled
        case "d": classifyCurrent(as: .readToday);    return .handled
        case "w": classifyCurrent(as: .readThisWeek); return .handled
        case "n": classifyCurrent(as: .waiting);      return .handled
        case "f": classifyCurrent(as: .ccFyi);        return .handled
        case " ": archiveCurrent();                    return .handled
        default:  return .ignored
        }
    }

    private func keyFor(_ bucket: TaskBucket) -> String {
        switch bucket {
        case .reply:        "R"
        case .action:       "A"
        case .calls:        "C"
        case .transit:      "T"
        case .readToday:    "D"
        case .readThisWeek: "W"
        case .waiting:      "N"
        case .ccFyi:        "F"
        }
    }
}

// MARK: - Slide direction

enum SlideDirection { case left, right }

// MARK: - Triage card (full email preview)

struct TriageCard: View {
    let item: TriageItem
    let isPreview: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Sender row
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(item.avatarColor.opacity(0.15)).frame(width: 44, height: 44)
                    Text(item.initials)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(item.avatarColor)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.sender)
                        .font(.system(size: 14, weight: .semibold))
                    Text("Received \(item.relativeTime) ago")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 14)

            Divider()

            // Subject
            Text(item.subject)
                .font(.system(size: 16, weight: .semibold))
                .padding(.horizontal, 20).padding(.top, 14).padding(.bottom, 8)

            // Preview body
            Text(item.preview)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .lineLimit(5)
                .padding(.horizontal, 20).padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Color(.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(isPreview ? 0.04 : 0.08), radius: isPreview ? 4 : 12, y: isPreview ? 2 : 4)
        .blur(radius: isPreview ? 0.5 : 0)
        .allowsHitTesting(!isPreview)
    }
}

// MARK: - Bucket button

struct BucketButton: View {
    let bucket: TaskBucket
    let key: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: bucket.icon)
                    .font(.system(size: 11))
                    .foregroundStyle(bucket.color)
                Text(bucket.rawValue)
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                Text(key)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(bucket.color)
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(bucket.color.opacity(0.1), in: RoundedRectangle(cornerRadius: 4))
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(bucket.color.opacity(0.06), in: RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Key hint modifier

extension Text {
    func keyHint(color: Color) -> some View {
        self
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 5).padding(.vertical, 2)
            .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 3))
    }
}
