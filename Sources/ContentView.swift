import Observation
import SwiftUI

struct ContentView: View {
    @State private var store = PlannerStore()
    @State private var showLeft = true
    @State private var showRight = true
    @State private var selectedContextFilter = "All"
    @State private var showAddTaskSheet = false
    @State private var addTaskDraft = AddTaskDraft()
    @State private var addTaskError: String?
    @State private var showCompletedToday = false

    var body: some View {
        ZStack {
            WindowChromeConfigurator()
            TimedVisualEffectBackground()
                .ignoresSafeArea()

            LinearGradient(
                colors: [
                    Color.black.opacity(0.18),
                    Color(red: 0.09, green: 0.10, blue: 0.14).opacity(0.28),
                    Color.black.opacity(0.24)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 18) {
                header

                HStack(alignment: .top, spacing: 16) {
                    if showLeft {
                        leftColumn
                            .frame(width: 320)
                            .transition(.move(edge: .leading).combined(with: .opacity))
                    }

                    centerColumn
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    if showRight {
                        rightColumn
                            .frame(width: 360)
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
                .animation(.easeInOut(duration: 0.24), value: showLeft)
                .animation(.easeInOut(duration: 0.24), value: showRight)
            }
            .padding(20)
        }
        .frame(minWidth: 1360, minHeight: 900)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showAddTaskSheet) {
            AddTaskSheet(
                draft: $addTaskDraft,
                errorMessage: $addTaskError,
                onSave: {
                    if let error = store.addManualTask(addTaskDraft) {
                        addTaskError = error
                        return
                    }
                    addTaskDraft = AddTaskDraft()
                    addTaskError = nil
                    showAddTaskSheet = false
                }
            )
        }
        .sheet(
            isPresented: Binding(
                get: { store.pendingImportBatch != nil },
                set: { isPresented in
                    if !isPresented {
                        store.discardPendingImport()
                    }
                }
            )
        ) {
            ImportReviewSheet(store: store)
        }
    }

    private var header: some View {
        TimedCard(title: "Workspace", icon: "calendar.badge.clock") {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Timed.")
                        .font(.custom("Fraunces", size: 34))
                        .fontWeight(.bold)
                        .foregroundStyle(.white)

                    Text(headerDateString)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.72))
                }

                Spacer()

                HStack(spacing: 10) {
                    HeaderActionButton(title: "Export", systemImage: "square.and.arrow.up") {
                        Task { await store.exportCalendar() }
                    }
                    HeaderActionButton(title: "Add Task", systemImage: "plus") {
                        showAddTaskSheet = true
                    }
                    HeaderActionButton(title: showLeft ? "Hide Left" : "Show Left", systemImage: "sidebar.leading") {
                        withAnimation(.easeInOut(duration: 0.24)) {
                            showLeft.toggle()
                        }
                    }
                    HeaderActionButton(title: showRight ? "Hide Right" : "Show Right", systemImage: "sidebar.trailing") {
                        withAnimation(.easeInOut(duration: 0.24)) {
                            showRight.toggle()
                        }
                    }
                    SettingsLink {
                        Label("Settings", systemImage: "gearshape")
                            .labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(.bordered)
                    .tint(.white.opacity(0.22))
                }
            }
        }
    }

    private var leftColumn: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                TimedCard(title: "Task Library", icon: "tray.full") {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(store.tasks.sorted(by: taskLibrarySort)) { task in
                            TimedCard(title: task.title, icon: icon(for: task.source)) {
                                VStack(alignment: .leading, spacing: 10) {
                                    HStack {
                                        Text(task.subject)
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundStyle(.white.opacity(0.72))

                                        Spacer()

                                        Text(task.source.rawValue)
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundStyle(.white.opacity(0.6))
                                    }

                                    Text(task.notes.isEmpty ? "No notes yet." : task.notes)
                                        .font(.system(size: 13))
                                        .foregroundStyle(.white.opacity(0.68))
                                        .lineLimit(2)

                                    if let dueDate = task.dueDate {
                                        Text("Due \(dueDate.formatted(date: .abbreviated, time: .omitted))")
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundStyle(.white.opacity(0.55))
                                    }
                                }
                            }
                            .overlay(selectionBorder(isSelected: store.selectedTaskID == task.id))
                            .onTapGesture {
                                store.selectTask(task)
                            }
                        }
                    }
                }

                TimedCard(title: "Import", icon: "square.and.arrow.down") {
                    VStack(alignment: .leading, spacing: 12) {
                        TextField("Import title", text: $store.importTitle)
                            .textFieldStyle(.plain)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(rowBackground)

                        Picker("Source", selection: $store.importSource) {
                            ForEach(ImportSource.allCases) { source in
                                Text(source.rawValue).tag(source)
                            }
                        }
                        .pickerStyle(.segmented)

                        TextEditor(text: $store.importText)
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: 180)
                            .padding(10)
                            .background(rowBackground)

                        Button("Parse import") {
                            store.importCurrentPayload()
                        }
                        .buttonStyle(.borderedProminent)

                        if !store.lastImportMessages.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(store.lastImportMessages, id: \.self) { line in
                                    Text(line)
                                        .font(.system(size: 12))
                                        .foregroundStyle(.white.opacity(0.62))
                                }
                            }
                        }
                    }
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    private var centerColumn: some View {
        VStack(spacing: 14) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    TimedCard(title: "Suggested prompts", icon: "wand.and.stars") {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(store.promptSuggestions(for: activeContextSubject), id: \.self) { suggestion in
                                    Button(suggestion) {
                                        if let quizSubject = extractSuggestionQuizSubject(suggestion) {
                                            Task { await store.startQuiz(subject: quizSubject) }
                                        } else {
                                            store.promptText = suggestion
                                            Task { await store.submitPrompt() }
                                        }
                                    }
                                    .buttonStyle(.bordered)
                                    .tint(.white.opacity(0.18))
                                }
                            }
                        }
                    }

                    TimedCard(title: "Ranked tasks", icon: "list.number") {
                        VStack(alignment: .leading, spacing: 14) {
                            ForEach(["Do now", "Today", "This week", "Later"], id: \.self) { band in
                                let tasksInBand = store.rankedTasks.filter { $0.band == band }
                                if !tasksInBand.isEmpty {
                                    VStack(alignment: .leading, spacing: 10) {
                                        Text(band)
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundStyle(.white.opacity(0.7))
                                            .textCase(.uppercase)

                                        ForEach(tasksInBand) { ranked in
                                            rankedTaskRow(ranked)
                                        }
                                    }
                                }
                            }

                            DisclosureGroup(isExpanded: $showCompletedToday) {
                                VStack(alignment: .leading, spacing: 10) {
                                    ForEach(store.completedToday) { task in
                                        TimedCard(title: task.title, icon: "checkmark.circle.fill") {
                                            VStack(alignment: .leading, spacing: 6) {
                                                Text(task.subject)
                                                    .font(.system(size: 12, weight: .semibold))
                                                    .foregroundStyle(.white.opacity(0.62))
                                                Text(task.completedAt?.formatted(date: .omitted, time: .shortened) ?? "Completed")
                                                    .font(.system(size: 12))
                                                    .foregroundStyle(.white.opacity(0.52))
                                            }
                                        }
                                    }
                                }
                                .padding(.top, 10)
                            } label: {
                                Text("Completed today")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.7))
                            }
                        }
                    }

                    TimedCard(title: "Schedule", icon: "clock") {
                        VStack(alignment: .leading, spacing: 12) {
                            if store.schedule.isEmpty {
                                Text("No schedule blocks yet. Rank tasks to build the next three hours.")
                                    .font(.system(size: 13))
                                    .foregroundStyle(.white.opacity(0.6))
                            } else {
                                ForEach(store.schedule) { block in
                                    scheduleRow(block)
                                }
                            }

                            if store.scheduleOverflowCount > 0 {
                                Text("\(store.scheduleOverflowCount) task(s) didn't fit — see full list.")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.58))
                            }
                        }
                    }

                    TimedCard(title: store.isQuizMode ? "Quiz chat" : "Planner chat", icon: store.isQuizMode ? "questionmark.bubble" : "message") {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(store.chat) { message in
                                PromptBubble(message: message)
                            }
                        }
                    }
                }
            }
            .scrollIndicators(.hidden)

            promptComposer
        }
    }

    private var rightColumn: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                TimedCard(title: "Context", icon: "doc.text.magnifyingglass") {
                    VStack(alignment: .leading, spacing: 12) {
                        Picker("Subject filter", selection: $selectedContextFilter) {
                            ForEach(contextFilterOptions, id: \.self) { option in
                                Text(option).tag(option)
                            }
                        }
                        .pickerStyle(.segmented)

                        if filteredContexts.isEmpty {
                            Text("No context matches this subject yet.")
                                .font(.system(size: 13))
                                .foregroundStyle(.white.opacity(0.6))
                        } else {
                            ForEach(filteredContexts) { context in
                                TimedCard(title: context.title, icon: "book.closed") {
                                    VStack(alignment: .leading, spacing: 10) {
                                        HStack {
                                            Text(context.subject)
                                                .font(.system(size: 12, weight: .semibold))
                                                .foregroundStyle(.white.opacity(0.65))
                                            Spacer()
                                            Text(context.createdAt.formatted(date: .abbreviated, time: .shortened))
                                                .font(.system(size: 11, weight: .medium))
                                                .foregroundStyle(.white.opacity(0.48))
                                        }

                                        Text(context.summary)
                                            .font(.system(size: 13))
                                            .foregroundStyle(.white.opacity(0.72))

                                        HStack(spacing: 10) {
                                            Button("View") {
                                                store.selectContext(context)
                                            }
                                            .buttonStyle(.bordered)

                                            Button("Quiz me") {
                                                Task { await store.startQuiz(subject: context.subject) }
                                            }
                                            .buttonStyle(.borderedProminent)
                                        }
                                    }
                                }
                                .overlay(selectionBorder(isSelected: store.selectedContextID == context.id))
                            }
                        }
                    }
                }

                if let selectedContext = store.selectedContext {
                    TimedCard(title: selectedContext.title, icon: "text.book.closed") {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(selectedContext.summary)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.white.opacity(0.82))

                            Text(selectedContext.detail)
                                .font(.system(size: 12))
                                .foregroundStyle(.white.opacity(0.64))
                                .textSelection(.enabled)
                        }
                    }
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    private var promptComposer: some View {
        TimedCard(title: store.isQuizMode ? "Answer the tutor" : "Ask Timed", icon: store.isQuizMode ? "questionmark.circle" : "sparkles") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 12) {
                    TextField(
                        store.isQuizMode ? "Type your answer or “End quiz”" : "What should I do now?",
                        text: $store.promptText
                    )
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(rowBackground)
                    .onSubmit {
                        Task { await store.submitPrompt() }
                    }

                    Button(store.isQuizMode ? "Send" : "Ask") {
                        Task { await store.submitPrompt() }
                    }
                    .buttonStyle(.borderedProminent)

                    if store.isQuizMode {
                        Button("End quiz") {
                            store.endQuiz()
                        }
                        .buttonStyle(.bordered)
                    }
                }

                HStack(spacing: 10) {
                    if store.isRunningPrompt {
                        ProgressView()
                            .controlSize(.small)
                        Text("Asking Timed...")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.68))
                    } else if let aiErrorText = store.aiErrorText {
                        Text(aiErrorText)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.red.opacity(0.9))
                        SettingsLink {
                            Text("Configure AI path")
                        }
                    } else {
                        Text(store.isQuizMode ? "Quiz mode is live." : "Planner mode uses your ranked tasks and context.")
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.58))
                    }
                }
            }
        }
    }

    private func rankedTaskRow(_ ranked: RankedTask) -> some View {
        TimedCard(title: ranked.task.title, icon: icon(for: ranked.task.source)) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(ranked.task.subject) · \(ranked.task.estimateMinutes) min · confidence \(ranked.task.confidence)/5")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.62))

                        if let dueDate = ranked.task.dueDate {
                            Text("Due \(dueDate.formatted(date: .abbreviated, time: .omitted))")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.white.opacity(0.56))
                        }
                    }

                    Spacer()

                    HStack(spacing: 8) {
                        badge(text: ranked.band, emphasis: .secondary)
                        badge(text: "\(ranked.score)", emphasis: .primary)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(ranked.reasons.prefix(2)), id: \.self) { reason in
                        Text(reason)
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.62))
                    }
                }

                Text(ranked.suggestedNextAction)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.82))

                HStack(spacing: 10) {
                    Button {
                        store.markTaskCompleted(ranked.task)
                    } label: {
                        Label("Complete", systemImage: "checkmark.circle")
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Focus") {
                        store.selectTask(ranked.task)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .overlay(selectionBorder(isSelected: store.selectedTaskID == ranked.task.id))
    }

    private func scheduleRow(_ block: ScheduleBlock) -> some View {
        TimedCard(title: block.title, icon: "calendar") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(block.timeRange)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white)
                    Spacer()
                    badge(text: block.isApproved ? "Approved" : "Pending", emphasis: block.isApproved ? .primary : .secondary)
                }

                Text(block.note)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.72))

                HStack(spacing: 10) {
                    Button(block.isApproved ? "Unapprove" : "Approve") {
                        store.toggleScheduleApproval(block)
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Remove") {
                        store.removeScheduleBlock(block)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private var filteredContexts: [ContextItem] {
        if selectedContextFilter == "All" {
            return store.sortedContexts
        }

        return store.sortedContexts.filter { $0.subject == selectedContextFilter }
    }

    private var contextFilterOptions: [String] {
        let subjects = Array(Set(store.sortedContexts.map(\.subject))).sorted()
        return Array((["All"] + subjects).prefix(5))
    }

    private var activeContextSubject: String? {
        if selectedContextFilter != "All" {
            return selectedContextFilter
        }
        return store.selectedContext?.subject
    }

    private var headerDateString: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.timeStyle = .none
        return formatter.string(from: .now)
    }

    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color.white.opacity(0.06))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
    }

    private func badge(text: String, emphasis: BadgeEmphasis) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(emphasis == .primary ? Color.white.opacity(0.18) : Color.white.opacity(0.08))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )
    }

    private func selectionBorder(isSelected: Bool) -> some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .stroke(isSelected ? Color.white.opacity(0.22) : Color.clear, lineWidth: 1)
    }

    private func taskLibrarySort(lhs: TaskItem, rhs: TaskItem) -> Bool {
        if lhs.isCompleted != rhs.isCompleted {
            return rhs.isCompleted == false
        }
        return lhs.title < rhs.title
    }

    private func icon(for source: TaskSource) -> String {
        switch source {
        case .seqta:
            return "graduationcap"
        case .tickTick:
            return "checklist"
        case .transcript:
            return "doc.text"
        case .chat:
            return "message"
        }
    }

    private func extractSuggestionQuizSubject(_ suggestion: String) -> String? {
        guard suggestion.lowercased().hasPrefix("quiz me on ") else { return nil }
        return String(suggestion.dropFirst("Quiz me on ".count))
    }
}

