import SwiftUI

struct HistoryRow: View {
    let session: QuizSessionSummary

    private var scorePercent: Int {
        guard session.totalQuestions > 0 else { return 0 }
        return Int(round(Double(session.correctAnswers) * 100.0 / Double(session.totalQuestions)))
    }
    private var badgeColor: Color {
        scorePercent >= 70 ? .green : .red
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(badgeColor.opacity(0.2))
                Text("\(scorePercent)%")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundColor(badgeColor)
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 4) {
                Text(titleText(session.mode))
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundColor(.white)
                Text(subtitleText)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.7))
            }
            Spacer()
            Image(systemName: "chevron.right")
                .foregroundColor(.white.opacity(0.4))
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.white.opacity(0.06))
        )
    }

    private var subtitleText: String {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .short
        return "\(df.string(from: session.endedAt)) • \(session.totalQuestions) Questions"
    }

    private func titleText(_ raw: String) -> String {
        if raw == "exam" { return "Exam • Mixed" }
        if raw == "reviewWrong" { return "Errors Retry" }
        if raw == "quick10" { return "Quick Quiz • Mixed" }
        if raw.hasPrefix("chapter:") {
            let id = raw.split(separator: ":").last.map(String.init) ?? ""
            return "Chapter \(id)"
        }
        return raw
    }
}
