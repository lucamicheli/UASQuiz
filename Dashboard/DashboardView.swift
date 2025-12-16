//
//  DashboardView.swift
//  UASA2QUIZ
//
//  Created by Luca Micheli on 02/12/2025.
//

import SwiftUI

private struct NavGauge: View {
    let percent: Double // 0...1
    var body: some View {
        ZStack {
            // Outer subtle ring
            Circle()
                .stroke(Color.primary.opacity(0.08), lineWidth: 2)
            // Background track (full circle)
            Circle()
                .inset(by: 4)
                .stroke(Color.primary.opacity(0.15), lineWidth: 6)
            // Foreground progress arc
            Circle()
                .inset(by: 4)
                .trim(from: 0, to: max(0, min(1, percent)))
                .stroke(Color.blue, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 36, height: 36)
        .drawingGroup()
    }
}

struct DashboardView: View {
    @EnvironmentObject var stats: QuizStats

    @State private var chapterCounts: (c1: Int, c2: Int, c3: Int) = (0, 0, 0)

    // Stati per la tabella per capitolo
    @State private var categories: [Category] = []
    @State private var totalQuestionsByCategory: [Int: Int] = [:]
    @State private var answerStatsByCategory: [Int: (totalAnswers: Int, uniqueCorrectQuestions: Int, totalWrongAnswers: Int)] = [:]

    // Exam preparation score (0...100) computed from DB aggregates
    @State private var examPreparationScore: Int = 0

    // Aggregati globali per riepilogo
    @State private var totalAnswersAll: Int = 0
    @State private var totalWrongAll: Int = 0

    // Recent quiz sessions
    @State private var sessions: [QuizSessionSummary] = []
    
    // Streak based on distinct days with at least one quiz, counting backwards from today without gaps
    @State private var streakDays: Int = 0

    var passRate: Double {
        guard stats.quizzesTaken > 0 else { return 0 }
        return Double(stats.quizzesPassed) / Double(stats.quizzesTaken)
    }

    // Soglia considerata "passato" (coerente con QuizView)
    private let passThreshold: Double = 0.75

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
            
                OverviewGrid(
                    quizzesPassed: stats.quizzesPassed,
                    quizzesTaken: stats.quizzesTaken,
                    totalSeenQuestions: totalAnswersAll,
                    totalQuestionsInDB: stats.totalQuestionsInDB,
                    streakDays: streakDays
                )

                SectionTitle("Start New Quiz")
                StartQuizGrid()

                SectionTitle("Chapter Progress")
                ChapterProgressList(
                    categories: categories,
                    totals: totalQuestionsByCategory,
                    stats: answerStatsByCategory
                )

                if !sessions.isEmpty {
                    SectionTitle("Quiz History", trailing: AnyView(
                        NavigationLink("View All", destination: HistoryListView(sessions: sessions))
                            .font(.system(size: 14, weight: .semibold))
                    ))
                    HistoryCards(sessions: sessions)
                }

                Spacer(minLength: 8)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
        }
        .background(Color(red: 0.07, green: 0.10, blue: 0.14).ignoresSafeArea())
        .onAppear {
            reloadDashboardData()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            reloadDashboardData()
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                ZStack {
                    Image(systemName: "person.fill")
                        .foregroundColor(.primary)
                }
                .frame(width: 32, height: 32)
                .accessibilityLabel("Profile")
            }
            ToolbarItem(placement: .principal) {
                VStack(spacing: 2) {
                    Text("WELCOME BACK")
                        .font(.system(size: 11, weight: .bold))
                        .opacity(0.7)
                    Text("Luke")
                        .font(.system(size: 20, weight: .heavy))
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                NavGauge(percent: stats.quizzesTaken > 0 ? Double(stats.quizzesPassed) / Double(max(1, stats.quizzesTaken)) : 0)
            }
        }
    }

    private func reloadDashboardData() {
        stats.totalQuestionsInDB = DatabaseManager.shared.totalQuestionCount()
        categories = DatabaseManager.shared.fetchCategories()
        totalQuestionsByCategory = DatabaseManager.shared.totalQuestionsPerCategory()
        answerStatsByCategory = DatabaseManager.shared.answeredStatsPerCategory()
        sessions = DatabaseManager.shared.fetchQuizSessions()
        
        streakDays = computeDailyStreak(from: sessions)

        // Compute preparation score (tenuto pronto per usi futuri)
        let scores = DatabaseManager.shared.preparationScores(k: 30)
        examPreparationScore = scores.examScore

        // Aggregati globali per riepilogo
        let allValues = Array(answerStatsByCategory.values)
        totalAnswersAll = allValues.reduce(0) { $0 + $1.totalAnswers }
        totalWrongAll = allValues.reduce(0) { $0 + $1.totalWrongAnswers }
    }
    
    private func computeDailyStreak(from sessions: [QuizSessionSummary]) -> Int {
        let calendar = Calendar.current
        let uniqueDays: Set<Date> = Set(sessions.map { calendar.startOfDay(for: $0.endedAt) })
        guard !uniqueDays.isEmpty else { return 0 }

        let today = calendar.startOfDay(for: Date())
        var startDay = today
        var streak = 0

        // If there's no quiz today, start counting from yesterday
        if !uniqueDays.contains(today) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: today) else { return 0 }
            startDay = yesterday
        }

        var day = startDay
        while uniqueDays.contains(day) {
            streak += 1
            guard let prev = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = prev
        }
        return streak
    }
}

