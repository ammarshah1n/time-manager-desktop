// SharingPane.swift — Timed Features
// Settings tab for workspace sharing: invite links, active PA members, status.

import SwiftUI

struct SharingPane: View {
    @EnvironmentObject private var auth: AuthService
    @State private var members: [PAMember] = []
    @State private var inviteURL: String = ""
    @State private var isGenerating = false
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var memberToRemove: PAMember?
    @State private var showRemoveConfirmation = false
    @State private var copied = false

    private var isConnected: Bool {
        let url = ProcessInfo.processInfo.environment["SUPABASE_URL"]
            ?? "https://fpmjuufefhtlwbfinxlx.supabase.co"
        return !url.contains("fake.supabase.co")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if !isConnected {
                disconnectedBanner
            } else {
                statusIndicator
                inviteSection
                membersSection
            }
            Spacer()
        }
        .task { await loadMembers() }
        .alert("Remove Member", isPresented: $showRemoveConfirmation, presenting: memberToRemove) { member in
            Button("Remove", role: .destructive) { Task { await removeMember(member) } }
            Button("Cancel", role: .cancel) { }
        } message: { member in
            Text("Remove \(member.fullName ?? member.email) from this workspace? They will lose access to all shared tasks.")
        }
    }

    // MARK: - Disconnected

    private var disconnectedBanner: some View {
        VStack(spacing: 12) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text("Sign in to enable sharing")
                .font(.headline)
            Text("Connect your Outlook account to share your plan and tasks with your PA or assistant.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Status

    private var statusIndicator: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(members.isEmpty ? Color(.systemGray) : Color(.systemGreen))
                .frame(width: 8, height: 8)
            Text(members.isEmpty ? "Not shared" : "Sharing active")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Invite

    private var inviteSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Share with PA")
                .font(.headline)

            Text("Share this link with your PA. They'll be able to see your full task list and mark items as complete.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                TextField("Invite link", text: .constant(inviteURL))
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
                    .disabled(true)

                Button {
                    guard !inviteURL.isEmpty else { return }
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(inviteURL, forType: .string)
                    copied = true
                    Task {
                        try? await Task.sleep(for: .seconds(2))
                        copied = false
                    }
                } label: {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                }
                .disabled(inviteURL.isEmpty)
                .help("Copy to clipboard")

                Button {
                    Task { await generateLink() }
                } label: {
                    if isGenerating {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text(inviteURL.isEmpty ? "Generate Link" : "New Link")
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isGenerating)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    // MARK: - Members

    private var membersSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Workspace Members")
                .font(.headline)

            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else if members.isEmpty {
                Text("No members yet. Generate an invite link to share your workspace.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 0) {
                    ForEach(members) { member in
                        memberRow(member)
                        if member.id != members.last?.id {
                            Divider().padding(.leading, 44)
                        }
                    }
                }
                .background(Color(.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private func memberRow(_ member: PAMember) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(member.role == "owner" ? Color.blue.opacity(0.15) : Color.purple.opacity(0.15))
                .frame(width: 32, height: 32)
                .overlay {
                    Text(initials(for: member))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(member.role == "owner" ? .blue : .purple)
                }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(member.fullName ?? member.email)
                        .font(.system(size: 13))
                    roleBadge(member.role)
                }
                Text(member.email)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if member.role != "owner" {
                Button("Remove", role: .destructive) {
                    memberToRemove = member
                    showRemoveConfirmation = true
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
    }

    private func roleBadge(_ role: String) -> some View {
        Text(role.uppercased())
            .font(.system(size: 9, weight: .semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                role == "owner"
                    ? Color.blue.opacity(0.12)
                    : Color.purple.opacity(0.12),
                in: Capsule()
            )
            .foregroundStyle(role == "owner" ? .blue : .purple)
    }

    private func initials(for member: PAMember) -> String {
        if let name = member.fullName {
            return name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined()
        }
        return String(member.email.prefix(2)).uppercased()
    }

    // MARK: - Actions

    private func loadMembers() async {
        guard isConnected, let workspaceId = auth.workspaceId else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            members = try await SharingService.shared.fetchPAMembers(workspaceId: workspaceId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func generateLink() async {
        guard let workspaceId = auth.workspaceId else {
            errorMessage = "Not signed in — no workspace available."
            return
        }
        isGenerating = true
        errorMessage = nil
        defer { isGenerating = false }

        do {
            let url = try await SharingService.shared.generateInviteLink(workspaceId: workspaceId)
            inviteURL = url.absoluteString
            copied = false
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func removeMember(_ member: PAMember) async {
        guard let workspaceId = auth.workspaceId else { return }
        do {
            try await SharingService.shared.removeMember(memberId: member.id, workspaceId: workspaceId)
            members.removeAll { $0.id == member.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
