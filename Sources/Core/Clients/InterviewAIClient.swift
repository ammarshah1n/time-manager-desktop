// InterviewAIClient.swift — Timed Core
// Opus-powered conversational morning interview.
// Generates personalised speech using the executive's full knowledge profile (ACB + briefings).
// Falls back silently when unavailable — callers get nil and use hardcoded scripts.

import Dependencies
import Foundation
import SwiftUI

// MARK: - Public Types

struct StepContext: Sendable {
    let step: Int
    let deferredTasks: [(title: String, daysOld: Int)]
    let calendarBlocks: [(title: String, time: String, attendees: [String])]
    let availableMinutes: Int
    let meetingMinutes: Int
    let gapCount: Int
    let todayCandidates: [String]
    let confirmedTasks: [String]
    let confirmedTotal: Int
    let energyLevel: Int
    let interruptibility: String
    let assumptions: [(title: String, minutes: Int)]
    let userLastSaid: String
}

struct ResolvedIntent: Sendable {
    let action: String
    let value: Int?
    let index: Int?
    let description: String?
    let ordinal: Int?
    let minutes: Int?
    let spokenResponse: String
}

// MARK: - Client

@MainActor
final class InterviewAIClient: ObservableObject {

    @Published private(set) var isGenerating: Bool = false

    private var apiKey: String { KeychainStore.string(for: .anthropicAPIKey) }

    private var cachedACB: String?
    private var cachedBriefing: String?
    private var systemBlocks: [[String: Any]]?
    private var conversationMessages: [[String: Any]] = []
    private var contextLoaded: Bool = false

    var isAvailable: Bool { !apiKey.isEmpty }

    // MARK: - Context Loading

    /// Fetch ACB + today's briefing from Supabase. Call once when the interview opens.
    func loadContext() async {
        guard !contextLoaded else { return }

        // Fetch ACB-full
        do {
            let acbData = try await MemoryStoreActor.shared.activeContextBuffer(variant: .full)
            if let acbString = String(data: acbData, encoding: .utf8) {
                cachedACB = acbString
            }
        } catch {
            TimedLogger.voice.info("InterviewAI: ACB fetch failed — \(error.localizedDescription)")
        }

        // Fetch today's briefing
        @Dependency(\.supabaseClient) var supabaseClient
        if let client = supabaseClient.rawClient,
           let executiveId = AuthService.shared.executiveId {
            let today = Date().formatted(.iso8601.year().month().day().dateSeparator(.dash))
            do {
                let briefing: MorningBriefing = try await client
                    .from("briefings")
                    .select()
                    .eq("profile_id", value: executiveId.uuidString)
                    .eq("date", value: today)
                    .single()
                    .execute()
                    .value
                let encoder = JSONEncoder()
                encoder.outputFormatting = .sortedKeys
                if let data = try? encoder.encode(briefing.content.sections),
                   let json = String(data: data, encoding: .utf8) {
                    cachedBriefing = json
                }
            } catch {
                TimedLogger.voice.info("InterviewAI: Briefing fetch failed — \(error.localizedDescription)")
            }
        }

        buildSystemBlocks()
        contextLoaded = true
    }

    // MARK: - Generate Step Prompt

    /// Generate Opus speech for a step. Returns nil on failure (caller uses hardcoded fallback).
    func generateStepPrompt(step: Int, context: StepContext) async -> String? {
        guard isAvailable else { return nil }
        if systemBlocks == nil { buildSystemBlocks() }

        isGenerating = true
        defer { isGenerating = false }

        let userMessage = buildStepMessage(context)
        conversationMessages.append(["role": "user", "content": userMessage])

        guard let responseText = await callOpus(useTools: false) else {
            conversationMessages.removeLast()
            return nil
        }

        conversationMessages.append(["role": "assistant", "content": responseText])
        return responseText
    }

    // MARK: - Resolve Unknown

