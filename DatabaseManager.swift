import Foundation
import SQLite3

// Swift bridge for SQLITE_TRANSIENT (-1 cast to sqlite3_destructor_type)
private let SQLITE_TRANSIENT_SWIFT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

struct Category: Identifiable, Hashable {
    let id: Int
    let name: String
}

// MARK: - Quiz History Models

struct QuizSessionSummary: Identifiable, Hashable {
    let id: Int64
    let mode: String
    let startedAt: Date
    let endedAt: Date
    let durationSeconds: Int
    let totalQuestions: Int
    let correctAnswers: Int
    let points: Int
    let passed: Bool
}

struct QuizSessionAnswerDetail: Identifiable, Hashable {
    let id: Int64
    let sessionId: Int64
    let orderIndex: Int
    let questionId: Int
    let selectedIndex: Int?
    let isCorrect: Bool
}

final class DatabaseManager {
    static let shared = DatabaseManager()
    
    private var db: OpaquePointer?
    private let dbFilename = "questions.sqlite"
    private let queue = DispatchQueue(label: "DatabaseManagerQueue")
    
    private init() {
        prepareDatabaseFileIfNeeded()
        openDatabase()
        enableForeignKeys()
        createUserAnswerTableIfNeeded()
        createQuizHistoryTablesIfNeeded()
        createUserFavoriteTableIfNeeded()
        print("📦 Database ready at: \(databasePath())")
    }
    
    deinit {
        if db != nil {
            sqlite3_close(db)
        }
    }
    
    // MARK: - Public API
    
