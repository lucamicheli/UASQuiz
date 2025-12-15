import SwiftUI

struct ResultItem: Identifiable, Hashable {
    let id: Int
    let orderIndex: Int
    let question: Question
    let selectedIndex: Int?
    var isCorrect: Bool { selectedIndex == question.correctIndex }
    init(id: Int, orderIndex: Int, question: Question, selectedIndex: Int?) {
        self.id = id
        self.orderIndex = orderIndex
        self.question = question
        self.selectedIndex = selectedIndex
    }
}

struct QuizResultsView: View {
    let title: String
    let scorePercent: Int
    let correctCount: Int
    let wrongCount: Int
    let durationText: String
    let items: [ResultItem]

    let onRetake: () -> Void
    let onDone: () -> Void

    @State private var filter: Filter = .all

    enum Filter { case all, incorrect, correct }

    init(title: String, scorePercent: Int, correctCount: Int, wrongCount: Int, durationText: String, items: [ResultItem], onRetake: @escaping () -> Void, onDone: @escaping () -> Void) {
        self.title = title
        self.scorePercent = scorePercent
        self.correctCount = correctCount
        self.wrongCount = wrongCount
        self.durationText = durationText
        self.items = items
        self.onRetake = onRetake
        self.onDone = onDone
    }

    private var filteredItems: [ResultItem] {
        switch filter {
        case .all: return items
        case .incorrect: return items.filter { !$0.isCorrect }
        case .correct: return items.filter { $0.isCorrect }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    scoreRing
                    statsRow
                    filterBar
                    ForEach(filteredItems) { item in
                        AnswerCard(item: item)
                    }
                    Spacer(minLength: 80)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
            }

            bottomBar
        }
        .navigationTitle("")
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 2) {
                    Text(title)
                        .font(.system(size: 18, weight: .heavy))
                        .foregroundColor(.white)
                    Text("Exam Results")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white.opacity(0.7))
                }
            }
        }
        .background(Color(red: 0.08, green: 0.11, blue: 0.15).ignoresSafeArea())
    }

    private var scoreRing: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.08), lineWidth: 18)
            Circle()
                .trim(from: 0, to: max(0, min(Double(scorePercent) / 100.0, 1.0)))
                .stroke(
                    AngularGradient(
                        gradient: Gradient(colors: [Color(red: 0.20, green: 0.55, blue: 1.0), Color(red: 0.20, green: 0.55, blue: 1.0).opacity(0.7), Color(red: 0.20, green: 0.55, blue: 1.0)]),
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 18, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.35), value: scorePercent)
            VStack(spacing: 2) {
                Text("\(scorePercent)%")
                    .font(.system(size: 32, weight: .heavy))
                    .foregroundColor(.white)
                Text("SCORE")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.6))
            }
        }
        .frame(width: 150, height: 150)
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    private var statsRow: some View {
        HStack(spacing: 12) {
            StatPill(icon: "checkmark.circle.fill", color: Color.green, value: "\(correctCount)", caption: "Correct")
            StatPill(icon: "xmark.octagon.fill", color: Color.red, value: "\(wrongCount)", caption: "Wrong")
            StatPill(icon: "timer", color: Color(red: 0.20, green: 0.55, blue: 1.0), value: durationText, caption: "Time")
        }
    }

    private var filterBar: some View {
        HStack(spacing: 8) {
            FilterChip(title: "All (\(items.count))", isSelected: filter == .all) { filter = .all }
            FilterChip(title: "Incorrect (\(wrongCount))", isSelected: filter == .incorrect) { filter = .incorrect }
            FilterChip(title: "Correct (\(correctCount))", isSelected: filter == .correct) { filter = .correct }
        }
        .padding(.top, 8)
    }

    private var bottomBar: some View {
        ZStack {
            Color.clear
            HStack {
                Button(action: onDone) {
                    Text("Done")
                        .font(.system(size: 16, weight: .heavy))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color(red: 0.20, green: 0.55, blue: 1.0))
                        )
                }
                .buttonStyle(.plain)
                Button(action: onRetake) {
                    Text("Retake")
                        .font(.system(size: 16, weight: .heavy))
                        .foregroundColor(Color(red: 0.20, green: 0.55, blue: 1.0))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color.white.opacity(0.05))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color.white.opacity(0.10), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 12)
        }
        .background(Color.clear)
    }
}

