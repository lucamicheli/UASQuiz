import Foundation
import Combine

final class QuizStats: ObservableObject {
    // MARK: - Published Counters
    @Published var quizzesTaken: Int { didSet { save() } }
    @Published var quizzesPassed: Int { didSet { save() } }

    // Total number of questions currently in the database (loaded externally)
    @Published var totalQuestionsInDB: Int { didSet { save() } }

    // Historical totals tracked by the app
    @Published var totalQuestionsAnswered: Int { didSet { save() } }
    @Published var totalCorrectAnswers: Int { didSet { save() } }
    @Published var totalWrongAnswers: Int { didSet { save() } }

    // MARK: - Derived Metrics
    /// Sum of correct and wrong answers recorded.
    var totalAnswers: Int { totalCorrectAnswers + totalWrongAnswers }

    /// Fraction of quizzes passed out of those taken (0...1). Returns 0 when none taken.
    var passRate: Double {
        guard quizzesTaken > 0 else { return 0 }
        return Double(quizzesPassed) / Double(quizzesTaken)
    }

    /// Fraction of correct answers out of total answers (0...1). Returns 0 when none answered.
    var accuracy: Double {
        let total = totalAnswers
        guard total > 0 else { return 0 }
        return Double(totalCorrectAnswers) / Double(total)
    }

    // MARK: - Persistence
    private struct Keys {
        static let quizzesTaken = "quizzesTaken"
        static let quizzesPassed = "quizzesPassed"
        static let totalQuestionsInDB = "totalQuestionsInDB"
        static let totalQuestionsAnswered = "totalQuestionsAnswered"
        static let totalCorrectAnswers = "totalCorrectAnswers"
        static let totalWrongAnswers = "totalWrongAnswers"
    }

    init() {
        let d = UserDefaults.standard
        quizzesTaken           = d.integer(forKey: Keys.quizzesTaken)
        quizzesPassed          = d.integer(forKey: Keys.quizzesPassed)
        totalQuestionsInDB     = d.integer(forKey: Keys.totalQuestionsInDB)
        totalQuestionsAnswered = d.integer(forKey: Keys.totalQuestionsAnswered)
        totalCorrectAnswers    = d.integer(forKey: Keys.totalCorrectAnswers)
        totalWrongAnswers      = d.integer(forKey: Keys.totalWrongAnswers)
    }

    // MARK: - Public API
    /// Records a completed quiz and updates counters.
    /// - Parameters:
    ///   - completed: Whether a quiz was completed (increments quizzesTaken when true).
    ///   - passed: Whether the quiz was passed (increments quizzesPassed when true).
    ///   - correct: Number of correct answers in this quiz.
    ///   - wrong: Number of wrong answers in this quiz.
    func recordQuiz(completed: Bool = true, passed: Bool, correct: Int, wrong: Int) {
        if completed { quizzesTaken += 1 }
        if passed { quizzesPassed += 1 }
        totalCorrectAnswers += max(0, correct)
        totalWrongAnswers += max(0, wrong)
        totalQuestionsAnswered += max(0, correct + wrong)
    }

    /// Records a single answer event.
    func recordAnswer(isCorrect: Bool) {
        if isCorrect { totalCorrectAnswers += 1 } else { totalWrongAnswers += 1 }
        totalQuestionsAnswered += 1
    }

    /// Resets all historical stats tracked by the app.
    func resetAllStats() {
        quizzesTaken = 0
        quizzesPassed = 0
        totalQuestionsAnswered = 0
        totalCorrectAnswers = 0
        totalWrongAnswers = 0
        // totalQuestionsInDB is loaded from DB, keep as-is
    }

    // MARK: - Private
    private func save() {
        let d = UserDefaults.standard
        d.set(quizzesTaken,           forKey: Keys.quizzesTaken)
        d.set(quizzesPassed,          forKey: Keys.quizzesPassed)
        d.set(totalQuestionsInDB,     forKey: Keys.totalQuestionsInDB)
        d.set(totalQuestionsAnswered, forKey: Keys.totalQuestionsAnswered)
        d.set(totalCorrectAnswers,    forKey: Keys.totalCorrectAnswers)
        d.set(totalWrongAnswers,      forKey: Keys.totalWrongAnswers)
    }
}
