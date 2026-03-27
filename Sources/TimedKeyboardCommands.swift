import SwiftUI

struct TimedKeyboardActions {
    let addTask: () -> Void
    let toggleStudyMode: () -> Void
    let startFocusTimer: () -> Void
    let exportCalendar: () -> Void
    let focusSearch: () -> Void
    let showKeyboardShortcuts: () -> Void
    let canUndoDecomposition: Bool
    let undoLastDecomposition: () -> Void
}

struct TimedRankedTaskSelection {
    let task: TaskItem?
}

private struct TimedKeyboardActionsKey: FocusedValueKey {
    typealias Value = TimedKeyboardActions
}

private struct TimedRankedTaskSelectionKey: FocusedValueKey {
    typealias Value = TimedRankedTaskSelection
}

extension FocusedValues {
    var timedKeyboardActions: TimedKeyboardActions? {
        get { self[TimedKeyboardActionsKey.self] }
        set { self[TimedKeyboardActionsKey.self] = newValue }
    }

    var timedRankedTaskSelection: TimedRankedTaskSelection? {
        get { self[TimedRankedTaskSelectionKey.self] }
        set { self[TimedRankedTaskSelectionKey.self] = newValue }
    }
}

struct TimedKeyboardCommands: Commands {
    @FocusedValue(\.timedKeyboardActions) private var keyboardActions
    @FocusedValue(\.timedRankedTaskSelection) private var rankedTaskSelection

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Add Task") {
                keyboardActions?.addTask()
            }
            .keyboardShortcut("n", modifiers: [.command])
            .disabled(keyboardActions == nil)
        }

        CommandMenu("Timed") {
            Button("Toggle Study Mode") {
                keyboardActions?.toggleStudyMode()
            }
            .keyboardShortcut("s", modifiers: [.command])
            .disabled(keyboardActions == nil)

            Button("Start Focus Timer") {
                keyboardActions?.startFocusTimer()
            }
            .keyboardShortcut("t", modifiers: [.command])
            .disabled(keyboardActions == nil || rankedTaskSelection?.task == nil)

            Button("Export Calendar") {
                keyboardActions?.exportCalendar()
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])
            .disabled(keyboardActions == nil)

            Divider()

            Button("Search") {
                keyboardActions?.focusSearch()
            }
            .keyboardShortcut("k", modifiers: [.command])
            .disabled(keyboardActions == nil)

            Button("Keyboard Shortcuts") {
                keyboardActions?.showKeyboardShortcuts()
            }
            .keyboardShortcut("/", modifiers: [.command])
            .disabled(keyboardActions == nil)

            Divider()

            Button("Undo Subtask Breakdown") {
                keyboardActions?.undoLastDecomposition()
            }
            .keyboardShortcut("z", modifiers: [.command])
            .disabled(!(keyboardActions?.canUndoDecomposition ?? false))
        }
    }
}
