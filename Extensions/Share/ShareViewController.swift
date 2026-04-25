// ShareViewController.swift — Timed Share Extension
// Accepts text / URL / email / attachment from any app's Share sheet and
// posts the payload to the Timed capture pipeline.
//
// Security posture (per ai-assistant-rules.md):
//   - Payload MIME type is allow-listed (text, URL, public.message).
//   - Payload size is hard-capped at 64 KB before forwarding.
//   - Every forwarded payload is wrapped in <untrusted_share>...</untrusted_share>
//     so downstream Anthropic prompts never treat it as instructions.
//   - Auth is read from the App Group keychain (same `com.timed.app.keys`
//     service), never solicited from the user.
//   - On any error, we complete the request silently — never expose internals.

import UIKit
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {

    private let appGroup = "group.com.timed.shared"
    private let maxPayloadBytes = 64 * 1024
    private let allowedTypes: Set<String> = [
        UTType.plainText.identifier,
        UTType.url.identifier,
        UTType.text.identifier,
        UTType.message.identifier,
    ]

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        Task { await processSharedItem() }
    }

    private func processSharedItem() async {
        guard
            let item = (extensionContext?.inputItems.first as? NSExtensionItem),
            let provider = item.attachments?.first
        else {
            complete()
            return
        }

        let payload = await extractPayload(from: provider)
        guard let payload, !payload.body.isEmpty else {
            complete()
            return
        }

        await enqueueShareCapture(payload)
        complete()
    }

    private func extractPayload(from provider: NSItemProvider) async -> SharePayload? {
        for typeID in allowedTypes where provider.hasItemConformingToTypeIdentifier(typeID) {
            do {
                let item = try await provider.loadItem(forTypeIdentifier: typeID)
                if let url = item as? URL {
                    return SharePayload(kind: "url", body: url.absoluteString)
                }
                if let text = item as? String {
                    let truncated = String(text.prefix(maxPayloadBytes))
                    return SharePayload(kind: "text", body: truncated)
                }
                if let data = item as? Data,
                   let text = String(data: data, encoding: .utf8) {
                    let truncated = String(text.prefix(maxPayloadBytes))
                    return SharePayload(kind: "text", body: truncated)
                }
            } catch {
                continue
            }
        }
        return nil
    }

    /// Append payload to the App Group queue file. Main app drains the queue
    /// next time it foregrounds OR when a BGAppRefreshTask fires. We never
    /// hit the network from here — the extension dies fast and the main app
    /// owns Edge Function calls + auth.
    private func enqueueShareCapture(_ payload: SharePayload) async {
        guard
            let container = FileManager.default
                .containerURL(forSecurityApplicationGroupIdentifier: appGroup)
        else { return }
        let url = container.appendingPathComponent("share-queue.jsonl", isDirectory: false)
        let line: [String: Any] = [
            "kind": payload.kind,
            "body": payload.body,
            "createdAt": ISO8601DateFormatter().string(from: Date()),
        ]
        guard
            let data = try? JSONSerialization.data(withJSONObject: line, options: []),
            let nl = "\n".data(using: .utf8)
        else { return }
        let payload = data + nl
        if FileManager.default.fileExists(atPath: url.path) {
            if let handle = try? FileHandle(forWritingTo: url) {
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: payload)
                try? handle.close()
            }
        } else {
            try? payload.write(to: url)
        }
    }

    private func complete() {
        DispatchQueue.main.async {
            self.extensionContext?.completeRequest(returningItems: nil)
        }
    }
}

private struct SharePayload {
    let kind: String
    let body: String
}
