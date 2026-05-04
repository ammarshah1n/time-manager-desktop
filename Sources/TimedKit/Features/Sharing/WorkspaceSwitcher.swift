#if os(macOS)
import SwiftUI

struct WorkspaceSwitcher: View {
    @EnvironmentObject var auth: AuthService

    var body: some View {
        if auth.availableWorkspaces.count > 1 {
            Menu {
                ForEach(auth.availableWorkspaces) { workspace in
                    Button {
                        Task { await auth.switchWorkspace(to: workspace.id) }
                    } label: {
                        HStack {
                            Text(workspace.name)
                            if workspace.id == auth.activeWorkspaceId {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "person.2")
                    Text(currentName)
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.caption2)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }

    private var currentName: String {
        auth.availableWorkspaces.first(where: { $0.id == auth.activeWorkspaceId })?.name
            ?? "Workspace"
    }
}
#endif
