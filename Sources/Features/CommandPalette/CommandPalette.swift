// CommandPalette.swift — Timed macOS V2
// Global command palette triggered by Cmd+K.
// Fuzzy-filtered action list with keyboard navigation.

import SwiftUI

// MARK: - Action Model

struct PaletteAction: Identifiable {
    let id = UUID()
    let title: String
    let shortcut: String?
    let icon: String
    let category: ActionCategory
    let action: () -> Void

    enum ActionCategory: String, CaseIterable {
        case navigation = "Navigate"
        case task       = "Tasks"
        case focus      = "Focus"
        case plan       = "Plan"
    }
}

// MARK: - Action Registry

struct ActionRegistry {
    static func actions(
        navigate: @escaping (NavSection) -> Void,
        showMorningInterview: @escaping () -> Void,
        showFocus: @escaping (TimedTask?) -> Void,
        addTask: @escaping () -> Void
    ) -> [PaletteAction] {
        [
            // Navigation
            PaletteAction(title: "Go to Today",    shortcut: "\u{2318}1", icon: "calendar",               category: .navigation) { navigate(.today) },
            PaletteAction(title: "Go to Triage",   shortcut: "\u{2318}2", icon: "tray.and.arrow.down.fill", category: .navigation) { navigate(.triage) },
            PaletteAction(title: "Go to Action",   shortcut: "\u{2318}3", icon: "bolt.fill",               category: .navigation) { navigate(.tasks(.action)) },
            PaletteAction(title: "Go to Calendar",  shortcut: "\u{2318}4", icon: "calendar",               category: .navigation) { navigate(.calendar) },
            PaletteAction(title: "Go to Capture",   shortcut: "\u{2318}5", icon: "mic.fill",               category: .navigation) { navigate(.capture) },
            PaletteAction(title: "Go to Settings",  shortcut: "\u{2318},", icon: "gear",                   category: .navigation) { navigate(.prefs) },
            PaletteAction(title: "Go to Waiting",   shortcut: nil,         icon: "clock.badge.questionmark", category: .navigation) { navigate(.waiting) },
            PaletteAction(title: "Go to Reply",     shortcut: nil,         icon: "arrowshape.turn.up.left.fill", category: .navigation) { navigate(.tasks(.reply)) },
            PaletteAction(title: "Go to Calls",     shortcut: nil,         icon: "phone.fill",             category: .navigation) { navigate(.tasks(.calls)) },

            // Tasks
            PaletteAction(title: "New Task",        shortcut: "\u{2318}N", icon: "plus.circle.fill",       category: .task) { addTask() },
            PaletteAction(title: "Mark Complete",   shortcut: nil,         icon: "checkmark.circle.fill",  category: .task) { /* handled by active pane */ },
            PaletteAction(title: "Set Estimate",    shortcut: "E",         icon: "clock.fill",             category: .task) { /* handled by active pane */ },
            PaletteAction(title: "Defer Task",      shortcut: nil,         icon: "arrow.uturn.forward",    category: .task) { /* handled by active pane */ },

            // Focus
            PaletteAction(title: "Start Focus Session", shortcut: "F",     icon: "target",                 category: .focus) { showFocus(nil) },
            PaletteAction(title: "Pause Focus",     shortcut: nil,         icon: "pause.circle.fill",      category: .focus) { /* handled by FocusPane */ },
            PaletteAction(title: "Stop Focus",      shortcut: nil,         icon: "stop.circle.fill",       category: .focus) { /* handled by FocusPane */ },

            // Plan
            PaletteAction(title: "Generate Plan",       shortcut: "\u{2318}\u{21A9}", icon: "wand.and.stars",  category: .plan) { /* trigger planning engine */ },
            PaletteAction(title: "Morning Interview",    shortcut: nil,                icon: "sun.max.fill",    category: .plan) { showMorningInterview() },
        ]
    }
}

// MARK: - Fuzzy Search

enum FuzzyMatcher {
    enum MatchKind: Comparable {
        case exactPrefix
        case wordStart
        case fuzzy
        case noMatch
    }

