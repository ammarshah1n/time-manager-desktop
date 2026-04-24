// OnboardingFlow.swift — Timed macOS
// First-launch setup wizard with ElevenLabs voice narration. 10 steps, animated transitions.

import SwiftUI
import Dependencies

// MARK: - OnboardingFlow

struct OnboardingFlow: View {
    let onComplete: () -> Void
    @StateObject private var auth = AuthService.shared
    @StateObject private var speechService = SpeechService()
    @StateObject private var voiceCapture = VoiceCaptureService()
    @StateObject private var onboardingAI = OnboardingAIClient()

    @State private var currentStep: Int = 0
    @State private var voiceState: VoiceState = .idle
    @State private var silenceTimer: Task<Void, Never>?

    private enum VoiceState: Equatable {
        case idle
        case speaking
        case listening
        case processing
        case confirming
    }

    /// Steps that support voice input (mic activates after speech)
    private var isVoiceStep: Bool {
        [1, 4, 5, 6, 7].contains(currentStep)
    }

    // Step 1 — Name
    @AppStorage("onboarding_userName") private var userName: String = ""

    // Step 2 — Voice
    @AppStorage("elevenlabs_voice_id") private var selectedVoiceId: String = "pFZP5JQG7iQjIQuC4Bku"

    // Step 3 — Accounts
    @AppStorage("accounts.outlook.connected") private var outlookConnected: Bool = false
    @AppStorage("accounts.supabase.connected") private var supabaseConnected: Bool = false

    // Step 4 — Connect Email
    @AppStorage("onboarding_email") private var emailHint: String = ""

    // Step 5 — Work Day
    @AppStorage("onboarding_workdayHours") private var workdayHours: Int = 9
    @AppStorage("onboarding_todayHours") private var todayHours: Int = 7
    @AppStorage("onboarding_workStartHour") private var workStartHour: Int = 9
    @AppStorage("onboarding_workEndHour") private var workEndHour: Int = 18

    // Step 6 — Email Cadence
    @AppStorage("onboarding_emailCadence") private var emailCadence: Int = 2
    @AppStorage("onboarding_familySurname") private var familySurname: String = ""

    // Step 7 — Time Defaults
    @AppStorage("onboarding_replyMins") private var replyMins: Int = 5
    @AppStorage("onboarding_actionMins") private var actionMins: Int = 30
    @AppStorage("onboarding_callMins") private var callMins: Int = 15
    @AppStorage("onboarding_readMins") private var readMins: Int = 20

    // Step 8 — Transit
    @AppStorage("onboarding_transitModes") private var transitModes: String = ""

    // Step 9 — PA
    @AppStorage("onboarding_paEmail") private var paEmail: String = ""
    @AppStorage("onboarding_paEnabled") private var paEnabled: Bool = false

    private let totalSteps = 10

    // Transit checkbox state
    @State private var transitChauffeur: Bool = false
    @State private var transitTrain: Bool = false
    @State private var transitPlane: Bool = false
    @State private var transitDrive: Bool = false

    // Hero animation
    @State private var heroTitleVisible = false
    @State private var heroSubtitleVisible = false
    @State private var heroStatVisible = false
    @State private var heroCtaVisible = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()

