// TimedApp.swift — Timed iOS Mockup
// Entry point + tab navigation. Drop into an iOS 17+ Xcode project.

import SwiftUI

@main
struct TimedApp: App {
    var body: some Scene {
        WindowGroup {
            RootTabView()
        }
    }
}

struct RootTabView: View {
    @State private var selectedTab: Tab = .inbox

    enum Tab { case inbox, calendar, focus, settings }

    var body: some View {
        TabView(selection: $selectedTab) {
            InboxView()
                .tabItem { Label("Inbox",    systemImage: "envelope") }
                .tag(Tab.inbox)

            CalendarView()
                .tabItem { Label("Calendar", systemImage: "calendar") }
                .tag(Tab.calendar)

            FocusTimerView()
                .tabItem { Label("Focus",    systemImage: "timer") }
                .tag(Tab.focus)

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gear") }
                .tag(Tab.settings)
        }
        .tint(.blue)
    }
}
