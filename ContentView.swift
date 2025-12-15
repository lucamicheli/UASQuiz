//
//  ContentView.swift
//  UASA2QUIZ
//
//  Created by Luca Micheli on 02/12/2025.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var stats = QuizStats()

    var body: some View {
        NavigationStack {
            DashboardView()
        }
        .environmentObject(stats)
    }
}

#Preview {
    ContentView()
}