            card
        }
        .onAppear { loadTransitModes() }
    }

    // MARK: - Card

    private var card: some View {
        VStack(spacing: 0) {
            progressDots
                .padding(.top, 28)
                .padding(.bottom, 32)

            stepContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 40)

            // Voice state indicator
            if isVoiceStep && voiceState != .idle && voiceState != .speaking {
                voiceIndicator
                    .padding(.horizontal, 40)
                    .padding(.bottom, 8)
            }

            navigationButtons
                .padding(.horizontal, 40)
                .padding(.bottom, 28)
        }
        .frame(width: 580, height: 560)
        .background(Color(.controlBackgroundColor))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.35), radius: 24, x: 0, y: 8)
        .onChange(of: currentStep) { _, newStep in
            speechService.stop()
            voiceCapture.stop()
            silenceTimer?.cancel()
            voiceState = .idle
            let name = userName.isEmpty ? "" : userName
            switch newStep {
            case 0: break // Hero handles its own speech
            case 1: // Name step
                voiceState = .speaking
                speechService.speak("What's your name, before we get started?")
            case 2: break // Voice picker handles its own speech
            case 3:
                voiceState = .speaking
                speechService.speak("Let's connect your Outlook\(name.isEmpty ? "" : ", \(name)"). This is how I'll understand your calendar and your emails.")
            case 4:
                voiceState = .speaking
                speechService.speak("How long is your typical work day? This helps me tell you how much you can realistically fit in.")
            case 5:
                voiceState = .speaking
                speechService.speak("How often do you check email? I'll batch replies and surface them at your cadence.")
            case 6:
                voiceState = .speaking
                speechService.speak("Set your time defaults. You can always override — but here's where we start.")
            case 7:
                voiceState = .speaking
                speechService.speak("How do you travel? I'll surface the right tasks when you're in transit.")
            case 8: break // PA — placeholder
            case 9:
                speechService.speak("You're ready\(name.isEmpty ? "" : ", \(name)"). Let's start your day.")
            default: break
            }
        }
        // After speech finishes → activate mic on voice-enabled steps
        .onChange(of: speechService.isSpeaking) { wasSpeaking, isSpeaking in
            if wasSpeaking && !isSpeaking && voiceState == .speaking && isVoiceStep {
                voiceState = .listening
                Task { await voiceCapture.start() }
                startSilenceTimer()
            }
            // After confirmation speech → auto-advance
            if wasSpeaking && !isSpeaking && voiceState == .confirming {
                voiceState = .idle
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    withAnimation(.spring(duration: 0.35)) {
                        currentStep += 1
                    }
                }
            }
        }
        // Watch transcript for silence detection reset
        .onChange(of: voiceCapture.liveTranscript) { _, transcript in
            if voiceState == .listening && !transcript.isEmpty {
                startSilenceTimer() // Reset on new speech
            }
        }
    }

    // MARK: - Progress Dots

    private var progressDots: some View {
        HStack(spacing: 8) {
            ForEach(0..<totalSteps, id: \.self) { index in
                Circle()
                    .fill(index <= currentStep ? Color.primary : Color.secondary.opacity(0.3))
                    .frame(width: 6, height: 6)
            }
        }
    }

    // MARK: - Step Content (animated)

    @ViewBuilder
    private var stepContent: some View {
        Group {
            switch currentStep {
            case 0: stepHero
            case 1: stepName
            case 2: stepVoicePicker
            case 3: stepAccounts
            case 4: stepWorkDay
            case 5: stepCadence
            case 6: stepTimeDefaults
            case 7: stepTransit
            case 8: stepPA
            case 9: stepDone
            default: EmptyView()
            }
        }
        .transition(.asymmetric(
            insertion: .move(edge: .trailing),
            removal: .move(edge: .leading)
        ))
        .animation(.spring(duration: 0.35), value: currentStep)
    }

    // MARK: - Step 0: Hero

    private var stepHero: some View {
        VStack(spacing: 0) {
            Spacer()

            Text("TIMED")
                .font(.system(size: 52, weight: .black))
                .tracking(6)
                .opacity(heroTitleVisible ? 1 : 0)

            Text("The most intelligent executive OS ever built.")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.top, 16)
                .opacity(heroSubtitleVisible ? 1 : 0)

            VStack(spacing: 4) {
                Text("CEOs spend 72% of their work week on task allocation,")
                Text("context switching, and deciding what to do next")
                Text("— not the work itself.")
                    .fontWeight(.semibold)
            }
            .font(.system(size: 13))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(.top, 32)
            .opacity(heroStatVisible ? 1 : 0)

            Text("That ends now.")
                .font(.system(size: 18, weight: .bold))
                .padding(.top, 24)
                .opacity(heroCtaVisible ? 1 : 0)

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .onAppear {
            withAnimation(.easeIn(duration: 0.6).delay(0.3)) { heroTitleVisible = true }
            withAnimation(.easeIn(duration: 0.6).delay(1.1)) { heroSubtitleVisible = true }
            withAnimation(.easeIn(duration: 0.6).delay(1.9)) { heroStatVisible = true }
            withAnimation(.easeIn(duration: 0.6).delay(2.7)) { heroCtaVisible = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                speechService.speak("Hey. Welcome to the most intelligent app ever built.")
            }
        }
    }

    // MARK: - Step 1: Name

    private var stepName: some View {
        VStack(spacing: 24) {
            Spacer()

            Text("What's your name?")
                .font(.title2.bold())

            Text("Before we get started.")
                .font(.body)
                .foregroundStyle(.secondary)

            TextField("Your first name", text: $userName)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 16))
                .frame(maxWidth: 280)
                .multilineTextAlignment(.center)
                .onChange(of: userName) { _, _ in
                    // User typed manually — reset voice state
                    if voiceState == .listening {
                        voiceCapture.stop()
                        silenceTimer?.cancel()
                        voiceState = .idle
                    }
                }

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Step 2: Voice Picker

    private let voiceOptions: [(id: String, name: String, desc: String)] = [
        ("pFZP5JQG7iQjIQuC4Bku", "Lily", "Velvety and warm"),
        ("cgSgspJ2msm6clMCkdW9", "Jessica", "Playful and bright"),
        ("cjVigY5qzO86Huf0OWal", "Eric", "Smooth and trustworthy"),
    ]

    private var stepVoicePicker: some View {
        VStack(spacing: 24) {
            Spacer()

            Text("Choose your voice")
                .font(.title2.bold())

            Text("This is how Timed will talk to you.")
                .font(.body)
                .foregroundStyle(.secondary)

            VStack(spacing: 12) {
                ForEach(voiceOptions, id: \.id) { voice in
                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(voice.name)
                                .font(.system(size: 15, weight: .semibold))
                            Text(voice.desc)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Button {
                            selectedVoiceId = voice.id
                            speechService.stop()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                speechService.speak("Good morning\(userName.isEmpty ? "" : ", \(userName)"). You have three meetings today and about four hours of free time. Let's make them count.")
                            }
                        } label: {
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 24))
                                .foregroundStyle(selectedVoiceId == voice.id ? Color.primary : Color.secondary)
                        }
                        .buttonStyle(.plain)

                        Image(systemName: selectedVoiceId == voice.id ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 20))
                            .foregroundStyle(selectedVoiceId == voice.id ? Color.primary : Color.secondary.opacity(0.3))
                            .onTapGesture {
                                selectedVoiceId = voice.id
                            }
                    }
                    .padding(.horizontal, 20).padding(.vertical, 14)
                    .background(
                        selectedVoiceId == voice.id ? Color.primary.opacity(0.06) : Color(.controlBackgroundColor),
                        in: RoundedRectangle(cornerRadius: 12)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(selectedVoiceId == voice.id ? Color.primary.opacity(0.2) : Color.clear, lineWidth: 1)
                    )
                }
            }
            .frame(maxWidth: 400)

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .onAppear {
            speechService.speak("Would you prefer I talk like this — or choose a different voice.")
        }
    }

    // MARK: - Step 3: Accounts

    private var outlookConfigured: Bool {
        let clientId = ProcessInfo.processInfo.environment["GRAPH_CLIENT_ID"]
            ?? "89e8f1c6-3cc4-47fb-83ae-f7e0528eb860"
        return !clientId.isEmpty
    }

    @State private var isConnecting = false

    private var stepAccounts: some View {
        StepLayout(
            icon: "envelope.badge.fill",
            iconColor: .blue,
            headline: "Connect Outlook",
            bodyText: "Timed reads your email and calendar to build your daily plan. Your data stays on this Mac."
        ) {
            VStack(spacing: 20) {
                if outlookConnected {
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(.green)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Outlook connected")
                                .font(.callout.bold())
                            Text(emailHint.isEmpty ? "Ready to go" : emailHint)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 24).padding(.vertical, 16)
                    .frame(maxWidth: 320)
                    .background(Color.green.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                } else {
                    Button {
                        isConnecting = true
                        Task {
                            await auth.signInWithGraph(loginHint: emailHint)
                            if auth.graphAccessToken != nil {
                                outlookConnected = true
                                if let email = auth.userEmail ?? emailHint.nilIfEmpty {
                                    let parts = email.components(separatedBy: "@").first?
                                        .components(separatedBy: ".") ?? []
                                    if let last = parts.last, last.count > 1 {
                                        familySurname = last.capitalized
                                    }
                                }
                            }
                            await auth.signInWithMicrosoft()
                            if auth.isSignedIn { supabaseConnected = true }
                            isConnecting = false
                        }
                    } label: {
                        HStack(spacing: 10) {
                            if isConnecting {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "envelope.badge.fill")
                                    .font(.system(size: 16))
                            }
                            Text(isConnecting ? "Connecting..." : "Connect Outlook")
                                .font(.system(size: 15, weight: .semibold))
                        }
                        .frame(maxWidth: 280)
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                    .controlSize(.large)
                    .disabled(isConnecting)

                    Text("You can also skip this and connect later in Settings.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    // MARK: - Step 4: Work Day

    private var stepWorkDay: some View {
        StepLayout(
            icon: "clock.fill",
            iconColor: .orange,
            headline: "How long is your typical work day?",
            bodyText: "Timed uses this to tell you how much you can realistically fit in."
        ) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Typical work day")
                        .font(.callout)
                    Spacer()
                    Stepper("\(workdayHours) hours", value: $workdayHours, in: 4...14)
                        .fixedSize()
                }

                HStack {
                    Text("Hours available today")
                        .font(.callout)
                    Spacer()
                    Stepper("\(todayHours) hours", value: $todayHours, in: 1...12)
                        .fixedSize()
                }

                Divider()

                HStack {
                    Text("Work starts at")
                        .font(.callout)
                    Spacer()
                    Stepper("\(workStartHour):00", value: $workStartHour, in: 5...12)
                        .fixedSize()
                }

                HStack {
                    Text("Work ends at")
                        .font(.callout)
                    Spacer()
                    Stepper("\(workEndHour):00", value: $workEndHour, in: 14...23)
                        .fixedSize()
                }
            }
            .frame(maxWidth: 360)
        }
    }

    // MARK: - Step 5: Email Cadence

    private let cadenceOptions = ["Once", "Twice", "3 × daily", "4+ times"]

    private var stepCadence: some View {
        StepLayout(
            icon: "tray.and.arrow.down.fill",
            iconColor: .red,
            headline: "How often do you check email?",
            bodyText: "Timed batches replies and surfaces them at your cadence."
        ) {
            VStack(alignment: .leading, spacing: 14) {
                Picker("", selection: $emailCadence) {
                    ForEach(cadenceOptions.indices, id: \.self) { i in
                        Text(cadenceOptions[i]).tag(i)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 360)
            }
        }
    }

    // MARK: - Step 6: Time Defaults

    private var stepTimeDefaults: some View {
        StepLayout(
            icon: "timer",
            iconColor: .primary,
            headline: "Set your time defaults",
            bodyText: "Timed estimates task time. You can override anytime — but here's where to start."
        ) {
            VStack(alignment: .leading, spacing: 10) {
                TimeDefaultRow(label: "Quick reply",   minutes: $replyMins)
                TimeDefaultRow(label: "Email action",  minutes: $actionMins)
                TimeDefaultRow(label: "Phone call",    minutes: $callMins)
                TimeDefaultRow(label: "Read / Review", minutes: $readMins)
            }
            .frame(maxWidth: 360)
        }
    }

    // MARK: - Step 7: Transit

    private var stepTransit: some View {
        StepLayout(
            icon: "car.fill",
            iconColor: .green,
            headline: "How do you travel?",
            bodyText: "Timed surfaces the right tasks when you're in transit — no desk, no focus required."
        ) {
            VStack(alignment: .leading, spacing: 10) {
                TransitToggle(label: "Chauffeur / rideshare", isOn: $transitChauffeur)
                    .onChange(of: transitChauffeur) { _, _ in saveTransitModes() }
                TransitToggle(label: "Train / public transport", isOn: $transitTrain)
                    .onChange(of: transitTrain) { _, _ in saveTransitModes() }
                TransitToggle(label: "Plane", isOn: $transitPlane)
                    .onChange(of: transitPlane) { _, _ in saveTransitModes() }
                TransitToggle(label: "Drive myself", isOn: $transitDrive)
                    .onChange(of: transitDrive) { _, _ in saveTransitModes() }

                Text("Transit tasks are surfaced when your calendar shows travel time.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
            .frame(maxWidth: 360, alignment: .leading)
        }
    }

    // MARK: - Step 8: PA

    private var stepPA: some View {
        StepLayout(
            icon: "person.2.fill",
            iconColor: .teal,
            headline: "PA sharing",
            bodyText: "Your assistant will be able to see your plan, tasks, and waiting items — read-only."
        ) {
            VStack(spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "clock.badge.checkmark")
                        .font(.system(size: 20))
                        .foregroundStyle(.teal)
                    Text("Coming in a future update")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 24).padding(.vertical, 16)
                .frame(maxWidth: 320)
                .background(Color.teal.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    // MARK: - Step 9: Done

    private var stepDone: some View {
        StepLayout(
            icon: "checkmark.seal.fill",
            iconColor: .primary,
            headline: "You're ready\(userName.isEmpty ? "" : ", \(userName)")",
            bodyText: "Timed is set up. Your first morning interview starts now — it takes 5 minutes and plans your whole day."
        ) {
            EmptyView()
        }
    }

    // MARK: - Voice Indicator

    private var voiceIndicator: some View {
        HStack(spacing: 10) {
            switch voiceState {
            case .listening:
                Image(systemName: "mic.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.red)
                    .symbolEffect(.pulse, isActive: true)
                Text("Listening...")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                // Mini waveform from audio level
                HStack(spacing: 2) {
                    ForEach(0..<8, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 1)
                            .fill(Color.primary.opacity(0.4))
                            .frame(width: 3, height: max(4, CGFloat(voiceCapture.audioLevel) * 20 * CGFloat.random(in: 0.5...1.5)))
                    }
                }
                .frame(height: 20)
            case .processing:
                ProgressView()
                    .controlSize(.small)
                Text("Understanding...")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            case .confirming:
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.green)
                Text("Got it")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            default:
                EmptyView()
            }
        }
        .frame(height: 24)
    }

    // MARK: - Navigation Buttons

    private var navigationButtons: some View {
        HStack {
            if currentStep > 0 {
                Button("← Back") {
                    withAnimation(.spring(duration: 0.35)) {
                        currentStep -= 1
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }

            Spacer()

            if currentStep == 0 {
                Button("Get started →") {
                    withAnimation(.spring(duration: 0.35)) {
                        currentStep += 1
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(.primary)
                .opacity(heroCtaVisible ? 1 : 0)
            } else if currentStep < totalSteps - 1 {
                Button("Continue →") {
                    withAnimation(.spring(duration: 0.35)) {
                        currentStep += 1
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(.primary)
            } else {
                Button("Start my day →") {
                    Task {
                        await persistExecutiveProfile()
                        await MainActor.run { onComplete() }
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(.primary)
            }
        }
    }

    // MARK: - Persist Executive Profile (Task 20)

    /// Upserts onboarding-collected state into `executive_profile`. AppStorage remains a local cache.
    @MainActor
    private func persistExecutiveProfile() async {
        guard let execId = AuthService.shared.executiveId else {
            // Auth hasn't bootstrapped — AppStorage cache is still written; server row lands on first signed-in launch.
            TimedLogger.supabase.debug("Onboarding complete without executiveId — skipping executive_profile upsert")
            return
        }

        let timeDefaults: [String: Int] = [
            "reply": replyMins,
            "action": actionMins,
            "call": callMins,
            "read": readMins,
        ]

        let transitList: [String] = transitModes
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        let payload = ExecutiveProfileUpsert(
            execId: execId,
            displayName: userName.isEmpty ? nil : userName,
            workHoursStart: String(format: "%02d:00", workStartHour),
            workHoursEnd: String(format: "%02d:00", workEndHour),
            typicalWorkdayHours: Double(workdayHours),
            emailCadenceMode: emailCadence,
            transitModes: transitList,
            timeDefaults: timeDefaults,
            paEmail: paEmail.isEmpty ? nil : paEmail,
            paEnabled: paEnabled,
            updatedAt: ISO8601DateFormatter().string(from: Date())
        )

        @Dependency(\.supabaseClient) var supa
        do {
            try await supa.upsertExecutiveProfile(payload)
        } catch {
            TimedLogger.supabase.error("executive_profile upsert failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Voice Conversation

    private func startSilenceTimer() {
        silenceTimer?.cancel()
        silenceTimer = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            if voiceState == .listening && !voiceCapture.liveTranscript.isEmpty {
                finishListening()
            }
        }
    }

    private func finishListening() {
        let transcript = voiceCapture.liveTranscript
        voiceCapture.stop()
        silenceTimer?.cancel()
        guard !transcript.trimmingCharacters(in: .whitespaces).isEmpty else {
            voiceState = .idle
            return
        }
        voiceState = .processing
        Task { await processVoiceResponse(transcript) }
    }

    private func processVoiceResponse(_ transcript: String) async {
        guard onboardingAI.isAvailable else {
            voiceState = .idle
            return
        }

        switch currentStep {
        case 1: // Name
            if let result = await onboardingAI.extractName(transcript) {
                userName = result.name
                voiceState = .confirming
                speechService.speak(result.spoken)
            } else { voiceState = .idle }

        case 4: // Work day
            if let result = await onboardingAI.extractWorkday(transcript) {
                workdayHours = result.workdayHours
                if let t = result.todayHours { todayHours = t }
                if let s = result.startHour { workStartHour = s }
                if let e = result.endHour { workEndHour = e }
                voiceState = .confirming
                speechService.speak(result.spoken)
            } else { voiceState = .idle }

        case 5: // Email cadence
            if let result = await onboardingAI.extractCadence(transcript) {
                emailCadence = result.cadenceIndex
                voiceState = .confirming
                speechService.speak(result.spoken)
            } else { voiceState = .idle }

        case 6: // Time defaults
            if let result = await onboardingAI.extractDefaults(transcript) {
                if let v = result.replyMins { replyMins = v }
                if let v = result.actionMins { actionMins = v }
                if let v = result.callMins { callMins = v }
                if let v = result.readMins { readMins = v }
                voiceState = .confirming
                speechService.speak(result.spoken)
            } else { voiceState = .idle }

        case 7: // Transit
            if let result = await onboardingAI.extractTransit(transcript) {
                transitChauffeur = result.chauffeur
                transitTrain = result.train
                transitPlane = result.plane
                transitDrive = result.drive
                saveTransitModes()
                voiceState = .confirming
                speechService.speak(result.spoken)
            } else { voiceState = .idle }

        default:
            voiceState = .idle
        }
    }

    // MARK: - Transit Mode Helpers

    private func loadTransitModes() {
        let modes = transitModes.split(separator: ",").map(String.init)
        transitChauffeur = modes.contains("chauffeur")
        transitTrain     = modes.contains("train")
        transitPlane     = modes.contains("plane")
        transitDrive     = modes.contains("drive")
    }

    private func saveTransitModes() {
        var modes: [String] = []
        if transitChauffeur { modes.append("chauffeur") }
        if transitTrain     { modes.append("train") }
        if transitPlane     { modes.append("plane") }
        if transitDrive     { modes.append("drive") }
        transitModes = modes.joined(separator: ",")
    }
}

// MARK: - StepLayout

private struct StepLayout<InputContent: View>: View {
    let icon: String
    let iconColor: Color
    let headline: String
    let bodyText: String
    @ViewBuilder let inputContent: () -> InputContent

    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(iconColor.opacity(0.10))
                    .frame(width: 72, height: 72)
                Image(systemName: icon)
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(iconColor)
            }

            VStack(spacing: 8) {
                Text(headline)
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)

                Text(bodyText)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 440)
            }

            inputContent()
                .padding(.top, 4)

            Spacer()
        }
    }
}

// MARK: - TimeDefaultRow

private struct TimeDefaultRow: View {
    let label: String
    @Binding var minutes: Int

    var body: some View {
        HStack {
            Text(label)
                .font(.callout)
                .frame(minWidth: 110, alignment: .leading)
            Spacer()
            Stepper("\(minutes) min", value: $minutes, in: 5...240, step: 5)
                .fixedSize()
        }
    }
}

// MARK: - TransitToggle

private struct TransitToggle: View {
    let label: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(label, isOn: $isOn)
            .font(.callout)
    }
}

// MARK: - OnboardingUserPrefs

/// Read-only access to all onboarding-set preferences from AppStorage.
struct OnboardingUserPrefs {
    static var userName: String {
        UserDefaults.standard.string(forKey: "onboarding_userName") ?? ""
    }

    static var email: String {
        UserDefaults.standard.string(forKey: "onboarding_email") ?? ""
    }

    static var workdayHours: Int {
        let v = UserDefaults.standard.integer(forKey: "onboarding_workdayHours")
        return v == 0 ? 9 : v
    }

    static var todayHours: Int {
        let v = UserDefaults.standard.integer(forKey: "onboarding_todayHours")
        return v == 0 ? 7 : v
    }

    static var emailCadence: Int {
        UserDefaults.standard.integer(forKey: "onboarding_emailCadence")
    }

    static var emailCadenceLabel: String {
        let options = ["Once", "Twice", "3 × daily", "4+ times"]
        let idx = emailCadence
        return options.indices.contains(idx) ? options[idx] : options[2]
    }

    static var familySurname: String {
        UserDefaults.standard.string(forKey: "onboarding_familySurname") ?? ""
    }

    static var replyMins: Int {
        let v = UserDefaults.standard.integer(forKey: "onboarding_replyMins")
        return v == 0 ? 5 : v
    }

    static var actionMins: Int {
        let v = UserDefaults.standard.integer(forKey: "onboarding_actionMins")
        return v == 0 ? 30 : v
    }

    static var callMins: Int {
        let v = UserDefaults.standard.integer(forKey: "onboarding_callMins")
        return v == 0 ? 15 : v
    }

    static var readMins: Int {
        let v = UserDefaults.standard.integer(forKey: "onboarding_readMins")
        return v == 0 ? 20 : v
    }

    static var transitModes: [String] {
        let raw = UserDefaults.standard.string(forKey: "onboarding_transitModes") ?? ""
        return raw.isEmpty ? [] : raw.split(separator: ",").map(String.init)
    }

    static var hasChauffeur: Bool    { transitModes.contains("chauffeur") }
    static var hasTrainTravel: Bool  { transitModes.contains("train") }
    static var hasPlaneTravel: Bool  { transitModes.contains("plane") }
    static var drivesSelf: Bool      { transitModes.contains("drive") }

    static var paEmail: String {
        UserDefaults.standard.string(forKey: "onboarding_paEmail") ?? ""
    }

    static var paEnabled: Bool {
        UserDefaults.standard.bool(forKey: "onboarding_paEnabled")
    }

    static var workStartHour: Int {
        let v = UserDefaults.standard.integer(forKey: "onboarding_workStartHour")
        return v == 0 ? 9 : v
    }

    static var workEndHour: Int {
        let v = UserDefaults.standard.integer(forKey: "onboarding_workEndHour")
        return v == 0 ? 18 : v
    }

    static var outlookConnected: Bool {
        UserDefaults.standard.bool(forKey: "accounts.outlook.connected")
    }

    static var supabaseConnected: Bool {
        UserDefaults.standard.bool(forKey: "accounts.supabase.connected")
    }
}
