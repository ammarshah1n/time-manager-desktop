import SwiftUI

struct TaskDetailView: View {
    let task: TaskItem
    let onStudy: () -> Void
    let onComplete: () -> Void
    let onSaveNotes: (String) -> Void

    @State private var isEditingNotes = false
    @State private var notesDraft = ""
    @State private var pendingSaveToken = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 10) {
                Text(task.title)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)

                Text("\(task.subject) · \(task.estimateMinutes) min · confidence \(task.confidence)/5 · importance \(task.importance)/5")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.62))
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center) {
                    Text("Notes")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.62))

                    Spacer()

                    Button {
                        toggleNotesMode()
                    } label: {
                        Label(isEditingNotes ? "Preview" : "Edit", systemImage: isEditingNotes ? "eye" : "pencil")
                    }
                    .buttonStyle(.bordered)
                    .keyboardShortcut("e", modifiers: [.command])
                    .help(isEditingNotes ? "Preview notes (⌘E)" : "Edit notes (⌘E)")
                }

                if isEditingNotes {
                    notesEditor
                } else {
                    notesPreview
                }
            }

            HStack(spacing: 10) {
                Button("Study") {
                    onStudy()
                }
                .buttonStyle(.borderedProminent)

                Button("Complete") {
                    flushPendingSave()
                    onComplete()
                }
                .buttonStyle(.bordered)
            }
        }
        .onAppear {
            loadTask(task)
        }
        .onChange(of: task.id) { _, _ in
            loadTask(task)
        }
        .onChange(of: task.notes) { _, newValue in
            syncDraft(with: newValue)
        }
        .onDisappear {
            flushPendingSave()
        }
    }

    private var notesEditor: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.06))

            TextEditor(text: $notesDraft)
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.82))
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 4)
                .padding(.vertical, 6)
                .frame(minHeight: 150)
                .onChange(of: notesDraft) { _, newValue in
                    scheduleSave(for: newValue)
                }

            if notesDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("Add notes…")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.34))
                    .padding(.top, 16)
                    .padding(.leading, 10)
                    .allowsHitTesting(false)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private var notesPreview: some View {
        Group {
            if notesDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("No task notes yet.")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.52))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            } else {
                Text(renderedNotes)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.78))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(12)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private var renderedNotes: AttributedString {
        if let rendered = try? AttributedString(markdown: notesDraft) {
            return rendered
        }
        return AttributedString(notesDraft)
    }

    private func toggleNotesMode() {
        if isEditingNotes {
            flushPendingSave()
        }
        isEditingNotes.toggle()
    }

    private func loadTask(_ task: TaskItem) {
        pendingSaveToken += 1
        notesDraft = task.notes
        isEditingNotes = task.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func syncDraft(with latestNotes: String) {
        guard latestNotes != notesDraft else { return }
        notesDraft = latestNotes
        if latestNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            isEditingNotes = true
        }
    }

    private func scheduleSave(for text: String) {
        pendingSaveToken += 1
        let token = pendingSaveToken
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            guard token == pendingSaveToken else { return }
            onSaveNotes(text)
        }
    }

    private func flushPendingSave() {
        pendingSaveToken += 1
        onSaveNotes(notesDraft)
    }
}
