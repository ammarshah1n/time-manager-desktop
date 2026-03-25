#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="$ROOT_DIR/docs/assets"
TMP_MAIN="/tmp/timed_screenshot_main.swift"
BIN="/tmp/timed-screenshot-renderer"

mkdir -p "$OUT_DIR"

cat >"$TMP_MAIN" <<'SWIFT'
import AppKit
import SwiftUI

@MainActor
func makePlannerStore() -> PlannerStore {
    let store = PlannerStore(storageURL: URL(fileURLWithPath: "/tmp/timed-screenshot-planner-\(UUID().uuidString).json"))
    store.promptText = "What should I do now?"
    store.chat = [
        PromptMessage(role: .assistant, text: "Timed is ready. Ask what to do now, plan the next three hours, or start a quiz."),
        PromptMessage(role: .user, text: "What should I do after school?"),
        PromptMessage(role: .assistant, text: "English essay draft: Start this immediately — it's a school assignment.\nMaths investigation: Block 30 minutes this afternoon.\nEconomics notes cleanup: Clear it in a low-energy block tonight.")
    ]
    store.rebuildPlan(now: ISO8601DateFormatter().date(from: "2026-03-25T16:00:00Z") ?? .now)
    return store
}

@MainActor
func makeQuizStore() -> PlannerStore {
    let store = makePlannerStore()
    store.isQuizMode = true
    store.activeQuizSubject = "Maths"
    store.selectedContextID = store.contexts.first(where: { $0.subject == "Maths" })?.id
    store.chat = [
        PromptMessage(role: .assistant, text: "Planner mode is ready."),
        PromptMessage(role: .student, text: "Quiz me on Maths.", isQuiz: true),
        PromptMessage(role: .tutor, text: "What assumption should you state before choosing the method in a maths investigation?", isQuiz: true),
        PromptMessage(role: .student, text: "I should state what variables stay fixed and what I am testing.", isQuiz: true),
        PromptMessage(role: .tutor, text: "Good. Keep it tighter in the write-up: define the fixed variables first, then justify the method choice in one sentence.", isQuiz: true)
    ]
    store.promptText = "Type your answer or End quiz"
    store.rebuildPlan(now: ISO8601DateFormatter().date(from: "2026-03-25T16:00:00Z") ?? .now)
    return store
}

@MainActor
func writePNG<V: View>(_ view: V, to path: String) throws {
    let renderer = ImageRenderer(
        content: view
            .frame(width: 1480, height: 940)
            .preferredColorScheme(.dark)
    )
    renderer.scale = 2
    renderer.isOpaque = false

    guard let image = renderer.nsImage else {
        throw NSError(domain: "TimedScreenshots", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not render SwiftUI view to image."])
    }

    guard
        let tiff = image.tiffRepresentation,
        let rep = NSBitmapImageRep(data: tiff),
        let png = rep.representation(using: .png, properties: [:])
    else {
        throw NSError(domain: "TimedScreenshots", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not encode PNG data."])
    }

    try png.write(to: URL(fileURLWithPath: path), options: [.atomic])
}

@main
struct TimedScreenshotRenderer {
    static func main() async throws {
        try await MainActor.run {
            try writePNG(ContentView(store: makePlannerStore()), to: CommandLine.arguments[1])
            try writePNG(ContentView(store: makeQuizStore()), to: CommandLine.arguments[2])
        }
    }
}
SWIFT

xcrun swiftc \
    -D SCREENSHOT_RENDERER \
    -target arm64-apple-macos15.0 \
    -sdk "$(xcrun --sdk macosx --show-sdk-path)" \
    "$ROOT_DIR"/Sources/*.swift \
    "$TMP_MAIN" \
    -o "$BIN"

"$BIN" \
    "$OUT_DIR/timed-planner.png" \
    "$OUT_DIR/timed-quiz.png"

echo "Rendered screenshots:"
ls -lh "$OUT_DIR"/timed-*.png
