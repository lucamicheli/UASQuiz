//
//  StatsView.swift
//  UASA2QUIZ
//
//  Created by Assistant on 16/12/2025.
//

import SwiftUI

struct StatsView: View {
    @EnvironmentObject var stats: QuizStats

    // Source-of-truth pulled similarly to DashboardView
    @State private var categories: [Category] = []
    @State private var totals: [Int: Int] = [:]
    @State private var perCategory: [Int: (totalAnswers: Int, uniqueCorrectQuestions: Int, totalWrongAnswers: Int)] = [:]
    @State private var sessions: [QuizSessionSummary] = []
    @State private var streakDays: Int = 0

    // Derived
    private var accuracy: Double {
        guard stats.quizzesTaken > 0 else { return 0 }
        return Double(stats.totalCorrectAnswers) / Double(max(1, stats.totalAnswers))
    }

    private var masteryPercent: Int {
        // Heuristic: proportion of uniquely correct questions over total in DB
        let totalsArr = Array(perCategory.values)
        let uniqueCorrect = totalsArr.reduce(0) { $0 + $1.uniqueCorrectQuestions }
        let totalQ = stats.totalQuestionsInDB
        guard totalQ > 0 else { return 0 }
        return Int(round(Double(uniqueCorrect) * 100.0 / Double(totalQ)))
    }

    private var quizzesCompleted: Int { stats.quizzesTaken }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                MasteryCard(mastery: masteryPercent, accuracy: Int(round(accuracy * 100)), quizzes: quizzesCompleted, streakDays: streakDays)

                DailyActivityCard(sessions: sessions)

                MonthlyStreakCard(sessions: sessions)

                AllExamResultsCard(sessions: sessions)

                StrengthFocusRow(categories: categories, totals: totals, perCategory: perCategory)

                TopicBreakdownList(categories: categories, totals: totals, perCategory: perCategory)
            }
            .padding(16)
        }
        .background(Color(red: 0.07, green: 0.10, blue: 0.14).ignoresSafeArea())
        .navigationTitle("Overview")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Overview")
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(.primary)
            }
        }
        .onAppear(perform: reload)
    }


    private func reload() {
        stats.totalQuestionsInDB = DatabaseManager.shared.totalQuestionCount()
        categories = DatabaseManager.shared.fetchCategories()
        totals = DatabaseManager.shared.totalQuestionsPerCategory()
        perCategory = DatabaseManager.shared.answeredStatsPerCategory()
        sessions = DatabaseManager.shared.fetchQuizSessions()
        streakDays = computeDailyStreak(from: sessions)
    }

    private func computeDailyStreak(from sessions: [QuizSessionSummary]) -> Int {
        let calendar = Calendar.current
        let uniqueDays: Set<Date> = Set(sessions.map { calendar.startOfDay(for: $0.endedAt) })
        guard !uniqueDays.isEmpty else { return 0 }

        let today = calendar.startOfDay(for: Date())
        var startDay = today
        var streak = 0

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

// MARK: - Components

private struct MasteryCard: View {
    let mastery: Int
    let accuracy: Int
    let quizzes: Int
    let streakDays: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center) {
                DonutProgress(percent: Double(mastery) / 100.0)
                    .frame(width: 120, height: 120)
                Spacer(minLength: 32)
                VStack(alignment: .leading, spacing: 14) {
                    MetricRow(icon: "checkmark.circle.fill", color: .green, title: "Accuracy", value: "\(accuracy)%")
                    MetricRow(icon: "questionmark.circle", color: .blue, title: "Quizzes", value: "\(quizzes)")
                    MetricRow(icon: "flame.fill", color: .orange, title: "Daily Streak", value: "\(streakDays) days")
                }
            }
        }
        .padding(32)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color.white.opacity(0.06)))
    }
}

