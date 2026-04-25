// TodayPriorityWidget.swift — Timed Widgets
// Lock Screen + Home Screen + StandBy widget showing today's top 3 priorities
// + tap-to-launch deep link `timed://capture` for the orb.
//
// Critically: Lock Screen rendering happens BEFORE device unlock. Email
// subjects + sender names + private task wording must be redacted in
// .accessoryRectangular / .accessoryCircular families. The redact() helper
// returns counts + bucket icons only on lock-screen-class families.

import SwiftUI
import WidgetKit

// MARK: - Timeline entry

struct TodayEntry: TimelineEntry {
    let date: Date
    let snapshot: TodaySnapshot
}

// MARK: - Provider

struct TodayPriorityProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodayEntry {
        TodayEntry(date: Date(), snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (TodayEntry) -> Void) {
        // Only fall back to the demo placeholder for the widget gallery
        // (`context.isPreview == true`). Real users get `.empty` when no
        // snapshot is available — never the bland-but-fake demo content.
        let snap: TodaySnapshot
        if context.isPreview {
            snap = SharedSnapshot.read() ?? .placeholder
        } else {
            snap = SharedSnapshot.read()?.takeIfFresh() ?? .empty
        }
        completion(TodayEntry(date: Date(), snapshot: snap))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayEntry>) -> Void) {
        let snap = SharedSnapshot.read()?.takeIfFresh() ?? .empty
        let entry = TodayEntry(date: Date(), snapshot: snap)
        // Reload at next 15min OR at midnight, whichever is sooner — so a
        // stale "yesterday's priorities" widget never lingers into a new day.
        let refresh = min(
            Date().addingTimeInterval(15 * 60),
            Calendar.current.startOfDay(for: Date().addingTimeInterval(86_400))
        )
        completion(Timeline(entries: [entry], policy: .after(refresh)))
    }
}

private extension TodaySnapshot {
    func takeIfFresh() -> TodaySnapshot? {
        isFreshToday ? self : nil
    }
}

// MARK: - Widget configuration

struct TodayPriorityWidget: Widget {
    let kind: String = "today-priorities"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TodayPriorityProvider()) { entry in
            TodayPriorityView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Today's Priorities")
        .description("Top 3 priorities + open the orb to capture.")
        .supportedFamilies([
            .systemSmall, .systemMedium, .systemLarge,
            .accessoryRectangular, .accessoryCircular, .accessoryInline,
        ])
    }
}

// MARK: - View

struct TodayPriorityView: View {
    let entry: TodayEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryCircular:
            circularLockScreenView
        case .accessoryInline:
            Text("Timed — \(entry.snapshot.topPriorities.count) priorities")
        case .accessoryRectangular:
            rectangularLockScreenView
        case .systemSmall:
            smallView
        case .systemMedium, .systemLarge:
            mediumLargeView
        default:
            smallView
        }
    }

    // Lock Screen: count only — never the actual title (could be confidential).
    private var circularLockScreenView: some View {
        VStack(spacing: 0) {
            Image(systemName: "waveform")
                .font(.system(size: 16, weight: .medium))
            Text("\(entry.snapshot.topPriorities.count)")
                .font(.system(size: 22, weight: .semibold))
        }
    }

    private var rectangularLockScreenView: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: "waveform")
                Text("Timed")
                    .font(.system(size: 12, weight: .semibold))
            }
            Text("\(entry.snapshot.topPriorities.count) priorities — tap to capture")
                .font(.system(size: 11))
                .lineLimit(2)
        }
        .widgetURL(URL(string: "timed://capture"))
    }

    // Home Screen: full content visible only post-unlock anyway.
    private var smallView: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Today")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Image(systemName: "waveform")
            }
            Spacer()
            ForEach(entry.snapshot.topPriorities.prefix(2)) { p in
                Text(p.title)
                    .font(.system(size: 11))
                    .lineLimit(1)
            }
        }
        .widgetURL(URL(string: "timed://capture"))
    }

    private var mediumLargeView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Today's priorities")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Link(destination: URL(string: "timed://capture")!) {
                    Image(systemName: "waveform.circle.fill")
                        .font(.system(size: 22))
                }
            }
            ForEach(entry.snapshot.topPriorities.prefix(family == .systemLarge ? 6 : 3)) { p in
                HStack(spacing: 6) {
                    Image(systemName: bucketIcon(for: p.bucket))
                        .frame(width: 16)
                    Text(p.title)
                        .font(.system(size: 12))
                        .lineLimit(1)
                    Spacer()
                    Text("\(p.estimatedMinutes)m")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            if let title = entry.snapshot.nextEventTitle {
                Divider()
                HStack {
                    Image(systemName: "calendar")
                    Text("Next: \(title)")
                        .font(.system(size: 11))
                        .lineLimit(1)
                }
            }
        }
        .widgetURL(URL(string: "timed://capture"))
    }

    private func bucketIcon(for bucket: String) -> String {
        switch bucket {
        case "reply":    return "envelope"
        case "decision": return "checkmark.seal"
        case "read":     return "doc.text"
        case "call":     return "phone"
        case "transit":  return "airplane"
        default:         return "circle"
        }
    }
}
