import Foundation
import Observation
import SwiftUI

struct QuizSessionSummary: Hashable {
    let attemptedCount: Int
    let correctCount: Int
    let confidenceDeltaPercent: Int
    let updatedConfidence: Int
}

struct QuizQuestion: Identifiable, Hashable, Codable {
    let id: UUID
    let question: String
    let options: [String]
    let correctIndex: Int
    let explanation: String
    let sourceTitle: String

    init(
        id: UUID = UUID(),
        question: String,
        options: [String],
        correctIndex: Int,
        explanation: String,
        sourceTitle: String
    ) {
        self.id = id
        self.question = question
        self.options = options
        self.correctIndex = correctIndex
        self.explanation = explanation
        self.sourceTitle = sourceTitle
    }
}

struct QuizAnswerRecord: Identifiable, Hashable {
    let id: UUID
    let question: QuizQuestion
    let selectedOptionIndex: Int?
    let freeformAnswer: String
    let isCorrect: Bool

    init(
        id: UUID = UUID(),
        question: QuizQuestion,
        selectedOptionIndex: Int?,
        freeformAnswer: String,
        isCorrect: Bool
    ) {
        self.id = id
        self.question = question
        self.selectedOptionIndex = selectedOptionIndex
        self.freeformAnswer = freeformAnswer
        self.isCorrect = isCorrect
    }
}

enum QuizSessionPhase {
    case intro
    case loading
    case question
    case feedback
    case summary
}

@MainActor
@Observable
final class QuizSessionModel {
    let task: TaskItem
    let documents: [ContextDocument]
    let transcriptContexts: [ContextItem]

    var phase: QuizSessionPhase = .intro
    var questions: [QuizQuestion] = []
    var history: [QuizAnswerRecord] = []
    var currentQuestionIndex = 0
    var selectedOptionIndex: Int?
    var freeformAnswer = ""
    var errorText: String?
    var isGenerating = false

    @ObservationIgnored private let runner: @Sendable (CodexRunRequest) async -> String?
    @ObservationIgnored private let workingRoot: String
    @ObservationIgnored private let additionalRoots: [String]
    @ObservationIgnored private let autonomousMode: Bool

    init(
        task: TaskItem,
        documents: [ContextDocument],
        contexts: [ContextItem],
        workingRoot: String,
        additionalRoots: [String],
        autonomousMode: Bool,
        runner: @escaping @Sendable (CodexRunRequest) async -> String?
    ) {
        self.task = task
        self.documents = documents
        self.transcriptContexts = contexts.filter { $0.kind.caseInsensitiveCompare("Obsidian") != .orderedSame }
        self.workingRoot = workingRoot
        self.additionalRoots = additionalRoots
        self.autonomousMode = autonomousMode
        self.runner = runner
    }

    var subject: String { task.subject }
    var initialConfidence: Int { task.confidence }
    var currentQuestion: QuizQuestion? {
        guard questions.indices.contains(currentQuestionIndex) else { return nil }
        return questions[currentQuestionIndex]
    }

    var hasGroundedMaterial: Bool {
        !documents.isEmpty || !transcriptContexts.isEmpty
    }

    var attemptedCount: Int { history.count }
    var correctCount: Int { history.filter(\.isCorrect).count }

    var confidenceDeltaPercent: Int {
        guard attemptedCount > 0 else { return 0 }
        let ratio = Double(correctCount) / Double(attemptedCount)
        let raw = (ratio - 0.5) * 20
        return max(-10, min(10, Int(raw.rounded())))
    }

    var updatedConfidence: Int {
        let rawValue = Double(initialConfidence) + (Double(confidenceDeltaPercent) / 10.0)
        return max(1, min(5, Int(rawValue.rounded())))
    }

    var summary: QuizSessionSummary {
        QuizSessionSummary(
            attemptedCount: attemptedCount,
            correctCount: correctCount,
            confidenceDeltaPercent: confidenceDeltaPercent,
            updatedConfidence: updatedConfidence
        )
    }

    var progressText: String {
        let questionNumber = min(currentQuestionIndex + 1, max(questions.count, 1))
        return "Question \(questionNumber) of \(max(questions.count, 1))"
    }

    func beginSession() async {
        await generateQuestions(count: 5)
    }

    func submitAnswer() {
        guard let currentQuestion else { return }

        let isCorrect = selectedOptionIndex == currentQuestion.correctIndex
        history.append(
            QuizAnswerRecord(
                question: currentQuestion,
                selectedOptionIndex: selectedOptionIndex,
                freeformAnswer: freeformAnswer.trimmingCharacters(in: .whitespacesAndNewlines),
                isCorrect: isCorrect
            )
        )
        phase = .feedback
    }

