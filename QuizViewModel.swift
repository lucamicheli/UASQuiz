//
//  QuizViewModel.swift
//  UASA2QUIZ
//
//  Created by Luca Micheli on 02/12/2025.
//

import Foundation
import Combine

final class QuizViewModel: ObservableObject {
    enum Mode: Equatable {
        case exam                  // 10/10/10 da capitoli 1,2,3
        case chapter(Int)          // 30 domande da uno specifico capitolo
        case reviewWrong           // ripasso errori
        case quick10               // 10 domande casuali miste
    }

    @Published var questions: [Question] = []
    @Published var currentIndex: Int = 0
    @Published var selectedIndex: Int? = nil
    @Published var correctAnswers: Int = 0
    @Published var isFinished: Bool = false
    @Published var answers: [AnsweredQuestion] = []

    // 30-minute exam (puoi variare in base alla modalità se desideri)
    @Published var timeRemaining: Int = 30 * 60

    private let mode: Mode

    // Storico quiz
    private var sessionId: Int64?
    private var sessionStartedAt: Date?
    private let serializedMode: String

    init(mode: Mode = .exam) {
        self.mode = mode
        self.serializedMode = Self.serialize(mode)
        loadQuestions()
        // Avvio sessione storico
        startSessionIfNeeded()
    }

    private func loadQuestions() {
        switch mode {
        case .exam:
            questions = DatabaseManager.shared.fetchQuestionsForExamDistribution()
            if questions.count < 30 {
                let allQuestions = DatabaseManager.shared.fetchQuestions(limit: 30)
                questions = Array(allQuestions.prefix(30))
            }
        case .chapter(let chapterId):
            questions = DatabaseManager.shared.fetchQuestionsForChapter(chapterId: chapterId, limit: 30)
            if questions.count < 30 {
                let fallback = DatabaseManager.shared.fetchQuestionsForChapter(chapterId: chapterId, limit: 1000)
                questions = Array(fallback.prefix(30))
            }
        case .reviewWrong:
            let wrongIDs = DatabaseManager.shared.fetchWrongQuestionIDs()
            let shuffled = wrongIDs.shuffled()
            questions = DatabaseManager.shared.fetchQuestionsByIDs(shuffled)
        case .quick10:
            let all = DatabaseManager.shared.fetchQuestions(limit: 10)
            questions = Array(all.prefix(10))
        }
    }

    func answerCurrentQuestion() {
        guard !isFinished, currentIndex < questions.count else { return }
        guard let selectedIndex else { return }

        let currentQuestion = questions[currentIndex]
        let answered = AnsweredQuestion(question: currentQuestion, selectedIndex: selectedIndex)
        answers.append(answered)

        let isCorrect = (selectedIndex == currentQuestion.correctIndex)
        if isCorrect {
            correctAnswers += 1
        }

        // Persist answer to DB (chapter_id read from DB)
        DatabaseManager.shared.recordAnswer(
            questionId: currentQuestion.id,
            chapterId: nil,
            isCorrect: isCorrect,
            answeredAt: Date()
        )

        // Storico: append risposta nella sessione
        if let sid = sessionId {
            DatabaseManager.shared.appendAnswerToSession(
                sessionId: sid,
                orderIndex: currentIndex,
                questionId: currentQuestion.id,
                selectedIndex: selectedIndex,
                isCorrect: isCorrect
            )
        }

        goToNextQuestion()
    }

    func goToNextQuestion() {
        selectedIndex = nil

        if currentIndex + 1 < questions.count {
            currentIndex += 1
        } else {
            finishExam()
        }
    }

    func finishExam() {
        isFinished = true

        // Chiudi sessione storico
        if let sid = sessionId, let started = sessionStartedAt {
            let ended = Date()
            let points = correctAnswers * 2
            let passByRate = passRate >= 0.75
            let passByPoints = points >= 45
            let passed = passByRate && passByPoints

            DatabaseManager.shared.finishQuizSession(
                sessionId: sid,
                endedAt: ended,
                correctAnswers: correctAnswers,
                points: points,
                passed: passed,
                startedAt: started
            )
        }
    }

    func tick() {
        guard !isFinished else { return }
        if timeRemaining > 0 {
            timeRemaining -= 1
        } else {
            finishExam()
        }
    }

    var formattedTime: String {
        let m = timeRemaining / 60
        let s = timeRemaining % 60
        return String(format: "%02d:%02d", m, s)
    }

    var passRate: Double {
        guard !questions.isEmpty else { return 0 }
        return Double(correctAnswers) / Double(questions.count)
    }

    // MARK: - Session helpers

    private func startSessionIfNeeded() {
        guard sessionId == nil else { return }
        sessionStartedAt = Date()
        let total = questions.count
        let sid = DatabaseManager.shared.startQuizSession(
            mode: serializedMode,
            totalQuestions: total,
            startedAt: sessionStartedAt ?? Date()
        )
        sessionId = sid
    }

    private static func serialize(_ mode: Mode) -> String {
        switch mode {
        case .exam: return "exam"
        case .chapter(let id): return "chapter:\(id)"
        case .reviewWrong: return "reviewWrong"
        case .quick10: return "quick10"
        }
    }
}
