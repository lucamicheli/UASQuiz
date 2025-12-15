import SwiftUI

struct ResultView: View {
    let score: Int
    let total: Int
    let answers: [AnsweredQuestion]
    let passed: Bool
    let onDone: () -> Void

    // Each correct answer is worth 2 points; max dynamic based on total questions
    private var maxPoints: Int { total * 2 }
    private var earnedPoints: Int { score * 2 }

    @State private var animatedPoints: Int = 0

    var body: some View {
        VStack(spacing: 16) {
            // Header con emoji esito
            Text(passed ? "✅" : "🙅")
                .font(.system(size: 72))
                .accessibilityHidden(true)

            // Titolo dinamico in base all'esito
            Text(passed ? "Passato" : "Non Passato")
                .font(.largeTitle)
                .bold()

            Text("You answered \(score) questions correctly out of \(total).")
                .font(.title3)

            // Pass/Fail summary with points
            HStack(spacing: 8) {
                Text("\(animatedPoints) Punti")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Color(.label))
            }
            .padding(.top, 4)

            Divider().padding(.vertical, 8)

            Text("Question Review")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            List {
                ForEach(answers) { answered in
                    QuestionReviewRow(answered: answered)
                }
            }
            .listStyle(.plain)

            Button(action: onDone) {
                Text("Back to Home")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .foregroundColor(.white)
                    .background(
                        LinearGradient(
                            gradient: Gradient(colors: [Color.blue, Color.blue.opacity(0.8)]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(Capsule())
            }
            .padding(.top, 8)
        }
        .padding()
        .background(Color(uiColor: .systemGroupedBackground))
        .onAppear {
            // Auto-animazione dei punti: +2 per ogni risposta corretta
            animatedPoints = 0
            startPointsAnimation()
        }
    }

    private func startPointsAnimation() {
        let steps = score // una "tacca" per ogni risposta corretta, +2 ciascuna
        let interval = 0.05
        guard steps > 0 else {
            animatedPoints = 0
            return
        }
        for i in 1...steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * interval) {
                withAnimation(.easeOut(duration: 0.04)) {
                    animatedPoints = min(i * 2, earnedPoints)
                }
            }
        }
    }
}

struct QuestionReviewRow: View {
    let answered: AnsweredQuestion

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(answered.question.question)
                .font(.subheadline)
                .bold()

            if let selectedIndex = answered.selectedIndex {
                Text("Your answer: \(answered.question.options[selectedIndex])")
                    .foregroundColor(answered.isCorrect ? .green : .red)
            } else {
                Text("Your answer: (no answer)")
                    .foregroundColor(.red)
            }

            let correctText = answered.question.options[answered.question.correctIndex]
            Text("Correct answer: \(correctText)")
                .foregroundColor(.green)

            Text(answered.isCorrect ? "Result: Correct" : "Result: Wrong")
                .foregroundColor(answered.isCorrect ? .green : .red)
                .font(.caption)
        }
        .padding(.vertical, 4)
    }
}
