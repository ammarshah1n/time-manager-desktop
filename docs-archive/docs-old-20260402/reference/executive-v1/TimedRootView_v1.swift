// TimedRootView.swift — Timed macOS V2
// Sidebar: Today → Triage → WORK (buckets + Waiting) → TOOLS (Capture, Calendar) → Settings
// Morning Interview auto-shows on open. Dish Me Up via sheet.

import SwiftUI

struct TimedRootView: View {
    @State private var selection: NavSection? = .today
    @State private var triageItems = TriageItem.samples
    @State private var tasks       = TimedTask.samples
    @State private var blocks      = CalendarBlock.samples

    @State private var showMorningInterview = true
    @State private var morningDone          = false
    @State private var showDishMeUp         = false
    @State private var focusTask: TimedTask? = nil
    @State private var showFocus: Bool = false

    var body: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            sidebar
                .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 260)
        } detail: {
            detailView
        }
        .navigationSplitViewStyle(.balanced)
        .sheet(isPresented: $showMorningInterview) {
            MorningInterviewPane(tasks: $tasks, isPresented: $showMorningInterview)
                .onDisappear { morningDone = true }
        }
        .sheet(isPresented: $showDishMeUp) {
            DishMeUpSheet(tasks: $tasks) {
                showDishMeUp = false
            } onAccept: { firstTask in
                showDishMeUp = false
                focusTask = firstTask
                showFocus = true
            }
        }
        .sheet(isPresented: $showFocus) {
            FocusPane(task: focusTask) {
                showFocus = false
                focusTask = nil
            }
            .frame(minWidth: 600, minHeight: 680)
        }
    }

    // MARK: - Sidebar

    @ViewBuilder
    private var sidebar: some View {
        List(selection: $selection) {

            // ── Today ──────────────────────────────────────────────────
            SidebarRow(
                label: "Today",
                icon: "sparkles",
                color: .indigo,
                badge: 0
            )
            .tag(NavSection.today)

            // ── Triage ─────────────────────────────────────────────────
            SidebarRow(
                label: "Triage",
                icon: "tray.and.arrow.down.fill",
                color: .red,
                badge: triageItems.count
            )
            .tag(NavSection.triage)

            // ── WORK ───────────────────────────────────────────────────
            Section {
                let workBuckets: [TaskBucket] = [.action, .calls, .reply, .readToday, .readThisWeek, .transit]
                ForEach(workBuckets, id: \.self) { bucket in
                    let bucketTasks = tasks.filter { $0.bucket == bucket && !$0.isDone }
                    let totalMins   = bucketTasks.reduce(0) { $0 + $1.estimatedMinutes }

                    SidebarRow(
                        label: bucket.rawValue,
                        icon: bucket.icon,
                        color: bucket.color,
                        badge: bucketTasks.count,
                        timeHint: totalMins > 0 ? timeHint(totalMins) : nil
                    )
                    .tag(NavSection.tasks(bucket))
                }

                // Waiting on Others
                SidebarRow(
                    label: "Waiting",
                    icon: "clock.badge.questionmark",
                    color: .teal,
                    badge: 0
                )
                .tag(NavSection.waiting)

            } header: {
                sidebarHeader("WORK")
            }

            // ── TOOLS ──────────────────────────────────────────────────
            Section {
                SidebarRow(label: "Capture", icon: "mic.fill", color: .purple, badge: 0)
                    .tag(NavSection.capture)

                SidebarRow(label: "Calendar", icon: "calendar", color: .blue, badge: 0)
                    .tag(NavSection.calendar)

            } header: {
                sidebarHeader("TOOLS")
            }

            // ── Settings ───────────────────────────────────────────────
            Section {
                SidebarRow(label: "Settings", icon: "gear", color: Color(.systemGray), badge: 0)
                    .tag(NavSection.prefs)
            }
        }
        .listStyle(.sidebar)
    }

    // MARK: - Detail

    @ViewBuilder
    private var detailView: some View {
        switch selection ?? .today {
        case .today:
            TodayPane(
                tasks: $tasks,
                blocks: $blocks,
                triageCount: triageItems.count,
                morningDone: morningDone,
                onStartMorning: { showMorningInterview = true },
                onDishMeUp: { showDishMeUp = true }
            )
        case .triage:
            TriagePane(items: $triageItems, tasks: $tasks)
        case .tasks(let bucket):
            TasksPane(bucket: bucket, tasks: $tasks, blocks: $blocks)
        case .waiting:
            WaitingPane()
        case .capture:
            CapturePane(tasks: $tasks)
        case .calendar:
            CalendarPane(blocks: $blocks)
        case .prefs:
            PrefsPane()
        }
    }

    // MARK: - Helpers

    private func timeHint(_ minutes: Int) -> String {
        minutes < 60 ? "\(minutes)m" : (minutes % 60 == 0 ? "\(minutes/60)h" : "\(minutes/60)h\(minutes%60)m")
    }

    @ViewBuilder
    private func sidebarHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
            .tracking(1.2)
    }
}

// MARK: - Nav section enum

enum NavSection: Hashable {
    case today
    case triage
    case tasks(TaskBucket)
    case waiting
    case capture
    case calendar
    case prefs
}

// MARK: - Sidebar row

struct SidebarRow: View {
    let label: String
    let icon: String
    let color: Color
    let badge: Int
    var timeHint: String? = nil

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(color)
                .frame(width: 20)

            Text(label)
                .font(.system(size: 13))

            Spacer()

            if let hint = timeHint {
                Text(hint)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            if badge > 0 {
                Text("\(badge)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(color.opacity(0.85), in: Capsule())
            }
        }
    }
}