    /// Resolve an unknown transcript using Opus tool use. Returns nil on failure.
    func resolveUnknown(transcript: String, step: Int) async -> ResolvedIntent? {
        guard isAvailable else { return nil }
        if systemBlocks == nil { buildSystemBlocks() }

        isGenerating = true
        defer { isGenerating = false }

        let message = """
        The executive just said: "\(transcript)"
        We are on step \(step). Interpret their intent and respond.
        Use the resolve_intent tool to indicate what action to take.
        """
        conversationMessages.append(["role": "user", "content": message])

        guard let data = await callOpusRaw(useTools: true) else {
            conversationMessages.removeLast()
            return nil
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]] else {
            conversationMessages.removeLast()
            return nil
        }

        // Look for tool_use block
        if let toolBlock = content.first(where: { ($0["type"] as? String) == "tool_use" }),
           let input = toolBlock["input"] as? [String: Any],
           let action = input["action"] as? String,
           let spoken = input["spoken_response"] as? String {
            let params = input["parameters"] as? [String: Any] ?? [:]

            conversationMessages.append(["role": "assistant", "content": spoken])

            return ResolvedIntent(
                action: action,
                value: params["value"] as? Int,
                index: params["index"] as? Int,
                description: params["description"] as? String,
                ordinal: params["ordinal"] as? Int,
                minutes: params["minutes"] as? Int,
                spokenResponse: spoken
            )
        }

        // Fallback: check for text response
        if let textBlock = content.first(where: { ($0["type"] as? String) == "text" }),
           let text = textBlock["text"] as? String {
            conversationMessages.append(["role": "assistant", "content": text])
            return ResolvedIntent(action: "unclear", value: nil, index: nil, description: nil, ordinal: nil, minutes: nil, spokenResponse: text)
        }

