import Foundation

// Single question
struct Question: Identifiable, Codable, Hashable {
    let id: Int
    let question: String
    let options: [String]
    let correctIndex: Int
}

// JSON structure with "flight-performance" key
struct QuestionBank: Codable {
    let flightPerformance: [Question]

    enum CodingKeys: String, CodingKey {
        case flightPerformance = "flight-performance"
    }
}

// User’s answer to a question
struct AnsweredQuestion: Identifiable, Hashable {
    let id = UUID()
    let question: Question
    let selectedIndex: Int?

    var isCorrect: Bool {
        selectedIndex == question.correctIndex
    }
}
