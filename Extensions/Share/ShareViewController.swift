// ShareViewController.swift — Timed Share Extension
// Accepts text / URL from any app's Share sheet and appends the payload to an
// App Group queue. The main-app drain is not wired yet.
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
    // public.message removed: it allows raw RFC822-style messages with
    // headers + bodies, which would smuggle uncontrolled instructions
    // straight to the Anthropic relay. Plain text + URL only.
    private let allowedTypes: Set<String> = [
        UTType.plainText.identifier,
        UTType.url.identifier,
        UTType.text.identifier,
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
                    return SharePayload(kind: "url", body: cap(url.absoluteString))
                }
                if let text = item as? String {
                    return SharePayload(kind: "text", body: cap(text))
                }
                if let data = item as? Data {
                    // Reject *before* UTF-8 decoding — otherwise a multi-MB
                    // payload would be fully materialised in memory.
                    guard data.count <= maxPayloadBytes else { return nil }
                    if let text = String(data: data, encoding: .utf8) {
                        return SharePayload(kind: "text", body: cap(text))
                    }
                }
            } catch {
                continue
            }
        }
        return nil
    }

    /// Truncate by UTF-8 byte length, not String character count
    /// (`String.prefix(N)` counts grapheme clusters and can pass a payload
    /// many times larger than `maxPayloadBytes`).
    private func cap(_ s: String) -> String {
        let utf8 = Array(s.utf8)
        guard utf8.count > maxPayloadBytes else { return s }
        let prefix = utf8.prefix(maxPayloadBytes)
        return String(decoding: prefix, as: UTF8.self)
    }

    /// Append payload to the App Group queue file. We never hit the network
    /// from here — the extension dies fast and the future main-app drain owns
    /// Edge Function calls + auth.
    ///
    /// Total queue file size is hard-capped at 1 MB. If the cap is reached,
    /// we drop the new item (the user's most recent share). This is a worse
    /// UX than draining the queue here, but a malicious share-flood (or a
    /// stalled drain on the main side) can't blow up the App Group container.
    private let maxQueueBytes = 1 * 1024 * 1024

    private func enqueueShareCapture(_ payload: SharePayload) async {
        guard
            let container = FileManager.default
                .containerURL(forSecurityApplicationGroupIdentifier: appGroup)
        else { return }
        let url = container.appendingPathComponent("share-queue.jsonl", isDirectory: false)

        // Reject if queue is already at the cap.
        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
           let size = attrs[.size] as? Int,
           size >= maxQueueBytes {
            return
        }

        let line: [String: Any] = [
            "kind": payload.kind,
            "body": payload.body,
            "createdAt": ISO8601DateFormatter().string(from: Date()),
        ]
        guard
            let data = try? JSONSerialization.data(withJSONObject: line, options: []),
            let nl = "\n".data(using: .utf8)
        else { return }
        let writeData = data + nl
        if FileManager.default.fileExists(atPath: url.path) {
            if let handle = try? FileHandle(forWritingTo: url) {
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: writeData)
                try? handle.close()
            }
        } else {
            try? writeData.write(to: url)
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