    func advanceAfterFeedback() async {
        if currentQuestionIndex + 1 < questions.count {
            currentQuestionIndex += 1
            resetAnswerState()
            phase = .question
            return
        }

        if attemptedCount >= 5 {
            phase = .summary
            return
        }

        await generateQuestions(count: max(5 - attemptedCount, 1))
    }

    func keepGoing() async {
        await generateQuestions(count: 5)
    }

    private func resetAnswerState() {
        selectedOptionIndex = nil
        freeformAnswer = ""
        errorText = nil
    }

    private func generateQuestions(count: Int) async {
        guard hasGroundedMaterial else {
            errorText = "No grounded Obsidian or transcript context is loaded for \(subject)."
            phase = .intro
            return
        }

        isGenerating = true
        errorText = nil
        phase = .loading

        let response = await runner(
            CodexRunRequest(
                prompt: buildQuestionPrompt(questionCount: count),
                autonomousMode: autonomousMode,
                workingRoot: workingRoot,
                additionalRoots: additionalRoots
            )
        )

        isGenerating = false

        guard let response, let parsedQuestions = Self.parseQuestions(from: response), !parsedQuestions.isEmpty else {
            errorText = "Timed could not generate grounded quiz questions for \(subject)."
            phase = history.isEmpty ? .intro : .summary
            return
        }

        questions = parsedQuestions
        currentQuestionIndex = 0
        resetAnswerState()
        phase = .question
    }

    private func buildQuestionPrompt(questionCount: Int) -> String {
        let noteBlocks = documents.prefix(3).map { document in
            """
            [Obsidian] \(document.title)
            Path: \(document.path)
            Content:
            \(Self.truncated(document.content, limit: 2_400))
            """
        }.joined(separator: "\n\n")

        let transcriptBlocks = transcriptContexts.prefix(6).map { context in
            """
            [\(context.kind)] \(context.title)
            Summary:
            \(context.summary)

            Detail:
            \(Self.truncated(context.detail, limit: 1_600))
            """
        }.joined(separator: "\n\n")

        let recentQuestions = history.prefix(8).map { record in
            let selectedAnswer = record.selectedOptionIndex.flatMap { index in
                record.question.options.indices.contains(index) ? record.question.options[index] : nil
            } ?? "No multiple-choice answer"

            let freeform = record.freeformAnswer.isEmpty ? "None" : record.freeformAnswer
            return """
            - Question: \(record.question.question)
              Student option: \(selectedAnswer)
              Student free-form: \(freeform)
              Correct: \(record.isCorrect ? "yes" : "no")
            """
        }.joined(separator: "\n")

        let allowedSources = (documents.map(\.title) + transcriptContexts.map(\.title)).joined(separator: " | ")

        return """
        You are generating study quiz questions for a school student.
        Use ONLY the grounded material below.
        Return raw JSON only. No markdown fences. No prose before or after the JSON.

        Return this exact shape:
        {
          "questions": [
            {
              "question": "Question text",
              "options": ["Option A", "Option B", "Option C", "Option D"],
              "correctIndex": 0,
              "explanation": "One or two sentence explanation.",
              "source": "Exact source title"
            }
          ]
        }

        Rules:
        - Generate exactly \(questionCount) questions.
        - Every question must have exactly 4 options.
        - correctIndex must be 0, 1, 2, or 3.
        - source must exactly match one of these titles: \(allowedSources)
        - Use school-level wording for \(subject).
        - Prefer the selected task when choosing topics: \(task.title).
        - Avoid repeating prior questions.
        - Ground every explanation in the provided notes only.

        Top Obsidian notes:
        \(noteBlocks.isEmpty ? "None loaded." : noteBlocks)

        Transcript and other grounded context:
        \(transcriptBlocks.isEmpty ? "None loaded." : transcriptBlocks)

        Prior questions to avoid:
        \(recentQuestions.isEmpty ? "None yet." : recentQuestions)
        """
    }

    nonisolated static func parseQuestions(from response: String) -> [QuizQuestion]? {
        for candidate in jsonCandidates(from: response) {
            if let questions = decodeEnvelope(from: candidate) {
                return questions
            }

            if let questions = decodeArray(from: candidate) {
                return questions
            }
        }

        return nil
    }

