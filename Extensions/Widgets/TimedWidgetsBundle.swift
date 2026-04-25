// TimedWidgetsBundle.swift — Timed Widgets target (iOS only)
// @main entry. WidgetBundle declares every WidgetKit + ActivityKit kind.
//
// This target is intentionally lean: it reads data from the App Group
// container (shared file + UserDefaults), not from Supabase or any AI key.
// The main app writes the snapshot on every DataBridge persist.

import SwiftUI
import WidgetKit

@main
struct TimedWidgetsBundle: WidgetBundle {
    var body: some Widget {
        TodayPriorityWidget()
        TimedConversationLiveActivity()
    }
}