    func totalQuestionCount() -> Int {
        var count = 0
        let sql = "SELECT COUNT(*) FROM question;"
        queue.sync {
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                if sqlite3_step(stmt) == SQLITE_ROW {
                    count = Int(sqlite3_column_int(stmt, 0))
                }
            } else {
                logLastError(prefix: "Prepare totalQuestionCount failed")
            }
            sqlite3_finalize(stmt)
        }
        return count
    }
    
    func fetchCategories() -> [Category] {
        var categories: [Category] = []
        let sql = "SELECT id, name FROM category ORDER BY id ASC;"
        queue.sync {
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                while sqlite3_step(stmt) == SQLITE_ROW {
                    let id = Int(sqlite3_column_int(stmt, 0))
                    let nameCStr = sqlite3_column_text(stmt, 1)
                    let name = nameCStr.flatMap { String(cString: $0) } ?? ""
                    categories.append(Category(id: id, name: name))
                }
            } else {
                logLastError(prefix: "fetchCategories prepare failed")
            }
            sqlite3_finalize(stmt)
        }
        return categories
    }
    
    func fetchQuestions(limit: Int?) -> [Question] {
        var questions: [(id: Int, text: String, correctIndex: Int)] = []
        var results: [Question] = []
        
        let limitClause = (limit != nil) ? " LIMIT \(limit!)" : ""
        let qSql = """
        SELECT q.id, q.question, q.correct_index
        FROM question q
        ORDER BY RANDOM()
        \(limitClause);
        """
        
        queue.sync {
            var qStmt: OpaquePointer?
            if sqlite3_prepare_v2(db, qSql, -1, &qStmt, nil) == SQLITE_OK {
                while sqlite3_step(qStmt) == SQLITE_ROW {
                    let id = Int(sqlite3_column_int(qStmt, 0))
                    let questionCStr = sqlite3_column_text(qStmt, 1)
                    let correctIndex = Int(sqlite3_column_int(qStmt, 2))
                    let questionText = questionCStr.flatMap { String(cString: $0) } ?? ""
                    questions.append((id: id, text: questionText, correctIndex: correctIndex))
                }
            } else {
                logLastError(prefix: "Prepare fetchQuestions failed")
            }
            sqlite3_finalize(qStmt)
            
            if questions.isEmpty {
                results = []
                return
            }
            
            results = assembleQuestions(from: questions)
        }
        
        return results
    }
    
    func fetchQuestionsForChapter(chapterId: Int, limit: Int = 30) -> [Question] {
        var questions: [(id: Int, text: String, correctIndex: Int)] = []
        var results: [Question] = []
        
        let qSql = """
        SELECT q.id, q.question, q.correct_index
        FROM question q
        WHERE q.category_id = ?
        ORDER BY RANDOM()
        LIMIT ?;
        """
        
        queue.sync {
            var qStmt: OpaquePointer?
            if sqlite3_prepare_v2(db, qSql, -1, &qStmt, nil) == SQLITE_OK {
                sqlite3_bind_int(qStmt, 1, Int32(chapterId))
                sqlite3_bind_int(qStmt, 2, Int32(limit))
                
                while sqlite3_step(qStmt) == SQLITE_ROW {
                    let id = Int(sqlite3_column_int(qStmt, 0))
                    let questionCStr = sqlite3_column_text(qStmt, 1)
                    let correctIndex = Int(sqlite3_column_int(qStmt, 2))
                    let questionText = questionCStr.flatMap { String(cString: $0) } ?? ""
                    questions.append((id: id, text: questionText, correctIndex: correctIndex))
                }
            } else {
                logLastError(prefix: "Prepare fetchQuestionsForChapter failed")
            }
            sqlite3_finalize(qStmt)
            
            if questions.isEmpty {
                results = []
                return
            }
            
            results = assembleQuestions(from: questions)
        }
        
        return results
    }
    
    func fetchQuestionsForExamDistribution() -> [Question] {
        let c1 = fetchQuestionsForChapter(chapterId: 1, limit: 10)
        let c2 = fetchQuestionsForChapter(chapterId: 2, limit: 10)
        let c3 = fetchQuestionsForChapter(chapterId: 3, limit: 10)
        let combined = c1 + c2 + c3
        return combined.shuffled()
    }
    
    // MARK: - Review wrong
    
    func fetchWrongQuestionIDs() -> [Int] {
        var ids: [Int] = []
        let sql = """
        SELECT question_id
        FROM user_answer
        GROUP BY question_id
        HAVING SUM(CASE WHEN is_correct = 1 THEN 1 ELSE 0 END) = 0
           AND SUM(CASE WHEN is_correct = 0 THEN 1 ELSE 0 END) > 0;
        """
        queue.sync {
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                while sqlite3_step(stmt) == SQLITE_ROW {
                    let qid = Int(sqlite3_column_int(stmt, 0))
                    ids.append(qid)
                }
            } else {
                logLastError(prefix: "fetchWrongQuestionIDs prepare failed")
            }
            sqlite3_finalize(stmt)
        }
        return ids
    }
    
    func fetchQuestionsByIDs(_ ids: [Int]) -> [Question] {
        guard !ids.isEmpty else { return [] }
        var rows: [(id: Int, text: String, correctIndex: Int)] = []
        var results: [Question] = []
        
        let placeholders = ids.map { _ in "?" }.joined(separator: ",")
        let qSql = """
        SELECT q.id, q.question, q.correct_index
        FROM question q
        WHERE q.id IN (\(placeholders))
        ORDER BY q.id ASC;
        """
        
        queue.sync {
            var qStmt: OpaquePointer?
            if sqlite3_prepare_v2(db, qSql, -1, &qStmt, nil) == SQLITE_OK {
                for (i, id) in ids.enumerated() {
                    sqlite3_bind_int(qStmt, Int32(i + 1), Int32(id))
                }
                while sqlite3_step(qStmt) == SQLITE_ROW {
                    let id = Int(sqlite3_column_int(qStmt, 0))
                    let questionCStr = sqlite3_column_text(qStmt, 1)
                    let correctIndex = Int(sqlite3_column_int(qStmt, 2))
                    let questionText = questionCStr.flatMap { String(cString: $0) } ?? ""
                    rows.append((id, questionText, correctIndex))
                }
            } else {
                logLastError(prefix: "fetchQuestionsByIDs prepare failed")
            }
            sqlite3_finalize(qStmt)
            
            if rows.isEmpty {
                results = []
                return
            }
            results = assembleQuestions(from: rows)
        }
        
        return results
    }
    
    // MARK: - Answers persistence (user_answer)
    
    private func createUserAnswerTableIfNeeded() {
        let sql = """
        CREATE TABLE IF NOT EXISTS user_answer (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            question_id INTEGER NOT NULL,
            chapter_id INTEGER NOT NULL,
            is_correct INTEGER NOT NULL,
            answered_at INTEGER NOT NULL,
            FOREIGN KEY(question_id) REFERENCES question(id) ON DELETE CASCADE
        );
        """
        queue.sync {
            if sqlite3_exec(db, sql, nil, nil, nil) != SQLITE_OK {
                logLastError(prefix: "Create user_answer failed")
            }
        }
    }
    
    private func chapterIdForQuestion(_ questionId: Int) -> Int? {
        var result: Int?
        let sql = "SELECT category_id FROM question WHERE id = ? LIMIT 1;"
        queue.sync {
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_int(stmt, 1, Int32(questionId))
                if sqlite3_step(stmt) == SQLITE_ROW {
                    result = Int(sqlite3_column_int(stmt, 0))
                }
            } else {
                logLastError(prefix: "Prepare chapterIdForQuestion failed")
            }
            sqlite3_finalize(stmt)
        }
        return result
    }
    
    func recordAnswer(questionId: Int, chapterId explicitChapterId: Int? = nil, isCorrect: Bool, answeredAt: Date = Date()) {
        let chapterId = explicitChapterId ?? chapterIdForQuestion(questionId)
        guard let chapterId else {
            print("⚠️ recordAnswer: missing chapterId for question \(questionId)")
            return
        }
        let timestamp = Int(answeredAt.timeIntervalSince1970)
        let sql = """
        INSERT INTO user_answer (question_id, chapter_id, is_correct, answered_at)
        VALUES (?, ?, ?, ?);
        """
        queue.sync {
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_int(stmt, 1, Int32(questionId))
                sqlite3_bind_int(stmt, 2, Int32(chapterId))
                sqlite3_bind_int(stmt, 3, isCorrect ? 1 : 0)
                sqlite3_bind_int(stmt, 4, Int32(timestamp))
                if sqlite3_step(stmt) != SQLITE_DONE {
                    logLastError(prefix: "recordAnswer step failed")
                }
            } else {
                logLastError(prefix: "recordAnswer prepare failed")
            }
            sqlite3_finalize(stmt)
        }
    }
    
    func answeredCountsPerChapter() -> (c1: Int, c2: Int, c3: Int) {
        var counts: [Int: Int] = [:]
        let sql = """
        SELECT chapter_id, COUNT(*) AS cnt
        FROM user_answer
        GROUP BY chapter_id;
        """
        queue.sync {
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                while sqlite3_step(stmt) == SQLITE_ROW {
                    let chap = Int(sqlite3_column_int(stmt, 0))
                    let cnt = Int(sqlite3_column_int(stmt, 1))
                    counts[chap] = cnt
                }
            } else {
                logLastError(prefix: "answeredCountsPerChapter prepare failed")
            }
            sqlite3_finalize(stmt)
        }
        let c1 = counts[1] ?? 0
        let c2 = counts[2] ?? 0
        let c3 = counts[3] ?? 0
        return (c1, c2, c3)
    }
    
    func totalAnsweredCount() -> Int {
        var total = 0
        let sql = "SELECT COUNT(*) FROM user_answer;"
        queue.sync {
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                if sqlite3_step(stmt) == SQLITE_ROW {
                    total = Int(sqlite3_column_int(stmt, 0))
                }
            } else {
                logLastError(prefix: "totalAnsweredCount prepare failed")
            }
            sqlite3_finalize(stmt)
        }
        return total
    }
    
    // MARK: - Aggregates for dashboard table
    
    func totalQuestionsPerCategory() -> [Int: Int] {
        var result: [Int: Int] = [:]
        let sql = """
        SELECT category_id, COUNT(*) AS total
        FROM question
        GROUP BY category_id;
        """
        queue.sync {
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                while sqlite3_step(stmt) == SQLITE_ROW {
                    let catId = Int(sqlite3_column_int(stmt, 0))
                    let total = Int(sqlite3_column_int(stmt, 1))
                    result[catId] = total
                }
            } else {
                logLastError(prefix: "totalQuestionsPerCategory prepare failed")
            }
            sqlite3_finalize(stmt)
        }
        return result
    }
    
    func answeredStatsPerCategory() -> [Int: (totalAnswers: Int, uniqueCorrectQuestions: Int, totalWrongAnswers: Int)] {
        var totalAnswersMap: [Int: Int] = [:]
        var uniqueCorrectMap: [Int: Int] = [:]
        var totalWrongMap: [Int: Int] = [:]
        
        let sqlTotal = """
        SELECT chapter_id, COUNT(*) AS total_answers
        FROM user_answer
        GROUP BY chapter_id;
        """
        let sqlUniqueCorrect = """
        SELECT chapter_id, COUNT(DISTINCT question_id) AS unique_correct
        FROM user_answer
        WHERE is_correct = 1
        GROUP BY chapter_id;
        """
        let sqlWrong = """
        SELECT chapter_id, COUNT(*) AS total_wrong
        FROM user_answer
        WHERE is_correct = 0
        GROUP BY chapter_id;
        """
        
        queue.sync {
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sqlTotal, -1, &stmt, nil) == SQLITE_OK {
                while sqlite3_step(stmt) == SQLITE_ROW {
                    let chap = Int(sqlite3_column_int(stmt, 0))
                    let total = Int(sqlite3_column_int(stmt, 1))
                    totalAnswersMap[chap] = total
                }
            } else {
                logLastError(prefix: "answeredStatsPerCategory total prepare failed")
            }
            sqlite3_finalize(stmt)
            
            var stmt2: OpaquePointer?
            if sqlite3_prepare_v2(db, sqlUniqueCorrect, -1, &stmt2, nil) == SQLITE_OK {
                while sqlite3_step(stmt2) == SQLITE_ROW {
                    let chap = Int(sqlite3_column_int(stmt2, 0))
                    let uniqueCorrect = Int(sqlite3_column_int(stmt2, 1))
                    uniqueCorrectMap[chap] = uniqueCorrect
                }
            } else {
                logLastError(prefix: "answeredStatsPerCategory uniqueCorrect prepare failed")
            }
            sqlite3_finalize(stmt2)
            
            var stmt3: OpaquePointer?
            if sqlite3_prepare_v2(db, sqlWrong, -1, &stmt3, nil) == SQLITE_OK {
                while sqlite3_step(stmt3) == SQLITE_ROW {
                    let chap = Int(sqlite3_column_int(stmt3, 0))
                    let wrong = Int(sqlite3_column_int(stmt3, 1))
                    totalWrongMap[chap] = wrong
                }
            } else {
                logLastError(prefix: "answeredStatsPerCategory wrong prepare failed")
            }
            sqlite3_finalize(stmt3)
        }
        
        var merged: [Int: (Int, Int, Int)] = [:]
        let allKeys = Set(totalAnswersMap.keys)
            .union(uniqueCorrectMap.keys)
            .union(totalWrongMap.keys)
        for key in allKeys {
            let total = totalAnswersMap[key] ?? 0
            let unique = uniqueCorrectMap[key] ?? 0
            let wrong = totalWrongMap[key] ?? 0
            merged[key] = (total, unique, wrong)
        }
        return merged
    }
    
    // MARK: - Helpers for assembling Questions
    
    private func assembleQuestions(from rows: [(id: Int, text: String, correctIndex: Int)]) -> [Question] {
        var results: [Question] = []
        let ids = rows.map { $0.id }
        let placeholders = ids.map { _ in "?" }.joined(separator: ",")
        // Leggiamo anche is_correct dalle option
        let oSql = """
        SELECT question_id, option_index, text, is_correct
        FROM question_option
        WHERE question_id IN (\(placeholders))
        ORDER BY question_id ASC, option_index ASC;
        """
        var oStmt: OpaquePointer?
        if sqlite3_prepare_v2(db, oSql, -1, &oStmt, nil) == SQLITE_OK {
            for (i, id) in ids.enumerated() {
                sqlite3_bind_int(oStmt, Int32(i + 1), Int32(id))
            }
            // Mappa: questionID -> [(option_index, text, is_correct)]
            var optionsMap: [Int: [(Int, String, Int)]] = [:]
            while sqlite3_step(oStmt) == SQLITE_ROW {
                let qid = Int(sqlite3_column_int(oStmt, 0))
                let optIndex = Int(sqlite3_column_int(oStmt, 1))
                let textCStr = sqlite3_column_text(oStmt, 2)
                let text = textCStr.flatMap { String(cString: $0) } ?? ""
                let isCorrect = Int(sqlite3_column_int(oStmt, 3)) // 0/1
                optionsMap[qid, default: []].append((optIndex, text, isCorrect))
            }
            results = rows.map { q in
                // Ordiniamo per option_index asc
                let tuples = (optionsMap[q.id] ?? []).sorted { $0.0 < $1.0 }
                let opts = tuples.map { $0.1 }
                // Troviamo l'indice corretto usando is_correct
                let correctIdxFromFlag = tuples.firstIndex(where: { $0.2 == 1 }) ?? 0
                return Question(id: q.id, question: q.text, options: opts, correctIndex: correctIdxFromFlag)
            }
        } else {
            logLastError(prefix: "assembleQuestions options prepare failed")
        }
        sqlite3_finalize(oStmt)
        return results
    }
    
    // MARK: - Exam Preparation Score (0–100)

    // Returns per-chapter scores [categoryId: Int(0...100)] and overall exam score (0...100)
    func preparationScores(k: Double = 30) -> (perChapter: [Int: Int], examScore: Int) {
        let totalsByCat = totalQuestionsPerCategory()
        let statsByCat = answeredStatsPerCategory()

        var perChapter: [Int: Int] = [:]
        var weightedSum: Double = 0
        var totalQuestionsSum: Int = 0

        for (catId, totalQuestions) in totalsByCat {
            let stats = statsByCat[catId] ?? (totalAnswers: 0, uniqueCorrectQuestions: 0, totalWrongAnswers: 0)
            let attempts = stats.totalAnswers
            let uniqueCorrect = stats.uniqueCorrectQuestions

            let accuracy: Double = attempts > 0 ? Double(uniqueCorrect) / Double(attempts) : 0
            let coverage: Double = totalQuestions > 0 ? Double(uniqueCorrect) / Double(totalQuestions) : 0
            let reliability: Double = 1.0 - exp(-Double(attempts) / k)
            let coverageBoost: Double = sqrt(max(coverage, 0))
            let accuracyAdjusted: Double = accuracy * (0.5 + 0.5 * reliability)

            var chapterScore = 100.0 * (0.55 * accuracyAdjusted + 0.35 * coverageBoost + 0.10 * reliability)
            chapterScore = max(0, min(100, chapterScore))
            let chapterScoreInt = Int(round(chapterScore))
            perChapter[catId] = chapterScoreInt

            weightedSum += chapterScore * Double(totalQuestions)
            totalQuestionsSum += totalQuestions
        }

        let examScore: Int
        if totalQuestionsSum > 0 {
            examScore = Int(round(weightedSum / Double(totalQuestionsSum)))
        } else {
            examScore = 0
        }

        return (perChapter, examScore)
    }
    
    // MARK: - Quiz History Tables and APIs
    
    private func createQuizHistoryTablesIfNeeded() {
        let sql1 = """
        CREATE TABLE IF NOT EXISTS quiz_session (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            mode TEXT NOT NULL,
            started_at INTEGER NOT NULL,
            ended_at INTEGER NOT NULL,
            duration_seconds INTEGER NOT NULL,
            total_questions INTEGER NOT NULL,
            correct_answers INTEGER NOT NULL,
            points INTEGER NOT NULL,
            passed INTEGER NOT NULL
        );
        """
        let sql2 = """
        CREATE TABLE IF NOT EXISTS quiz_session_answer (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            session_id INTEGER NOT NULL,
            order_index INTEGER NOT NULL,
            question_id INTEGER NOT NULL,
            selected_index INTEGER,
            is_correct INTEGER NOT NULL,
            FOREIGN KEY(session_id) REFERENCES quiz_session(id) ON DELETE CASCADE,
            FOREIGN KEY(question_id) REFERENCES question(id) ON DELETE CASCADE
        );
        """
        queue.sync {
            if sqlite3_exec(db, sql1, nil, nil, nil) != SQLITE_OK {
                logLastError(prefix: "Create quiz_session failed")
            }
            if sqlite3_exec(db, sql2, nil, nil, nil) != SQLITE_OK {
                logLastError(prefix: "Create quiz_session_answer failed")
            }
        }
    }
    
    func startQuizSession(mode: String, totalQuestions: Int, startedAt: Date) -> Int64 {
        let ts = Int(startedAt.timeIntervalSince1970)
        let sql = """
        INSERT INTO quiz_session (mode, started_at, ended_at, duration_seconds, total_questions, correct_answers, points, passed)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?);
        """
        var insertedId: Int64 = 0
        queue.sync {
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_text(stmt, 1, (mode as NSString).utf8String, -1, SQLITE_TRANSIENT_SWIFT)
                sqlite3_bind_int(stmt, 2, Int32(ts))
                sqlite3_bind_int(stmt, 3, Int32(ts))
                sqlite3_bind_int(stmt, 4, 0)
                sqlite3_bind_int(stmt, 5, Int32(totalQuestions))
                sqlite3_bind_int(stmt, 6, 0)
                sqlite3_bind_int(stmt, 7, 0)
                sqlite3_bind_int(stmt, 8, 0)
                if sqlite3_step(stmt) == SQLITE_DONE {
                    insertedId = sqlite3_last_insert_rowid(db)
                } else {
                    logLastError(prefix: "startQuizSession step failed")
                }
            } else {
                logLastError(prefix: "startQuizSession prepare failed")
            }
            sqlite3_finalize(stmt)
        }
        return insertedId
    }
    
    func appendAnswerToSession(sessionId: Int64, orderIndex: Int, questionId: Int, selectedIndex: Int?, isCorrect: Bool) {
        let sql = """
        INSERT INTO quiz_session_answer (session_id, order_index, question_id, selected_index, is_correct)
        VALUES (?, ?, ?, ?, ?);
        """
        queue.sync {
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_int64(stmt, 1, sessionId)
                sqlite3_bind_int(stmt, 2, Int32(orderIndex))
                sqlite3_bind_int(stmt, 3, Int32(questionId))
                if let selectedIndex {
                    sqlite3_bind_int(stmt, 4, Int32(selectedIndex))
                } else {
                    sqlite3_bind_null(stmt, 4)
                }
                sqlite3_bind_int(stmt, 5, isCorrect ? 1 : 0)
                if sqlite3_step(stmt) != SQLITE_DONE {
                    logLastError(prefix: "appendAnswerToSession step failed")
                }
            } else {
                logLastError(prefix: "appendAnswerToSession prepare failed")
            }
            sqlite3_finalize(stmt)
        }
    }
    
    func finishQuizSession(sessionId: Int64, endedAt: Date, correctAnswers: Int, points: Int, passed: Bool, startedAt: Date) {
        let endTS = Int(endedAt.timeIntervalSince1970)
        let startTS = Int(startedAt.timeIntervalSince1970)
        let duration = max(0, endTS - startTS)
        let sql = """
        UPDATE quiz_session
        SET ended_at = ?, duration_seconds = ?, correct_answers = ?, points = ?, passed = ?
        WHERE id = ?;
        """
        queue.sync {
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_int(stmt, 1, Int32(endTS))
                sqlite3_bind_int(stmt, 2, Int32(duration))
                sqlite3_bind_int(stmt, 3, Int32(correctAnswers))
                sqlite3_bind_int(stmt, 4, Int32(points))
                sqlite3_bind_int(stmt, 5, passed ? 1 : 0)
                sqlite3_bind_int64(stmt, 6, sessionId)
                if sqlite3_step(stmt) != SQLITE_DONE {
                    logLastError(prefix: "finishQuizSession step failed")
                }
            } else {
                logLastError(prefix: "finishQuizSession prepare failed")
            }
            sqlite3_finalize(stmt)
        }
    }
    
    func fetchQuizSessions() -> [QuizSessionSummary] {
        var items: [QuizSessionSummary] = []
        let sql = """
        SELECT id, mode, started_at, ended_at, duration_seconds, total_questions, correct_answers, points, passed
        FROM quiz_session
        ORDER BY id DESC;
        """
        queue.sync {
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                while sqlite3_step(stmt) == SQLITE_ROW {
                    let id = sqlite3_column_int64(stmt, 0)
                    let modeC = sqlite3_column_text(stmt, 1)
                    let mode = modeC.flatMap { String(cString: $0) } ?? ""
                    let startedAt = Date(timeIntervalSince1970: TimeInterval(sqlite3_column_int(stmt, 2)))
                    let endedAt = Date(timeIntervalSince1970: TimeInterval(sqlite3_column_int(stmt, 3)))
                    let duration = Int(sqlite3_column_int(stmt, 4))
                    let totalQuestions = Int(sqlite3_column_int(stmt, 5))
                    let correctAnswers = Int(sqlite3_column_int(stmt, 6))
                    let points = Int(sqlite3_column_int(stmt, 7))
                    let passed = sqlite3_column_int(stmt, 8) == 1
                    items.append(
                        QuizSessionSummary(
                            id: id,
                            mode: mode,
                            startedAt: startedAt,
                            endedAt: endedAt,
                            durationSeconds: duration,
                            totalQuestions: totalQuestions,
                            correctAnswers: correctAnswers,
                            points: points,
                            passed: passed
                        )
                    )
                }
            } else {
                logLastError(prefix: "fetchQuizSessions prepare failed")
            }
            sqlite3_finalize(stmt)
        }
        return items
    }
    
    func fetchQuizSessionAnswers(sessionId: Int64) -> [QuizSessionAnswerDetail] {
        var items: [QuizSessionAnswerDetail] = []
        let sql = """
        SELECT id, session_id, order_index, question_id, selected_index, is_correct
        FROM quiz_session_answer
        WHERE session_id = ?
        ORDER BY order_index ASC;
        """
        queue.sync {
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_int64(stmt, 1, sessionId)
                while sqlite3_step(stmt) == SQLITE_ROW {
                    let id = sqlite3_column_int64(stmt, 0)
                    let sessionId = sqlite3_column_int64(stmt, 1)
                    let orderIndex = Int(sqlite3_column_int(stmt, 2))
                    let questionId = Int(sqlite3_column_int(stmt, 3))
                    let hasSel = sqlite3_column_type(stmt, 4) != SQLITE_NULL
                    let selectedIndex = hasSel ? Int(sqlite3_column_int(stmt, 4)) : nil
                    let isCorrect = sqlite3_column_int(stmt, 5) == 1
                    items.append(
                        QuizSessionAnswerDetail(
                            id: id,
                            sessionId: sessionId,
                            orderIndex: orderIndex,
                            questionId: questionId,
                            selectedIndex: selectedIndex,
                            isCorrect: isCorrect
                        )
                    )
                }
            } else {
                logLastError(prefix: "fetchQuizSessionAnswers prepare failed")
            }
            sqlite3_finalize(stmt)
        }
        return items
    }
    
    // MARK: - Favorites (user_favorite)
    
    private func createUserFavoriteTableIfNeeded() {
        let sql = """
        CREATE TABLE IF NOT EXISTS user_favorite (
            question_id INTEGER PRIMARY KEY,
            created_at INTEGER NOT NULL DEFAULT (strftime('%s','now')),
            FOREIGN KEY(question_id) REFERENCES question(id) ON DELETE CASCADE
        );
        """
        queue.sync {
            if sqlite3_exec(db, sql, nil, nil, nil) != SQLITE_OK {
                logLastError(prefix: "Create user_favorite failed")
            }
        }
    }
    
    func favoriteQuestionIDs() -> Set<Int> {
        var ids: Set<Int> = []
        let sql = "SELECT question_id FROM user_favorite;"
        queue.sync {
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                while sqlite3_step(stmt) == SQLITE_ROW {
                    let qid = Int(sqlite3_column_int(stmt, 0))
                    ids.insert(qid)
                }
            } else {
                logLastError(prefix: "favoriteQuestionIDs prepare failed")
            }
            sqlite3_finalize(stmt)
        }
        return ids
    }
    
    func addFavorite(questionId: Int) {
        let sql = "INSERT OR IGNORE INTO user_favorite (question_id) VALUES (?);"
        queue.sync {
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_int(stmt, 1, Int32(questionId))
                if sqlite3_step(stmt) != SQLITE_DONE {
                    logLastError(prefix: "addFavorite step failed")
                }
            } else {
                logLastError(prefix: "addFavorite prepare failed")
            }
            sqlite3_finalize(stmt)
        }
    }
    
    func removeFavorite(questionId: Int) {
        let sql = "DELETE FROM user_favorite WHERE question_id = ?;"
        queue.sync {
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_int(stmt, 1, Int32(questionId))
                if sqlite3_step(stmt) != SQLITE_DONE {
                    logLastError(prefix: "removeFavorite step failed")
                }
            } else {
                logLastError(prefix: "removeFavorite prepare failed")
            }
            sqlite3_finalize(stmt)
        }
    }
    
    // MARK: - Seen/Wrong helpers
    
    func seenQuestionIDs(for questionIDs: [Int]) -> Set<Int> {
        guard !questionIDs.isEmpty else { return [] }
        var result: Set<Int> = []
        let placeholders = questionIDs.map { _ in "?" }.joined(separator: ",")
        let sql = """
        SELECT DISTINCT question_id
        FROM user_answer
        WHERE question_id IN (\(placeholders));
        """
        queue.sync {
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                for (i, id) in questionIDs.enumerated() {
                    sqlite3_bind_int(stmt, Int32(i + 1), Int32(id))
                }
                while sqlite3_step(stmt) == SQLITE_ROW {
                    let qid = Int(sqlite3_column_int(stmt, 0))
                    result.insert(qid)
                }
            } else {
                logLastError(prefix: "seenQuestionIDs prepare failed")
            }
            sqlite3_finalize(stmt)
        }
        return result
    }
    
    func wrongQuestionIDs(for questionIDs: [Int]) -> Set<Int> {
        guard !questionIDs.isEmpty else { return [] }
        var result: Set<Int> = []
        let placeholders = questionIDs.map { _ in "?" }.joined(separator: ",")
        let sql = """
        SELECT DISTINCT question_id
        FROM user_answer
        WHERE is_correct = 0
          AND question_id IN (\(placeholders));
        """
        queue.sync {
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                for (i, id) in questionIDs.enumerated() {
                    sqlite3_bind_int(stmt, Int32(i + 1), Int32(id))
                }
                while sqlite3_step(stmt) == SQLITE_ROW {
                    let qid = Int(sqlite3_column_int(stmt, 0))
                    result.insert(qid)
                }
            } else {
                logLastError(prefix: "wrongQuestionIDs prepare failed")
            }
            sqlite3_finalize(stmt)
        }
        return result
    }
    
    // MARK: - Setup
    
    private func openDatabase() {
        let url = databaseURL()
        let path = url.path
        if sqlite3_open(path, &db) != SQLITE_OK {
            print("❌ Unable to open database at \(path)")
        }
    }
    
    private func enableForeignKeys() {
        queue.sync {
            if sqlite3_exec(db, "PRAGMA foreign_keys = ON;", nil, nil, nil) != SQLITE_OK {
                logLastError(prefix: "Enable foreign_keys failed")
            }
        }
    }
    
    private func prepareDatabaseFileIfNeeded() {
        let fm = FileManager.default
        let destURL = databaseURL()
        if fm.fileExists(atPath: destURL.path) {
            return
        }
        if let bundledURL = Bundle.main.url(forResource: "questions", withExtension: "sqlite") {
            do {
                try fm.copyItem(at: bundledURL, to: destURL)
            } catch {
                print("⚠️ Failed to copy bundled questions.sqlite: \(error)")
            }
        } else {
            fm.createFile(atPath: destURL.path, contents: nil)
        }
    }
    
    private func databaseURL() -> URL {
        let fm = FileManager.default
        let baseDir = try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let dir = baseDir?.appendingPathComponent("UASA2QUIZ", isDirectory: true)
        if let dir, !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return (dir ?? fm.temporaryDirectory).appendingPathComponent(dbFilename)
    }
    
    func databasePath() -> String {
        databaseURL().path
    }
    
    private func logLastError(prefix: String) {
        if let err = sqlite3_errmsg(db) {
            print("❌ \(prefix): \(String(cString: err))")
        }
    }
}