    private nonisolated static func decodeEnvelope(from candidate: String) -> [QuizQuestion]? {
        guard let data = candidate.data(using: .utf8) else { return nil }
        guard let envelope = try? JSONDecoder().decode(QuizQuestionEnvelope.self, from: data) else { return nil }
        let questions = envelope.questions.compactMap(\.resolvedQuestion)
        return questions.isEmpty ? nil : questions
    }

    private nonisolated static func decodeArray(from candidate: String) -> [QuizQuestion]? {
        guard let data = candidate.data(using: .utf8) else { return nil }
        guard let payloads = try? JSONDecoder().decode([QuizQuestionPayload].self, from: data) else { return nil }
        let questions = payloads.compactMap(\.resolvedQuestion)
        return questions.isEmpty ? nil : questions
    }

    private nonisolated static func jsonCandidates(from response: String) -> [String] {
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
        var candidates: [String] = [trimmed]

        if let fenceStart = trimmed.range(of: "```"), let fenceEnd = trimmed.range(of: "```", options: .backwards), fenceStart.lowerBound != fenceEnd.lowerBound {
            let fencedBody = trimmed[fenceStart.upperBound..<fenceEnd.lowerBound]
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "json\n", with: "")
            candidates.append(fencedBody)
        }

        if let objectStart = trimmed.firstIndex(of: "{"), let objectEnd = trimmed.lastIndex(of: "}") {
            candidates.append(String(trimmed[objectStart...objectEnd]))
        }

        if let arrayStart = trimmed.firstIndex(of: "["), let arrayEnd = trimmed.lastIndex(of: "]") {
            candidates.append(String(trimmed[arrayStart...arrayEnd]))
        }

        return Array(Set(candidates.filter { !$0.isEmpty }))
    }

    private nonisolated static func truncated(_ text: String, limit: Int) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > limit else { return trimmed }
        return String(trimmed.prefix(limit)) + "…"
    }
}

struct QuizView: View {
    @Bindable var session: QuizSessionModel
    let onClose: () -> Void
    let onEndSession: (QuizSessionSummary) -> Void

    var body: some View {
        ZStack {
            TimedVisualEffectBackground(material: .fullScreenUI, blendingMode: .behindWindow)
                .ignoresSafeArea()

            LinearGradient(
                colors: [
                    Color.black.opacity(0.86),
                    Color(red: 0.10, green: 0.12, blue: 0.18).opacity(0.92),
                    Color.black.opacity(0.88)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Color.black.opacity(0.28)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                header

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        switch session.phase {
                        case .intro:
                            introCard
                        case .loading:
                            loadingCard
                        case .question:
                            questionCard
                        case .feedback:
                            feedbackCard
                        case .summary:
                            summaryCard
                        }
                    }
                    .padding(.horizontal, 28)
                    .padding(.bottom, 28)
                }
                .scrollIndicators(.hidden)
            }
            .padding(.top, 22)
            .padding(.bottom, 18)
        }
        .transition(.opacity)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Study Session")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.58))
                    .textCase(.uppercase)
                    .tracking(1.1)

                Text(session.subject)
                    .font(.custom("Fraunces", size: 36))
                    .fontWeight(.bold)
                    .foregroundStyle(.white)

