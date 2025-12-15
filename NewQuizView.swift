import SwiftUI

struct NewQuizView: View {
    @State private var categories: [Category] = []
    @State private var isLoading: Bool = true
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Bottone simulazione d'esame
                NavigationLink {
                    QuizView(mode: .exam)
                } label: {
                    Text("Inizia Simulazione d'esame")
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
                        .padding(.top, 24)
                }
                
                NavigationLink {
                    QuizView(mode: .quick10)
                } label: {
                    Text("Quiz Veloce")
                        .font(.system(size: 18, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .foregroundColor(.white)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Color.indigo)
                        )
                        .clipShape(Capsule())
                }

                NavigationLink {
                    QuizView(mode: .reviewWrong)
                } label: {
                    Text("Ripasso errori")
                        .font(.system(size: 18, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .foregroundColor(.white)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Color.indigo)
                        )
                        .clipShape(Capsule())
                }

               
                // Label
                Text("Quiz per argomento")
                    .font(.system(size: 20, weight: .semibold))
                    .padding(.top, 8)

                if isLoading {
                    ProgressView().padding(.vertical, 16)
                } else if let errorMessage {
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .font(.subheadline)
                } else if categories.isEmpty {
                    Text("Nessuna categoria trovata.")
                        .foregroundColor(.secondary)
                } else {
                    // Bottoni per ogni categoria
                    VStack(spacing: 12) {
                        ForEach(categories) { cat in
                            NavigationLink {
                                QuizView(mode: .chapter(cat.id))
                            } label: {
                                Text(cat.name)
                                    .font(.system(size: 16, weight: .semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .foregroundColor(.white)
                                    .background(
                                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                                            .fill(Color.indigo)
                                    )
                                    .clipShape(Capsule())
                            }
                        }
                    }
                }

                Spacer(minLength: 16)
            }
            .padding(.horizontal, 24)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .onAppear {
            loadCategories()
        }
        .navigationTitle("New Quiz")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func loadCategories() {
        isLoading = true
        errorMessage = nil
        let cats = DatabaseManager.shared.fetchCategories()
        self.categories = cats
        self.isLoading = false
    }
}

#Preview {
    NavigationStack {
        NewQuizView()
    }
}