@ViewBuilder
private func SectionTitle(_ title: String, trailing: AnyView? = nil) -> some View {
    HStack {
        Text(title)
            .font(.system(size: 18, weight: .heavy))
            .foregroundColor(.white)
        Spacer()
        if let trailing { trailing }
    }
    .padding(.top, 4)
}

private struct OverviewGrid: View {
    @EnvironmentObject var stats: QuizStats

    let quizzesPassed: Int
    let quizzesTaken: Int
    let totalSeenQuestions: Int
    let totalQuestionsInDB: Int
    let streakDays: Int

    var readinessPercent: Int {
        guard quizzesTaken > 0 else { return 0 }
        return Int(round(Double(quizzesPassed) * 100.0 / Double(max(quizzesTaken, 1))))
    }
    var seenPercent: Int {
        guard totalQuestionsInDB > 0 else { return 0 }
        return Int(round(Double(totalSeenQuestions) * 100.0 / Double(totalQuestionsInDB)))
    }

    let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            NavigationLink { StatsView().environmentObject(stats) } label: {
                MetricCard(title: "Readiness", value: "\(readinessPercent)", icon: "gauge", color: .blue, suffix: "%")
                    .id("overview.readiness")
            }.buttonStyle(.plain)

            NavigationLink { StatsView().environmentObject(stats) } label: {
                MetricCard(title: "Passed", value: "\(quizzesPassed)", icon: "checkmark.seal.fill", color: .green, suffix: "quizzes")
                    .id("overview.passed")
            }.buttonStyle(.plain)

            NavigationLink { StatsView().environmentObject(stats) } label: {
                MetricCard(title: "Seen", value: "\(seenPercent)", icon: "eye", color: .blue, suffix: "%", progress: Double(seenPercent) / 100.0)
                    .id("overview.seen")
            }.buttonStyle(.plain)

            NavigationLink { StatsView().environmentObject(stats) } label: {
                MetricCard(title: "Streak", value: "\(streakDays)", icon: "flame.fill", color: .orange, suffix: "days")
                    .id("overview.streak")
            }.buttonStyle(.plain)
        }
    }
}

private struct MetricCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    // Optional suffix shown next to the value (e.g., "quizzes", "days", "%")
    var suffix: String? = nil
    // Optional progress (0...1) for cards like "Seen"
    var progress: Double? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Top row: compact icon left, title right
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(color.opacity(0.15))
                    Image(systemName: icon)
                        .foregroundColor(color)
                        .font(.system(size: 13, weight: .bold))
                }
                .frame(width: 22, height: 22)

                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white.opacity(0.85))
                Spacer()
            }

            // Big value line with optional suffix
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(value)
                    .font(.system(size: 28, weight: .heavy))
                    .foregroundColor(.white)
                if let suffix, !suffix.isEmpty {
                    Text(suffix)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white.opacity(0.75))
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
    }
}

private struct StartQuizGrid: View {
    let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            NavigationLink {
                QuizView(mode: .exam)
            } label: {
                StartCard(
                    id: "exam",
                    title: "Exam Sim",
                    subtitle: "Full length test mode",
                    icon: "timer",
                    color: .blue
                )
                .id("exam")
            }
            .buttonStyle(.plain)

            NavigationLink {
                QuizView(mode: .quick10)
            } label: {
                StartCard(
                    id: "quick10",
                    title: "Quick Quiz",
                    subtitle: "10 random questions",
                    icon: "bolt.fill",
                    color: .green
                )
                .id("quick10")
            }
            .buttonStyle(.plain)

            NavigationLink {
                QuizView(mode: .reviewWrong)
            } label: {
                StartCard(
                    id: "reviewWrong",
                    title: "Errors Retry",
                    subtitle: "Practice mistakes",
                    icon: "arrow.triangle.2.circlepath",
                    color: .orange
                )
                .id("reviewWrong")
            }
            .buttonStyle(.plain)

