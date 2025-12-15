// QuizSessionDetailView.swift
import SwiftUI

struct QuizSessionDetailView: View {
    let session: QuizSessionSummary

    @State private var answers: [QuizSessionAnswerDetail] = []
    @State private var questionsById: [Int: Question] = [:]
    @State private var isLoading = true

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
            } else {
                let items: [ResultItem] = answers.enumerated().compactMap { idx, a in
                    if let q = questionsById[a.questionId] {
                        return ResultItem(id: q.id, orderIndex: idx, question: q, selectedIndex: a.selectedIndex)
                    }
                    return nil
                }
                let correct = answers.filter { $0.isCorrect }.count
                let total = max(answers.count, 1)
                let percent = Int(round(Double(correct) * 100.0 / Double(total)))
                let durationText = String(format: "%02d:%02d", session.durationSeconds/60, session.durationSeconds%60)

                QuizResultsView(
                    title: prettyMode(session.mode),
                    scorePercent: percent,
                    correctCount: correct,
                    wrongCount: max(0, answers.count - correct),
                    durationText: durationText,
                    items: items,
                    onRetake: {
                        // Navigate to a fresh quiz with same mode; keep simple: no-op here, handled by parent if needed
                    },
                    onDone: { }
                )
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: loadData)
    }

    private func loadData() {
        isLoading = true
        let fetched = DatabaseManager.shared.fetchQuizSessionAnswers(sessionId: session.id)
        self.answers = fetched

        // Preleva i testi delle domande per tutti gli ID coinvolti
        let ids = Array(Set(fetched.map { $0.questionId }))
        let questions = DatabaseManager.shared.fetchQuestionsByIDs(ids)
        self.questionsById = Dictionary(uniqueKeysWithValues: questions.map { ($0.id, $0) })

        self.isLoading = false
    }

    private func prettyMode(_ raw: String) -> String {
        if raw == "exam" { return "Esame" }
        if raw == "reviewWrong" { return "Ripasso errori" }
        if raw == "quick10" { return "Quiz veloce (10)" }
        if raw.hasPrefix("chapter:") {
            let id = raw.split(separator: ":").last.map(String.init) ?? ""
            return "Capitolo \(id)"
        }
        return raw
    }
}