private enum BadgeEmphasis {
    case primary
    case secondary
}

private struct HeaderActionButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
        }
        .buttonStyle(.bordered)
        .tint(.white.opacity(0.22))
    }
}

private struct PromptBubble: View {
    let message: PromptMessage

    var body: some View {
        HStack {
            if message.role == .tutor || message.role == .assistant {
                bubble
                Spacer(minLength: 40)
            } else {
                Spacer(minLength: 40)
                bubble
            }
        }
    }

    private var bubble: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: iconName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.82))
                .padding(8)
                .background(Circle().fill(Color.white.opacity(0.08)))

            VStack(alignment: .leading, spacing: 6) {
                Text(message.role.displayName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.54))

                Text(message.text)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.9))
                    .textSelection(.enabled)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(message.isQuiz ? Color.white.opacity(0.1) : Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }

    private var iconName: String {
        switch message.role {
        case .assistant:
            return "sparkles"
        case .tutor:
            return "questionmark.circle"
        case .student:
            return "person.fill"
        case .user:
            return "person.crop.circle"
        }
    }
}

private struct AddTaskSheet: View {
    @Binding var draft: AddTaskDraft
    @Binding var errorMessage: String?
    let onSave: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                TextField("Title", text: $draft.title)
                Picker("Subject", selection: $draft.subject) {
                    ForEach(SubjectCatalog.supported, id: \.self) { subject in
                        Text(subject).tag(subject)
                    }
                }
                Stepper("Estimate \(draft.estimateMinutes) min", value: $draft.estimateMinutes, in: 5...300, step: 5)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Importance \(Int(draft.importance.rounded()))")
                    Slider(value: $draft.importance, in: 1...5, step: 1)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Confidence \(Int(draft.confidence.rounded()))")
                    Slider(value: $draft.confidence, in: 1...5, step: 1)
                }
                DatePicker("Due date", selection: $draft.dueDate, displayedComponents: [.date, .hourAndMinute])
                Picker("Energy", selection: $draft.energy) {
                    ForEach(TaskEnergy.allCases) { energy in
                        Text(energy.rawValue).tag(energy)
                    }
                }
                Picker("Source", selection: $draft.source) {
                    ForEach(TaskSource.allCases) { source in
                        Text(source.rawValue).tag(source)
                    }
                }
                TextEditor(text: $draft.notes)
                    .frame(minHeight: 120)

                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Add task")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave()
                    }
                }
            }
        }
        .frame(minWidth: 480, minHeight: 560)
    }
}