                Text(session.task.title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white.opacity(0.72))
            }

            Spacer()

            HStack(spacing: 10) {
                statChip(title: "Confidence", value: "\(session.initialConfidence)/5")
                statChip(title: "Correct", value: "\(session.correctCount)/\(max(session.attemptedCount, 1))")

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white.opacity(0.82))
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(Color.white.opacity(0.10)))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 22)
    }

    private var introCard: some View {
        TimedCard(title: "Ready to study", icon: "graduationcap.fill") {
            VStack(alignment: .leading, spacing: 18) {
                Text("Timed will generate a 5-question quiz using the top Obsidian notes and grounded transcript context for this subject.")
                    .font(.system(size: 15))
                    .foregroundStyle(.white.opacity(0.78))

                HStack(spacing: 12) {
                    statPanel(title: "Top notes", value: "\(session.documents.count)")
                    statPanel(title: "Transcript items", value: "\(session.transcriptContexts.count)")
                    statPanel(title: "Baseline confidence", value: "\(session.initialConfidence)/5")
                }

                if let errorText = session.errorText {
                    Text(errorText)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.red.opacity(0.92))
                }

                HStack(spacing: 10) {
                    Button("Start Quiz") {
                        Task { await session.beginSession() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!session.hasGroundedMaterial || session.isGenerating)

                    Button("Close", action: onClose)
                        .buttonStyle(.bordered)
                }
            }
        }
        .frame(maxWidth: 920)
    }

    private var loadingCard: some View {
        TimedCard(title: "Generating questions", icon: "sparkles") {
            VStack(alignment: .leading, spacing: 16) {
                ProgressView()
                    .controlSize(.regular)

                Text("Timed is grounding new questions from the selected notes and transcript context.")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.76))
            }
        }
        .frame(maxWidth: 920)
    }

    private var questionCard: some View {
        TimedCard(title: session.progressText, icon: "list.bullet.rectangle") {
            VStack(alignment: .leading, spacing: 18) {
                if let currentQuestion = session.currentQuestion {
                    Text(currentQuestion.question)
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(.white)

                    VStack(spacing: 12) {
                        ForEach(Array(currentQuestion.options.enumerated()), id: \.offset) { index, option in
                            optionButton(
                                index: index,
                                text: option,
                                isSelected: session.selectedOptionIndex == index,
                                feedbackState: .neutral
                            ) {
                                session.selectedOptionIndex = index
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Free-form answer")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.58))

                        TextField("Optional short answer or why you chose that option", text: $session.freeformAnswer, axis: .vertical)
                            .textFieldStyle(.plain)
                            .font(.system(size: 14))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .background(inputBackground)
                    }

                    HStack(spacing: 10) {
                        Button("Submit") {
                            session.submitAnswer()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(session.selectedOptionIndex == nil)

                        Text(currentQuestion.sourceTitle)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.54))
                    }
                }
            }
        }
        .frame(maxWidth: 920)
    }

    private var feedbackCard: some View {
        TimedCard(title: session.progressText, icon: "checkmark.circle") {
            VStack(alignment: .leading, spacing: 18) {
                if
                    let currentQuestion = session.currentQuestion,
                    let lastRecord = session.history.last
                {
                    Text(currentQuestion.question)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(.white)

                    VStack(spacing: 12) {
                        ForEach(Array(currentQuestion.options.enumerated()), id: \.offset) { index, option in
                            optionButton(
                                index: index,
                                text: option,
                                isSelected: lastRecord.selectedOptionIndex == index,
                                feedbackState: feedbackState(for: index, question: currentQuestion, selectedIndex: lastRecord.selectedOptionIndex)
                            ) { }
                            .disabled(true)
                        }
                    }

                    TimedCard(title: lastRecord.isCorrect ? "Correct" : "Review", icon: lastRecord.isCorrect ? "checkmark.seal.fill" : "xmark.octagon.fill") {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Answer: \(currentQuestion.options[currentQuestion.correctIndex])")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.white)

                            Text(currentQuestion.explanation)
                                .font(.system(size: 14))
                                .foregroundStyle(.white.opacity(0.78))

                            Text("Source note: \(currentQuestion.sourceTitle)")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.white.opacity(0.56))
                        }
                    }

                    HStack(spacing: 10) {
                        Button(session.currentQuestionIndex + 1 >= session.questions.count ? "View Summary" : "Next Question") {
                            Task { await session.advanceAfterFeedback() }
                        }
                        .buttonStyle(.borderedProminent)

                        statChip(
                            title: "Confidence delta",
                            value: deltaText(session.confidenceDeltaPercent),
                            tint: deltaColor(session.confidenceDeltaPercent)
                        )
                    }
                }
            }
        }
        .frame(maxWidth: 920)
    }

    private var summaryCard: some View {
        TimedCard(title: "Session Summary", icon: "chart.bar.fill") {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 12) {
                    statPanel(title: "Score", value: "\(session.correctCount)/\(session.attemptedCount)")
                    statPanel(title: "Confidence delta", value: deltaText(session.confidenceDeltaPercent))
                    statPanel(title: "New confidence", value: "\(session.updatedConfidence)/5")
                }

                Text("Timed will write the updated confidence back into the planner when you end this session.")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.76))

                HStack(spacing: 10) {
                    Button("End Session") {
                        onEndSession(session.summary)
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Keep Going") {
                        Task { await session.keepGoing() }
                    }
                    .buttonStyle(.bordered)

                    Button("Close", action: onClose)
                        .buttonStyle(.bordered)
                }
            }
        }
        .frame(maxWidth: 920)
    }

    private func statChip(title: String, value: String, tint: Color = .white.opacity(0.12)) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.56))
                .textCase(.uppercase)
            Text(value)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(tint)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
    }

    private func statPanel(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.56))
                .textCase(.uppercase)
                .tracking(1)

            Text(value)
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(inputBackground)
    }

    private func optionButton(
        index: Int,
        text: String,
        isSelected: Bool,
        feedbackState: QuizOptionFeedbackState,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                Text(letter(for: index))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Color.white.opacity(0.12)))

                Text(text)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(optionBackground(isSelected: isSelected, feedbackState: feedbackState))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(optionBorder(isSelected: isSelected, feedbackState: feedbackState), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func optionBackground(isSelected: Bool, feedbackState: QuizOptionFeedbackState) -> some View {
        let fillColor: Color
        switch feedbackState {
        case .neutral:
            fillColor = isSelected ? Color.white.opacity(0.16) : Color.white.opacity(0.08)
        case .correct:
            fillColor = Color.green.opacity(0.24)
        case .incorrect:
            fillColor = Color.red.opacity(0.24)
        }

        return RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(fillColor)
    }

    private func optionBorder(isSelected: Bool, feedbackState: QuizOptionFeedbackState) -> Color {
        switch feedbackState {
        case .neutral:
            return Color.white.opacity(isSelected ? 0.22 : 0.10)
        case .correct:
            return Color.green.opacity(0.9)
        case .incorrect:
            return Color.red.opacity(0.9)
        }
    }

    private func feedbackState(for index: Int, question: QuizQuestion, selectedIndex: Int?) -> QuizOptionFeedbackState {
        if index == question.correctIndex {
            return .correct
        }
        if index == selectedIndex {
            return .incorrect
        }
        return .neutral
    }

    private func deltaText(_ value: Int) -> String {
        value >= 0 ? "+\(value)%" : "\(value)%"
    }

    private func deltaColor(_ value: Int) -> Color {
        if value > 0 {
            return Color.green.opacity(0.24)
        }
        if value < 0 {
            return Color.red.opacity(0.24)
        }
        return Color.white.opacity(0.12)
    }

    private func letter(for index: Int) -> String {
        guard let scalar = UnicodeScalar(65 + index) else { return "A" }
        return String(Character(scalar))
    }

    private var inputBackground: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Color.white.opacity(0.08))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
            )
    }
}

