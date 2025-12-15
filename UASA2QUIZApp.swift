import SwiftUI

@main
struct UASA2QUIZApp: App {
    @StateObject private var stats = QuizStats()

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                DashboardView()
            }
            .environmentObject(stats)
        }
    }
}
