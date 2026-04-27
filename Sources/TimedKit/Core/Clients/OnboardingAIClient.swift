// OnboardingAIClient.swift — Timed Core
// Opus-powered voice parsing for onboarding setup steps.
// Extracts structured data from natural language voice responses.
// Falls back silently when unavailable — caller keeps form-based input.

import Foundation
import SwiftUI

// MARK: - Result Types

struct NameResult { let name: String; let spoken: String }
struct WorkdayResult { let workdayHours: Int; let todayHours: Int?; let startHour: Int?; let endHour: Int?; let spoken: String }
struct CadenceResult { let cadenceIndex: Int; let spoken: String }  // 0=once, 1=twice, 2=3x, 3=4+
struct DefaultsResult { let replyMins: Int?; let actionMins: Int?; let callMins: Int?; let readMins: Int?; let spoken: String }
struct TransitResult { let chauffeur: Bool; let train: Bool; let plane: Bool; let drive: Bool; let spoken: String }

// MARK: - Client

@MainActor
final class OnboardingAIClient: ObservableObject {

    @Published private(set) var isProcessing: Bool = false

    /// Always available — proxied through anthropic-proxy Edge Function.
    var isAvailable: Bool { true }

    // MARK: - Step Extractors

    func extractName(_ transcript: String) async -> NameResult? {
        let tool: [String: Any] = [
            "name": "extract_name",
            "description": "Extract the user's first name from their spoken response.",
            "input_schema": [
                "type": "object",
                "properties": [
                    "name": ["type": "string", "description": "The user's first name."],
                    "spoken_response": ["type": "string", "description": "Short confirmation, e.g. 'Nice to meet you, Yasser.'"]
                ],
                "required": ["name", "spoken_response"]
            ]
        ]
        guard let result = await callWithTool(transcript, stepDesc: "The user was asked their name.", tool: tool) else { return nil }
        guard let name = result["name"] as? String, let spoken = result["spoken_response"] as? String else { return nil }
        return NameResult(name: name, spoken: spoken)
    }

    func extractWorkday(_ transcript: String) async -> WorkdayResult? {
        let tool: [String: Any] = [
            "name": "extract_workday",
            "description": "Extract work day configuration from the user's spoken response.",
            "input_schema": [
                "type": "object",
                "properties": [
                    "workday_hours": ["type": "integer", "description": "Typical work day length in hours. Default 9."],
                    "today_hours": ["type": "integer", "description": "Hours available today, if mentioned."],
                    "start_hour": ["type": "integer", "description": "Work start hour (24h format), if mentioned. e.g. 9 for 9am."],
                    "end_hour": ["type": "integer", "description": "Work end hour (24h format), if mentioned. e.g. 18 for 6pm."],
                    "spoken_response": ["type": "string", "description": "Confirm what you heard, e.g. 'Got it — 9 hour day, starting at 9, finishing at 6.'"]
                ],
                "required": ["workday_hours", "spoken_response"]
            ]
        ]
        guard let result = await callWithTool(transcript, stepDesc: "The user was asked how long their typical work day is, what hours they're available today, and when they start and finish.", tool: tool) else { return nil }
        guard let hours = result["workday_hours"] as? Int, let spoken = result["spoken_response"] as? String else { return nil }
        return WorkdayResult(
            workdayHours: hours,
            todayHours: result["today_hours"] as? Int,
            startHour: result["start_hour"] as? Int,
            endHour: result["end_hour"] as? Int,
            spoken: spoken
        )
    }

    func extractCadence(_ transcript: String) async -> CadenceResult? {
        let tool: [String: Any] = [
            "name": "extract_cadence",
            "description": "Extract email checking frequency from the user's spoken response.",
            "input_schema": [
                "type": "object",
                "properties": [
                    "cadence": [
                        "type": "string",
                        "enum": ["once", "twice", "three", "four_plus"],
                        "description": "How often they check email per day."
                    ],
                    "spoken_response": ["type": "string", "description": "Confirm, e.g. 'Three times a day — got it.'"]
                ],
                "required": ["cadence", "spoken_response"]
            ]
        ]
        guard let result = await callWithTool(transcript, stepDesc: "The user was asked how often they check email per day.", tool: tool) else { return nil }
        guard let cadence = result["cadence"] as? String, let spoken = result["spoken_response"] as? String else { return nil }
        let index: Int
        switch cadence {
        case "once": index = 0
        case "twice": index = 1
        case "three": index = 2
        case "four_plus": index = 3
        default: index = 2
        }
        return CadenceResult(cadenceIndex: index, spoken: spoken)
    }