private struct MetricRow: View {
    let icon: String
    let color: Color
    let title: String
    let value: String
    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(color.opacity(0.2)).frame(width: 24, height: 24)
                .overlay(Image(systemName: icon).foregroundColor(color).font(.system(size: 12, weight: .bold)))
            Text(title).foregroundColor(.white.opacity(0.8)).font(.system(size: 13, weight: .semibold))
            Spacer()
            Text(value).foregroundColor(.white).font(.system(size: 16, weight: .heavy))
        }
    }
}

private struct DonutProgress: View {
    let percent: Double // 0...1
    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.08), lineWidth: 14)
            Circle()
                .trim(from: 0, to: percent)
                .stroke(AngularGradient(gradient: Gradient(colors: [.blue, .blue.opacity(0.9)]), center: .center), style: StrokeStyle(lineWidth: 14, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 2) {
                Text("\(Int(round(percent*100)))%")
                    .font(.system(size: 28, weight: .heavy))
                    .foregroundColor(.white)
                Text("MASTERY")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white.opacity(0.6))
            }
        }
    }
}

private struct DailyActivityCard: View {
    let sessions: [QuizSessionSummary]

    private var countsByWeekday: [Int] {
        var dict: [Int: Int] = [:] // 1..7
        let cal = Calendar.current
        for s in sessions {
            let wd = cal.component(.weekday, from: s.endedAt)
            dict[wd, default: 0] += 1
        }
        return (1...7).map { dict[$0, default: 0] }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Daily Quiz Activity")
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundColor(.white)
                Spacer()
                HStack(spacing: 6) {
                    Circle().fill(Color.blue).frame(width: 6, height: 6)
                    Text("Quizzes Completed")
                        .foregroundColor(.white.opacity(0.7))
                        .font(.system(size: 12, weight: .semibold))
                }
            }
            BarChart(values: countsByWeekday)
                .frame(height: 160)
                .padding(.top, 6)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color.white.opacity(0.06)))
    }
}

private struct BarChart: View {
    let values: [Int] // 7 values
    private let labels = ["Mon","Tue","Wed","Thu","Fri","Sat","Sun"]
    var body: some View {
        GeometryReader { geo in
            let maxV = max(1, values.max() ?? 1)
            HStack(alignment: .bottom, spacing: 12) {
                ForEach(values.indices, id: \.self) { i in
                    VStack(spacing: 6) {
                        Text(values[i] > 0 ? "\(values[i])" : "")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white.opacity(0.7))
                        RoundedRectangle(cornerRadius: 6)
                            .fill(i == (values.firstIndex(of: maxV) ?? -1) ? Color.blue : Color.blue.opacity(0.6))
                            .frame(width: (geo.size.width - 6*12)/7, height: CGFloat(values[i]) / CGFloat(maxV) * (geo.size.height - 30))
                        Text(labels[i])
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.white.opacity(0.6))
                    }
                }
            }
        }
    }
}

private struct StrengthFocusRow: View {
    let categories: [Category]
    let totals: [Int: Int]
    let perCategory: [Int: (totalAnswers: Int, uniqueCorrectQuestions: Int, totalWrongAnswers: Int)]

    private var strongest: (Category, Int)? {
        categories.compactMap { c in
            let total = totals[c.id] ?? 0
            guard total > 0 else { return nil }
            let right = perCategory[c.id]?.uniqueCorrectQuestions ?? 0
            let pct = Int(round(Double(right) * 100.0 / Double(total)))
            return (c, pct)
        }.max(by: { $0.1 < $1.1 })
    }

    private var focus: (Category, Int)? {
        categories.compactMap { c in
            let total = totals[c.id] ?? 0
            guard total > 0 else { return nil }
            let right = perCategory[c.id]?.uniqueCorrectQuestions ?? 0
            let pct = Int(round(Double(right) * 100.0 / Double(total)))
            return (c, pct)
        }.min(by: { $0.1 < $1.1 })
    }

