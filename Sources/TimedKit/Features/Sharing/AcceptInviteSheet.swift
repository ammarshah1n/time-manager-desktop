#if os(macOS)
// AcceptInviteSheet.swift
// Presented when `timed://invite/<code>` resolves and user is signed in.

import SwiftUI

struct AcceptInviteSheet: View {
    let code: String
    let onAccepted: (AcceptInviteResponse) -> Void
    let onDismiss: () -> Void

    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var success: AcceptInviteResponse?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Image(systemName: "person.2.fill")
                .font(.system(size: 36))
                .foregroundStyle(.tint)

            if let success {
                Text(success.alreadyMember
                     ? "You were already a PA for \(success.ownerEmail)."
                     : "You're now PA for \(success.ownerEmail).")
                    .font(.headline)
                Text("\(success.workspaceName) is now in your sidebar.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                Spacer()
                HStack {
                    Spacer()
                    Button("Done") { onDismiss() }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                Text("Accept Invite")
                    .font(.headline)
                Text("You've been invited to co-edit a Timed workspace as a PA. You'll be able to add and complete tasks. You will NOT see emails, briefings, or private intelligence.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                Spacer()
                HStack {
                    Button("Cancel") { onDismiss() }
                    Spacer()
                    Button {
                        Task { await accept() }
                    } label: {
                        if isWorking {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("Accept")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isWorking)
                }
            }
        }
        .padding(24)
        .frame(minWidth: 380, minHeight: 260)
    }

    private func accept() async {
        isWorking = true
        defer { isWorking = false }
        do {
            let response = try await SharingService.shared.acceptInvite(code: code)
            success = response
            onAccepted(response)
        } catch {
            errorMessage = humanise(error)
        }
    }

    private func humanise(_ error: Error) -> String {
        let raw = error.localizedDescription
        return raw.isEmpty ? "Something went wrong. Please try again." : raw
    }
}
#endif