private enum QuizOptionFeedbackState {
    case neutral
    case correct
    case incorrect
}

private struct QuizQuestionEnvelope: Decodable {
    let questions: [QuizQuestionPayload]
}

private struct QuizQuestionPayload: Decodable {
    let question: String
    let options: [String]
    let correctIndex: Int?
    let correct: IntOrStringValue?
    let explanation: String
    let source: String

    var resolvedQuestion: QuizQuestion? {
        let normalizedOptions = options
            .map(Self.normalizedOption)
            .filter { !$0.isEmpty }
            .prefix(4)

        guard normalizedOptions.count == 4 else { return nil }
        let resolvedOptions = Array(normalizedOptions)
        guard let resolvedCorrectIndex = resolveCorrectIndex(using: resolvedOptions), resolvedOptions.indices.contains(resolvedCorrectIndex) else {
            return nil
        }

        return QuizQuestion(
            question: question.trimmingCharacters(in: .whitespacesAndNewlines),
            options: resolvedOptions,
            correctIndex: resolvedCorrectIndex,
            explanation: explanation.trimmingCharacters(in: .whitespacesAndNewlines),
            sourceTitle: source.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private func resolveCorrectIndex(using normalizedOptions: [String]) -> Int? {
        if let correctIndex, normalizedOptions.indices.contains(correctIndex) {
            return correctIndex
        }

        if let correct {
            switch correct {
            case let .int(value):
                return normalizedOptions.indices.contains(value) ? value : nil
            case let .string(value):
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if let index = Self.index(forLetter: trimmed) {
                    return normalizedOptions.indices.contains(index) ? index : nil
                }

                let normalizedValue = Self.normalizedOption(trimmed)
                return normalizedOptions.firstIndex(where: {
                    Self.normalizedOption($0).caseInsensitiveCompare(normalizedValue) == .orderedSame
                })
            }
        }

        return nil
    }

    private static func normalizedOption(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let scalars = Array(trimmed.unicodeScalars)
        guard scalars.count >= 2 else { return trimmed }

        let first = scalars[0]
        let second = scalars[1]
        if CharacterSet.letters.contains(first), second == "." || second == ")" || second == ":" {
            return String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return trimmed
    }

    private static func index(forLetter value: String) -> Int? {
        let uppercased = value.uppercased()
        switch uppercased {
        case "A":
            return 0
        case "B":
            return 1
        case "C":
            return 2
        case "D":
            return 3
        default:
            return nil
        }
    }
}

private enum IntOrStringValue: Decodable {
    case int(Int)
    case string(String)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let intValue = try? container.decode(Int.self) {
            self = .int(intValue)
            return
        }
        self = .string(try container.decode(String.self))
    }
}