    var body: some View {
        HStack(spacing: 12) {
            if let s = strongest {
                HighlightCard(title: "STRONGEST", icon: "hand.thumbsup.fill", color: .green, name: s.0.name, percent: s.1)
            }
            if let f = focus {
                HighlightCard(title: "FOCUS AREA", icon: "exclamationmark.circle.fill", color: .red, name: f.0.name, percent: f.1)
            }
        }
    }
}

private struct HighlightCard: View {
    let title: String
    let icon: String
    let color: Color
    let name: String
    let percent: Int
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: icon).foregroundColor(color)
                Text(title).foregroundColor(.white.opacity(0.8)).font(.system(size: 12, weight: .heavy))
                Spacer()
            }
            Text(name)
                .foregroundColor(.white)
                .font(.system(size: 18, weight: .heavy))
                .lineLimit(1)
                .truncationMode(.tail)
            ProgressView(value: Double(percent)/100.0)
                .tint(color)
                .progressViewStyle(.linear)
                .padding(.vertical, 4)
            HStack { Spacer(); Text("\(percent)%").foregroundColor(.white.opacity(0.8)).font(.system(size: 12, weight: .bold)) }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(color.opacity(0.18))
        )
    }
}

private struct TopicBreakdownList: View {
    let categories: [Category]
    let totals: [Int: Int]
    let perCategory: [Int: (totalAnswers: Int, uniqueCorrectQuestions: Int, totalWrongAnswers: Int)]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Topic Breakdown")
                .font(.system(size: 18, weight: .heavy))
                .foregroundColor(.white)
            VStack(spacing: 12) {
                ForEach(categories) { c in
                    let total = totals[c.id] ?? 0
                    let right = perCategory[c.id]?.uniqueCorrectQuestions ?? 0
                    let pct = total > 0 ? Double(right) / Double(total) : 0
                    TopicRow(name: c.name, percent: pct)
                }
            }
        }
    }
}

private struct TopicRow: View {
    let name: String
    let percent: Double // 0...1
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().strokeBorder(Color.white.opacity(0.12))
                Text(String(name.prefix(1)).uppercased()).foregroundColor(.white).font(.system(size: 14, weight: .heavy))
            }
            .frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(name).foregroundColor(.white).font(.system(size: 16, weight: .heavy))
                    Spacer()
                    Text("\(Int(round(percent*100)))%")
                        .foregroundColor(.white.opacity(0.8))
                        .font(.system(size: 13, weight: .bold))
                }
                ProgressView(value: percent)
                    .tint(.blue)
                    .progressViewStyle(.linear)
                    .padding(.top, 4)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.06)))
    }
}

private struct MonthlyStreakCard: View {
    let sessions: [QuizSessionSummary]
    private var last28Days: [Date] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        return (0..<28).compactMap { cal.date(byAdding: .day, value: -$0, to: today) }.reversed()
    }

    private var weekdayInitials: [String] {
        let cal = Calendar.current
        let df = DateFormatter()
        df.locale = Locale.current
        df.dateFormat = "E" // short weekday name
        let firstWeek = Array(last28Days.prefix(7))
        return firstWeek.map { date in
            let symbol = df.string(from: date)
            return String(symbol.prefix(1)).uppercased()
        }
    }

    private var activitySet: Set<Date> {
        let cal = Calendar.current
        return Set(sessions.map { cal.startOfDay(for: $0.endedAt) })
    }

    private var streakCount: Int {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        var day = today
        var count = 0
        while activitySet.contains(day) {
            count += 1
            guard let prev = cal.date(byAdding: .day, value: -1, to: day) else { break }
            day = prev
        }
        return count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "flame.fill").foregroundColor(.orange)
                    Text("Monthly Streak").font(.system(size: 18, weight: .heavy)).foregroundColor(.white)
                }
                Spacer()
                Text("\(streakCount) Days").foregroundColor(.white.opacity(0.8)).font(.system(size: 13, weight: .bold))
            }

            let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    ForEach(weekdayInitials, id: \.self) { d in
                        Text(d)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white.opacity(0.6))
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
                LazyVGrid(columns: columns, spacing: 6) {
                    ForEach(Array(last28Days.enumerated()), id: \.offset) { _, d in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(activitySet.contains(d) ? Color.orange : Color.white.opacity(0.12))
                            .frame(width: 14, height: 14)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color.white.opacity(0.06)))
    }
}

