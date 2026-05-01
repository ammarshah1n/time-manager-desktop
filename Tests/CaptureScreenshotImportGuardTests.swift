import Foundation
import Testing

@Suite("Capture Screenshot Import Guards")
struct CaptureScreenshotImportGuardTests {
    @Test func screenshotImportUsesLocalVisionOCR() throws {
        let contents = try read("Sources/TimedKit/Features/Capture/CapturePane.swift")

        #expect(contents.contains("import Vision"),
                "Screenshot task import should use local Apple Vision OCR.")
        #expect(contents.contains("VNRecognizeTextRequest"),
                "Screenshot task import should recognize text locally before creating drafts.")
        #expect(contents.contains("Import screenshot"),
                "Capture UI should expose screenshot import beside paste.")
    }

    @Test func captureRowConversionUsesEditedDraftValues() throws {
        let contents = try read("Sources/TimedKit/Features/Capture/CapturePane.swift")

        #expect(contents.contains("onConvert(editingTitle, editingMins, editingBucket)"),
                "Draft row edits must be passed into conversion.")
        #expect(contents.contains("items[idx].parsedTitle = task.title"),
                "Converted capture item should keep the edited title.")
        #expect(contents.contains("items[idx].suggestedMinutes = minutes"),
                "Converted capture item should keep the edited minutes.")
        #expect(contents.contains("items[idx].suggestedBucket = bucket"),
                "Converted capture item should keep the edited bucket.")
    }

    @Test func convertAllUsesSyncedDraftValues() throws {
        let contents = try read("Sources/TimedKit/Features/Capture/CapturePane.swift")

        #expect(contents.contains("private func updateItem"),
                "Row edits should sync back to parent drafts before Convert All runs.")
        #expect(contents.contains("onUpdate(value, editingMins, editingBucket)"),
                "Title edits should update the parent draft.")
        #expect(contents.contains("onUpdate(editingTitle, value, editingBucket)"),
                "Minute edits should update the parent draft.")
        #expect(contents.contains("onUpdate(editingTitle, editingMins, value)"),
                "Bucket edits should update the parent draft.")
    }

    private func read(_ relativePath: String) throws -> String {
        try String(contentsOf: repoRoot().appendingPathComponent(relativePath), encoding: .utf8)
    }

    private func repoRoot() -> URL {
        var url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while url.path != "/" {
            if FileManager.default.fileExists(atPath: url.appendingPathComponent("Package.swift").path) {
                return url
            }
            url.deleteLastPathComponent()
        }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    }
}
