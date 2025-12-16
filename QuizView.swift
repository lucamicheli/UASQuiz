import SwiftUI
import Combine

struct QuizView: View {
    @EnvironmentObject var stats: QuizStats
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    // Accept a mode and use it to initialize the view model
    private let mode: QuizViewModel.Mode
    @StateObject private var viewModel: QuizViewModel

    // Feedback state: first tap shows correctness, second tap advances
    @State private var showFeedback: Bool = false
    @State private var wasCorrect: Bool = false
    @State private var showExitConfirm: Bool = false

    // Passed state computed at finish
    @State private var passedFlag: Bool = false

    // Preferiti
    @State private var favoriteIDs: Set<Int> = []

    // Animation state for collapsing to two options during feedback
    @State private var visibleOptionIndices: [Int]? = nil

    private let timer = Timer
        .publish(every: 1, on: .main, in: .common)
        .autoconnect()

    private let passThreshold: Double = 0.75

    // Designated initializer to pass the desired mode
    init(mode: QuizViewModel.Mode = .exam) {
        self.mode = mode
        _viewModel = StateObject(wrappedValue: QuizViewModel(mode: mode))
    }

    // Background always dark color for consistent dark theme
    private var backgroundColor: Color {
        return Color(red: 0.07, green: 0.10, blue: 0.14)
    }

    // Background tint that reacts to correctness during feedback
    private var questionBackgroundColor: Color {
        guard showFeedback else { return backgroundColor }
        return wasCorrect ? Color(red: 0.05, green: 0.20, blue: 0.12) : Color(red: 0.20, green: 0.08, blue: 0.08)
    }

    // Colore base del testo per domanda e opzioni
    private var baseTextColor: Color {
        .white
    }

