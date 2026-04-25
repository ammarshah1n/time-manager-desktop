import Foundation
import SwiftUI

enum ConversationAIEvent {
    case textDelta(String)
    case toolResult(String)
    case completed
    case endConversation
}

@MainActor
final class ConversationAIClient: ObservableObject {
    private let tools: ConversationTools
    private var messages: [[String: Any]] = []
    private var activeTask: Task<Void, Never>?

    init(tools: ConversationTools) {
        self.tools = tools
    }

    func reset() {
        activeTask?.cancel()
        activeTask = nil
        messages = []
    }

    func cancelCurrentTurn() {
        activeTask?.cancel()
        activeTask = nil
    }

    func streamTurn(
        userText: String,
        clientState: [String: Any]?
    ) -> AsyncThrowingStream<ConversationAIEvent, Error> {
        messages.append(["role": "user", "content": userText])

        return AsyncThrowingStream { continuation in
            activeTask?.cancel()
            let task = Task { @MainActor in
                do {
                    try await runToolLoop(clientState: clientState, continuation: continuation)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            activeTask = task
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func runToolLoop(
        clientState: [String: Any]?,
        continuation: AsyncThrowingStream<ConversationAIEvent, Error>.Continuation
    ) async throws {
        for _ in 0..<5 {
            try Task.checkCancellation()
            let turn = try await streamOnce(clientState: clientState, continuation: continuation)
            if !turn.assistantContent.isEmpty {
                messages.append(["role": "assistant", "content": turn.assistantContent])
            }
            guard !turn.toolUses.isEmpty else {
                continuation.yield(.completed)
                return
            }

            var toolResults: [[String: Any]] = []
            for toolUse in turn.toolUses {
                let result = await tools.dispatch(toolUseId: toolUse.id, name: toolUse.name, input: toolUse.input)
                continuation.yield(.toolResult(result.content))
                toolResults.append([
                    "type": "tool_result",
                    "tool_use_id": result.toolUseId,
                    "content": result.content,
                ])
                if result.endsConversation {
                    messages.append(["role": "user", "content": toolResults])
                    continuation.yield(.endConversation)
                    return
                }
            }
            messages.append(["role": "user", "content": toolResults])
        }
        continuation.yield(.completed)
    }

    private func streamOnce(
        clientState: [String: Any]?,
        continuation: AsyncThrowingStream<ConversationAIEvent, Error>.Continuation
    ) async throws -> AnthropicTurn {
        let bytes = try await EdgeFunctions.shared.conversationStream(
            messages: messages,
            clientState: clientState
        )

        var assistantText = ""
        var toolBuffers: [Int: ToolUseBuffer] = [:]
        var toolUses: [ConversationToolUse] = []

        for try await line in bytes.lines {
            try Task.checkCancellation()
            guard line.hasPrefix("data: ") else { continue }
            let payload = String(line.dropFirst(6))
            guard payload != "[DONE]",
                  let data = payload.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = json["type"] as? String else {
                continue
            }

            switch type {
            case "content_block_start":
                if let index = json["index"] as? Int,
                   let block = json["content_block"] as? [String: Any],
                   (block["type"] as? String) == "tool_use",
                   let id = block["id"] as? String,
                   let name = block["name"] as? String {
                    toolBuffers[index] = ToolUseBuffer(id: id, name: name, inputJSON: "")
                }
            case "content_block_delta":
                guard let delta = json["delta"] as? [String: Any] else { continue }
                if (delta["type"] as? String) == "text_delta",
                   let text = delta["text"] as? String {
                    assistantText += text
                    continuation.yield(.textDelta(text))
                } else if (delta["type"] as? String) == "input_json_delta",
                          let index = json["index"] as? Int,
                          let partial = delta["partial_json"] as? String,
                          var buffer = toolBuffers[index] {
                    buffer.inputJSON += partial
                    toolBuffers[index] = buffer
                }
            case "content_block_stop":
                if let index = json["index"] as? Int,
                   let buffer = toolBuffers[index] {
                    toolUses.append(ConversationToolUse(id: buffer.id, name: buffer.name, input: parseToolInput(buffer.inputJSON)))
                }
            case "message_stop":
                break
            default:
                break
            }
        }

        var content: [[String: Any]] = []
        let trimmedText = assistantText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedText.isEmpty {
            content.append(["type": "text", "text": trimmedText])
        }
        for toolUse in toolUses {
            content.append([
                "type": "tool_use",
                "id": toolUse.id,
                "name": toolUse.name,
                "input": toolUse.input,
            ])
        }

        return AnthropicTurn(assistantContent: content, toolUses: toolUses)
    }

    private func parseToolInput(_ text: String) -> [String: Any] {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return json
    }
}

private struct AnthropicTurn {
    let assistantContent: [[String: Any]]
    let toolUses: [ConversationToolUse]
}

private struct ToolUseBuffer {
    let id: String
    let name: String
    var inputJSON: String
}

private struct ConversationToolUse {
    let id: String
    let name: String
    let input: [String: Any]
}
