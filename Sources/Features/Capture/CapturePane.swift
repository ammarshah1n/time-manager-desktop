// CapturePane.swift — Timed macOS
// Voice/text quick capture. Replaces Recap → Dropbox → PA transcription workflow.
// Transcript E3: "If I could just transcribe that straight to the app."

import SwiftUI

struct CapturePane: View {
    @Binding var tasks: [TimedTask]
    // en-US is always supported — init? returns nil only for unsupported locales
    @StateObject private var voice = VoiceCaptureService()!
    @Binding var items: [CaptureItem]
    @State private var textInput = ""
    @State private var pulseAnimation = false

    private var unconverted: [CaptureItem] { items.filter { !$0.isConverted } }
    private var converted: [CaptureItem]   { items.filter { $0.isConverted } }

    var body: some View {
        VStack(spacing: 0) {
            captureHeader
            Divider()
            captureInput
            Divider()
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    if !unconverted.isEmpty {
                        captureSection("PENDING REVIEW", items: unconverted)
                    }
                    if !converted.isEmpty {
                        captureSection("CONVERTED", items: converted)
                    }
                    if items.isEmpty {
                        emptyState
                    }
                }
                .padding(.horizontal, 24).padding(.vertical, 20)
            }
        }
        .navigationTitle("Capture")
        .onChange(of: voice.isRecording) { _, isNowRecording in
            pulseAnimation = isNowRecording
            if !isNowRecording && !voice.parsedItems.isEmpty {
                let newItems = voice.parsedItems.map { parsed in
                    CaptureItem(
                        id: parsed.id,
                        inputType: .voice,
                        rawText: voice.liveTranscript,
                        parsedTitle: parsed.title,
                        suggestedBucket: bucketFromVoice(parsed.bucketType),
                        suggestedMinutes: parsed.estimatedMinutes ?? 10,
                        capturedAt: Date()
                    )
                }
                items.insert(contentsOf: newItems, at: 0)
            }
        }
    }

    // MARK: - Header

    private var captureHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Capture")
                    .font(.system(size: 14, weight: .semibold))
                Text("\(unconverted.count) pending review")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if !unconverted.isEmpty {
                Button("Convert All") {
                    for i in items.indices {
                        if !items[i].isConverted {
                            convertItem(items[i])
                        }
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
    }

    // MARK: - Input area

    private var captureInput: some View {
        VStack(spacing: 16) {
            // Voice button
            Button {
                if voice.isRecording {
                    voice.stop()
                } else {
                    Task { await voice.start() }
                }
            } label: {
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(voice.isRecording ? Color.red : Color.indigo)
                            .frame(width: 48, height: 48)
                        Circle()
                            .fill(voice.isRecording ? Color.red.opacity(0.3) : Color.clear)
                            .frame(width: 48, height: 48)
                            .scaleEffect(pulseAnimation ? 1.5 : 1.0)
                            .opacity(pulseAnimation ? 0 : 0.6)
                            .animation(
                                voice.isRecording
                                    ? .easeInOut(duration: 1.0).repeatForever(autoreverses: false)
                                    : .default,
                                value: pulseAnimation
                            )
                        Image(systemName: voice.isRecording ? "stop.fill" : "mic.fill")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(.white)
                    }
                    .shadow(color: voice.isRecording ? .red.opacity(0.4) : .indigo.opacity(0.3), radius: voice.isRecording ? 8 : 4)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(voice.isRecording ? "Recording… tap to stop" : "Hold to record")
                            .font(.system(size: 14, weight: .medium))
                        Text(voice.isRecording ? "Speak your tasks — I'll parse them automatically" : "\"Call John back, 5 mins. Review contract from David, 30 mins.\"")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        if voice.isRecording && !voice.liveTranscript.isEmpty {
                            Text(voice.liveTranscript)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                                .truncationMode(.head)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, 4)
                        }
                    }
                    Spacer()
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
                .background(
                    voice.isRecording ? Color.red.opacity(0.06) : Color(.controlBackgroundColor),
                    in: RoundedRectangle(cornerRadius: 12)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(voice.isRecording ? Color.red.opacity(0.3) : Color.clear, lineWidth: 1.5)
                )
            }
            .buttonStyle(.plain)

            if let error = voice.lastError {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.red)
                    Text(error.localizedDescription)
                        .font(.system(size: 11))
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
                .padding(.horizontal, 4)
            }

            // Text input
            HStack(spacing: 8) {
                TextField("Or type a task… \"Fix bookmarks in laptop, 10 min, transit\"", text: $textInput)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .onSubmit { addTextCapture() }

                Button("Add") {
                    addTextCapture()
                }
                .buttonStyle(.borderedProminent)
                .tint(.indigo)
                .controlSize(.small)
                .disabled(textInput.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(Color(.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 9))
        }
        .padding(.horizontal, 20).padding(.vertical, 16)
    }

    // MARK: - Section

    @ViewBuilder
    private func captureSection(_ title: String, items: [CaptureItem]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .tracking(1.2)
                Text("·  \(items.count)")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 2) {
                ForEach(items) { item in
                    CaptureRow(item: item) {
                        convertItem(item)
                    } onDelete: {
                        self.items.removeAll { $0.id == item.id }
                    }
                }
            }
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "mic.slash")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(.secondary.opacity(0.5))
            Text("Nothing captured yet")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
            Text("Use the mic button or type tasks above.\nThey'll appear here for review before entering your task list.")
                .font(.system(size: 12))
                .foregroundStyle(Color(.tertiaryLabelColor))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    // MARK: - Actions

    private func addTextCapture() {
        let t = textInput.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        let item = CaptureItem(
            id: UUID(), inputType: .text,
            rawText: t, parsedTitle: t,
            suggestedBucket: .action, suggestedMinutes: 15,
            capturedAt: Date()
        )
        items.insert(item, at: 0)
        textInput = ""
    }

    private func convertItem(_ item: CaptureItem) {
        let task = TimedTask(
            id: UUID(),
            title: item.parsedTitle,
            sender: "Capture",
            estimatedMinutes: item.suggestedMinutes,
            bucket: item.suggestedBucket,
            emailCount: 0,
            receivedAt: item.capturedAt
        )
        tasks.append(task)
        if let idx = items.firstIndex(where: { $0.id == item.id }) {
            items[idx].isConverted = true
        }
    }

    private func bucketFromVoice(_ type: String) -> TaskBucket {
        switch type {
        case "calls":       return .calls
        case "reply_email": return .reply
        case "read_today":  return .readToday
        case "action":      return .action
        default:            return .action
        }
    }
}

