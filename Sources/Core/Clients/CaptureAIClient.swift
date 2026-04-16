// CaptureAIClient.swift — Timed Core
// Opus-powered intelligent task extraction from voice and text input.
// Replaces regex-based TranscriptParser when available. Falls back silently.

import Foundation
import SwiftUI

// MARK: - Types

struct CaptureContext: Sendable {
    let existingBuckets: [String]
    let calendarToday: [String]
    let recentTasks: [String]
}

struct ExtractedTask: Sendable {
    let title: String
    let duration: Int
    let bucket: String
    let dueDate: String?
    let priority: String?
    let spokenConfirmation: String
}

// MARK: - Client

@MainActor
final class CaptureAIClient: ObservableObject {

    @AppStorage("anthropic_api_key") private var apiKey: String = ""
    @Published private(set) var isProcessing: Bool = false

    var isAvailable: Bool { !apiKey.isEmpty }

    // MARK: - Extract Tasks

    func extractTasks(_ rawText: String, context: CaptureContext) async -> [ExtractedTask]? {
        guard isAvailable else { return nil }

        isProcessing = true
        defer { isProcessing = false }

        let systemPrompt = """
        You are an executive assistant extracting tasks from natural language input.
        The executive speaks naturally — extract structured task data from what they say.
        Multiple tasks may be mentioned in a single input — extract ALL of them.

        CONTEXT:
        - Available buckets: \(context.existingBuckets.joined(separator: ", "))
        - Today's calendar: \(context.calendarToday.joined(separator: "; "))
        - Recent tasks (for dedup): \(context.recentTasks.joined(separator: "; "))

        Use the extract_tasks tool to return structured results.
        """

        let tool: [String: Any] = [
            "name": "extract_tasks",
            "description": "Extract one or more structured tasks from the executive's natural language input.",
            "input_schema": [
                "type": "object",
                "properties": [
                    "tasks": [
                        "type": "array",
                        "items": [
                            "type": "object",
                            "properties": [
                                "title": [
                                    "type": "string",
                                    "description": "Clean, concise task title."
                                ],
                                "duration": [
                                    "type": "integer",
                                    "description": "Estimated minutes. Default 15 if not mentioned."
                                ],
                                "bucket": [
                                    "type": "string",
                                    "enum": ["action", "calls", "reply", "readToday", "readThisWeek", "transit", "waiting", "ccFyi"],
                                    "description": "Task category based on content."
                                ],
                                "due_date": [
                                    "type": "string",
                                    "description": "ISO date if mentioned, null otherwise."
                                ],
                                "priority": [
                                    "type": "string",
                                    "enum": ["high", "medium", "low"],
                                    "description": "Priority if inferable."
                                ],
                                "spoken_confirmation": [
                                    "type": "string",
                                    "description": "Short confirmation to speak back. Under 20 words."
                                ]
                            ],
                            "required": ["title", "duration", "bucket", "spoken_confirmation"]
                        ]
                    ]
                ],
                "required": ["tasks"]
            ]
        ]

        guard let url = URL(string: "https://api.anthropic.com/v1/messages") else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.timeoutInterval = 15

        let body: [String: Any] = [
            "model": "claude-opus-4-6",
            "max_tokens": 500,
            "system": [
                [
                    "type": "text",
                    "text": systemPrompt,
                    "cache_control": ["type": "ephemeral"]
                ]
            ],
            "messages": [
                ["role": "user", "content": "The executive said: \"\(rawText)\""]
            ],
            "tools": [tool],
            "tool_choice": ["type": "tool", "name": "extract_tasks"]
        ]

        guard let httpBody = try? JSONSerialization.data(withJSONObject: body) else { return nil }
        request.httpBody = httpBody

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return nil
            }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let content = json["content"] as? [[String: Any]],
                  let toolBlock = content.first(where: { ($0["type"] as? String) == "tool_use" }),
                  let input = toolBlock["input"] as? [String: Any],
                  let tasksArray = input["tasks"] as? [[String: Any]] else {
                return nil
            }

            return tasksArray.compactMap { dict -> ExtractedTask? in
                guard let title = dict["title"] as? String,
                      let duration = dict["duration"] as? Int,
                      let bucket = dict["bucket"] as? String,
                      let spoken = dict["spoken_confirmation"] as? String else {
                    return nil
                }
                return ExtractedTask(
                    title: title,
                    duration: duration,
                    bucket: bucket,
                    dueDate: dict["due_date"] as? String,
                    priority: dict["priority"] as? String,
                    spokenConfirmation: spoken
                )
            }
        } catch {
            return nil
        }
    }
}
