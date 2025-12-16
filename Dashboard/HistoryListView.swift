import SwiftUI

struct HistoryListView: View {
    let sessions: [QuizSessionSummary]
    var body: some View {
        ZStack {
            Color(red: 0.07, green: 0.10, blue: 0.14).ignoresSafeArea()
            List {
                ForEach(sessions) { s in
                    ZStack {
                        NavigationLink(destination: QuizSessionDetailView(session: s)) {
                            EmptyView()
                        }
                        .opacity(0)
                        HistoryRow(session: s)
                            .contentShape(Rectangle())
                    }
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 8, trailing: 16))
                    .listRowBackground(Color.clear)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("All Sessions")
    }
}
