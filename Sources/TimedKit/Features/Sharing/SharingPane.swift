#if os(macOS)
// SharingPane.swift — Timed Features
// Settings tab for workspace sharing: invite links, active PA members, status.

import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

struct SharingPane: View {
    @EnvironmentObject private var auth: AuthService
    @State private var members: [PAMember] = []
    @State private var activeInvites: [WorkspaceInviteSummary] = []
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

    private var activeWorkspaceRole: String? {
        guard let id = auth.activeOrPrimaryWorkspaceId else { return nil }
        return auth.availableWorkspaces.first(where: { $0.id == id })?.role
    }

    private var isActiveWorkspaceOwner: Bool {
        activeWorkspaceRole == "owner"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if !isConnected {
                disconnectedBanner
            } else {
                statusIndicator
                if isActiveWorkspaceOwner {
                    inviteSection
                    activeInvitesSection
                }
                membersSection
                leaveWorkspaceSection
            }
            Spacer()
        }
        .task {
            await loadMembers()
            await loadInvites()
        }
        .onChange(of: auth.activeWorkspaceId) { _, _ in
            resetWorkspaceScopedSharingState()
            Task {
                await loadMembers()
                await loadInvites()
            }
        }
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
            Text("Sign in to Timed to invite your PA to co-edit your task list.")
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
            Text("Invite your PA to co-edit")
                .font(.headline)

