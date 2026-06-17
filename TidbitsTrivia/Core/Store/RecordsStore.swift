import Foundation
import SwiftData

/// Persists the outcome of a finished game: the record itself, any missed
/// facts (for spaced re-asking — the testing effect), and the Daily
/// streak. Centralized so every platform writes records identically.
@MainActor
enum RecordsStore {

    @discardableResult
    static func record(_ summary: GameSummary, in context: ModelContext) -> Bool {
        let priorBest = bestScore(mode: summary.mode, categoryID: summary.category.id, in: context)
        let isNewBest = summary.score > priorBest

        let rec = GameRecord(
            mode: summary.mode, categoryID: summary.category.id,
            score: summary.score, correct: summary.correct, total: summary.total,
            maxStreak: summary.maxStreak)
        context.insert(rec)

        for miss in summary.missed {
            registerMiss(miss.question, in: context)
        }
        // Re-asked-and-correct resolves an earlier miss.
        for right in summary.answered where right.isCorrect {
            resolveMiss(questionID: right.question.id, in: context)
        }

        if summary.mode == .daily { bumpDailyStreak(in: context) }

        try? context.save()
        return isNewBest
    }

    static func bestScore(mode: GameMode, categoryID: String, in context: ModelContext) -> Int {
        let modeRaw = mode.rawValue
        var desc = FetchDescriptor<GameRecord>(
            predicate: #Predicate { $0.modeRaw == modeRaw && $0.categoryID == categoryID },
            sortBy: [SortDescriptor(\.score, order: .reverse)])
        desc.fetchLimit = 1
        return (try? context.fetch(desc))?.first?.score ?? 0
    }

    private static func registerMiss(_ q: Question, in context: ModelContext) {
        let id = q.id
        let desc = FetchDescriptor<MissedFact>(predicate: #Predicate { $0.questionID == id })
        if let existing = try? context.fetch(desc).first {
            existing.missCount += 1
            existing.lastSeen = .now
            existing.resolved = false
        } else {
            context.insert(MissedFact(question: q))
        }
    }

    private static func resolveMiss(questionID: String, in context: ModelContext) {
        let desc = FetchDescriptor<MissedFact>(predicate: #Predicate { $0.questionID == questionID })
        if let existing = try? context.fetch(desc).first, !existing.resolved {
            existing.resolved = true
            existing.lastSeen = .now
        }
    }

    private static func bumpDailyStreak(in context: ModelContext) {
        let today = QuestionProvider.dayKey()
        let yesterday = QuestionProvider.dayKey(Calendar.current.date(byAdding: .day, value: -1, to: .now) ?? .now)
        let streak: DailyStreak
        if let existing = try? context.fetch(FetchDescriptor<DailyStreak>()).first {
            streak = existing
        } else {
            streak = DailyStreak(); context.insert(streak)
        }
        guard streak.lastPlayedDay != today else { return }  // already counted today
        streak.current = (streak.lastPlayedDay == yesterday) ? streak.current + 1 : 1
        streak.best = max(streak.best, streak.current)
        streak.lastPlayedDay = today
    }
}
