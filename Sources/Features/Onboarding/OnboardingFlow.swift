// OnboardingFlow.swift — Timed macOS
// First-launch voice-style setup wizard. 8 steps, animated transitions.

import SwiftUI

// MARK: - OnboardingFlow

struct OnboardingFlow: View {
    let onComplete: () -> Void
    @StateObject private var auth = AuthService.shared

    @State private var currentStep: Int = 0

    // Step 1 — Accounts
    @AppStorage("accounts.outlook.connected") private var outlookConnected: Bool = false
    @AppStorage("accounts.supabase.connected") private var supabaseConnected: Bool = false

    // Step 2 — Connect Email
    @AppStorage("onboarding_email") private var emailHint: String = ""

    // Step 3 — Work Day
    @AppStorage("onboarding_workdayHours") private var workdayHours: Int = 9
    @AppStorage("onboarding_todayHours") private var todayHours: Int = 7
    @AppStorage("onboarding_workStartHour") private var workStartHour: Int = 9
    @AppStorage("onboarding_workEndHour") private var workEndHour: Int = 18

    // Step 4 — Email Cadence
    @AppStorage("onboarding_emailCadence") private var emailCadence: Int = 2
    @AppStorage("onboarding_familySurname") private var familySurname: String = ""

    // Step 5 — Time Defaults
    @AppStorage("onboarding_replyMins") private var replyMins: Int = 5
    @AppStorage("onboarding_actionMins") private var actionMins: Int = 30
    @AppStorage("onboarding_callMins") private var callMins: Int = 15
    @AppStorage("onboarding_readMins") private var readMins: Int = 20

    // Step 6 — Transit
    @AppStorage("onboarding_transitModes") private var transitModes: String = ""

    // Step 7 — PA
    @AppStorage("onboarding_paEmail") private var paEmail: String = ""
    @AppStorage("onboarding_paEnabled") private var paEnabled: Bool = false

    private let totalSteps = 8

    // Transit checkbox state (derived from transitModes AppStorage)
    @State private var transitChauffeur: Bool = false
    @State private var transitTrain: Bool = false
    @State private var transitPlane: Bool = false
    @State private var transitDrive: Bool = false

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