// MARK: - Capture Row

struct CaptureRow: View {
    var item: CaptureItem
    let onConvert: () -> Void
    let onDelete: () -> Void

    @State private var editingTitle: String
    @State private var editingMins: Int
    @State private var editingBucket: TaskBucket

    init(item: CaptureItem, onConvert: @escaping () -> Void, onDelete: @escaping () -> Void) {
        self.item = item
        self.onConvert = onConvert
        self.onDelete = onDelete
        self._editingTitle  = State(initialValue: item.parsedTitle)
        self._editingMins   = State(initialValue: item.suggestedMinutes)
        self._editingBucket = State(initialValue: item.suggestedBucket)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: item.inputType == .voice ? "mic.fill" : "text.cursor")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .frame(width: 14)

                if item.isConverted {
                    Text(item.parsedTitle)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .strikethrough(true, color: .secondary)
                } else {
                    TextField("Task title", text: $editingTitle)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                }

                Spacer()

                if !item.isConverted {
                    Picker("Bucket", selection: $editingBucket) {
                        ForEach(TaskBucket.allCases, id: \.self) { b in
                            Label(b.rawValue, systemImage: b.icon).tag(b)
                        }
                    }
                    .labelsHidden()
                    .controlSize(.mini)
                    .frame(width: 120)

                    HStack(spacing: 2) {
                        Button { editingMins = max(5, editingMins - 5) } label: {
                            Image(systemName: "minus").font(.system(size: 9))
                        }
                        .buttonStyle(.plain)
                        Text("\(editingMins)m")
                            .font(.system(size: 11, weight: .medium))
                            .monospacedDigit()
                            .frame(width: 32)
                        Button { editingMins += 5 } label: {
                            Image(systemName: "plus").font(.system(size: 9))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Color(.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))

                    Button("Add to Tasks") { onConvert() }
                        .buttonStyle(.borderedProminent)
                        .tint(.indigo)
                        .controlSize(.mini)
                }

                if item.isConverted {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.system(size: 13))
                }

                Button(role: .destructive) { onDelete() } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .foregroundStyle(Color(.tertiaryLabelColor))
                }
                .buttonStyle(.plain)
            }

            // Raw transcript (for voice)
            if item.inputType == .voice && !item.isConverted {
                Text(item.rawText)
                    .font(.system(size: 10))
                    .foregroundStyle(Color(.tertiaryLabelColor))
                    .padding(.leading, 22)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(
            item.isConverted ? Color(.controlBackgroundColor).opacity(0.5) : Color(.controlBackgroundColor),
            in: RoundedRectangle(cornerRadius: 9)
        )
    }
}
