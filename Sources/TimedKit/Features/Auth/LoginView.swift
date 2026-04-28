// LoginView.swift — Timed Auth
// First screen shown when AuthService.isSignedIn is false.
// One button: Sign in with Microsoft. Routes through Supabase Auth (Azure provider).
// OAuth redirect is the explicit exception to the orb-led-onboarding rule.

import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var auth: AuthService

    var body: some View {
        ZStack {
            Color.Timed.backgroundPrimary
                .ignoresSafeArea()

            VStack(spacing: 32) {
                Spacer()

                VStack(spacing: 12) {
                    Text("Timed")
                        .font(.system(size: 28, weight: .semibold, design: .default))
                        .foregroundStyle(Color.Timed.labelPrimary)
                    Text("Continue with your Microsoft 365 account.")
                        .font(.system(size: 15))
                        .foregroundStyle(Color.Timed.labelSecondary)
                        .multilineTextAlignment(.center)
                }

                Button(action: { Task { await auth.signInWithMicrosoft() } }) {
                    HStack(spacing: 10) {
                        if auth.isLoading {
                            ProgressView()
                                .controlSize(.small)
                                .tint(.white)
                        } else {
                            Image(systemName: "person.crop.circle.fill")
                                .font(.system(size: 16))
                        }
                        Text(auth.isLoading ? "Opening Microsoft sign-in…" : "Sign in with Microsoft")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .frame(maxWidth: 320)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.Timed.accent)
                .controlSize(.large)
                .disabled(auth.isLoading)

                if let error = auth.error, !error.isEmpty {
                    Text(error)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.Timed.destructive)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                        .frame(maxWidth: 360)
                }

                Spacer()

                Text("A browser window will open for sign-in. After approval, return here.")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.Timed.labelTertiary)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 32)
                    .padding(.horizontal, 32)
            }
            .frame(maxWidth: 480)
        }
    }
}
