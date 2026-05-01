#if os(macOS)
// CapturePane.swift — Timed macOS
// Voice/text quick capture. Replaces Recap → Dropbox → PA transcription workflow.
// Transcript E3: "If I could just transcribe that straight to the app."

import SwiftUI
import AppKit
import UniformTypeIdentifiers
import Vision

struct CapturePane: View {
    @Binding var tasks: [TimedTask]
    @StateObject private var voice = VoiceCaptureService()
    @StateObject private var captureAI = CaptureAIClient()
    @StateObject private var speechService = SpeechService()
    @Binding var items: [CaptureItem]
    @State private var textInput = ""
    @State private var pulseAnimation = false
    @State private var showBulkImport = false
    @State private var showScreenshotImport = false
    @State private var bulkText = ""
    @State private var screenshotImportError: String?
    @State private var screenshotImportIsProcessing = false

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
            if !isNowRecording && !voice.liveTranscript.isEmpty {
                let transcript = voice.liveTranscript
                Task {
                    if captureAI.isAvailable {
                        let context = CaptureContext(
                            existingBuckets: TaskBucket.allCases.map(\.rawValue),
                            calendarToday: [],
                            recentTasks: tasks.prefix(5).map(\.title)
                        )
                        if let extracted = await captureAI.extractTasks(transcript, context: context), !extracted.isEmpty {
                            let newItems = extracted.map { task in
                                CaptureItem(
                                    id: UUID(),
                                    inputType: .voice,
                                    rawText: transcript,
                                    parsedTitle: task.title,
                                    suggestedBucket: bucketFromAI(task.bucket),
                                    suggestedMinutes: task.duration,
                                    capturedAt: Date()
                                )
                            }
                            items.insert(contentsOf: newItems, at: 0)
                            if let first = extracted.first {
                                speechService.speak(first.spokenConfirmation)
                            }
                            return
                        }
                    }
                    // Fallback to parser
                    if !voice.parsedItems.isEmpty {
                        let newItems = voice.parsedItems.map { parsed in
                            CaptureItem(
                                id: parsed.id,
                                inputType: .voice,
                                rawText: transcript,
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
        }
    }

    // MARK: - Header

    private var captureHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Quick Capture")
                    .font(.system(size: 14, weight: .semibold))
                Text("Add tasks by voice, text, or paste — review and convert to your task list")
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
                        // Recording = live destructive signal; idle = primary (black/white).
                        Circle()
                            .fill(voice.isRecording ? Color.Timed.destructive : Color.primary)
                            .frame(width: 48, height: 48)
                        Circle()
                            .fill(voice.isRecording ? Color.Timed.destructive.opacity(0.3) : Color.clear)
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
                    .shadow(color: voice.isRecording ? Color.Timed.destructive.opacity(0.4) : .primary.opacity(0.3), radius: voice.isRecording ? 8 : 4)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(voice.isRecording ? "Recording… tap to stop" : "Tap to record")
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
                    Color(.controlBackgroundColor),
                    in: RoundedRectangle(cornerRadius: 12)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(voice.isRecording ? Color.Timed.destructive.opacity(0.3) : Color.clear, lineWidth: 1.5)
                )
            }
            .buttonStyle(.plain)

            if let error = voice.lastError {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.Timed.destructive)
                    Text(error.localizedDescription)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.Timed.destructive)
                        .lineLimit(2)
                    Spacer()
                    Button("Open Settings") {
                        openVoicePrivacySettings()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                }
                .padding(.horizontal, 4)
            }

            if captureAI.isProcessing {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Understanding...")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
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
                .tint(.primary)
                .controlSize(.small)
                .disabled(textInput.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(Color(.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 9))

            // Bulk paste import
            Button {
                showBulkImport = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 13))
                    Text("Paste a task list")
                        .font(.system(size: 13))
                }
                .foregroundStyle(.primary)
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $showBulkImport) {
                bulkImportSheet
            }

            Button {
                showScreenshotImport = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "photo.on.rectangle")
                        .font(.system(size: 13))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Import screenshot")
                            .font(.system(size: 13))
                        Text("Take a screenshot of your to-do list and insert it here")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if screenshotImportIsProcessing {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 12).padding(.vertical, 9)
                .background(Color(.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 9))
            }
            .buttonStyle(.plain)
            .disabled(screenshotImportIsProcessing)
            .fileImporter(
                isPresented: $showScreenshotImport,
                allowedContentTypes: [.image],
                allowsMultipleSelection: false
            ) { result in
                handleScreenshotImport(result)
            }

            if let screenshotImportError {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.Timed.destructive)
                    Text(screenshotImportError)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.Timed.destructive)
                    Spacer()
                }
                .padding(.horizontal, 4)
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 16)
    }

    // MARK: - Bulk Import Sheet

    private var bulkImportSheet: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Import task list")
                    .font(.headline)
                Spacer()
                Button("Cancel") { showBulkImport = false }
                    .buttonStyle(.plain)
            }

            Text("One task per line. Timed will create a draft for each line — you can adjust times and categories after.")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextEditor(text: $bulkText)
                .font(.system(size: 13, design: .monospaced))
                .frame(minHeight: 200)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(Color(.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            HStack {
                let lineCount = bulkText.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.count
                Text("\(lineCount) task\(lineCount == 1 ? "" : "s") detected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Import") {
                    importBulkTasks()
                    showBulkImport = false
                }
                .buttonStyle(.borderedProminent)
                .tint(.primary)
                .disabled(bulkText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 480, height: 380)
    }

    private func importBulkTasks() {
        let lines = bulkText.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        let newItems = lines.flatMap { line -> [CaptureItem] in
            let parsed = TranscriptParser.parse(line)
            if parsed.isEmpty {
                return [
                    CaptureItem(
                        id: UUID(),
                        inputType: .text,
                        rawText: line,
                        parsedTitle: line,
                        suggestedBucket: .action,
                        suggestedMinutes: 15,
                        capturedAt: Date()
                    )
                ]
            }
            return parsed.map { item in
                CaptureItem(
                    id: item.id,
                    inputType: .text,
                    rawText: line,
                    parsedTitle: item.title,
                    suggestedBucket: bucketFromVoice(item.bucketType),
                    suggestedMinutes: item.estimatedMinutes ?? 15,
                    capturedAt: Date()
                )
            }
        }
        items.insert(contentsOf: newItems, at: 0)
        bulkText = ""
    }

    private func handleScreenshotImport(_ result: Result<[URL], Error>) {
        screenshotImportError = nil
        guard case .success(let urls) = result, let url = urls.first else { return }
        screenshotImportIsProcessing = true
        Task {
            do {
                let text = try await recognizeTextInImage(at: url)
                await MainActor.run {
                    screenshotImportIsProcessing = false
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmed.isEmpty {
                        screenshotImportError = "No readable tasks found in that screenshot."
                    } else {
                        bulkText = trimmed
                        showBulkImport = true
                    }
                }
            } catch {
                await MainActor.run {
                    screenshotImportIsProcessing = false
                    screenshotImportError = "Could not read that screenshot."
                }
            }
        }
    }

    private func recognizeTextInImage(at url: URL) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            let didStartAccess = url.startAccessingSecurityScopedResource()
            defer {
                if didStartAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            guard let image = NSImage(contentsOf: url) else {
                throw CocoaError(.fileReadCorruptFile)
            }
            var rect = CGRect(origin: .zero, size: image.size)
            guard let cgImage = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else {
                throw CocoaError(.fileReadCorruptFile)
            }

            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: cgImage)
            try handler.perform([request])

            return (request.results ?? [])
                .compactMap { $0.topCandidates(1).first?.string.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
        }.value
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
                    CaptureRow(item: item) { title, minutes, bucket in
                        updateItem(item, title: title, minutes: minutes, bucket: bucket)
                    } onConvert: { title, minutes, bucket in
                        convertItem(item, title: title, minutes: minutes, bucket: bucket)
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
        let input = t
        textInput = ""

        Task {
            if captureAI.isAvailable {
                let context = CaptureContext(
                    existingBuckets: TaskBucket.allCases.map(\.rawValue),
                    calendarToday: [],
                    recentTasks: tasks.prefix(5).map(\.title)
                )
                if let extracted = await captureAI.extractTasks(input, context: context), !extracted.isEmpty {
                    let newItems = extracted.map { task in
                        CaptureItem(
                            id: UUID(),
                            inputType: .text,
                            rawText: input,
                            parsedTitle: task.title,
                            suggestedBucket: bucketFromAI(task.bucket),
                            suggestedMinutes: task.duration,
                            capturedAt: Date()
                        )
                    }
                    items.insert(contentsOf: newItems, at: 0)
                    if let first = extracted.first {
                        speechService.speak(first.spokenConfirmation)
                    }
                    return
                }
            }
            // Fallback to TranscriptParser
            let parsed = TranscriptParser.parse(input)
            let newItems: [CaptureItem]
            if parsed.isEmpty {
                newItems = [CaptureItem(
                    id: UUID(), inputType: .text,
                    rawText: input, parsedTitle: input,
                    suggestedBucket: .action, suggestedMinutes: 15,
                    capturedAt: Date()
                )]
            } else {
                newItems = parsed.map { p in
                    CaptureItem(
                        id: p.id, inputType: .text,
                        rawText: input, parsedTitle: p.title,
                        suggestedBucket: bucketFromVoice(p.bucketType),
                        suggestedMinutes: p.estimatedMinutes ?? 15,
                        capturedAt: Date()
                    )
                }
            }
            items.insert(contentsOf: newItems, at: 0)
        }
    }

    private func updateItem(_ item: CaptureItem, title: String, minutes: Int, bucket: TaskBucket) {
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[idx].parsedTitle = title
        items[idx].suggestedMinutes = minutes
        items[idx].suggestedBucket = bucket
    }

    private func convertItem(_ item: CaptureItem) {
        convertItem(
            item,
            title: item.parsedTitle,
            minutes: item.suggestedMinutes,
            bucket: item.suggestedBucket
        )
    }

    private func convertItem(_ item: CaptureItem, title: String, minutes: Int, bucket: TaskBucket) {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let task = TimedTask(
            id: UUID(),
            title: cleanTitle.isEmpty ? item.parsedTitle : cleanTitle,
            sender: "Capture",
            estimatedMinutes: minutes,
            bucket: bucket,
            emailCount: 0,
            receivedAt: item.capturedAt
        )
        tasks.append(task)
        if let idx = items.firstIndex(where: { $0.id == item.id }) {
            items[idx].parsedTitle = task.title
            items[idx].suggestedMinutes = minutes
            items[idx].suggestedBucket = bucket
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

    private func bucketFromAI(_ bucket: String) -> TaskBucket {
        switch bucket {
        case "calls":        return .calls
        case "reply":        return .reply
        case "readToday":    return .readToday
        case "readThisWeek": return .readThisWeek
        case "transit":      return .transit
        case "waiting":      return .waiting
        case "ccFyi":        return .ccFyi
        case "action":       return .action
        default:             return .action
        }
    }

    private func openVoicePrivacySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") else { return }
        NSWorkspace.shared.open(url)
    }
}

// MARK: - Capture Row

struct CaptureRow: View {
    var item: CaptureItem
    let onUpdate: (String, Int, TaskBucket) -> Void
    let onConvert: (String, Int, TaskBucket) -> Void
    let onDelete: () -> Void

    @State private var editingTitle: String
    @State private var editingMins: Int
    @State private var editingBucket: TaskBucket

    init(
        item: CaptureItem,
        onUpdate: @escaping (String, Int, TaskBucket) -> Void,
        onConvert: @escaping (String, Int, TaskBucket) -> Void,
        onDelete: @escaping () -> Void
    ) {
        self.item = item
        self.onUpdate = onUpdate
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

                    Button("Add to Tasks") { onConvert(editingTitle, editingMins, editingBucket) }
                        .buttonStyle(.borderedProminent)
                        .tint(.primary)
                        .controlSize(.mini)
                }

                if item.isConverted {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.Timed.labelSecondary)
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
        .onChange(of: editingTitle) { _, value in
            onUpdate(value, editingMins, editingBucket)
        }
        .onChange(of: editingMins) { _, value in
            onUpdate(editingTitle, value, editingBucket)
        }
        .onChange(of: editingBucket) { _, value in
            onUpdate(editingTitle, editingMins, value)
        }
    }
}

#endif
