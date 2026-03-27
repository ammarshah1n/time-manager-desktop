import Foundation
import Testing

@testable import time_manager_desktop

@Suite("Quiz sessions")
struct QuizSessionTests {
    @Test("testQuizQuestionParsingHandlesJSONEnvelope")
    func testQuizQuestionParsingHandlesJSONEnvelope() {
        let response = """
        {
          "questions": [
            {
              "question": "What does PED measure?",
              "options": ["Consumer spending", "Responsiveness of quantity demanded to price", "Business profit", "Government revenue"],
              "correctIndex": 1,
              "explanation": "Price elasticity of demand measures how quantity demanded changes when price changes.",
              "source": "PED notes"
            }
          ]
        }
        """

        let questions = QuizSessionModel.parseQuestions(from: response)

        #expect(questions?.count == 1)
        #expect(questions?.first?.correctIndex == 1)
        #expect(questions?.first?.sourceTitle == "PED notes")
    }

    @Test("testQuizConfidenceDeltaUpdatesSummary")
    @MainActor
    func testQuizConfidenceDeltaUpdatesSummary() {
        let task = TaskItem(
            id: "economics-test",
            title: "Economics test",
            list: "Seqta",
            source: .seqta,
            subject: "Economics",
            estimateMinutes: 45,
            confidence: 3,
            importance: 5,
            dueDate: nil,
            notes: "Revise PED and surplus.",
            energy: .high,
            isCompleted: false,
            completedAt: nil
        )

        let model = QuizSessionModel(
            task: task,
            documents: [
                ContextDocument(
                    id: "doc-1",
                    subject: "Economics",
                    title: "PED notes",
                    content: "Elasticity content",
                    path: "/tmp/ped.md",
                    importedAt: .now
                )
            ],
            contexts: [],
            workingRoot: "/tmp",
            additionalRoots: [],
            autonomousMode: false,
            runner: { _ in nil },
            loadStoredQuestions: { _ in [] },
            loadDueQuestions: { _, _ in [] },
            replaceStoredQuestions: { _, _ in },
            reviewStoredQuestion: { _, question, _, _ in question },
            nextReviewDays: { _, _ in nil }
        )

        let question = QuizQuestion(
            question: "What does PED measure?",
            options: ["A", "B", "C", "D"],
            correctIndex: 1,
            explanation: "Explanation",
            sourceTitle: "PED notes"
        )

        model.history = [
            QuizAnswerRecord(question: question, selectedOptionIndex: 1, freeformAnswer: "", isCorrect: true, qualityScore: 5),
            QuizAnswerRecord(question: question, selectedOptionIndex: 1, freeformAnswer: "", isCorrect: true, qualityScore: 4),
            QuizAnswerRecord(question: question, selectedOptionIndex: 1, freeformAnswer: "", isCorrect: true, qualityScore: 4),
            QuizAnswerRecord(question: question, selectedOptionIndex: 2, freeformAnswer: "", isCorrect: false, qualityScore: 1),
            QuizAnswerRecord(question: question, selectedOptionIndex: 1, freeformAnswer: "", isCorrect: true, qualityScore: 5)
        ]

        #expect(model.summary.attemptedCount == 5)
        #expect(model.summary.correctCount == 4)
        #expect(abs(model.summary.averageQuality - 3.8) < 0.0001)
        #expect(model.summary.confidenceDeltaPercent == 16)
        #expect(model.summary.updatedConfidence == 4)
        #expect(model.summary.updatedConfidencePercent == 76)
    }

    @Test("testSpacedRepetitionReviewUpdatesInterval")
    func testSpacedRepetitionReviewUpdatesInterval() {
        let now = ISO8601DateFormatter().date(from: "2026-03-27T08:00:00Z") ?? .now
        let question = QuizQuestion(
            question: "What is aggregate demand?",
            options: ["A", "B", "C", "D"],
            correctIndex: 0,
            explanation: "Explanation",
            sourceTitle: "Macro notes",
            easeFactor: 2.5,
            interval: 1,
            nextDue: now
        )

        let reviewed = SpacedRepetitionEngine.review(question, quality: 5, now: now)

        #expect(reviewed.interval == 6)
        #expect(reviewed.easeFactor == 2.6)
        #expect(SpacedRepetitionEngine.daysUntilDue(reviewed, now: now) == 6)
    }

    @Test("testPlannerStoreReturnsOnlyDueQuizCards")
    @MainActor
    func testPlannerStoreReturnsOnlyDueQuizCards() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let storageURL = directory.appendingPathComponent("planner-state.json")
        let store = PlannerStore(storageURL: storageURL)
        let now = ISO8601DateFormatter().date(from: "2026-03-27T08:00:00Z") ?? .now

        store.replaceQuizCards(
            for: "Economics",
            with: [
                QuizQuestion(
                    question: "Due now",
                    options: ["A", "B", "C", "D"],
                    correctIndex: 0,
                    explanation: "Explanation",
                    sourceTitle: "Micro notes",
                    nextDue: now
                ),
                QuizQuestion(
                    question: "Due later",
                    options: ["A", "B", "C", "D"],
                    correctIndex: 1,
                    explanation: "Explanation",
                    sourceTitle: "Macro notes",
                    nextDue: Calendar.current.date(byAdding: .day, value: 3, to: now) ?? now
                )
            ]
        )

        let dueCards = store.dueQuizCards(for: "Economics", now: now)

        #expect(dueCards.count == 1)
        #expect(dueCards.first?.question == "Due now")
        #expect(store.nextQuizReviewDays(for: "Economics", now: now) == 3)
    }
}