    static func score(_ query: String, against title: String) -> MatchKind {
        let q = query.lowercased()
        let t = title.lowercased()

        guard !q.isEmpty else { return .exactPrefix }

        // Exact prefix
        if t.hasPrefix(q) { return .exactPrefix }

        // Word start — every word in query starts a word in title
        let queryWords = q.split(separator: " ")
        let titleWords = t.split(separator: " ")
        let allWordsMatch = queryWords.allSatisfy { qw in
            titleWords.contains { tw in tw.hasPrefix(qw) }
        }
        if allWordsMatch && !queryWords.isEmpty { return .wordStart }

        // Fuzzy — all chars of query appear in order in title
        var tIdx = t.startIndex
        for ch in q {
            guard let found = t[tIdx...].firstIndex(of: ch) else { return .noMatch }
            tIdx = t.index(after: found)
        }
        return .fuzzy
    }

    static func filter(_ query: String, actions: [PaletteAction]) -> [PaletteAction] {
        guard !query.isEmpty else { return actions }

        return actions
            .map { action in (action, score(query, against: action.title)) }
            .filter { $0.1 != .noMatch }
            .sorted { $0.1 < $1.1 }
            .prefix(10)
            .map(\.0)
    }
}

// MARK: - Command Row

struct CommandRow: View {
    let action: PaletteAction
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: action.icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(isSelected ? .white : .secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 1) {
                Text(action.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isSelected ? .white : .primary)

                Text(action.category.rawValue)
                    .font(.system(size: 10))
                    .foregroundStyle(isSelected ? Color.white.opacity(0.7) : Color.secondary.opacity(0.6))
            }

            Spacer()

            if let shortcut = action.shortcut {
                Text(shortcut)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(isSelected ? Color.white.opacity(0.7) : Color.secondary.opacity(0.6))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(isSelected ? Color.white.opacity(0.15) : Color.primary.opacity(0.06))
                    )
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.accentColor : Color.clear)
        )
    }
}

// MARK: - Command Palette View

struct CommandPaletteView: View {
    @Binding var isPresented: Bool
    let actions: [PaletteAction]

    @State private var query = ""
    @State private var selectedIndex = 0
    @FocusState private var isFocused: Bool

    private var filteredActions: [PaletteAction] {
        FuzzyMatcher.filter(query, actions: actions)
    }

    var body: some View {
        ZStack {
            // Dismiss backdrop
            Color.black.opacity(0.25)
                .ignoresSafeArea()
                .onTapGesture { isPresented = false }

            VStack(spacing: 0) {
                // Search field
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)

                    TextField("Type a command\u{2026}", text: $query)
                        .textFieldStyle(.plain)
                        .font(.system(size: 15))
                        .focused($isFocused)
                        .onSubmit { executeSelected() }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)

                Divider()

                // Results
                if filteredActions.isEmpty {
                    VStack(spacing: 8) {
                        Spacer()
                        Text("No matching commands")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .frame(height: 120)
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 2) {
                                ForEach(Array(filteredActions.enumerated()), id: \.element.id) { index, action in
                                    CommandRow(action: action, isSelected: index == selectedIndex)
                                        .id(action.id)
                                        .contentShape(Rectangle())
                                        .onTapGesture {
                                            selectedIndex = index
                                            executeSelected()
                                        }
                                }
                            }
                            .padding(.vertical, 6)
                            .padding(.horizontal, 6)
                        }
                        .frame(maxHeight: 340)
                        .onChange(of: selectedIndex) { _, newValue in
                            guard newValue < filteredActions.count else { return }
                            proxy.scrollTo(filteredActions[newValue].id, anchor: .center)
                        }
                    }
                }
            }
            .frame(width: 500)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.3), radius: 30, y: 10)
            .padding(.top, 80)
            .frame(maxHeight: .infinity, alignment: .top)
            .onAppear {
                isFocused = true
                selectedIndex = 0
            }
            .onChange(of: query) { _, _ in
                selectedIndex = 0
            }
            .onExitCommand { isPresented = false }
            .onKeyPress(.upArrow)   { moveSelection(-1); return .handled }
            .onKeyPress(.downArrow) { moveSelection(1);  return .handled }
        }
    }

    private func moveSelection(_ delta: Int) {
        let count = filteredActions.count
        guard count > 0 else { return }
        selectedIndex = (selectedIndex + delta + count) % count
    }

    private func executeSelected() {
        guard selectedIndex < filteredActions.count else { return }
        let action = filteredActions[selectedIndex]
        isPresented = false
        action.action()
    }
}