            NavigationLink {
                ChapterSelectionView()
            } label: {
                StartCard(
                    id: "byChapter",
                    title: "By Chapter",
                    subtitle: "Select topic",
                    icon: "book.closed.fill",
                    color: .purple
                )
                .id("byChapter")
            }
            .buttonStyle(.plain)
        }
    }
}

private struct StartCard: View {
    let id: String
    let title: String
    let subtitle: String
    let icon: String
    let color: Color

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.white.opacity(0.08))
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10).fill(color.opacity(0.25))
                        Image(systemName: icon).foregroundColor(.white)
                    }
                    .frame(width: 36, height: 36)
                    Spacer()
                }
                Text(title)
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundColor(.white)
                Text(subtitle)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.7))
            }
            .padding(16)
        }
        .frame(height: 120)
    }
}

private struct HistoryCards: View {
    let sessions: [QuizSessionSummary]
    var body: some View {
        VStack(spacing: 12) {
            ForEach(Array(sessions.prefix(5)), id: \.id) { s in
                NavigationLink {
                    QuizSessionDetailView(session: s)
                } label: {
                    HistoryCard(session: s)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct HistoryCard: View {
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
        }
        .padding(8)
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

private struct ChapterProgressList: View {
    let categories: [Category]
    let totals: [Int: Int]
    let stats: [Int: (totalAnswers: Int, uniqueCorrectQuestions: Int, totalWrongAnswers: Int)]

    var body: some View {
        VStack(spacing: 12) {
            ForEach(categories) { cat in
                let totalQ = totals[cat.id] ?? 0
                let s = stats[cat.id] ?? (0, 0, 0)
                NavigationLink {
                    ChapterQuestionsView(chapterId: cat.id, chapterName: cat.name)
                } label: {
                    ChapterProgressCard(
                        chapterId: cat.id,
                        name: cat.name,
                        totalQuestions: totalQ,
                        right: s.uniqueCorrectQuestions,
                        wrong: s.totalWrongAnswers
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct ChapterProgressCard: View {
    let chapterId: Int
    let name: String
    let totalQuestions: Int
    let right: Int
    let wrong: Int

    private var left: Int { max(0, totalQuestions - (right + wrong)) }
    private var percent: Int {
        guard totalQuestions > 0 else { return 0 }
        return Int(round(Double(right) * 100.0 / Double(totalQuestions)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(spacing: 8) {
                    // Number badge icon for chapter index; now uses chapterId directly
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.white.opacity(0.12))
                            .frame(width: 32, height: 32)
                        Text("\(chapterId)")
                            .font(.system(size: 14, weight: .heavy))
                            .foregroundColor(.white)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(formattedChapterTitle(name))
                            .font(.system(size: 16, weight: .heavy))
                            .foregroundColor(.white)
                        Text("\(totalQuestions) total questions")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white.opacity(0.6))
                    }
                }
                Spacer()
                Text("\(percent)%")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundColor(.white.opacity(0.9))
            }

            GeometryReader { geo in
                let width = geo.size.width
                let total = max(1, totalQuestions)
                let wRight = width * CGFloat(right) / CGFloat(total)
                let wWrong = width * CGFloat(wrong) / CGFloat(total)
                let wLeft  = width - (wRight + wWrong)

                HStack(spacing: 0) {
                    Rectangle().fill(Color.green).frame(width: wRight)
                    Rectangle().fill(Color.red).frame(width: wWrong)
                    Rectangle().fill(Color.white.opacity(0.15)).frame(width: max(0, wLeft))
                }
                .clipShape(Capsule())
            }
            .frame(height: 10)

            HStack(spacing: 16) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 10, height: 10)
                    Text("\(right) Right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white.opacity(0.8))
                }
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 10, height: 10)
                    Text("\(wrong) Wrong")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white.opacity(0.8))
                }
                Spacer()
                Text("\(left) Left")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.6))
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.white.opacity(0.06))
        )
    }

    private func formattedChapterTitle(_ title: String) -> String {
        // Lowercase then capitalized (first letter uppercase, rest lowercase for each word)
        let lower = title.lowercased()
        return lower.capitalized
    }
}

private struct Badge: View {
    let text: String
    let color: Color
    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(color == .white.opacity(0.4) ? .white.opacity(0.8) : color)
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .background(
                Capsule()
                    .fill(color.opacity(0.15))
            )
    }
}

// Simple categories list for "By Chapter" card
private struct CategoriesListView: View {
    @State private var categories: [Category] = []
    var body: some View {
        List(categories) { cat in
            NavigationLink(destination: ChapterQuestionsView(chapterId: cat.id, chapterName: cat.name)) {
                Text(cat.name)
            }
        }
        .onAppear {
            categories = DatabaseManager.shared.fetchCategories()
        }
        .navigationTitle("Chapters")
    }
}

