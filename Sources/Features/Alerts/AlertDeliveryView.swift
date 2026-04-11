import SwiftUI

/// Phase 8.04: Alert delivery UI — menu bar notification style.
/// 1-2 sentences max, text-first. Voice only for composite > 0.8 AND opt-in.
struct AlertDeliveryView: View {
    let alert: AlertViewModel
    let onAcknowledge: () -> Void
    let onDismiss: () -> Void
    let onActionable: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack {
                Circle()
                    .fill(urgencyColor)
                    .frame(width: 8, height: 8)
                Text(alert.title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
                Text(alert.timeAgo)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            // Body (1-2 sentences max)
            Text(alert.body)
                .font(.callout)
                .lineSpacing(2)
                .lineLimit(3)

            // Confidence indicator
            if let confidence = alert.confidence {
                Text(confidenceLabel(confidence))
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(confidence > 0.7 ? Color.green.opacity(0.15) : Color.orange.opacity(0.15))
                    .clipShape(Capsule())
            }

            // Action buttons
            HStack(spacing: 12) {
                Button(action: {
                    onActionable(true)
                    onAcknowledge()
                }) {
                    Label("Useful", systemImage: "hand.thumbsup")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.green)

                Button(action: {
                    onActionable(false)
                    onDismiss()
                }) {
                    Label("Not now", systemImage: "xmark")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                Spacer()
            }
        }
        .padding(12)
        .frame(maxWidth: 320)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(radius: 4)
    }

    private var urgencyColor: Color {
        if alert.compositeScore > 0.7 { return .red }
        if alert.compositeScore > 0.5 { return .orange }
        return .yellow
    }

    private func confidenceLabel(_ confidence: Double) -> String {
        if confidence > 0.8 { return "High confidence" }
        if confidence > 0.6 { return "Moderate confidence" }
        return "Developing observation"
    }
}

// MARK: - View Model

struct AlertViewModel: Identifiable, Sendable {
    let id: UUID
    let title: String
    let body: String
    let source: String
    let compositeScore: Double
    let confidence: Double?
    let timestamp: Date

    var timeAgo: String {
        let seconds = Int(Date().timeIntervalSince(timestamp))
        if seconds < 60 { return "Just now" }
        if seconds < 3600 { return "\(seconds / 60)m ago" }
        return "\(seconds / 3600)h ago"
    }
}