private struct StatPill: View {
    let icon: String
    let color: Color
    let value: String
    let caption: String

    var body: some View {
        VStack(alignment: .center, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: icon).foregroundColor(color)
                Text(caption)
                    .foregroundColor(.white.opacity(0.8))
                    .font(.system(size: 14, weight: .semibold))
            }
            .frame(maxWidth: .infinity, alignment: .center)
            Text(value)
                .font(.system(size: 22, weight: .heavy))
                .foregroundColor(.white)
        }
        .frame(maxWidth: .infinity)
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .center)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }
}

private struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .heavy))
                .foregroundColor(isSelected ? Color.black : Color.white.opacity(0.9))
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(
                    Capsule()
                        .fill(isSelected ? Color(red: 0.90, green: 0.95, blue: 1.0) : Color.white.opacity(0.06))
                )
                .overlay(
                    Capsule()
                        .stroke(isSelected ? Color(red: 0.20, green: 0.55, blue: 1.0) : Color.white.opacity(0.10), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

private struct AnswerCard: View {
    let item: ResultItem

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            selectionSection
            correctionSection
        }
        .padding(16)
        .background(cardBackground)
    }

    // MARK: - Subviews

    private var header: some View {
        HStack(spacing: 10) {
            numberBadge
            questionText
            Spacer()
        }
    }

    private var numberBadge: some View {
        Circle()
            .fill(Color.white.opacity(0.06))
            .frame(width: 28, height: 28)
            .overlay(
                Text("\(item.orderIndex + 1)")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundColor(.white.opacity(0.9))
            )
    }

    private var questionText: some View {
        Text(item.question.question)
            .font(.system(size: 18, weight: .heavy))
            .foregroundColor(.white)
    }

    private var selectionSection: some View {
        Group {
            if let selected = item.selectedIndex {
                selectionCard(selectedIndex: selected)
            } else {
                noSelectionText
            }
        }
    }

    private func selectionCard(selectedIndex: Int) -> some View {
        let isCorrect = item.isCorrect
        let selectedText = item.question.options[selectedIndex]
        return HStack(alignment: .top, spacing: 8) {
            Image(systemName: isCorrect ? "checkmark.circle.fill" : "xmark.octagon.fill")
                .foregroundColor(isCorrect ? .green : .red)
            VStack(alignment: .leading, spacing: 2) {
                Text("Your Answer")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.6))
                Text(selectedText)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(isCorrect ? .green : .red)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke((isCorrect ? Color.green : Color.red).opacity(0.35), lineWidth: 1)
                )
        )
    }

    private var noSelectionText: some View {
        Text("No answer selected")
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(.white.opacity(0.7))
    }

    private var correctionSection: some View {
        Group {
            if !item.isCorrect {
                correctAnswerCard
            }
        }
    }

    private var correctAnswerCard: some View {
        let correctText = item.question.options[item.question.correctIndex]
        return HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
            VStack(alignment: .leading, spacing: 2) {
                Text("Correct Answer")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.6))
                Text(correctText)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.green)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 20)
            .fill(Color.white.opacity(0.05))
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
    }
}

#Preview {
    // Minimal preview with fake data if Question type is available
    let q = Question(id: 1, question: "Example?", options: ["A","B","C","D"], correctIndex: 2)
    return QuizResultsView(
        title: "UAS Module 1",
        scorePercent: 80,
        correctCount: 18,
        wrongCount: 2,
        durationText: "12:05",
        items: [
            ResultItem(id: 1, orderIndex: 0, question: q, selectedIndex: 1),
            ResultItem(id: 2, orderIndex: 1, question: q, selectedIndex: 2)
        ],
        onRetake: {},
        onDone: {}
    )
}

