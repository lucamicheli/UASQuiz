import SwiftUI

struct ChapterSelectionView: View {
    @Environment(\.dismiss) private var dismiss

    // Data
    @State private var categories: [Category] = []
    @State private var totalsByCategory: [Int: Int] = [:]

    // Selection
    @State private var selected: Set<Int> = []

    // Navigation state
    @State private var showQuizView: Bool = false

    var body: some View {
        ZStack(alignment: .bottom) {
            // Background
            Color(red: 0.07, green: 0.10, blue: 0.14).ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Select Chapters")
                        .font(.system(size: 24, weight: .heavy))
                        .foregroundColor(.white)
                        .padding(.top, 8)
                        .frame(maxWidth: .infinity, alignment: .center)

                    VStack(spacing: 12) {
                        ForEach(Array(categories.enumerated()), id: \.element.id) { index, cat in
                            let total = totalsByCategory[cat.id] ?? 0
                            ChapterSelectRow(
                                index: index + 1,
                                title: cat.name,
                                totalQuestions: total,
                                isSelected: selected.contains(cat.id)
                            ) {
                                toggle(cat.id)
                            }
                        }
                    }
                    .padding(.top, 8)

                    HStack {
                        Text("\(selected.count) chapter\(selected.count == 1 ? "" : "s") selected")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white.opacity(0.7))
                        Spacer()
                        Button("Clear selection") {
                            selected.removeAll()
                        }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.blue)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)

                    Spacer(minLength: 80)
                }
                .padding(.horizontal, 16)
            }

            // Bottom bar button
            VStack(spacing: 10) {
                Button(action: startQuiz) {
                    HStack {
                        Text("Start Quiz (\(selected.count))")
                            .font(.system(size: 18, weight: .heavy))
                        Image(systemName: "arrow.right")
                            .font(.system(size: 18, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.blue)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                }
                .disabled(selected.isEmpty)
                .opacity(selected.isEmpty ? 0.5 : 1)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .onAppear(perform: load)
        .background(
            NavigationLink(
                destination: QuizView(mode: .chapter(selected.sorted().first ?? 0)),
                isActive: $showQuizView,
                label: { EmptyView() }
            )
            .hidden()
        )
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Text("Select Chapters")
                .font(.system(size: 18, weight: .heavy))
                .foregroundColor(.white)
        }
    }

    private func load() {
        categories = DatabaseManager.shared.fetchCategories()
        totalsByCategory = DatabaseManager.shared.totalQuestionsPerCategory()
    }

    private func toggle(_ id: Int) {
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
    }

    private func startQuiz() {
        guard !selected.isEmpty else { return }
        showQuizView = true
    }
}

private struct ChapterSelectRow: View {
    let index: Int
    let title: String
    let totalQuestions: Int
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .center, spacing: 12) {
                // Checkbox
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.white.opacity(0.10))
                        .frame(width: 28, height: 28)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(Color.white.opacity(0.25), lineWidth: 2)
                        )
                    if isSelected {
                        Image(systemName: "checkmark")
                            .foregroundColor(.white)
                            .font(.system(size: 14, weight: .heavy))
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(String(format: "%02d.", index))
                            .font(.system(size: 16, weight: .heavy))
                            .foregroundColor(.white.opacity(0.85))
                        Text(title)
                            .font(.system(size: 18, weight: .heavy))
                            .foregroundColor(.white)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                    Text("\(totalQuestions) Questions available")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white.opacity(0.6))
                }
                Spacer()
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(0.06))
            )
        }
        .buttonStyle(.plain)
    }
}

// Navigation helper wrapper to actually push QuizView once selection is made.
// This keeps ChapterSelectionView UI simple and stateless for navigation.
struct ChapterSelectionLauncher: View {
    @State private var go: Bool = false
    let selectedIds: [Int]

    var body: some View {
        VStack { EmptyView() }
            .background(
                NavigationLink("", isActive: $go) {
                    // For now, start with the first selected chapter. You can extend QuizView to accept multiple.
                    QuizView(mode: .chapter(selectedIds.first ?? 0))
                }
                .hidden()
            )
            .onAppear {
                // Trigger navigation immediately
                DispatchQueue.main.async { go = true }
            }
    }
}