private struct AllExamResultsCard: View {
    let sessions: [QuizSessionSummary]

    private var examSessions: [QuizSessionSummary] {
        let exams = sessions.filter { $0.mode == "exam" }.sorted { $0.endedAt < $1.endedAt }
        return Array(exams.suffix(10))
    }

    private struct ExamSlot: Identifiable {
        let id: Int
        let correct: Int
        let total: Int
        let isPlaceholder: Bool
        let label: String
    }

    private var slots: [ExamSlot] {
        let items = examSessions
        let count = items.count
        let startIndex = max(0, 10 - count)
        var arr: [ExamSlot] = []
        let df = DateFormatter()
        df.dateFormat = "dd/MM"
        // pad leading placeholders so newest are at the right
        if startIndex > 0 {
            for i in 0..<startIndex {
                arr.append(ExamSlot(id: i, correct: 0, total: 0, isPlaceholder: true, label: "--/--"))
            }
        }
        for (idx, s) in items.enumerated() {
            arr.append(ExamSlot(id: startIndex + idx, correct: s.correctAnswers, total: s.totalQuestions, isPlaceholder: false, label: df.string(from: s.endedAt)))
        }
        return arr
    }

    private var passThreshold: Double { 0.75 }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("All Exam Results")
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundColor(.white)
                Spacer()
                HStack(spacing: 8) {
                    Circle().fill(Color.green).frame(width: 8, height: 8)
                    Text("Passed").foregroundColor(.white.opacity(0.7)).font(.system(size: 12, weight: .semibold))
                    Circle().fill(Color.red).frame(width: 8, height: 8)
                    Text("Failed").foregroundColor(.white.opacity(0.7)).font(.system(size: 12, weight: .semibold))
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                let maxCorrect = max(1, slots.map { $0.correct }.max() ?? 1)
                let thresholdBasis = max(slots.last?.total ?? 0, 100)
                let thresholdValue = Int(round(passThreshold * Double(thresholdBasis)))
                VStack(alignment: .leading, spacing: 8) {
                    ZStack(alignment: .topLeading) {
                        // Threshold line across the visible area
                        GeometryReader { geo in
                            let thresholdY = geo.size.height - (CGFloat(thresholdValue) / CGFloat(maxCorrect)) * (geo.size.height - 24)
                            Path { p in
                                p.move(to: CGPoint(x: 0, y: thresholdY))
                                p.addLine(to: CGPoint(x: geo.size.width, y: thresholdY))
                            }
                            .stroke(Color.white.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [6,6]))
                        }
                        .allowsHitTesting(false)
                        HStack(alignment: .bottom, spacing: 12) {
                            ForEach(Array(slots.enumerated()), id: \.offset) { i, slot in
                                VStack(spacing: 6) {
                                    let passed = slot.total > 0 && (Double(slot.correct) >= passThreshold * Double(slot.total))
                                    let barColor: Color = slot.total == 0 ? Color.white.opacity(0.12) : (passed ? .green : .red)
                                    let height = max(4, CGFloat(slot.total == 0 ? 0 : slot.correct) / CGFloat(maxCorrect) * 140)
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(barColor)
                                        .frame(width: 28, height: height)
                                    Text(slot.label)
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundColor(.white.opacity(0.7))
                                }
                            }
                        }
                        .padding(.vertical, 12)
                    }
                    .frame(height: 180)
                }
                .padding(.horizontal, 4)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color.white.opacity(0.06)))
    }
}

