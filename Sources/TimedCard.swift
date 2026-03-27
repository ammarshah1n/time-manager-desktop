import AppKit
import SwiftUI

struct TimedCard<Content: View>: View {
    let title: String
    let icon: String?
    let accent: Color?
    @ViewBuilder let content: Content

    init(title: String, icon: String? = nil, accent: Color? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.accent = accent
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                if let icon {
                    Image(systemName: icon)
                        .timedScaledFont(13, weight: .semibold)
                        .foregroundStyle(.white.opacity(0.82))
                }

                Text(title)
                    .timedScaledFont(15, weight: .semibold)
                    .foregroundStyle(.white)
            }

            content
        }
        .padding(16)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.ultraThinMaterial)

                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(nsColor: .windowBackgroundColor).opacity(0.45))

                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                (accent ?? Color.white).opacity(accent == nil ? 0.10 : 0.22),
                                accent?.opacity(0.08) ?? Color.white.opacity(0.04),
                                Color.clear
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .opacity(0.18)
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.22), radius: 18, x: 0, y: 12)
    }
}