    func extractDefaults(_ transcript: String) async -> DefaultsResult? {
        let tool: [String: Any] = [
            "name": "extract_defaults",
            "description": "Extract time default preferences from the user's spoken response.",
            "input_schema": [
                "type": "object",
                "properties": [
                    "reply_mins": ["type": "integer", "description": "Minutes for a quick email reply."],
                    "action_mins": ["type": "integer", "description": "Minutes for an email action item."],
                    "call_mins": ["type": "integer", "description": "Minutes for a phone call."],
                    "read_mins": ["type": "integer", "description": "Minutes for reading/reviewing a document."],
                    "spoken_response": ["type": "string", "description": "Confirm the defaults, e.g. '5 minutes for replies, 30 for actions, 15 for calls, 20 for reading.'"]
                ],
                "required": ["spoken_response"]
            ]
        ]
        guard let result = await callWithTool(transcript, stepDesc: "The user was asked about their time defaults: how long a quick reply, email action, phone call, and read/review typically take.", tool: tool) else { return nil }
        guard let spoken = result["spoken_response"] as? String else { return nil }
        return DefaultsResult(
            replyMins: result["reply_mins"] as? Int,
            actionMins: result["action_mins"] as? Int,
            callMins: result["call_mins"] as? Int,
            readMins: result["read_mins"] as? Int,
            spoken: spoken
        )
    }

    func extractTransit(_ transcript: String) async -> TransitResult? {
        let tool: [String: Any] = [
            "name": "extract_transit",
            "description": "Extract travel/transit preferences from the user's spoken response.",
            "input_schema": [
                "type": "object",
                "properties": [
                    "chauffeur": ["type": "boolean", "description": "Uses chauffeur or rideshare."],
                    "train": ["type": "boolean", "description": "Uses train or public transport."],
                    "plane": ["type": "boolean", "description": "Travels by plane."],
                    "drive": ["type": "boolean", "description": "Drives themselves."],
                    "spoken_response": ["type": "string", "description": "Confirm, e.g. 'So you're usually driven — got it.'"]
                ],
                "required": ["chauffeur", "train", "plane", "drive", "spoken_response"]
            ]
        ]
        guard let result = await callWithTool(transcript, stepDesc: "The user was asked how they typically travel/commute.", tool: tool) else { return nil }
        guard let spoken = result["spoken_response"] as? String else { return nil }
        return TransitResult(
            chauffeur: result["chauffeur"] as? Bool ?? false,
            train: result["train"] as? Bool ?? false,
            plane: result["plane"] as? Bool ?? false,
            drive: result["drive"] as? Bool ?? false,
            spoken: spoken
        )
    }

    // MARK: - Opus API

    private func callWithTool(_ transcript: String, stepDesc: String, tool: [String: Any]) async -> [String: Any]? {
        guard isAvailable else { return nil }

        isProcessing = true
        defer { isProcessing = false }

        let systemPrompt = """
        You are setting up a productivity app for a C-suite executive. They are answering setup questions by voice. Extract the structured data from their spoken response. If something is ambiguous, make a reasonable assumption and confirm in your spoken_response. Keep spoken_response under 20 words, warm and conversational.
        """

        guard let url = SupabaseEndpoints.functionURL("anthropic-proxy") else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(SupabaseEndpoints.authHeader, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15

        let toolName = (tool["name"] as? String) ?? "extract"

        let body: [String: Any] = [
            "model": "claude-opus-4-7",
            "max_tokens": 300,
            "system": [
                ["type": "text", "text": systemPrompt, "cache_control": ["type": "ephemeral"]]
            ],
            "messages": [
                ["role": "user", "content": "\(stepDesc) They said: \"\(transcript)\""]
            ],
            "tools": [tool],
            "tool_choice": ["type": "tool", "name": toolName]
        ]

        guard let httpBody = try? JSONSerialization.data(withJSONObject: body) else { return nil }
        request.httpBody = httpBody

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else { return nil }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let content = json["content"] as? [[String: Any]],
                  let toolBlock = content.first(where: { ($0["type"] as? String) == "tool_use" }),
                  let input = toolBlock["input"] as? [String: Any] else { return nil }

            return input
        } catch {
            return nil
        }
    }
}