private struct ImportReviewSheet: View {
    @Bindable var store: PlannerStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                Text("Review imported tasks")
                    .font(.system(size: 15, weight: .semibold))

                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if let messages = store.pendingImportBatch?.messages, !messages.isEmpty {
                            ForEach(messages, id: \.self) { message in
                                Text(message)
                                    .font(.system(size: 12))
                                    .foregroundStyle(.white.opacity(0.7))
                            }
                        }

                        ForEach(taskDraftIndices, id: \.self) { index in
                            if let binding = bindingForDraft(at: index) {
                                ImportDraftEditor(draft: binding)
                            }
                        }
                    }
                }
            }
            .padding(20)
            .navigationTitle("Import review")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Discard") {
                        store.discardPendingImport()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply import") {
                        store.applyPendingImport()
                        dismiss()
                    }
                }
            }
        }
        .frame(minWidth: 640, minHeight: 640)
    }

    private func bindingForDraft(at index: Int) -> Binding<ImportTaskDraft>? {
        guard store.pendingImportBatch?.taskDrafts.indices.contains(index) == true else { return nil }
        return Binding(
            get: { store.pendingImportBatch!.taskDrafts[index] },
            set: { store.pendingImportBatch!.taskDrafts[index] = $0 }
        )
    }

    private var taskDraftIndices: [Int] {
        if let drafts = store.pendingImportBatch?.taskDrafts {
            return Array(drafts.indices)
        }
        return []
    }
}