            navigationButtons
                .padding(.horizontal, 40)
                .padding(.bottom, 28)
        }
        .frame(width: 580, height: 560)
        .background(Color(.controlBackgroundColor))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.35), radius: 24, x: 0, y: 8)
    }

    // MARK: - Progress Dots

    private var progressDots: some View {
        HStack(spacing: 8) {
            ForEach(0..<totalSteps, id: \.self) { index in
                Circle()
                    .fill(index <= currentStep ? Color.indigo : Color.secondary.opacity(0.3))
                    .frame(width: 6, height: 6)
            }
        }
    }

    // MARK: - Step Content (animated)

    @ViewBuilder
    private var stepContent: some View {
        Group {
            switch currentStep {
            case 0: step1Welcome
            case 1: step2Accounts
            case 2: step4WorkDay
            case 3: step5Cadence
            case 4: step6TimeDefaults
            case 5: step7Transit
            case 6: step8PA
            case 7: step9Done
            default: EmptyView()
            }
        }
        .transition(.asymmetric(
            insertion: .move(edge: .trailing),
            removal: .move(edge: .leading)
        ))
        .animation(.spring(duration: 0.35), value: currentStep)
    }

    // MARK: - Step 1: Welcome

    private var step1Welcome: some View {
        StepLayout(
            icon: "sparkles",
            iconColor: .indigo,
            headline: "Welcome to Timed",
            bodyText:"The time allocation engine. Set up takes 2 minutes."
        ) {
            EmptyView()
        }
    }

    // MARK: - Step 2: Accounts

    private var outlookConfigured: Bool {
        // GraphClient has hardcoded client ID fallback — always configured
        let clientId = ProcessInfo.processInfo.environment["GRAPH_CLIENT_ID"]
            ?? "89e8f1c6-3cc4-47fb-83ae-f7e0528eb860"
        return !clientId.isEmpty
    }

    private var supabaseConfigured: Bool {
        // SupabaseClient has hardcoded URL fallback — always configured
        let url = ProcessInfo.processInfo.environment["SUPABASE_URL"]
            ?? "https://fpmjuufefhtlwbfinxlx.supabase.co"
        return !url.contains("fake.supabase.co")
    }

    private var neitherConfigured: Bool {
        !outlookConfigured && !supabaseConfigured
    }

    @State private var isConnecting = false

    private var step2Accounts: some View {
        StepLayout(
            icon: "envelope.badge.fill",
            iconColor: .blue,
            headline: "Connect Outlook",
            bodyText: "Timed reads your email and calendar to build your daily plan. Your data stays on this Mac."
        ) {
            VStack(spacing: 20) {
                if outlookConnected {
                    // Connected state
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
                    // Connect button — single prominent action
                    Button {
                        isConnecting = true
                        Task {
                            await auth.signInWithGraph(loginHint: emailHint)
                            if auth.graphAccessToken != nil {
                                outlookConnected = true
                                // Infer family surname from user's email
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

    // MARK: - Step 3: Connect Email

    private var step3Email: some View {
        StepLayout(
            icon: "envelope.badge.fill",
            iconColor: .blue,
            headline: "Connect your Outlook",
            bodyText:"Timed pulls from Microsoft 365 to triage, not replace, your inbox."
        ) {
            TextField("your@company.com", text: $emailHint)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 320)
        }
    }

    // MARK: - Step 4: Work Day

    private var step4WorkDay: some View {
        StepLayout(
            icon: "clock.fill",
            iconColor: .orange,
            headline: "How long is your typical work day?",
            bodyText:"Timed uses this to tell you how much you can realistically fit in."
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

    private var step5Cadence: some View {
        StepLayout(
            icon: "tray.and.arrow.down.fill",
            iconColor: .red,
            headline: "How often do you check email?",
            bodyText:"Timed batches replies and surfaces them at your cadence."
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

    private var step6TimeDefaults: some View {
        StepLayout(
            icon: "timer",
            iconColor: .purple,
            headline: "Set your time defaults",
            bodyText:"Timed estimates task time. You can override anytime — but here's where to start."
        ) {
            VStack(alignment: .leading, spacing: 10) {
                TimeDefaultRow(label: "Quick reply",  minutes: $replyMins)
                TimeDefaultRow(label: "Email action", minutes: $actionMins)
                TimeDefaultRow(label: "Phone call",   minutes: $callMins)
                TimeDefaultRow(label: "Read / Review", minutes: $readMins)
            }
            .frame(maxWidth: 360)
        }
    }

    // MARK: - Step 7: Transit

    private var step7Transit: some View {
        StepLayout(
            icon: "car.fill",
            iconColor: .green,
            headline: "How do you travel?",
            bodyText:"Timed surfaces the right tasks when you're in transit — no desk, no focus required."
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

    private var step8PA: some View {
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

    private var step9Done: some View {
        StepLayout(
            icon: "checkmark.seal.fill",
            iconColor: .indigo,
            headline: "You're ready",
            bodyText:"Timed is set up. Your first morning interview starts now — it takes 5 minutes and plans your whole day."
        ) {
            EmptyView()
        }
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

            if currentStep < totalSteps - 1 {
                Button("Continue →") {
                    withAnimation(.spring(duration: 0.35)) {
                        currentStep += 1
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(.indigo)
            } else {
                Button("Start my day →") {
                    onComplete()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(.indigo)
            }
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
            // Icon
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(iconColor.opacity(0.10))
                    .frame(width: 72, height: 72)
                Image(systemName: icon)
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(iconColor)
            }

            // Text
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

// MARK: - AccountConnectionRow

private struct AccountConnectionRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let isConfigured: Bool
    let isConnected: Bool
    let configuredMessage: String
    let notConfiguredMessage: String
    let onConnect: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(iconColor)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout.bold())

                if isConnected {
                    Label("Connected", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                } else if isConfigured {
                    Text(configuredMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text(notConfiguredMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if isConnected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.title3)
            } else if isConfigured {
                Button("Sign In") {
                    onConnect()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }
}

// MARK: - OnboardingUserPrefs

/// Read-only access to all onboarding-set preferences from AppStorage.
/// Use this throughout the app instead of reading @AppStorage keys directly.
struct OnboardingUserPrefs {
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