            Text("Send a link. Your PA installs Timed, signs up, and can manage your tasks alongside you. They will not see your emails or any private intelligence.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Button {
                    Task { await generateAndShare() }
                } label: {
                    if isGenerating {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Invite your PA", systemImage: "person.crop.circle.badge.plus")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isGenerating)

                if !inviteURL.isEmpty {
                    Button {
                        PlatformPasteboard.copy(inviteURL)
                        copied = true
                        Task {
                            try? await Task.sleep(for: .seconds(2))
                            copied = false
                        }
                    } label: {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    }
                    .help("Copy link")
                }
            }

            if !inviteURL.isEmpty {
                Text(inviteURL)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private var activeInvitesSection: some View {
        let unconsumed = activeInvites.filter { $0.consumedAt == nil && !$0.isRevoked && $0.expiresAt > Date() }
        return Group {
            if !unconsumed.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Active Invites")
                        .font(.headline)
                    ForEach(unconsumed) { invite in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(String(invite.code.uuidString.prefix(8)) + "…")
                                    .font(.system(size: 11, design: .monospaced))
                                Text("Expires \(invite.expiresAt.formatted(.relative(presentation: .named)))")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Revoke") {
                                Task { await revoke(invite) }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
    }

    private var currentRoleIsPA: Bool {
        auth.availableWorkspaces.first { $0.id == auth.activeWorkspaceId }?.role == "pa"
    }

    private var leaveWorkspaceSection: some View {
        Group {
            if currentRoleIsPA, let activeId = auth.activeWorkspaceId, let myId = auth.executiveId {
                VStack(alignment: .leading, spacing: 10) {
                    Divider().padding(.vertical, 6)
                    Text("Leave this workspace")
                        .font(.headline)
                    Text("You'll lose access to this workspace's tasks. The owner can re-invite you anytime.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Leave \(currentName)") {
                        Task {
                            do {
                                let fallbackOwner = auth.availableWorkspaces.first(where: { $0.role == "owner" })?.id
                                try await SharingService.shared.leaveWorkspace(workspaceId: activeId, profileId: myId)
                                if let fallbackOwner {
                                    await auth.switchWorkspace(to: fallbackOwner)
                                }
                                await auth.reloadAvailableWorkspaces()
                            } catch {
                                errorMessage = error.localizedDescription
                            }
                        }
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                }
            }
        }
    }

    private var currentName: String {
        auth.availableWorkspaces.first(where: { $0.id == auth.activeWorkspaceId })?.name ?? "this workspace"
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
                Text("No members yet. Invite your PA when you're ready to co-edit.")
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
                .fill(member.role == "owner" ? Color.blue.opacity(0.15) : Color.secondary.opacity(0.15))
                .frame(width: 32, height: 32)
                .overlay {
                    Text(initials(for: member))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(member.role == "owner" ? .blue : .secondary)
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

            if isActiveWorkspaceOwner && member.role != "owner" {
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
                    : Color.secondary.opacity(0.12),
                in: Capsule()
            )
            .foregroundStyle(role == "owner" ? .blue : .secondary)
    }

    private func initials(for member: PAMember) -> String {
        if let name = member.fullName {
            return name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined()
        }
        return String(member.email.prefix(2)).uppercased()
    }

    // MARK: - Actions

    private func resetWorkspaceScopedSharingState() {
        members = []
        activeInvites = []
        inviteURL = ""
        memberToRemove = nil
        showRemoveConfirmation = false
        copied = false
        errorMessage = nil
    }

    private func loadMembers() async {
        guard isConnected, let workspaceId = auth.activeOrPrimaryWorkspaceId else { return }
        isLoading = true
        defer {
            if auth.activeOrPrimaryWorkspaceId == workspaceId {
                isLoading = false
            }
        }

        do {
            let fetchedMembers = try await SharingService.shared.fetchPAMembers(workspaceId: workspaceId)
            guard auth.activeOrPrimaryWorkspaceId == workspaceId else { return }
            members = fetchedMembers
        } catch {
            guard auth.activeOrPrimaryWorkspaceId == workspaceId else { return }
            members = []
            errorMessage = error.localizedDescription
        }
    }

    private func loadInvites() async {
        guard isConnected, let workspaceId = auth.activeOrPrimaryWorkspaceId else { return }
        guard isActiveWorkspaceOwner else {
            activeInvites = []
            inviteURL = ""
            return
        }
        do {
            let fetchedInvites = try await SharingService.shared.fetchInvites(workspaceId: workspaceId)
            guard auth.activeOrPrimaryWorkspaceId == workspaceId else { return }
            activeInvites = fetchedInvites
        } catch {
            guard auth.activeOrPrimaryWorkspaceId == workspaceId else { return }
            activeInvites = []
            // Invite history is secondary; don't block the pane for a transient fetch failure.
        }
    }

    private func generateAndShare() async {
        guard let workspaceId = auth.activeOrPrimaryWorkspaceId else {
            errorMessage = "Not signed in — no workspace available."
            return
        }
        guard isActiveWorkspaceOwner else {
            errorMessage = "Only the workspace owner can create invite links."
            return
        }
        isGenerating = true
        errorMessage = nil
        defer { isGenerating = false }

        do {
            let appURL = try await SharingService.shared.generateInviteLink(workspaceId: workspaceId)
            let code = appURL.lastPathComponent
            let webURL = "https://facilitated.com.au/timed/invite/\(code)"
            inviteURL = webURL
            copied = false
            presentSystemShareSheet(for: webURL)
            await loadInvites()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    #if os(macOS)
    private func presentSystemShareSheet(for url: String) {
        guard let nsURL = URL(string: url) else { return }
        let picker = NSSharingServicePicker(items: [nsURL])
        if let window = NSApp.keyWindow,
           let contentView = window.contentView {
            picker.show(relativeTo: .zero, of: contentView, preferredEdge: .minY)
        }
    }
    #endif

    private func revoke(_ invite: WorkspaceInviteSummary) async {
        do {
            try await SharingService.shared.revokeInvite(id: invite.id)
            await loadInvites()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func removeMember(_ member: PAMember) async {
        guard let workspaceId = auth.activeOrPrimaryWorkspaceId else { return }
        do {
            try await SharingService.shared.removeMember(memberId: member.id, workspaceId: workspaceId)
            members.removeAll { $0.id == member.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#endif