private struct ImportDraftEditor: View {
    @Binding var draft: ImportTaskDraft

    var body: some View {
        TimedCard(title: draft.title, icon: "square.and.pencil") {
            VStack(alignment: .leading, spacing: 10) {
                TextField("Title", text: $draft.title)
                Picker("Subject", selection: $draft.subject) {
                    ForEach(SubjectCatalog.supported, id: \.self) { subject in
                        Text(subject).tag(subject)
                    }
                }
                Stepper("Estimate \(draft.estimateMinutes) min", value: $draft.estimateMinutes, in: 5...240, step: 5)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Importance \(draft.importance)")
                    Slider(
                        value: Binding(
                            get: { Double(draft.importance) },
                            set: { draft.importance = Int($0.rounded()) }
                        ),
                        in: 1...5,
                        step: 1
                    )
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Confidence \(draft.confidence)")
                    Slider(
                        value: Binding(
                            get: { Double(draft.confidence) },
                            set: { draft.confidence = Int($0.rounded()) }
                        ),
                        in: 1...5,
                        step: 1
                    )
                }
                DatePicker("Due", selection: $draft.dueDate, displayedComponents: [.date, .hourAndMinute])
                Picker("Energy", selection: $draft.energy) {
                    ForEach(TaskEnergy.allCases) { energy in
                        Text(energy.rawValue).tag(energy)
                    }
                }
            }
        }
    }
}
