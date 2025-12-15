import SwiftUI

private enum ChapterTab: String, CaseIterable, Identifiable {
    case unseen = "Non viste"
    case seen = "Viste"
    case favorites = "Salvate"
    case wrong = "Errate"

    var id: String { rawValue }
}

struct ChapterQuestionsView: View {
    let chapterId: Int
    let chapterName: String

    @State private var questions: [Question] = []
    @State private var seenIDs: Set<Int> = []
    @State private var favoriteIDs: Set<Int> = []
    @State private var wrongIDs: Set<Int> = []
    @State private var isLoading = true

    @State private var selectedTab: ChapterTab = .unseen

    private var filteredQuestions: [Question] {
        switch selectedTab {
        case .unseen:
            return questions.filter { !seenIDs.contains($0.id) }
        case .seen:
            return questions.filter { seenIDs.contains($0.id) }
        case .favorites:
            return questions.filter { favoriteIDs.contains($0.id) }
        case .wrong:
            return questions.filter { wrongIDs.contains($0.id) }
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            // Segmented control in alto
            Picker("", selection: $selectedTab) {
                ForEach(ChapterTab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 12)
            .padding(.top, 8)

            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else if filteredQuestions.isEmpty {
                Text(emptyMessage(for: selectedTab))
                    .foregroundColor(.secondary)
                    .padding(.top, 24)
                Spacer()
            } else {
                List {
                    ForEach(filteredQuestions, id: \.self) { q in
                        QuestionCard(
                            question: q,
                            isSeen: seenIDs.contains(q.id),
                            isFavorite: favoriteIDs.contains(q.id),
                            onSelectOption: canInteract(question: q) ? { idx in
                                handleAnswer(question: q, selectedIndex: idx)
                            } : nil,
                            onToggleFavorite: { toggleFavorite(for: q.id) }
                        )
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle(chapterName)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: loadData)
    }

    private func emptyMessage(for tab: ChapterTab) -> String {
        switch tab {
        case .unseen: return "Nessuna domanda non vista."
        case .seen: return "Nessuna domanda vista."
        case .favorites: return "Nessuna domanda salvata."
        case .wrong: return "Nessuna domanda errata."
        }
    }

    private func canInteract(question: Question) -> Bool {
        // Interazione consentita solo se non vista nella tab "Non viste"
        return !seenIDs.contains(question.id) && selectedTab == .unseen
    }

    private func loadData() {
        isLoading = true
        // Carica tutte le domande del capitolo; usa un limite alto per includerle tutte
        let qs = DatabaseManager.shared.fetchQuestionsForChapter(chapterId: chapterId, limit: 10_000)
        questions = qs
        let ids = qs.map { $0.id }
        seenIDs = DatabaseManager.shared.seenQuestionIDs(for: ids)
        favoriteIDs = DatabaseManager.shared.favoriteQuestionIDs()
        wrongIDs = DatabaseManager.shared.wrongQuestionIDs(for: ids)
        isLoading = false
    }

    private func handleAnswer(question: Question, selectedIndex: Int) {
        let isCorrect = (selectedIndex == question.correctIndex)
        // feedback sonoro
        if isCorrect {
            SoundManager.shared.playCorrect()
        } else {
            SoundManager.shared.playWrong()
        }
        // salva su DB
        DatabaseManager.shared.recordAnswer(
            questionId: question.id,
            chapterId: chapterId,
            isCorrect: isCorrect,
            answeredAt: Date()
        )
        // aggiorna stati locali
        seenIDs.insert(question.id)
        if !isCorrect {
            wrongIDs.insert(question.id)
        } else {
            // se è stata corretta ora, potremmo rimuoverla dall'insieme "errate"
            wrongIDs.remove(question.id)
        }
    }

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

private struct QuestionCard: View {
    let question: Question
    let isSeen: Bool
    let isFavorite: Bool
    // se non nil, la card è interattiva e consente risposta
    let onSelectOption: ((Int) -> Void)?
    let onToggleFavorite: () -> Void

    @State private var selectedIndex: Int? = nil
    @State private var showFeedback: Bool = false
    @State private var wasCorrect: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(question.question)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Color(.label))

                Spacer()

                // Badge vista
                if isSeen {
                    Text("Vista")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.vertical, 4)
                        .padding(.horizontal, 8)
                        .background(Capsule().fill(Color.blue.opacity(0.8)))
                }

                // Favorite toggle
                Button(action: onToggleFavorite) {
                    Image(systemName: isFavorite ? "star.fill" : "star")
                        .foregroundColor(isFavorite ? .yellow : .secondary)
                }
                .buttonStyle(.plain)
            }

            VStack(spacing: 8) {
                ForEach(question.options.indices, id: \.self) { idx in
                    let canInteract = (onSelectOption != nil) && !showFeedback
                    HStack(alignment: .center, spacing: 10) {
                        Image(systemName: symbolName(for: idx))
                            .foregroundColor(symbolColor(for: idx))
                        Text(question.options[idx])
                            .foregroundColor(textColor(for: idx))
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer()
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color(.secondarySystemBackground))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(highlightStrokeColor(for: idx), lineWidth: showFeedback && selectedIndex == idx ? 2 : 0)
                    )
                    .scaleEffect(showFeedback && selectedIndex == idx ? 1.02 : 1.0)
                    .animation(.spring(response: 0.25, dampingFraction: 0.8), value: showFeedback)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard canInteract else { return }
                        selectedIndex = idx
                        wasCorrect = (idx == question.correctIndex)
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showFeedback = true
                        }
                        // callback esterna per persistere e aggiornare "vista/errata"
                        onSelectOption?(idx)
                        // nasconde il feedback dopo un attimo per bloccare ulteriori tap
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                            showFeedback = false
                        }
                    }
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.systemBackground))
                .shadow(color: Color.black.opacity(0.06), radius: 6, x: 0, y: 3)
        )
    }

    private func symbolName(for idx: Int) -> String {
        if showFeedback, let selectedIndex {
            if idx == question.correctIndex {
                return "checkmark.circle.fill"
            }
            if idx == selectedIndex, !wasCorrect {
                return "xmark.circle.fill"
            }
        }
        return "circle"
    }

    private func symbolColor(for idx: Int) -> Color {
        if showFeedback, let selectedIndex {
            if idx == question.correctIndex {
                return .green
            }
            if idx == selectedIndex, !wasCorrect {
                return .red
            }
        }
        return .secondary
    }

    private func textColor(for idx: Int) -> Color {
        if showFeedback, let selectedIndex {
            if idx == question.correctIndex {
                return .green
            }
            if idx == selectedIndex, !wasCorrect {
                return .red
            }
        }
        return Color(.label)
    }

    private func highlightStrokeColor(for idx: Int) -> Color {
        if showFeedback, let selectedIndex {
            if idx == question.correctIndex {
                return .green
            }
            if idx == selectedIndex, !wasCorrect {
                return .red
            }
        }
        return .clear
    }
}
