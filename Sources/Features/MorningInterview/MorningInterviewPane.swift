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
        case correcting(step: Int, field: String)
        case interrupted(resumeStep: Int)
        case ambiguous(step: Int, prompt: String)
    }

    @Binding var tasks: [TimedTask]
    @Binding var blocks: [CalendarBlock]
    @Binding var isPresented: Bool

    @State private var step = 0
    @State private var availableMinutes = 180
    @State private var confirmedIds: Set<UUID>
    @State private var estimates: [UUID: Int] = [:]
    @State private var hasTravelToday: Bool = false

    // Dish Me Up: energy & interruptibility (Q2 + Q3)
    @State private var energyLevel: Int = 5         // 1-10
    @State private var interruptibility: StateOfDay.Interruptibility = .medium

    // Voice mode
    @AppStorage("prefs.morningInterview.voiceMode") private var voiceMode: Bool = true
    @StateObject private var speechService = SpeechService()
    @StateObject private var voiceCapture: VoiceCaptureService = VoiceCaptureService()
    @State private var isListening: Bool = false
    @State private var voiceProcessing: Bool = false
    @State private var voiceStatusText: String = ""
    @State private var conversationState: ConversationState = .idle

    // Silence timeout tracking
    @State private var silenceTimer: Task<Void, Never>?
    @State private var lastTranscriptSnapshot: String = ""
    @State private var silenceTimeoutCount: Int = 0

    // Computed free time (step 1)
    @State private var computedFreeMinutes: Int = 0
    @State private var computedGapCount: Int = 0
    @State private var computedMeetingMinutes: Int = 0
    @State private var workEndOverride: Int? = nil  // nil = use default from prefs
    @State private var manualSubtract: Int = 0      // user-reported off-calendar time
    @State private var freeTimeComputed: Bool = false

    // Deferral review (step 0) — tasks from yesterday not completed
    @State private var deferredTasks: [TimedTask] = []
    @State private var showDeferralStep: Bool = false

    // Confidence-based text fallback
    @State private var showConfirmationBanner: Bool = false
    @State private var pendingTranscript: String = ""
    @State private var showTextFallback: Bool = false

    // Undo stack — stores (step, action description) for last voice action
    @State private var undoStack: [(step: Int, action: () -> Void)] = []

    // First-time workday question — ask once, remember forever
    @AppStorage("interview.workHoursConfirmed") private var workHoursConfirmed: Bool = false
    @State private var lastRawTranscript: String = ""
    @State private var awaitingWorkHoursAnswer: Bool = false

    // Adaptive question skipping — consecutive non-override counts per step
    @AppStorage("interview.skipCount.step0") private var skipCountStep0: Int = 0
    @AppStorage("interview.skipCount.step1") private var skipCountStep1: Int = 0
    @AppStorage("interview.skipCount.step2") private var skipCountStep2: Int = 0
    @AppStorage("interview.skipCount.step3") private var skipCountStep3: Int = 0
    @State private var skippedSteps: Set<Int> = []
    private let skipThreshold = 5

    // Steps: deferral review (0), time (1), energy (2), interruptibility (3), due today (4), estimates (5), confirm (6)
    private let totalSteps = 7

    init(tasks: Binding<[TimedTask]>, blocks: Binding<[CalendarBlock]>, isPresented: Binding<Bool>) {
        self._tasks = tasks
        self._blocks = blocks
        self._isPresented = isPresented
        // pre-select all due-today tasks
        let ids = Set(tasks.wrappedValue.filter { $0.dueToday || $0.isDoFirst }.map(\.id))
        self._confirmedIds = State(initialValue: ids)
        // Detect deferred tasks — overdue, not done, not due-today flagged
        let deferred = tasks.wrappedValue.filter { !$0.isDone && $0.isStale && !$0.dueToday }
        self._deferredTasks = State(initialValue: deferred)
        self._showDeferralStep = State(initialValue: !deferred.isEmpty)
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

    private var effectiveWorkEndHour: Int {
        workEndOverride ?? OnboardingUserPrefs.workEndHour
    }

    private var effectiveFreeMinutes: Int {
        max(0, computedFreeMinutes - manualSubtract)
    }

    private func recomputeFreeTime() {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let startHour = OnboardingUserPrefs.workStartHour
        let endHour = effectiveWorkEndHour
        guard let workStart = cal.date(bySettingHour: startHour, minute: 0, second: 0, of: today),
              let workEnd = cal.date(bySettingHour: endHour, minute: 0, second: 0, of: today) else { return }
        let result = TimeSlotAllocator.computeFreeTime(
            calendarBlocks: blocks,
            workStart: workStart,
            workEnd: workEnd
        )
        computedFreeMinutes = result.totalFreeMinutes
        computedGapCount = result.gapCount
        computedMeetingMinutes = result.meetingMinutes
        availableMinutes = effectiveFreeMinutes
        freeTimeComputed = true
    }

    private var confirmedTotal: Int {
        confirmedTasks.reduce(0) { $0 + (estimates[$1.id] ?? $1.estimatedMinutes) }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            ZStack {
                if step == 0 { stepDeferralReview.transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading))) }
                if step == 1 { stepTimeDeclaration.transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading))) }
                if step == 2 { stepEnergyLevel.transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading))) }
                if step == 3 { stepInterruptibility.transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading))) }
                if step == 4 { stepDueTodayReview.transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading))) }
                if step == 5 { stepAssumptions.transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading))) }
                if step == 6 { stepPlanConfirm.transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading))) }
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
                // Step 6: preserve step + confirmedIds when toggling voice off
                // Only stop audio services, don't reset state machine position
                speechService.stop()
                stopListening()
                cancelSilenceTimer()
                conversationState = .idle
                // step and confirmedIds intentionally preserved for touch continuation
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
            // Barge-in: user speaks while app is speaking → interrupt TTS
            if case .appSpeaking(let spokenStep) = conversationState, !newTranscript.isEmpty {
                speechService.stop()
                conversationState = .interrupted(resumeStep: spokenStep)
                // Process barge-in speech after a short delay for accumulation
                Task {
                    try? await Task.sleep(for: .milliseconds(800))
                    finishListening()
                }
                return
            }
            // Any new speech resets the silence timer
            if case .listening(let listenStep) = conversationState, !newTranscript.isEmpty {
                lastTranscriptSnapshot = newTranscript
                resetSilenceTimer(forStep: listenStep)
            }
        }
        .onAppear {
            // Skip deferral step if no deferred tasks
            if !showDeferralStep && step == 0 {
                step = 1
            }
            // Compute which steps are auto-skippable (adaptive skipping)
            if skipCountStep1 >= skipThreshold { skippedSteps.insert(1) }
            if skipCountStep2 >= skipThreshold { skippedSteps.insert(4) }
            if skipCountStep3 >= skipThreshold { skippedSteps.insert(5) }

            // Compute free time from calendar for step 1
            recomputeFreeTime()

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
                VStack(spacing: 6) {
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
                        case .interrupted:
                            processingIndicator
                        case .correcting:
                            listeningIndicator
                        case .ambiguous:
                            ambiguousIndicator
                        case .idle:
                            idleVoiceIndicator
                        }
                    }
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(voiceStatusBackground, in: RoundedRectangle(cornerRadius: 10))

                    // Confidence confirmation banner
                    if showConfirmationBanner {
                        HStack(spacing: 8) {
                            Image(systemName: "questionmark.circle.fill")
                                .foregroundStyle(.orange)
                            Text("Did you mean: \"\(pendingTranscript)\"?")
                                .font(.system(size: 12))
                                .lineLimit(2)
                            Spacer()
                            Button("Yes") { confirmPendingTranscript() }
                                .buttonStyle(.borderedProminent)
                                .tint(.indigo)
                                .controlSize(.mini)
                            Button("No") { rejectPendingTranscript() }
                                .buttonStyle(.bordered)
                                .controlSize(.mini)
                        }
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                    }

                    // Text fallback input
                    if showTextFallback {
                        HStack(spacing: 8) {
                            Image(systemName: "keyboard")
                                .foregroundStyle(.secondary)
                            Text("Voice unclear — use buttons or try again")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("Retry Voice") {
                                showTextFallback = false
                                conversationState = .idle
                                speakForStep(step)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                        }
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(Color(.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
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

    private var ambiguousIndicator: some View {
        HStack(spacing: 8) {
            Image(systemName: "questionmark.circle.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.orange)
            if case .ambiguous(_, let prompt) = conversationState {
                Text(prompt)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.orange)
                    .lineLimit(2)
            }
            Spacer()
        }
    }

    private var voiceStatusBackground: Color {
        switch conversationState {
        case .appSpeaking, .waitingToListen: return Color.indigo.opacity(0.06)
        case .listening, .correcting: return Color.red.opacity(0.06)
        case .processing, .interrupted: return Color(.controlBackgroundColor)
        case .ambiguous: return Color.orange.opacity(0.06)
        case .idle: return Color(.controlBackgroundColor)
        }
    }

    // MARK: - Step 0: Deferral review (yesterday's unfinished tasks)

    private var stepDeferralReview: some View {
        VStack(alignment: .leading, spacing: 16) {
            voiceStatusBar

            VStack(alignment: .leading, spacing: 8) {
                Text("Yesterday's unfinished tasks")
                    .font(.system(size: 16, weight: .medium))
                Text("You deferred \(deferredTasks.count) task\(deferredTasks.count == 1 ? "" : "s"). Carry them over?")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 2) {
                    ForEach(deferredTasks) { task in
                        HStack(spacing: 12) {
                            Image(systemName: confirmedIds.contains(task.id) ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 16))
                                .foregroundStyle(confirmedIds.contains(task.id) ? Color.indigo : Color(.separatorColor))

                            VStack(alignment: .leading, spacing: 2) {
                                Text(task.title)
                                    .font(.system(size: 13))
                                    .lineLimit(1)
                                Text("\(task.daysInQueue) days in queue")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.orange)
                            }

                            Spacer()

                            Text(task.timeLabel)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        .padding(.horizontal, 12).padding(.vertical, 9)
                        .background(
                            confirmedIds.contains(task.id) ? Color.indigo.opacity(0.06) : Color(.controlBackgroundColor),
                            in: RoundedRectangle(cornerRadius: 8)
                        )
                        .onTapGesture {
                            if confirmedIds.contains(task.id) {
                                confirmedIds.remove(task.id)
                            } else {
                                confirmedIds.insert(task.id)
                            }
                        }
                    }

                    if deferredTasks.isEmpty {
                        Text("No deferred tasks.")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 20)
                    }
                }
            }

            HStack(spacing: 8) {
                Button("Carry All Over") {
                    for task in deferredTasks { confirmedIds.insert(task.id) }
                    advanceStep()
                }
                .buttonStyle(.borderedProminent)
                .tint(.indigo)
                .controlSize(.small)

                Button("Skip All") {
                    for task in deferredTasks { confirmedIds.remove(task.id) }
                    advanceStep()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Spacer()
            }

            if !voiceMode {
                voiceButton
            }
        }
        .padding(.horizontal, 28).padding(.top, 8)
    }

    // MARK: - Step 1: Computed free time confirmation (was time declaration)

    private var stepTimeDeclaration: some View {
        VStack(alignment: .leading, spacing: 20) {
            voiceStatusBar

            VStack(alignment: .leading, spacing: 8) {
                Text("Your free time today")
                    .font(.system(size: 16, weight: .medium))
                Text("Computed from your calendar and work hours.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            // Prominent free time display
            HStack(spacing: 20) {
                freeTimeStat(
                    value: formatMins(effectiveFreeMinutes),
                    label: "Free",
                    icon: "clock.fill",
                    color: .indigo
                )
                freeTimeStat(
                    value: "\(computedGapCount)",
                    label: computedGapCount == 1 ? "Block" : "Blocks",
                    icon: "square.split.2x1.fill",
                    color: .teal
                )
                freeTimeStat(
                    value: formatMins(computedMeetingMinutes),
                    label: "Meetings",
                    icon: "person.2.fill",
                    color: .orange
                )
            }

            // Work window info
            HStack(spacing: 8) {
                Image(systemName: "calendar")
                    .font(.system(size: 11))
                    .foregroundStyle(.indigo)
                Text("Work window: \(OnboardingUserPrefs.workStartHour):00 – \(effectiveWorkEndHour):00")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                if workEndOverride != nil {
                    Text("(adjusted)")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.orange)
                }
            }
            .padding(10)
            .background(Color.indigo.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))

            // Manual subtract display
            if manualSubtract > 0 {
                HStack(spacing: 8) {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                    Text("\(formatMins(manualSubtract)) subtracted for off-calendar commitments")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        manualSubtract = 0
                        availableMinutes = effectiveFreeMinutes
                    } label: {
                        Text("Reset")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.orange)
                    }
                    .buttonStyle(.plain)
                }
                .padding(10)
                .background(Color.orange.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
            }

            // Override actions (non-voice)
            if !voiceMode {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Need to adjust?")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        // End time override menu
                        Menu {
                            ForEach([13, 14, 15, 16, 17, 18, 19, 20], id: \.self) { hour in
                                Button("\(hour):00") {
                                    workEndOverride = hour
                                    recomputeFreeTime()
                                }
                            }
                            if workEndOverride != nil {
                                Divider()
                                Button("Reset to default") {
                                    workEndOverride = nil
                                    recomputeFreeTime()
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "clock.arrow.2.circlepath")
                                    .font(.system(size: 11))
                                Text("Leaving early?")
                                    .font(.system(size: 12))
                            }
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(Color(.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)

                        // Manual subtract
                        Menu {
                            ForEach([15, 30, 45, 60, 90], id: \.self) { mins in
                                Button("−\(formatMins(mins))") {
                                    manualSubtract += mins
                                    availableMinutes = effectiveFreeMinutes
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "minus.circle")
                                    .font(.system(size: 11))
                                Text("Off-calendar call?")
                                    .font(.system(size: 12))
                            }
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(Color(.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                    }
                }

                voiceButton
            }

            Spacer()
        }
        .padding(.horizontal, 28).padding(.top, 8)
    }

    @ViewBuilder
    private func freeTimeStat(value: String, label: String, icon: String, color: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(color)
            Text(value)
                .font(.system(size: 20, weight: .bold))
                .monospacedDigit()
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(color.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Step 2: Energy Level (Q2)

    private var stepEnergyLevel: some View {
        VStack(alignment: .leading, spacing: 16) {
            voiceStatusBar

            VStack(alignment: .leading, spacing: 4) {
                Text("How's your energy today?")
                    .font(.system(size: 16, weight: .medium))
                Text("This helps match tasks to your current cognitive capacity.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 10) {
                energyButton(range: 9...10, label: "Peak energy",       desc: "Deep analytical work, big decisions", icon: "bolt.fill",             tint: .green)
                energyButton(range: 7...8,  label: "Good energy",       desc: "Focused work, meetings, calls",       icon: "sun.max.fill",          tint: .blue)
                energyButton(range: 5...6,  label: "Moderate",          desc: "Mix of focused and routine tasks",     icon: "cloud.sun.fill",        tint: .indigo)
                energyButton(range: 3...4,  label: "Low energy",        desc: "Quick replies, light admin, reading",  icon: "moon.fill",             tint: .orange)
                energyButton(range: 1...2,  label: "Running on empty",  desc: "Only essentials — defer what you can", icon: "battery.25percent",     tint: .red)
            }
            .padding(.top, 4)
        }
        .padding(.horizontal, 28).padding(.top, 8)
    }

    private func energyButton(range: ClosedRange<Int>, label: String, desc: String, icon: String, tint: Color) -> some View {
        let isSelected = range.contains(energyLevel)
        return Button {
            energyLevel = (range.lowerBound + range.upperBound) / 2
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundStyle(tint)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 1) {
                    Text(label).font(.system(size: 14, weight: .medium))
                    Text(desc).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.indigo)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? Color.indigo.opacity(0.08) : Color(.controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? Color.indigo.opacity(0.3) : .clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Step 3: Interruptibility (Q3)

    private var stepInterruptibility: some View {
        VStack(alignment: .leading, spacing: 16) {
            voiceStatusBar

            VStack(alignment: .leading, spacing: 4) {
                Text("Will you be interrupted today?")
                    .font(.system(size: 16, weight: .medium))
                Text("This affects how long each task block should be.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 10) {
                interruptButton(.low,    "No — protected time",    "lock.shield.fill",  .green)
                interruptButton(.medium, "A few interruptions",     "bell.badge.fill",   .orange)
                interruptButton(.high,   "Frequent interruptions",  "bell.and.waves.left.and.right.fill", .red)
            }
            .padding(.top, 8)
        }
        .padding(.horizontal, 28).padding(.top, 8)
    }

    private func interruptButton(_ level: StateOfDay.Interruptibility, _ label: String, _ icon: String, _ tint: Color) -> some View {
        Button {
            interruptibility = level
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundStyle(tint)
                    .frame(width: 24)
                Text(label)
                    .font(.system(size: 14))
                Spacer()
                if interruptibility == level {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.indigo)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(interruptibility == level ? Color.indigo.opacity(0.08) : Color(.controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(interruptibility == level ? Color.indigo.opacity(0.3) : .clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Step 4: Due today review

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

    // MARK: - Step 3: Assumptions review (was step 2)

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
                    step = 4
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

    // MARK: - Step 4: Plan confirmation (was step 3)

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

        // Adaptive skipping: if this step is skippable, auto-advance
        if skippedSteps.contains(stepIndex) && stepIndex > 0 && stepIndex < totalSteps - 1 {
            advanceStep()
            return
        }

        let text: String
        switch stepIndex {
        case 0:
            if deferredTasks.isEmpty {
                advanceStep()
                return
            }
            let titles = deferredTasks.prefix(3).map(\.title).joined(separator: ", ")
            if deferredTasks.count == 1 {
                text = "Morning. Before we start — you left one thing unfinished yesterday: \(titles). Carry it over?"
            } else {
                text = "Morning. Before we start — you left a few things on the table yesterday. \(titles). Carry those over, or start fresh?"
            }
        case 1:
            // First-time: ask about usual workday before calendar narration
            if !workHoursConfirmed {
                awaitingWorkHoursAnswer = true
                text = "Quick question before we dive in — what time do you usually start and finish work? Something like nine to six."
            } else {
                awaitingWorkHoursAnswer = false
                text = buildCalendarNarration()
            }
        case 2:
            text = "How are you feeling this morning? Sharp and ready to go, or more of a slow start? Give me a number, one to ten."
        case 3:
            text = "Are you expecting many interruptions today, or is it fairly protected?"
        case 4:
            let count = todayCandidates.count
            if count == 0 {
                text = "Nothing flagged for today. Moving on."
                advanceStep()
                return
            }
            let titles = todayCandidates.prefix(3).map(\.title).joined(separator: ", ")
            if count == 1 {
                text = "For today, I've got one thing: \(titles). Keep it?"
            } else {
                text = "For today, I've pulled in \(count) things. The main ones are \(titles). Look right, or want to drop any?"
            }
        case 5:
            let topAssumptions = assumptions.prefix(3).map { task in
                let mins = estimates[task.id] ?? task.estimatedMinutes
                return "\(task.title) at \(spokenTime(mins))"
            }.joined(separator: ", ")
            text = "Time-wise, I've got \(topAssumptions). Any of those feel off?"
        case 6:
            let taskCount = confirmedTasks.count
            let taskWord = taskCount == 1 ? "task" : "tasks"
            text = "All right, that's \(taskCount) \(taskWord), about \(spokenTime(confirmedTotal)) of work, fitting into \(spokenTime(effectiveFreeMinutes)) of free time. Shall I lock it in?"
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
        let confidence = voiceCapture.lastConfidence
        stopListening()
        cancelSilenceTimer()
        guard !transcript.isEmpty else {
            conversationState = .idle
            return
        }

        // STT Confidence Guard
        if confidence < 0.30 {
            // Auto-switch to text fallback
            showTextFallback = true
            conversationState = .idle
            return
        } else if confidence < 0.50 {
            // Re-prompt with text fallback option
            showTextFallback = true
            conversationState = .ambiguous(step: step, prompt: "I didn't catch that clearly. Could you try again?")
            speechService.speak("I didn't catch that clearly. Could you try again, or use the text input?")
            return
        } else if confidence < 0.75 {
            // Show confirmation banner
            pendingTranscript = transcript
            showConfirmationBanner = true
            conversationState = .ambiguous(step: step, prompt: "Did you mean: \(transcript)?")
            speechService.speak("Did you mean: \(transcript)?")
            return
        }

        processTranscript(transcript)
    }

    private func confirmPendingTranscript() {
        showConfirmationBanner = false
        let transcript = pendingTranscript
        pendingTranscript = ""
        processTranscript(transcript)
    }

    private func rejectPendingTranscript() {
        showConfirmationBanner = false
        pendingTranscript = ""
        conversationState = .idle
        if voiceMode {
            speakForStep(step)
        }
    }

    private func processTranscript(_ transcript: String) {
        conversationState = .processing
        voiceProcessing = true
        lastRawTranscript = transcript
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
        // Universal intents handled first, regardless of step
        switch response {
        case .skip:
            recordNonOverride(forStep: step)
            advanceStep()
            return
        case .done, .noMore:
            recordNonOverride(forStep: step)
            applyPlan()
            isPresented = false
            return
        case .repeat_:
            speakForStep(step)
            return
        case .goBack:
            if step > 0 {
                speechService.stop()
                stopListening()
                cancelSilenceTimer()
                step -= 1
                if voiceMode { speakForStep(step) }
            }
            return
        case .undo:
            if let last = undoStack.popLast() {
                last.action()
                if voiceMode {
                    speechService.speak("Undone.")
                    Task {
                        try? await Task.sleep(for: .milliseconds(600))
                        guard voiceMode else { return }
                        speakForStep(step)
                    }
                }
            }
            return
        case .addTask(let description):
            let newTask = TimedTask(
                id: UUID(), title: description, sender: "",
                estimatedMinutes: 15, bucket: .action, emailCount: 0,
                receivedAt: Date(), dueToday: true
            )
            tasks.append(newTask)
            confirmedIds.insert(newTask.id)
            if voiceMode {
                speechService.speak("Added: \(description).")
            }
            return
        default:
            break
        }

        // Step-specific handling
        switch step {
        case 0:
            handleDeferralResponse(response)
        case 1:
            handleTimeResponse(response)
        case 2:
            handleEnergyResponse(response)
        case 3:
            handleInterruptResponse(response)
        case 4:
            handleDueTodayResponse(response)
        case 5:
            handleAssumptionsResponse(response)
        case 6:
            handlePlanResponse(response)
        default:
            break
        }
    }

    private func handleDeferralResponse(_ response: VoiceResponse) {
        switch response {
        case .affirmative:
            // Carry all deferred tasks over
            for task in deferredTasks { confirmedIds.insert(task.id) }
            advanceStep()
        case .negative:
            // Skip all deferred
            for task in deferredTasks { confirmedIds.remove(task.id) }
            advanceStep()
        case .moveToTomorrow(let idx):
            // Defer specific item by index
            if let idx, idx > 0, idx <= deferredTasks.count {
                confirmedIds.remove(deferredTasks[idx - 1].id)
            }
        case .removeItem(let idx):
            let resolvedIndex = idx == -1 ? deferredTasks.count - 1 : idx - 1
            if resolvedIndex >= 0 && resolvedIndex < deferredTasks.count {
                confirmedIds.remove(deferredTasks[resolvedIndex].id)
            }
        default:
            break
        }
    }

    private func handleTimeResponse(_ response: VoiceResponse) {
        // First-time workday question: intercept before normal flow
        if awaitingWorkHoursAnswer {
            switch response {
            case .adjustEndTime(let hour):
                // "I finish at 5" — set end hour, keep current start
                UserDefaults.standard.set(hour, forKey: "onboarding_workEndHour")
                workHoursConfirmed = true
                awaitingWorkHoursAnswer = false
                recomputeFreeTime()
                if voiceMode {
                    speechService.speak("Got it, finishing at \(hour). " + buildCalendarNarration())
                }
                return
            case .number(let mins):
                // "8 hours" → infer end = start + hours
                let hours = mins >= 60 ? mins / 60 : mins
                let startHour = OnboardingUserPrefs.workStartHour
                UserDefaults.standard.set(startHour + hours, forKey: "onboarding_workEndHour")
                workHoursConfirmed = true
                awaitingWorkHoursAnswer = false
                recomputeFreeTime()
                if voiceMode {
                    speechService.speak("So about \(hours) hours. " + buildCalendarNarration())
                }
                return
            default:
                // Try parsing "9 to 5" from raw transcript
                if let (start, end) = parseWorkHoursFromRaw(lastRawTranscript) {
                    UserDefaults.standard.set(start, forKey: "onboarding_workStartHour")
                    UserDefaults.standard.set(end, forKey: "onboarding_workEndHour")
                    workHoursConfirmed = true
                    awaitingWorkHoursAnswer = false
                    recomputeFreeTime()
                    if voiceMode {
                        speechService.speak("Right, \(start) to \(end). " + buildCalendarNarration())
                    }
                    return
                }
                // Couldn't parse — re-prompt
                if voiceMode {
                    speechService.speak("I didn't catch that. What time do you start and finish? Something like nine to five.")
                }
                return
            }
        }

        switch response {
        case .affirmative:
            recordNonOverride(forStep: step)
            advanceStep()
        case .adjustEndTime(let hour):
            let oldOverride = workEndOverride
            let oldSubtract = manualSubtract
            workEndOverride = hour
            recomputeFreeTime()
            undoStack.append((step: step, action: { [self] in
                self.workEndOverride = oldOverride
                self.manualSubtract = oldSubtract
                self.recomputeFreeTime()
            }))
            recordOverride(forStep: step)
            if voiceMode {
                speechService.speak("Right, wrapping up at \(hour). That's \(spokenTime(effectiveFreeMinutes)) to play with. Sound right?")
            }
        case .subtractTime(let mins):
            let oldSubtract = manualSubtract
            manualSubtract += mins
            availableMinutes = effectiveFreeMinutes
            undoStack.append((step: step, action: { [self] in
                self.manualSubtract = oldSubtract
                self.availableMinutes = self.effectiveFreeMinutes
            }))
            recordOverride(forStep: step)
            if voiceMode {
                speechService.speak("Noted. That brings you down to \(spokenTime(effectiveFreeMinutes)) free. Sound right?")
            }
        case .number(let mins):
            let oldMins = availableMinutes
            availableMinutes = mins
            undoStack.append((step: step, action: { [self] in self.availableMinutes = oldMins }))
            recordOverride(forStep: step)
            advanceStep()
        case .negative:
            if voiceMode {
                conversationState = .ambiguous(step: step, prompt: "How would you like to adjust?")
                speechService.speak("No worries. Tell me when you're finishing, or how much to subtract, or just give me a number of hours.")
            }
        default:
            break
        }
    }

    private func handleEnergyResponse(_ response: VoiceResponse) {
        switch response {
        case .number(let rawValue):
            // VoiceResponseParser treats bare numbers as hours → minutes (*60)
            // For energy: if divisible by 60 and quotient is 1-10, use the quotient
            let level: Int
            if rawValue >= 60 && rawValue % 60 == 0 && rawValue / 60 <= 10 {
                level = rawValue / 60
            } else {
                level = rawValue
            }
            energyLevel = min(10, max(1, level))
            advanceStep()
        case .affirmative:
            advanceStep()
        default:
            if voiceMode {
                speechService.speak("Just a number from one to ten. One is running on empty, ten is firing on all cylinders.")
            }
        }
    }

    private func handleInterruptResponse(_ response: VoiceResponse) {
        switch response {
        case .negative:
            interruptibility = .low  // "No interruptions" = protected time
            advanceStep()
        case .affirmative:
            interruptibility = .high  // "Yes" = frequent interruptions
            advanceStep()
        default:
            // Default to medium and advance
            interruptibility = .medium
            advanceStep()
        }
    }

    private func handleDueTodayResponse(_ response: VoiceResponse) {
        switch response {
        case .affirmative:
            recordNonOverride(forStep: step)
            advanceStep()
        case .negative:
            let oldIds = confirmedIds
            confirmedIds.removeAll()
            undoStack.append((step: step, action: { [self] in self.confirmedIds = oldIds }))
            recordOverride(forStep: step)
            advanceStep()
        case .removeItem(let idx):
            let candidates = todayCandidates
            let resolvedIndex = idx == -1 ? candidates.count - 1 : idx - 1
            if resolvedIndex >= 0 && resolvedIndex < candidates.count {
                let removedId = candidates[resolvedIndex].id
                confirmedIds.remove(removedId)
                undoStack.append((step: step, action: { [self] in self.confirmedIds.insert(removedId) }))
            }
            recordOverride(forStep: step)
            advanceStep()
        case .moveToTomorrow(let idx):
            // Remove specific item from today
            let candidates = todayCandidates
            if let idx, idx > 0, idx <= candidates.count {
                let removedId = candidates[idx - 1].id
                confirmedIds.remove(removedId)
                undoStack.append((step: step, action: { [self] in self.confirmedIds.insert(removedId) }))
            }
            recordOverride(forStep: step)
        default:
            break
        }
    }

    private func handleAssumptionsResponse(_ response: VoiceResponse) {
        switch response {
        case .affirmative:
            recordNonOverride(forStep: step)
            advanceStep()
        case .estimateOverride(let ordinal, let minutes):
            let list = assumptions
            let resolvedIndex = ordinal == -1 ? list.count - 1 : ordinal - 1
            if resolvedIndex >= 0, resolvedIndex < list.count {
                let taskId = list[resolvedIndex].id
                let oldEstimate = estimates[taskId]
                estimates[taskId] = max(5, minutes)
                undoStack.append((step: step, action: { [self] in
                    if let old = oldEstimate {
                        self.estimates[taskId] = old
                    } else {
                        self.estimates.removeValue(forKey: taskId)
                    }
                }))
            }
            recordOverride(forStep: step)
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
            _ = (a, b)  // acknowledged — swap logic deferred to ordered list support
            break
        case .negative:
            step = 2
        default:
            break
        }
    }

    private func advanceStep() {
        if step < totalSteps - 1 {
            step += 1
            // Auto-skip steps marked as skippable (adaptive skipping)
            if skippedSteps.contains(step) && step < totalSteps - 1 {
                step += 1
            }
        }
    }

    // MARK: - Adaptive skipping counters

    private func recordNonOverride(forStep s: Int) {
        switch s {
        case 1: skipCountStep0 += 1  // step 1: time
        case 4: skipCountStep1 += 1  // step 4: due today
        case 5: skipCountStep2 += 1  // step 5: estimates
        default: break
        }
    }

    private func recordOverride(forStep s: Int) {
        // Reset counter on override
        switch s {
        case 1: skipCountStep0 = 0
        case 4: skipCountStep1 = 0
        case 5: skipCountStep2 = 0
        default: break
        }
        skippedSteps.remove(s)
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
        let displayStep = showDeferralStep ? step + 1 : step
        let displayTotal = showDeferralStep ? totalSteps : totalSteps - 1
        switch step {
        case 0: return "Step \(displayStep) of \(displayTotal) — Yesterday's deferrals"
        case 1: return "Step \(displayStep) of \(displayTotal) — Your free time today"
        case 2: return "Step \(displayStep) of \(displayTotal) — Energy level"
        case 3: return "Step \(displayStep) of \(displayTotal) — Interruption forecast"
        case 4: return "Step \(displayStep) of \(displayTotal) — Confirm what's on for today"
        case 5: return "Step \(displayStep) of \(displayTotal) — Check time estimates"
        case 6: return "Step \(displayStep) of \(displayTotal) — Review and start"
        default: return ""
        }
    }

    private func formatMins(_ m: Int) -> String {
        m < 60 ? "\(m)m" : (m % 60 == 0 ? "\(m / 60)h" : "\(m / 60)h \(m % 60)m")
    }

    /// Natural spoken time: "45 minutes", "2 hours", "about 3 and a half hours"
    private func spokenTime(_ minutes: Int) -> String {
        if minutes < 60 {
            return "\(minutes) minutes"
        }
        let hours = minutes / 60
        let remaining = minutes % 60
        if remaining == 0 {
            return hours == 1 ? "1 hour" : "\(hours) hours"
        } else if remaining >= 25 && remaining <= 35 {
            return "about \(hours) and a half hours"
        } else if remaining < 25 {
            return hours == 1 ? "just over an hour" : "about \(hours) hours"
        } else {
            return "about \(hours + 1) hours"
        }
    }

    /// Build the Step 1 calendar narration with meeting names and free time
    private func buildCalendarNarration() -> String {
        let timeDesc = spokenTime(effectiveFreeMinutes)

        if let meetingDesc = meetingNarration() {
            return "\(meetingDesc) That leaves you about \(timeDesc) to work with. Sound about right?"
        } else if !blocks.isEmpty || freeTimeComputed {
            return "Your calendar looks clear today — no meetings. That gives you about \(timeDesc). Shall we plan around that?"
        } else {
            return "I can't see your calendar at the moment. How much free time do you reckon you have today?"
        }
    }

    /// Narrate today's meetings with names and times
    private func meetingNarration() -> String? {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        guard let tomorrow = cal.date(byAdding: .day, value: 1, to: today) else { return nil }

        let meetings = blocks.filter { block in
            block.category == .meeting &&
            block.startTime >= today && block.startTime < tomorrow
        }.sorted { $0.startTime < $1.startTime }

        guard !meetings.isEmpty else { return nil }

        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm"

        let descriptions = meetings.prefix(4).map { meeting -> String in
            let time = formatter.string(from: meeting.startTime)
            if let names = meeting.attendeeNames, let first = names.first, !first.isEmpty {
                let people = names.prefix(2).joined(separator: " and ")
                return "\(meeting.title) with \(people) at \(time)"
            }
            return "\(meeting.title) at \(time)"
        }

        if descriptions.count == 1 {
            return "You've got \(descriptions[0])."
        }
        let allButLast = descriptions.dropLast().joined(separator: ", ")
        return "You've got \(allButLast), and \(descriptions.last!)."
    }

    /// Parse "9 to 5", "nine to six", "8 until 4" from raw transcript
    private func parseWorkHoursFromRaw(_ raw: String) -> (start: Int, end: Int)? {
        let lower = raw.lowercased()
            .replacingOccurrences(of: "one", with: "1")
            .replacingOccurrences(of: "two", with: "2")
            .replacingOccurrences(of: "three", with: "3")
            .replacingOccurrences(of: "four", with: "4")
            .replacingOccurrences(of: "five", with: "5")
            .replacingOccurrences(of: "six", with: "6")
            .replacingOccurrences(of: "seven", with: "7")
            .replacingOccurrences(of: "eight", with: "8")
            .replacingOccurrences(of: "nine", with: "9")
            .replacingOccurrences(of: "ten", with: "10")
            .replacingOccurrences(of: "eleven", with: "11")
            .replacingOccurrences(of: "twelve", with: "12")

        // Match patterns like "9 to 5", "8 until 6", "9 through 5", "9 till 6"
        let pattern = #"(\d{1,2})\s*(?:to|until|till|through|–|-)\s*(\d{1,2})"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)),
              let startRange = Range(match.range(at: 1), in: lower),
              let endRange = Range(match.range(at: 2), in: lower),
              let start = Int(lower[startRange]),
              let end = Int(lower[endRange]) else {
            return nil
        }

        // Normalize to 24h: assume start <= 12 means AM, end <= 12 means PM
        let normalizedStart = start <= 12 && start >= 5 ? start : start
        let normalizedEnd = end <= 12 && end < normalizedStart ? end + 12 : end
        guard normalizedStart >= 4 && normalizedStart <= 12,
              normalizedEnd > normalizedStart && normalizedEnd <= 23 else {
            return nil
        }
        return (normalizedStart, normalizedEnd)
    }

    private func applyPlan() {
        // Apply any overridden estimates back to the task list
        for (id, mins) in estimates {
            if let idx = tasks.firstIndex(where: { $0.id == id }) {
                tasks[idx].estimatedMinutes = mins
            }
        }

        // Produce StateOfDay from interview answers
        let pinnedIds = Array(confirmedIds.prefix(2))
        let sod = StateOfDay(
            timeBudgetMinutes: availableMinutes,
            energyLevel: energyLevel,
            interruptibility: interruptibility,
            pinnedTaskIds: pinnedIds,
            carryOverConfirmed: showDeferralStep
        )
        // Store for downstream consumers (DishMeUpSheet, PlanPane)
        MorningInterviewState.shared.latestStateOfDay = sod
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
