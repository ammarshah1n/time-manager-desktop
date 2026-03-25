import Foundation

struct CodexBridge {
    private let candidateExecutables = [
        "/Applications/Codex.app/Contents/Resources/codex",
        "/Users/ammarshahin/code/codex-mem/dist/cli.js"
    ]

    func run(prompt: String) async -> String? {
        for path in candidateExecutables where FileManager.default.fileExists(atPath: path) {
            let url = URL(fileURLWithPath: path)
            if let output = await runProcess(url: url, arguments: ["--no-alt-screen", prompt]) {
                let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    return trimmed
                }
            }
        }
        return nil
    }

    private func runProcess(url: URL, arguments: [String]) async -> String? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                let pipe = Pipe()
                process.executableURL = url
                process.arguments = arguments
                process.standardOutput = pipe
                process.standardError = pipe

                do {
                    try process.run()
                    process.waitUntilExit()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    continuation.resume(returning: String(data: data, encoding: .utf8))
                } catch {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}