    var body: some View {
        ZStack {
            // Background che ignora la safe area per coprire tutta la schermata
            questionBackgroundColor.ignoresSafeArea()

            VStack(spacing: 0) {
                if viewModel.isFinished {
                    QuizResultsView(
                        title: prettyModeTitle(mode: mode),
                        scorePercent: {
                            let total = max(viewModel.questions.count, 1)
                            return Int(round(Double(viewModel.correctAnswers) * 100.0 / Double(total)))
                        }(),
                        correctCount: viewModel.correctAnswers,
                        wrongCount: max(0, viewModel.answers.count - viewModel.correctAnswers),
                        durationText: viewModel.formattedTime, // shows remaining; replace with elapsed if tracked
                        items: viewModel.answers.enumerated().map { idx, a in
                            ResultItem(id: a.question.id, orderIndex: idx, question: a.question, selectedIndex: a.selectedIndex)
                        },
                        onRetake: {
                            // Retake same mode: dismiss then push a new QuizView if needed (caller should handle)
                            dismiss()
                        },
                        onDone: { dismiss() }
                    )
                } else {
                    // Contenuto principale (domanda + opzioni)
                    questionScreen
                        .onReceive(timer) { _ in
                            viewModel.tick()
                        }

                    // Barra fissa in basso con solo il bottone principale e bookmark a sinistra
                    bottomFixedBar
                }
            }
        }
        // Hide default back while the quiz is active so we control exit via our button.
        .navigationBarBackButtonHidden(!viewModel.isFinished)
        .toolbar {
            if !viewModel.isFinished {
                // Left: Xmark button to dismiss
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 18, weight: .semibold))
                    }
                }
                // Principal center: timer and question count
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 6) {
                        HStack(spacing: 6) {
                            Image(systemName: "timer")
                            Text(viewModel.formattedTime)
                                .monospacedDigit()
                        }
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Color.white.opacity(0.7))
                        Text("Question \(viewModel.currentIndex + 1) of \(viewModel.questions.count)")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                    }
                }
                // Right: score capsule chip
                ToolbarItem(placement: .topBarTrailing) {
                    Text("SCORE: \(viewModel.correctAnswers * 2)")
                        .font(.system(size: 13, weight: .heavy))
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        .foregroundColor(.white)
                }
            }
        }
        .overlay(alignment: .topLeading) {
            GeometryReader { geo in
                let total = max(viewModel.questions.count, 1)
                let progress = Double(viewModel.answers.count) / Double(total)
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.blue)
                    .frame(width: max(0, min(geo.size.width * progress, geo.size.width)), height: 3)
                    .animation(.easeInOut(duration: 0.25), value: viewModel.answers.count)
                    .opacity(0.9)
            }
            .allowsHitTesting(false)
        }
        .onAppear {
            // reflect current DB question count every time
            stats.totalQuestionsInDB = DatabaseManager.shared.totalQuestionCount()
            // carica preferiti correnti
            favoriteIDs = DatabaseManager.shared.favoriteQuestionIDs()
        }
        .onChange(of: viewModel.isFinished) { oldValue, newValue in
            guard newValue else { return }
            stats.quizzesTaken += 1
            stats.totalQuestionsAnswered += viewModel.answers.count
            if passedFlag {
                stats.quizzesPassed += 1
            }
        }
        .confirmationDialog(
            "Exit exam?",
            isPresented: $showExitConfirm,
            titleVisibility: .visible
        ) {
            Button("Exit", role: .destructive) {
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to exit? Your current progress will be lost.")
        }
    }

    private var currentQuestion: Question? {
        guard !viewModel.questions.isEmpty,
              viewModel.currentIndex >= 0,
              viewModel.currentIndex < viewModel.questions.count else { return nil }
        return viewModel.questions[viewModel.currentIndex]
    }

    private var questionScreen: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if let question = currentQuestion {
                    Text(question.question)
                        .font(.system(size: 28, weight: .heavy))
                        .foregroundColor(.white)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(spacing: 12) {
                        let indices: [Int] = {
                            if let custom = visibleOptionIndices { return custom }
                            return Array(question.options.indices)
                        }()

                        ForEach(indices, id: \.self) { idx in
                            let isSelected = viewModel.selectedIndex == idx
                            let isCorrectOption = idx == question.correctIndex
                            OptionButton(
                                title: question.options[idx],
                                isSelected: isSelected,
                                textColor: .white,
                                // While showing feedback, tint selected as green/red and show correct answer as green if user was wrong
                                highlightColor: showFeedback
                                    ? (isSelected
                                        ? (wasCorrect ? .green : .red)
                                        : (!wasCorrect && isCorrectOption ? .green : nil))
                                    : nil
                            ) {
                                guard !showFeedback else { return } // lock selection during feedback
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
                                    viewModel.selectedIndex = idx
                                }
                            }
                            .transition(.asymmetric(
                                insertion: .move(edge: .top).combined(with: .opacity),
                                removal: .move(edge: .leading).combined(with: .opacity)
                            ))
                        }
                    }

                    if showFeedback {
                        HStack(spacing: 8) {
                            Image(systemName: wasCorrect ? "checkmark.circle.fill" : "xmark.octagon.fill")
                                .foregroundColor(.white) // icona bianca su sfondo colorato
                            Text(wasCorrect ? "Corretto!" : "Sbagliato")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white)
                        }
                        .padding(.top, 4)
                        .accessibilityLabel(wasCorrect ? "Correct" : "Wrong")
                    }
                }

                Spacer(minLength: 48) // più spazio prima della barra fissa
            }
            .padding(.horizontal, 20)
            .padding(.top, 16) // più distacco dalla navigation bar
            .padding(.bottom, 8) // piccolo padding per non coprire contenuti
        }
        // piccolo inset sotto la navigation bar per evitare sovrapposizioni visive
        .safeAreaInset(edge: .top) {
            Color.clear.frame(height: 8)
        }
    }

    // MARK: - Barra fissa in basso

    private var bottomFixedBar: some View {
        HStack(spacing: 12) {
            if let q = currentQuestion {
                Button {
                    toggleFavorite(for: q.id)
                } label: {
                    Image(systemName: favoriteIDs.contains(q.id) ? "bookmark.fill" : "bookmark")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 52, height: 52)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Color.white.opacity(0.06))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(Color.white.opacity(0.12), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }

            Button {
                handlePrimaryButtonTap()
            } label: {
                Text(primaryButtonTitle)
                    .font(.system(size: 18, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .foregroundColor(.white)
                    .background(Color.blue)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
            .disabled(viewModel.selectedIndex == nil && !showFeedback)
            .opacity(viewModel.selectedIndex == nil && !showFeedback ? 0.5 : 1)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
        .padding(.top, 8)
    }

    private var primaryButtonTitle: String {
        if showFeedback {
            return "Next"
        } else {
            return "Check Answer"
        }
    }

    private func handlePrimaryButtonTap() {
        guard !viewModel.isFinished else { return }
        if showFeedback {
            // Commit the answer and advance
            let currentQuestion = viewModel.questions[viewModel.currentIndex]
            if let selectedIndex = viewModel.selectedIndex {
                wasCorrect = (selectedIndex == currentQuestion.correctIndex)
            } else {
                wasCorrect = false
            }
            viewModel.answerCurrentQuestion()
            withAnimation(.easeInOut(duration: 0.25)) {
                visibleOptionIndices = nil
            }
            withAnimation(.easeInOut(duration: 0.25)) {
                showFeedback = false
                wasCorrect = false
            }
            // Se abbiamo finito, calcoliamo passedFlag qui
            if viewModel.currentIndex >= viewModel.questions.count {
                computePassedFlag()
            }
        } else {
            // Show feedback per la selezione corrente (colora lo sfondo)
            if let selectedIndex = viewModel.selectedIndex,
               viewModel.currentIndex < viewModel.questions.count {
                let currentQuestion = viewModel.questions[viewModel.currentIndex]
                wasCorrect = (selectedIndex == currentQuestion.correctIndex)
                if !wasCorrect {
                    Haptics.wrongAnswer()
                }
                // Build the collapsed, ordered set of indices for feedback display
                let correctIdx = currentQuestion.correctIndex
                if wasCorrect {
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                        visibleOptionIndices = [correctIdx]
                    }
                } else {
                    let chosen = selectedIndex
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                        visibleOptionIndices = [correctIdx, chosen]
                    }
                }
                showFeedback = true
                if wasCorrect {
                    SoundManager.shared.playCorrect()
                } else {
                    SoundManager.shared.playWrong()
                }
            }
        }
    }

    private func computePassedFlag() {
        let rateOK = viewModel.passRate >= passThreshold
        let points = viewModel.correctAnswers * 2
        switch mode {
        case .exam:
            let pointsOK = points >= 45
            passedFlag = rateOK && pointsOK
        case .quick10, .chapter, .reviewWrong:
            passedFlag = rateOK
        }
    }

    private func prettyModeTitle(mode: QuizViewModel.Mode) -> String {
        switch mode {
        case .exam: return "Exam"
        case .quick10: return "Quick Quiz"
        case .reviewWrong: return "Errors Retry"
        case .chapter(let id): return "Chapter \(id)"
        }
    }

    // MARK: - Favorites

    private func toggleFavorite(for questionId: Int) {
        if favoriteIDs.contains(questionId) {
            DatabaseManager.shared.removeFavorite(questionId: questionId)
            favoriteIDs.remove(questionId)
        } else {
            DatabaseManager.shared.addFavorite(questionId: questionId)
            favoriteIDs.insert(questionId)
        }
    }
}

// MARK: - Simple circular progress used in bottom bar

private struct CircularProgress: View {
    let label: String
    let progress: Double // 0...1

    var body: some View {
        ZStack {
            Circle()
                .inset(by: 2)
                .stroke(Color(uiColor: .systemGray4), lineWidth: 4)

            Circle()
                .inset(by: 2)
                .trim(from: 0, to: max(0, min(progress, 1.0)))
                .stroke(
                    Color.blue,
                    style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.25), value: progress)

            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .monospacedDigit()
                .minimumScaleFactor(0.6)
        }
        .frame(width: 48, height: 48)
        .padding(.vertical, 2)
    }
}

// Option button aggiornato con textColor e highlightColor opzionale

struct OptionButton: View {
    let title: String
    let isSelected: Bool
    let textColor: Color
    let highlightColor: Color?
    let onTap: () -> Void

    init(
        title: String,
        isSelected: Bool,
        textColor: Color,
        highlightColor: Color? = nil,
        onTap: @escaping () -> Void
    ) {
        self.title = title
        self.isSelected = isSelected
        self.textColor = textColor
        self.highlightColor = highlightColor
        self.onTap = onTap
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.25), lineWidth: 3)
                        .frame(width: 26, height: 26)

                    if isSelected {
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 12, height: 12)
                    }
                }

                Text(title)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.leading)

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 18)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill((highlightColor ?? Color.white.opacity(0.06)).opacity(highlightColor == nil ? 1 : 0.25))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(
                        highlightColor ?? (isSelected ? Color.blue : Color.white.opacity(0.12)),
                        lineWidth: 2
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

