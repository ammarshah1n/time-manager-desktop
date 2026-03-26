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
            runner: { _ in nil }
        )

        let question = QuizQuestion(
            question: "What does PED measure?",
            options: ["A", "B", "C", "D"],
            correctIndex: 1,
            explanation: "Explanation",
            sourceTitle: "PED notes"
        )

        model.history = [
            QuizAnswerRecord(question: question, selectedOptionIndex: 1, freeformAnswer: "", isCorrect: true),
            QuizAnswerRecord(question: question, selectedOptionIndex: 1, freeformAnswer: "", isCorrect: true),
            QuizAnswerRecord(question: question, selectedOptionIndex: 1, freeformAnswer: "", isCorrect: true),
            QuizAnswerRecord(question: question, selectedOptionIndex: 2, freeformAnswer: "", isCorrect: false),
            QuizAnswerRecord(question: question, selectedOptionIndex: 1, freeformAnswer: "", isCorrect: true)
        ]

        #expect(model.summary.attemptedCount == 5)
        #expect(model.summary.correctCount == 4)
        #expect(model.summary.confidenceDeltaPercent == 6)
        #expect(model.summary.updatedConfidence == 4)
    }
}
