import Foundation
import Combine

final class QuizStats: ObservableObject {
    @Published var quizzesTaken: Int {
        didSet { save() }
    }

    @Published var quizzesPassed: Int {
        didSet { save() }
    }

    @Published var totalQuestionsInDB: Int {
        didSet { save() }
    }

    @Published var totalQuestionsAnswered: Int {
        didSet { save() }
    }

    private struct Keys {
        static let quizzesTaken = "quizzesTaken"
        static let quizzesPassed = "quizzesPassed"
        static let totalQuestionsInDB = "totalQuestionsInDB"
        static let totalQuestionsAnswered = "totalQuestionsAnswered"
    }

    init() {
        let d = UserDefaults.standard
        quizzesTaken           = d.integer(forKey: Keys.quizzesTaken)
        quizzesPassed          = d.integer(forKey: Keys.quizzesPassed)
        totalQuestionsInDB     = d.integer(forKey: Keys.totalQuestionsInDB)
        totalQuestionsAnswered = d.integer(forKey: Keys.totalQuestionsAnswered)
    }

    func resetAllStats() {
        quizzesTaken = 0
        quizzesPassed = 0
        totalQuestionsAnswered = 0
        // totalQuestionsInDB is loaded from DB, no need to reset
    }

    private func save() {
        let d = UserDefaults.standard
        d.set(quizzesTaken,           forKey: Keys.quizzesTaken)
        d.set(quizzesPassed,          forKey: Keys.quizzesPassed)
        d.set(totalQuestionsInDB,     forKey: Keys.totalQuestionsInDB)
        d.set(totalQuestionsAnswered, forKey: Keys.totalQuestionsAnswered)
    }
}
