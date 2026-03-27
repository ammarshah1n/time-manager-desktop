import SwiftUI

struct KeyboardShortcutsHelpView: View {
    @Environment(\.dismiss) private var dismiss

    private let shortcuts: [(keys: String, description: String)] = [
        ("⌘K", "Open search and focus the search field"),
        ("↑ / ↓", "Move through the ranked task list"),
        ("Return", "Open task detail for the focused ranked task"),
        ("Tab", "Cycle between the left, center, and right planner panels"),
        ("⇧Tab", "Cycle panels in reverse"),
        ("⌘N", "Open Add Task"),
        ("⌘S", "Toggle study mode"),
        ("⌘T", "Start the focus timer for the selected task"),
        ("⌘P", "Export today’s plan to PDF"),
        ("⌘E", "Toggle task notes edit and preview in the right drawer"),
        ("⇧⌘E", "Export approved blocks to Apple Calendar"),
        ("⌘/ or ?", "Show this keyboard shortcuts help")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Keyboard shortcuts")
                        .font(.custom("Fraunces", size: 24))
                        .fontWeight(.bold)
                        .foregroundStyle(.white)

                    Text("Timed is designed to stay usable without touching the mouse.")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.68))
                }

                Spacer()

                Button("Close") {
                    dismiss()
                }
                .buttonStyle(.bordered)
            }

            LazyVGrid(
                columns: [
                    GridItem(.fixed(110), alignment: .leading),
                    GridItem(.flexible(), alignment: .leading)
                ],
                alignment: .leading,
                spacing: 12
            ) {
                ForEach(shortcuts, id: \.keys) { shortcut in
                    shortcutKey(shortcut.keys)
                    Text(shortcut.description)
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.78))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Text("Tip: click a ranked task once to anchor keyboard selection, then keep moving with the arrow keys.")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.56))
        }
        .padding(22)
        .frame(width: 520)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(Color.white.opacity(0.10), lineWidth: 1)
                )
        )
        .padding(16)
    }

    private func shortcutKey(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.10))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )
    }
}
