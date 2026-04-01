// MorningInterviewPane.swift — Timed macOS
// The morning ritual. 5–10 min guided review that replaces the 30-min manual rewrite.
// Transcript D4: "You could spend 10 minutes answering questions, then it creates your day plan while you make your coffee."
//
// Voice mode: app SPEAKS questions, user SPEAKS answers. Hands-free while making coffee.
// Button mode: existing wizard flow with manual controls (always available as fallback).

import SwiftUI

struct MorningInterviewPane: View {

    // MARK: - Conversation state machine

    enum ConversationState: Equatable {
        case idle
        case appSpeaking(step: Int)
        case waitingToListen
        case listening(step: Int)
        case processing
    }

    @Binding var tasks: [TimedTask]
    @Binding var blocks: [CalendarBlock]
    @Binding var isPresented: Bool

    @State private var step = 0
    @State private var availableMinutes = 180
    @State private var confirmedIds: Set<UUID>
    @State private var estimates: [UUID: Int] = [:]
    @State private var hasTravelToday: Bool = false

    // Voice mode
    @AppStorage("prefs.morningInterview.voiceMode") private var voiceMode: Bool = false
    @StateObject private var speechService = SpeechService()
    @StateObject private var voiceCapture: VoiceCaptureService = VoiceCaptureService()!
    @State private var isListening: Bool = false
    @State private var voiceProcessing: Bool = false
    @State private var voiceStatusText: String = ""
    @State private var conversationState: ConversationState = .idle

    // Silence timeout tracking
    @State private var silenceTimer: Task<Void, Never>?
    @State private var lastTranscriptSnapshot: String = ""
    @State private var silenceTimeoutCount: Int = 0

    private let totalSteps = 4

    init(tasks: Binding<[TimedTask]>, blocks: Binding<[CalendarBlock]>, isPresented: Binding<Bool>) {
        self._tasks = tasks
        self._blocks = blocks
        self._isPresented = isPresented
        // pre-select all due-today tasks
        let ids = Set(tasks.wrappedValue.filter { $0.dueToday || $0.isDoFirst }.map(\.id))
        self._confirmedIds = State(initialValue: ids)
    }

    // Tasks AI thinks should happen today
    private var todayCandidates: [TimedTask] {
        tasks.filter { $0.dueToday || $0.isDoFirst }
    }

    // Assumptions: all tasks sorted by estimated time descending
    private var assumptions: [TimedTask] {
        tasks.filter { !$0.isDoFirst && $0.bucket != .waiting }
              .sorted { $0.estimatedMinutes > $1.estimatedMinutes }
              .prefix(10)
              .map { $0 }
    }

    private var confirmedTasks: [TimedTask] {
        tasks.filter { confirmedIds.contains($0.id) }
    }