        conversationMessages.removeLast()
        return nil
    }

    // MARK: - Reset

    /// Clear conversation history for next interview session.
    func reset() {
        conversationMessages.removeAll()
        contextLoaded = false
        cachedACB = nil
        cachedBriefing = nil
        systemBlocks = nil
    }

    // MARK: - Private

    private func buildSystemBlocks() {
        let acbSection = cachedACB.map { "\n\nEXECUTIVE KNOWLEDGE PROFILE:\n<acb>\n\($0)\n</acb>" } ?? ""
        let briefingSection = cachedBriefing.map { "\n\nTODAY'S INTELLIGENCE BRIEFING:\n<briefing>\n\($0)\n</briefing>" } ?? ""

        let prompt = """
        You are the morning voice assistant for a C-suite executive. You speak in short, natural British English — warm but efficient. Two to three sentences maximum per response.

        You are conducting a 7-step morning planning session. Generate ONLY the speech text — no markdown, no labels, no JSON. Just the words to speak aloud.

        RULES:
        - Under 60 words per response
        - Reference what you know about the executive naturally — patterns, tendencies, relationships
        - Never say "based on your data", "my analysis shows", or "according to records"
        - Speak like a trusted chief of staff who has worked with this person for years
        - Name meetings, tasks, and people by their actual names
        - If you notice avoidance patterns or cognitive biases, mention them gently
        - First response (step 0 or step 1 if no deferrals) should include a greeting

        STEP GUIDE:
        0: Deferred tasks — name them, note how many days deferred, flag avoidance if relevant
        1: Calendar + free time — narrate meetings with attendees and times, state free time
        2: Energy level — ask how they're feeling, reference energy patterns if known
        3: Interruptions — ask about expected interruptions
        4: Due today — name the tasks, highlight relationship or deadline relevance
        5: Time estimates — state top estimates, flag any that historically overrun
        6: Confirm — task count, total time vs free time, ask to lock it in\(acbSection)\(briefingSection)
        """

        systemBlocks = [
            [
                "type": "text",
                "text": prompt,
                "cache_control": ["type": "ephemeral"]
            ]
        ]
    }

    private func buildStepMessage(_ context: StepContext) -> String {
        var parts: [String] = ["Step \(context.step)."]

        if !context.deferredTasks.isEmpty {
            let items = context.deferredTasks.map { "\($0.title) (\($0.daysOld)d)" }.joined(separator: ", ")
            parts.append("Deferred: \(items).")
        }

        if !context.calendarBlocks.isEmpty {
            let items = context.calendarBlocks.map { block in
                let attendees = block.attendees.isEmpty ? "" : " with \(block.attendees.joined(separator: ", "))"
                return "\(block.title)\(attendees) at \(block.time)"
            }.joined(separator: "; ")
            parts.append("Calendar: \(items).")
        }

        parts.append("Free time: \(context.availableMinutes) minutes. Meetings: \(context.meetingMinutes) minutes. Gaps: \(context.gapCount).")

        if !context.todayCandidates.isEmpty {
            parts.append("Tasks today: \(context.todayCandidates.joined(separator: ", ")).")
        }

        if !context.confirmedTasks.isEmpty {
            parts.append("Confirmed: \(context.confirmedTasks.joined(separator: ", ")). Total: \(context.confirmedTotal) min.")
        }

        parts.append("Energy: \(context.energyLevel)/10. Interruptions: \(context.interruptibility).")

        if !context.assumptions.isEmpty {
            let items = context.assumptions.map { "\($0.title): \($0.minutes)m" }.joined(separator: ", ")
            parts.append("Estimates: \(items).")
        }

        if !context.userLastSaid.isEmpty {
            parts.append("Executive just said: \"\(context.userLastSaid)\"")
        }

        return parts.joined(separator: " ")
    }

    // MARK: - Anthropic API

    private func callOpus(useTools: Bool) async -> String? {
        guard let data = await callOpusRaw(useTools: useTools) else { return nil }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              let textBlock = content.first(where: { ($0["type"] as? String) == "text" }),
              let text = textBlock["text"] as? String else {
            return nil
        }
        return text
    }

    private func callOpusRaw(useTools: Bool) async -> Data? {
        guard let url = URL(string: "https://api.anthropic.com/v1/messages") else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.timeoutInterval = 20

        var body: [String: Any] = [
            "model": "claude-opus-4-6",
            "max_tokens": 300,
            "system": systemBlocks ?? [],
            "messages": conversationMessages
        ]

        if useTools {
            body["tools"] = [resolveIntentTool]
            body["tool_choice"] = ["type": "tool", "name": "resolve_intent"]
        }

        guard let httpBody = try? JSONSerialization.data(withJSONObject: body) else { return nil }
        request.httpBody = httpBody

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return nil
            }
            return data
        } catch {
            TimedLogger.voice.error("InterviewAI: Opus call failed — \(error.localizedDescription)")
            return nil
        }
    }

    private var resolveIntentTool: [String: Any] {
        [
            "name": "resolve_intent",
            "description": "Interpret the executive's spoken response and determine what action to take.",
            "input_schema": [
                "type": "object",
                "properties": [
                    "action": [
                        "type": "string",
                        "enum": [
                            "affirmative", "negative", "number", "adjustEndTime", "subtractTime",
                            "removeItem", "addTask", "moveToTomorrow", "estimateOverride",
                            "skip", "done", "repeat", "goBack", "undo", "unclear"
                        ],
                        "description": "The intent behind the executive's response."
                    ],
                    "parameters": [
                        "type": "object",
                        "description": "Action parameters: value (Int) for number/adjustEndTime/subtractTime, index (Int) for removeItem, description (String) for addTask, ordinal + minutes (Int) for estimateOverride.",
                        "properties": [
                            "value": ["type": "integer"],
                            "index": ["type": "integer"],
                            "description": ["type": "string"],
                            "ordinal": ["type": "integer"],
                            "minutes": ["type": "integer"]
                        ]
                    ],
                    "spoken_response": [
                        "type": "string",
                        "description": "What to say back to the executive — confirmation, clarification, or follow-up. Under 30 words, conversational British English."
                    ]
                ],
                "required": ["action", "spoken_response"]
            ]
        ]
    }
}
