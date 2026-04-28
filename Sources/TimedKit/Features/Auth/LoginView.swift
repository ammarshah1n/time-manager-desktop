// LoginView.swift — Timed Auth
// First screen shown when AuthService.isSignedIn is false.
// Two paths: email + password, or Sign in with Microsoft (Supabase OAuth, Azure provider).

import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var auth: AuthService

    @State private var mode: Mode = .signIn
    @State private var email: String = ""
    @State private var password: String = ""
    @FocusState private var focused: Field?

    enum Mode: String, CaseIterable, Identifiable {
        case signIn = "Sign in"
        case signUp = "Create account"
        var id: String { rawValue }
    }

    enum Field: Hashable { case email, password }

    var body: some View {
        ZStack {
            Color.Timed.backgroundPrimary
                .ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer()

                VStack(spacing: 8) {
                    Text("Timed")
                        .font(.system(size: 28, weight: .semibold, design: .default))
                        .foregroundStyle(Color.Timed.labelPrimary)

                    ZStack {
                        Text(subtitle)
                            .font(.system(size: 15))
                            .foregroundStyle(Color.Timed.labelSecondary)
                            .multilineTextAlignment(.center)
                            .id(mode)
                            .transition(.opacity)
                    }
                    .animation(TimedMotion.springy, value: mode)
                }

                Picker("", selection: $mode.animation(TimedMotion.springy)) {
                    ForEach(Mode.allCases) { m in
                        Text(m.rawValue).tag(m)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 320)
                .disabled(auth.isLoading)

                VStack(spacing: 12) {
                    TextField("Email", text: $email)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 14))
                        .focused($focused, equals: .email)
                        .submitLabel(.next)
                        .onSubmit { focused = .password }
                        #if os(macOS)
                        .textContentType(.username)
                        .autocorrectionDisabled(true)
                        #endif

                    SecureField("Password", text: $password)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 14))
                        .focused($focused, equals: .password)
                        .submitLabel(.go)
                        .onSubmit { Task { await primaryAction() } }
                        #if os(macOS)
                        .textContentType(mode == .signUp ? .newPassword : .password)
                        #endif
                }
                .frame(maxWidth: 320)

                Button(action: { Task { await primaryAction() } }) {
                    HStack(spacing: 10) {
                        if auth.isLoading {
                            ProgressView()
                                .controlSize(.small)
                                .tint(.white)
                        }
                        Text(primaryLabel)
                            .font(.system(size: 15, weight: .semibold))
                            .id(mode)
                            .transition(.asymmetric(
                                insertion: .move(edge: .trailing).combined(with: .opacity),
                                removal: .move(edge: .leading).combined(with: .opacity)
                            ))
                    }
                    .frame(maxWidth: 320)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.Timed.accent)
                .controlSize(.large)
                .disabled(auth.isLoading || !canSubmit)
                .animation(TimedMotion.springy, value: mode)

                if mode == .signIn {
                    Button("Forgot password?") {
                        Task { await auth.sendPasswordReset(email: email) }
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.Timed.labelTertiary)
                    .disabled(auth.isLoading)
                    .transition(.opacity)
                }

                HStack(spacing: 12) {
                    Rectangle()
                        .fill(Color.Timed.labelTertiary.opacity(0.3))
                        .frame(height: 1)
                    Text("or")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.Timed.labelTertiary)
                    Rectangle()
                        .fill(Color.Timed.labelTertiary.opacity(0.3))
                        .frame(height: 1)
                }
                .frame(maxWidth: 320)

                Button(action: { Task { await auth.signInWithMicrosoft() } }) {
                    HStack(spacing: 10) {
                        Image("ms-logo")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 16, height: 16)
                        Text("Continue with Microsoft")
                            .font(.system(size: 14, weight: .medium))
                    }
                    .frame(maxWidth: 320)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(auth.isLoading)

                if let error = auth.error, !error.isEmpty {
                    Text(error)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.Timed.destructive)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                        .frame(maxWidth: 360)
                        .transition(.opacity)
                }

                Spacer()

                Text(footerText)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.Timed.labelTertiary)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 32)
                    .padding(.horizontal, 32)
                    .id(mode)
                    .transition(.opacity)
                    .animation(TimedMotion.springy, value: mode)
            }
            .frame(maxWidth: 480)
            .animation(TimedMotion.springy, value: mode)

            // Welcome banner — fades in on successful auth, holds for ~1.4s before sheet swap.
            if let welcome = auth.welcomeMessage {
                VStack {
                    Text(welcome)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(Color.Timed.labelPrimary)
                        .padding(.horizontal, 28)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(.ultraThinMaterial)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Color.Timed.labelTertiary.opacity(0.15), lineWidth: 1)
                        )
                        .shadow(color: .black.opacity(0.08), radius: 18, y: 6)
                        .padding(.top, 80)
                    Spacer()
                }
                .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
            }
        }
        .onAppear { focused = .email }
        .onChange(of: mode) { _, _ in auth.error = nil }
        .animation(TimedMotion.springy, value: auth.welcomeMessage)
    }

    private var subtitle: String {
        switch mode {
        case .signIn: return "Sign in to your Timed account."
        case .signUp: return "Create an account to start using Timed."
        }
    }

    private var primaryLabel: String {
        if auth.isLoading {
            return mode == .signIn ? "Signing in…" : "Creating account…"
        }
        return mode == .signIn ? "Sign in" : "Create account"
    }

    private var canSubmit: Bool {
        !email.trimmingCharacters(in: .whitespaces).isEmpty &&
        password.count >= (mode == .signUp ? 8 : 1)
    }

    private var footerText: String {
        switch mode {
        case .signIn: return "Microsoft sign-in opens a browser window. After approval, return here."
        case .signUp: return "Your account stores your tasks, briefings, and signals — only you can see it."
        }
    }

    private func primaryAction() async {
        switch mode {
        case .signIn: await auth.signInWithEmail(email, password: password)
        case .signUp: await auth.signUpWithEmail(email, password: password)
        }
    }
}