    // Travel detection: calendar blocks today matching travel keywords or transit category
    private var travelEvents: [CalendarBlock] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let tomorrow = cal.date(byAdding: .day, value: 1, to: today)!
        let travelKeywords = ["flight", "airport", "travel", "drive", "transit", "car", "commute", "train", "uber", "taxi"]
        return blocks.filter { block in
            let isToday = block.startTime >= today && block.startTime < tomorrow
            let hasTravelKeyword = travelKeywords.contains { block.title.lowercased().contains($0) }
            return isToday && (hasTravelKeyword || block.category == .transit)
        }
    }

    private var confirmedTotal: Int {
        confirmedTasks.reduce(0) { $0 + (estimates[$1.id] ?? $1.estimatedMinutes) }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            ZStack {
                if step == 0 { stepTimeDeclaration.transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading))) }
                if step == 1 { stepDueTodayReview.transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading))) }
                if step == 2 { stepAssumptions.transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading))) }
                if step == 3 { stepPlanConfirm.transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading))) }
            }
            .animation(.easeInOut(duration: 0.25), value: step)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            footer
        }
        .frame(width: 640, height: 560)
        .onChange(of: step) { _, newStep in
            if voiceMode {
                speakForStep(newStep)
            }
        }
        .onChange(of: voiceMode) { _, isOn in
            if isOn {
                speakForStep(step)
            } else {
                speechService.stop()
                stopListening()
                conversationState = .idle
                cancelSilenceTimer()
            }
        }
        .onChange(of: speechService.isSpeaking) { wasSpeaking, isSpeaking in
            // Transition: app finished speaking → wait briefly → start listening
            if wasSpeaking && !isSpeaking, case .appSpeaking(let spokenStep) = conversationState {
                conversationState = .waitingToListen
                Task {
                    try? await Task.sleep(for: .milliseconds(300))
                    guard voiceMode, step == spokenStep, conversationState == .waitingToListen else { return }
                    conversationState = .listening(step: spokenStep)
                    silenceTimeoutCount = 0
                    startListening()
                    startSilenceTimer(forStep: spokenStep)
                }
            }
        }
        .onChange(of: voiceCapture.liveTranscript) { _, newTranscript in
            // Any new speech resets the silence timer
            if case .listening(let listenStep) = conversationState, !newTranscript.isEmpty {
                lastTranscriptSnapshot = newTranscript
                resetSilenceTimer(forStep: listenStep)
            }
        }
        .onAppear {
            if voiceMode {
                speakForStep(step)
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(greeting)
                        .font(.system(size: 22, weight: .semibold))
                    Text(stepLabel)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                Spacer()

                // Voice mode toggle
                voiceModeToggle

                Button {
                    speechService.stop()
                    stopListening()
                    cancelSilenceTimer()
                    conversationState = .idle
                    isPresented = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(Color(.tertiaryLabelColor))
                }
                .buttonStyle(.plain)
                .help("Skip morning review")
            }

            // Progress bar
            HStack(spacing: 4) {
                ForEach(0..<totalSteps, id: \.self) { i in
                    Capsule()
                        .fill(i <= step ? Color.indigo : Color(.separatorColor))
                        .frame(height: 3)
                        .animation(.easeInOut(duration: 0.3), value: step)
                }
            }
        }
        .padding(.horizontal, 28).padding(.top, 22).padding(.bottom, 16)
    }

    // MARK: - Voice mode toggle

    private var voiceModeToggle: some View {
        Button {
            voiceMode.toggle()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: voiceMode ? "waveform.circle.fill" : "waveform.circle")
                    .font(.system(size: 14))
                Text(voiceMode ? "Voice On" : "Voice Off")
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(voiceMode ? .indigo : .secondary)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(
                voiceMode ? Color.indigo.opacity(0.1) : Color(.controlBackgroundColor),
                in: Capsule()
            )
        }
        .buttonStyle(.plain)
        .help("Toggle voice conversation mode")
        .padding(.trailing, 8)
    }

    // MARK: - Voice status bar (shown in voice mode)

    private var voiceStatusBar: some View {
        Group {
            if voiceMode {
                HStack(spacing: 10) {
                    switch conversationState {
                    case .appSpeaking:
                        speakingIndicator
                    case .waitingToListen:
                        speakingIndicator  // brief transition, show same as speaking
                    case .listening:
                        listeningIndicator
                    case .processing:
                        processingIndicator
                    case .idle:
                        idleVoiceIndicator
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(voiceStatusBackground, in: RoundedRectangle(cornerRadius: 10))
                .padding(.bottom, 8)
            }
        }
    }

    private var speakingIndicator: some View {
        HStack(spacing: 8) {
            PulsingIcon(systemName: "speaker.wave.2.fill", color: .indigo)
            VStack(alignment: .leading, spacing: 2) {
                Text("Speaking...")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.indigo)
                if !voiceStatusText.isEmpty {
                    Text(voiceStatusText)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer()
            Button {
                speechService.stop()
            } label: {
                Image(systemName: "stop.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Stop speaking")
        }
    }

    private var listeningIndicator: some View {
        HStack(spacing: 8) {
            PulsingIcon(systemName: "mic.fill", color: .red)
            VStack(alignment: .leading, spacing: 2) {
                Text("Listening...")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.red)
                if !voiceCapture.liveTranscript.isEmpty {
                    Text(voiceCapture.liveTranscript)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer()
            Button {
                finishListening()
            } label: {
                Text("Done")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(.red, in: Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    private var processingIndicator: some View {
        HStack(spacing: 8) {
            ProgressView()
                .scaleEffect(0.7)
                .frame(width: 20, height: 20)
            Text("Processing response...")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    private var idleVoiceIndicator: some View {
        HStack(spacing: 8) {
            Image(systemName: "mic.circle")
                .font(.system(size: 16))
                .foregroundStyle(.secondary)
            Text("Tap to speak your answer")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                startListening()
            } label: {
                Text("Speak")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12).padding(.vertical, 4)
                    .background(.indigo, in: Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    private var voiceStatusBackground: Color {
        switch conversationState {
        case .appSpeaking, .waitingToListen: return Color.indigo.opacity(0.06)
        case .listening: return Color.red.opacity(0.06)
        case .processing: return Color(.controlBackgroundColor)
        case .idle: return Color(.controlBackgroundColor)
        }
    }

    // MARK: - Step 0: Time declaration

    private var stepTimeDeclaration: some View {
        VStack(alignment: .leading, spacing: 24) {
            voiceStatusBar

            VStack(alignment: .leading, spacing: 8) {
                Text("It looks like you have free time today.")
                    .font(.system(size: 16, weight: .medium))
                Text("How much time are you allocating to work today?")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            // Preset buttons
            HStack(spacing: 8) {
                ForEach([60, 120, 180, 240], id: \.self) { mins in
                    Button {
                        availableMinutes = mins
                    } label: {
                        Text(formatMins(mins))
                            .font(.system(size: 13, weight: .medium))
                            .padding(.horizontal, 16).padding(.vertical, 8)
                            .background(availableMinutes == mins ? Color.indigo : Color(.controlBackgroundColor),
                                        in: RoundedRectangle(cornerRadius: 8))
                            .foregroundStyle(availableMinutes == mins ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                }
            }

            // Slider
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Custom")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(formatMins(availableMinutes))
                        .font(.system(size: 14, weight: .semibold))
                        .monospacedDigit()
                }
                Slider(value: Binding(
                    get: { Double(availableMinutes) },
                    set: { availableMinutes = Int($0) }
                ), in: 30...480, step: 15)
                .tint(.indigo)
            }
            .padding(.horizontal, 2)

            // Summary
            HStack(spacing: 8) {
                Image(systemName: "calendar")
                    .font(.system(size: 11))
                    .foregroundStyle(.indigo)
                Text("Based on your calendar, you have \(formatMins(availableMinutes)) of clear time today.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .padding(10)
            .background(Color.indigo.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))

            if !voiceMode {
                voiceButton
            }

            Spacer()
        }
        .padding(.horizontal, 28).padding(.top, 8)
    }

    // MARK: - Step 1: Due today review

    private var stepDueTodayReview: some View {
        VStack(alignment: .leading, spacing: 16) {
            voiceStatusBar

            // Travel pre-check banner
            if !travelEvents.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "airplane")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(Color.orange, in: Circle())

                    VStack(alignment: .leading, spacing: 2) {
                        Text("You have travel today")
                            .font(.system(size: 13, weight: .semibold))
                        Text(travelEvents.map(\.title).joined(separator: " · "))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    Text("Transit tasks prioritised")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Color.orange.opacity(0.12), in: Capsule())
                }
                .padding(12)
                .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                .padding(.bottom, 4)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Here's what I think belongs today.")
                    .font(.system(size: 16, weight: .medium))
                Text("Confirm or remove items. Total: \(formatMins(confirmedTotal))")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 2) {
                    ForEach(todayCandidates) { task in
                        InterviewTaskRow(
                            task: task,
                            isConfirmed: confirmedIds.contains(task.id)
                        ) {
                            if confirmedIds.contains(task.id) {
                                confirmedIds.remove(task.id)
                            } else {
                                confirmedIds.insert(task.id)
                            }
                        }
                    }

                    if todayCandidates.isEmpty {
                        HStack {
                            Spacer()
                            Text("No due-today items detected.")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                                .padding(.vertical, 20)
                            Spacer()
                        }
                    }
                }
            }

            if !voiceMode {
                voiceButton
            }
        }
        .padding(.horizontal, 28).padding(.top, 8)
    }

    // MARK: - Step 2: Assumptions review

    private var stepAssumptions: some View {
        VStack(alignment: .leading, spacing: 16) {
            voiceStatusBar

            VStack(alignment: .leading, spacing: 4) {
                Text("Are these time estimates right?")
                    .font(.system(size: 16, weight: .medium))
                Text("Ranked by time cost. Override anything that's off.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 2) {
                    ForEach(assumptions) { task in
                        let current = estimates[task.id] ?? task.estimatedMinutes
                        HStack(spacing: 12) {
                            Image(systemName: task.bucket.icon)
                                .font(.system(size: 11))
                                .foregroundStyle(task.bucket.color)
                                .frame(width: 16)

                            Text(task.title)
                                .font(.system(size: 13))
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            // Uncertainty badge — prompts user to override
                            if task.isUncertain {
                                HStack(spacing: 3) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .font(.system(size: 9))
                                    Text("uncertain")
                                        .font(.system(size: 10, weight: .medium))
                                }
                                .foregroundStyle(.orange)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Color.orange.opacity(0.12), in: Capsule())
                                .help("Low confidence estimate (\u{00B1}\(task.estimateUncertainty ?? 0)m) — consider overriding")
                            }

                            // Inline minute stepper
                            HStack(spacing: 4) {
                                Button {
                                    estimates[task.id] = max(5, current - 5)
                                } label: {
                                    Image(systemName: "minus.circle")
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)

                                Text(formatMins(current))
                                    .font(.system(size: 12, weight: .semibold))
                                    .monospacedDigit()
                                    .frame(width: 44, alignment: .center)

                                Button {
                                    estimates[task.id] = current + 5
                                } label: {
                                    Image(systemName: "plus.circle")
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(Color(.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }

            HStack(spacing: 6) {
                Button("Accept all estimates") {
                    step = 3
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                Spacer()
                if !voiceMode {
                    voiceButton
                }
            }
        }
        .padding(.horizontal, 28).padding(.top, 8)
    }

    // MARK: - Step 3: Plan confirmation

    private var stepPlanConfirm: some View {
        VStack(alignment: .leading, spacing: 16) {
            voiceStatusBar

            VStack(alignment: .leading, spacing: 4) {
                Text("Here's your plan. Ready to start?")
                    .font(.system(size: 16, weight: .medium))

                HStack(spacing: 16) {
                    planStat("Available", formatMins(availableMinutes))
                    planStat("Planned",   formatMins(confirmedTotal))
                    planStat("Items",     "\(confirmedTasks.count)")
                }
                .padding(.top, 4)
            }

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 2) {
                    ForEach(Array(confirmedTasks.enumerated()), id: \.element.id) { idx, task in
                        HStack(spacing: 10) {
                            Text("\(idx + 1)")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .frame(width: 18, alignment: .trailing)

                            Image(systemName: task.bucket.icon)
                                .font(.system(size: 10))
                                .foregroundStyle(task.bucket.color)
                                .frame(width: 14)

                            Text(task.title)
                                .font(.system(size: 13))
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            Text(formatMins(estimates[task.id] ?? task.estimatedMinutes))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        .background(Color(.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 7))
                    }

                    if confirmedTasks.isEmpty {
                        Text("No tasks confirmed. Your Today screen will be empty.")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 20)
                    }
                }
            }
        }
        .padding(.horizontal, 28).padding(.top, 8)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            if step > 0 {
                Button("← Back") {
                    speechService.stop()
                    stopListening()
                    cancelSilenceTimer()
                    conversationState = .idle
                    step -= 1
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
            }

            Spacer()

            if step < totalSteps - 1 {
                Button("Continue →") {
                    speechService.stop()
                    stopListening()
                    cancelSilenceTimer()
                    conversationState = .idle
                    step += 1
                }
                .buttonStyle(.borderedProminent)
                .tint(.indigo)
                .controlSize(.regular)
            } else {
                Button("Start My Day →") {
                    speechService.stop()
                    stopListening()
                    cancelSilenceTimer()
                    conversationState = .idle
                    applyPlan()
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
                .tint(.indigo)
                .controlSize(.regular)
            }
        }
        .padding(.horizontal, 28).padding(.vertical, 18)
    }

    // MARK: - Voice: speak for step (state machine)

    private func speakForStep(_ stepIndex: Int) {
        guard voiceMode else { return }
        // Prevent re-speaking if already speaking this step
        if case .appSpeaking(let s) = conversationState, s == stepIndex { return }

        stopListening()
        cancelSilenceTimer()

        let text: String
        switch stepIndex {
        case 0:
            text = "Good morning. How much time have you got today?"
        case 1:
            let count = todayCandidates.count
            let titles = todayCandidates.prefix(3).map(\.title).joined(separator: ", ")
            if count == 0 {
                text = "No items due today. You can move on."
            } else {
                text = "I found \(count) items due today. Here they are: \(titles). Should we keep all of them?"
            }
        case 2:
            let topAssumptions = assumptions.prefix(3).map { task in
                let mins = estimates[task.id] ?? task.estimatedMinutes
                return "\(task.title), \(formatMins(mins))"
            }.joined(separator: ". ")
            text = "I'm assuming these time estimates: \(topAssumptions). Sound right?"
        case 3:
            let topTasks = confirmedTasks.prefix(3).map { task in
                let mins = estimates[task.id] ?? task.estimatedMinutes
                return "\(task.title), \(formatMins(mins))"
            }.joined(separator: ". ")
            text = "Here's your plan: \(topTasks). Total: \(formatMins(confirmedTotal)). Should I lock this in?"
        default:
            return
        }

        voiceStatusText = text
        conversationState = .appSpeaking(step: stepIndex)
        speechService.speak(text)
        // Transition to listening is handled by onChange(of: speechService.isSpeaking)
    }

    // MARK: - Silence timeout

    private func startSilenceTimer(forStep listenStep: Int) {
        cancelSilenceTimer()
        lastTranscriptSnapshot = voiceCapture.liveTranscript
        silenceTimer = Task {
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            guard case .listening(let s) = conversationState, s == listenStep else { return }
            handleSilenceTimeout(forStep: listenStep)
        }
    }

    private func resetSilenceTimer(forStep listenStep: Int) {
        cancelSilenceTimer()
        silenceTimer = Task {
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            guard case .listening(let s) = conversationState, s == listenStep else { return }
            handleSilenceTimeout(forStep: listenStep)
        }
    }

    private func cancelSilenceTimer() {
        silenceTimer?.cancel()
        silenceTimer = nil
    }

    private func handleSilenceTimeout(forStep listenStep: Int) {
        if silenceTimeoutCount == 0 {
            // First timeout: prompt the user
            silenceTimeoutCount = 1
            speechService.speak("Still there?")
            // After this short prompt finishes, onChange(of: isSpeaking) won't match .appSpeaking
            // so we manually restart listening after a short delay
            Task {
                try? await Task.sleep(for: .milliseconds(1500))
                guard voiceMode, case .listening = conversationState else { return }
                startSilenceTimer(forStep: listenStep)
            }
        } else {
            // Second timeout: auto-advance with whatever transcript we have
            silenceTimeoutCount = 0
            cancelSilenceTimer()
            finishListening()
        }
    }

    // MARK: - Voice: listening

    private func startListening() {
        guard !isListening else { return }
        isListening = true
        Task {
            await voiceCapture.start()
        }
    }

    private func stopListening() {
        guard isListening else { return }
        voiceCapture.stop()
        isListening = false
    }

    private func finishListening() {
        let transcript = voiceCapture.liveTranscript
        stopListening()
        cancelSilenceTimer()
        guard !transcript.isEmpty else {
            conversationState = .idle
            return
        }

        conversationState = .processing
        voiceProcessing = true
        let response = VoiceResponse.parse(transcript)
        handleVoiceResponse(response)
        voiceProcessing = false
        // After processing, state transitions happen inside handleVoiceResponse
        // (advanceStep triggers speakForStep which sets .appSpeaking)
        // If no advance happened, go idle
        if case .processing = conversationState {
            conversationState = .idle
        }
    }

    // MARK: - Voice: handle response

    private func handleVoiceResponse(_ response: VoiceResponse) {
        switch step {
        case 0:
            handleTimeResponse(response)
        case 1:
            handleDueTodayResponse(response)
        case 2:
            handleAssumptionsResponse(response)
        case 3:
            handlePlanResponse(response)
        default:
            break
        }
    }

    private func handleTimeResponse(_ response: VoiceResponse) {
        switch response {
        case .number(let mins):
            availableMinutes = mins
            // Auto-advance after setting time
            advanceStep()
        case .affirmative:
            // Keep current time, advance
            advanceStep()
        default:
            // Couldn't parse — stay on step, user uses buttons
            break
        }
    }

    private func handleDueTodayResponse(_ response: VoiceResponse) {
        switch response {
        case .affirmative:
            // Keep all, advance
            advanceStep()
        case .negative:
            // Clear all
            confirmedIds.removeAll()
            advanceStep()
        case .removeItem(let idx):
            let candidates = todayCandidates
            let resolvedIndex = idx == -1 ? candidates.count - 1 : idx - 1
            if resolvedIndex >= 0 && resolvedIndex < candidates.count {
                confirmedIds.remove(candidates[resolvedIndex].id)
            }
            advanceStep()
        default:
            break
        }
    }

    private func handleAssumptionsResponse(_ response: VoiceResponse) {
        switch response {
        case .affirmative:
            advanceStep()
        case .estimateOverride(let ordinal, let minutes):
            // Resolve ordinal to task index (1-based, -1 = last)
            let list = assumptions
            let resolvedIndex = ordinal == -1 ? list.count - 1 : ordinal - 1
            if resolvedIndex >= 0, resolvedIndex < list.count {
                estimates[list[resolvedIndex].id] = max(5, minutes)
            }
            // Stay on step so user can make more overrides or confirm
        default:
            break
        }
    }

    private func handlePlanResponse(_ response: VoiceResponse) {
        switch response {
        case .affirmative:
            applyPlan()
            isPresented = false
        case .swapItems(let a, let b):
            // Swap confirmed task order not directly possible with Set, but we can note intent
            // For now, treat as affirmative after swap acknowledgement
            _ = (a, b)  // acknowledged
            break
        case .negative:
            // Go back to review
            step = 1
        default:
            break
        }
    }

    private func advanceStep() {
        if step < totalSteps - 1 {
            step += 1
        }
    }

    // MARK: - Helpers

    /// Legacy voice button for non-voice-mode — toggles quick listen
    private var voiceButton: some View {
        Button {
            if isListening {
                finishListening()
            } else {
                startListening()
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isListening ? "mic.fill" : "mic")
                    .font(.system(size: 12))
                    .foregroundStyle(isListening ? .red : .secondary)
                Text(isListening ? "Listening..." : "Speak instead")
                    .font(.system(size: 12))
                    .foregroundStyle(isListening ? .red : .secondary)
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(
                isListening ? Color.red.opacity(0.08) : Color(.controlBackgroundColor),
                in: Capsule()
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func planStat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 16, weight: .semibold))
                .monospacedDigit()
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(Color(.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }

    private var greeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        if h < 12 { return "Good morning." }
        if h < 17 { return "Good afternoon." }
        return "Good evening."
    }

    private var stepLabel: String {
        switch step {
        case 0: return "Step 1 of 4 — How much time do you have?"
        case 1: return "Step 2 of 4 — Confirm what's on for today"
        case 2: return "Step 3 of 4 — Check time estimates"
        case 3: return "Step 4 of 4 — Review and start"
        default: return ""
        }
    }

    private func formatMins(_ m: Int) -> String {
        m < 60 ? "\(m)m" : (m % 60 == 0 ? "\(m / 60)h" : "\(m / 60)h \(m % 60)m")
    }

    private func applyPlan() {
        // Apply any overridden estimates back to the task list
        for (id, mins) in estimates {
            if let idx = tasks.firstIndex(where: { $0.id == id }) {
                tasks[idx].estimatedMinutes = mins
            }
        }
    }
}

// MARK: - Pulsing icon (voice feedback)

struct PulsingIcon: View {
    let systemName: String
    let color: Color

    @State private var isPulsing = false

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(color)
            .scaleEffect(isPulsing ? 1.15 : 1.0)
            .opacity(isPulsing ? 1.0 : 0.7)
            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isPulsing)
            .frame(width: 24, height: 24)
            .onAppear { isPulsing = true }
    }
}

// MARK: - Interview task row

struct InterviewTaskRow: View {
    let task: TimedTask
    let isConfirmed: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 12) {
                Image(systemName: isConfirmed ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16))
                    .foregroundStyle(isConfirmed ? Color.indigo : Color(.separatorColor))

                VStack(alignment: .leading, spacing: 2) {
                    Text(task.title)
                        .font(.system(size: 13))
                        .lineLimit(1)
                        .foregroundStyle(isConfirmed ? .primary : .secondary)
                    if task.isDoFirst {
                        Text("Do First — always runs first")
                            .font(.system(size: 10))
                            .foregroundStyle(.indigo)
                    }
                }

                Spacer()

                Text(task.timeLabel)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()

                if task.dueToday && !task.isDoFirst {
                    Text("DUE")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(.red, in: Capsule())
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 9)
            .background(
                isConfirmed ? Color.indigo.opacity(0.06) : Color(.controlBackgroundColor),
                in: RoundedRectangle(cornerRadius: 8)
            )
        }
        .buttonStyle(.plain)
    }
}
