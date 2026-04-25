// TimedConversationLiveActivity.swift — Timed Widgets / Live Activity
// ActivityKit-driven Dynamic Island + Lock Screen presentation while:
//   - the orb is in a conversation, OR
//   - email/calendar sync is running.
//
// Activity is started by the main app via `Activity<TimedConversationActivityAttributes>.request(...)`
// when ConversationModel transitions out of `.idle`. Update with
// `activity.update(...)` on every state change. End with `activity.end(...)`
// once the conversation ends.

import ActivityKit
import SwiftUI
import WidgetKit

public struct TimedConversationActivityAttributes: ActivityAttributes {
    public typealias ContentState = State

    public struct State: Codable, Hashable {
        public var phase: Phase
        public var transcriptLine: String  // "Listening..." or live transcript snippet
        public var startedAt: Date

        public init(phase: Phase, transcriptLine: String, startedAt: Date) {
            self.phase = phase
            self.transcriptLine = transcriptLine
            self.startedAt = startedAt
        }
    }

    public enum Phase: String, Codable, Hashable {
        case listening
        case thinking
        case speaking
        case syncingEmail
        case syncingCalendar

        public var label: String {
            switch self {
            case .listening:       return "Listening"
            case .thinking:        return "Thinking"
            case .speaking:        return "Speaking"
            case .syncingEmail:    return "Syncing email"
            case .syncingCalendar: return "Syncing calendar"
            }
        }

        public var systemImage: String {
            switch self {
            case .listening:       return "waveform"
            case .thinking:        return "sparkles"
            case .speaking:        return "speaker.wave.2"
            case .syncingEmail:    return "envelope"
            case .syncingCalendar: return "calendar"
            }
        }
    }

    public init() {}
}

struct TimedConversationLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TimedConversationActivityAttributes.self) { context in
            // Lock Screen / Banner UI
            HStack(spacing: 12) {
                Image(systemName: context.state.phase.systemImage)
                    .font(.system(size: 22, weight: .medium))
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.state.phase.label)
                        .font(.system(size: 13, weight: .semibold))
                    // Transcript redacted on Lock Screen — show count of words instead
                    Text(redactedSummary(of: context.state.transcriptLine))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
            }
            .padding()
            .activityBackgroundTint(.clear)
            .activitySystemActionForegroundColor(.primary)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: context.state.phase.systemImage)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(elapsedString(from: context.state.startedAt))
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.phase.label)
                        .font(.system(size: 13, weight: .semibold))
                }
                DynamicIslandExpandedRegion(.bottom) {
                    // Dynamic Island can render on the Lock Screen via the
                    // Lock Screen presentation when the device is locked.
                    // Redact the transcript line here too — the user can
                    // tap to open the app for the full transcript.
                    Text(redactedSummary(of: context.state.transcriptLine))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            } compactLeading: {
                Image(systemName: context.state.phase.systemImage)
            } compactTrailing: {
                Text(context.state.phase.label)
                    .font(.system(size: 11))
            } minimal: {
                Image(systemName: context.state.phase.systemImage)
            }
            .keylineTint(.accentColor)
        }
    }

    /// Lock-screen safe summary: never reveal the actual transcript text.
    private func redactedSummary(of transcript: String) -> String {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        let wordCount = trimmed.split(whereSeparator: \.isWhitespace).count
        return "\(wordCount) word\(wordCount == 1 ? "" : "s")"
    }

    private func elapsedString(from start: Date) -> String {
        let secs = Int(Date().timeIntervalSince(start))
        return String(format: "%d:%02d", secs / 60, secs % 60)
    }
}
