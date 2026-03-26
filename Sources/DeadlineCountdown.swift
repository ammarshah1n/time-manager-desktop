import SwiftUI

enum DeadlineCountdownFormatter {
    static let badgeWindow: TimeInterval = 48 * 3600

    static func badgeText(for dueDate: Date?, now: Date = .now) -> String? {
        guard let dueDate else { return nil }

        let remaining = dueDate.timeIntervalSince(now)
        if remaining < 0 {
            return "Overdue"
        }

        guard remaining <= badgeWindow else { return nil }

        let totalMinutes = max(0, Int((remaining / 60).rounded(.down)))
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        if hours >= 1 {
            return minutes == 0 ? "\(hours)h" : "\(hours)h \(minutes)m"
        }

        return "\(max(1, totalMinutes))m"
    }
}

struct DeadlineCountdownBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(Color(red: 1, green: 0.78, blue: 0.78))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.red.opacity(text == "Overdue" ? 0.30 : 0.18))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(Color.red.opacity(0.42), lineWidth: 1)
            )
            .accessibilityLabel("Deadline countdown \(text)")
    }
}
