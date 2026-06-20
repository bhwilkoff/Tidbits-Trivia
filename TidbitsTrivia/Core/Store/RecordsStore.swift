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
        if summary.mode == .stake { addCalibration(summary.stakeOutcomes, in: context) }
        recordTelemetry(summary.answered, mode: summary.mode)

        try? context.save()
        return isNewBest
    }

    /// Questions due for spaced re-asking — unresolved misses, most-missed
    /// and oldest first (the testing effect: a later re-ask, not same-game).
    static func dueReview(in context: ModelContext, limit: Int = 2) -> [Question] {
        var desc = FetchDescriptor<MissedFact>(
            predicate: #Predicate { !$0.resolved },
            sortBy: [SortDescriptor(\.missCount, order: .reverse),
                     SortDescriptor(\.lastSeen, order: .forward)])
        desc.fetchLimit = limit * 3
        let facts = (try? context.fetch(desc)) ?? []
        return Array(facts.compactMap(\.question).prefix(limit))
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

    /// Lifetime calibration tallies, highest tier first (Sure, Likely, Hunch).
    static func calibration(in context: ModelContext) -> [CalibrationTally] {
        let all = (try? context.fetch(FetchDescriptor<CalibrationTally>())) ?? []
        return all.sorted { $0.tierValue > $1.tierValue }
    }

    private static func addCalibration(_ outcomes: [Int: StakeOutcome], in context: ModelContext) {
        for (tier, outcome) in outcomes where outcome.total > 0 {
            let desc = FetchDescriptor<CalibrationTally>(predicate: #Predicate { $0.tierValue == tier })
            if let existing = try? context.fetch(desc).first {
                existing.hits += outcome.hits
                existing.total += outcome.total
            } else {
                context.insert(CalibrationTally(tierValue: tier, hits: outcome.hits, total: outcome.total))
            }
        }
    }

    // MARK: - Answer-distribution telemetry (F4)

    /// Local, privacy-respecting per-option answer counter. Records which
    /// option index the player chose for each MCQ question, keyed by question
    /// id, as `[questionID: [perOptionCount]]` in UserDefaults. No PII, no
    /// network — this is the invisible foundation a backend later aggregates
    /// into the "X% picked this" / Predict-the-Crowd reveal. Modes whose
    /// chosenIndex is synthetic (closest/ordering/matching/type-answer encode
    /// 0/1 = right/wrong, not a real option pick) are skipped.
    private static let telemetryKey = "tidbits.answerTelemetry"
    private static let telemetryCap = 5000  // bound the dict; oldest data is disposable

    private static func recordTelemetry(_ answered: [AnsweredQuestion], mode: GameMode) {
        switch mode {
        case .closestCall, .ordering, .matching, .typeAnswer: return  // synthetic chosenIndex
        default: break
        }
        let defaults = UserDefaults.standard
        var map = (defaults.dictionary(forKey: telemetryKey) as? [String: [Int]]) ?? [:]
        for a in answered {
            guard let chosen = a.chosenIndex,
                  a.question.options.count >= 2,
                  a.question.options.indices.contains(chosen) else { continue }
            var counts = map[a.question.id] ?? Array(repeating: 0, count: a.question.options.count)
            if counts.count < a.question.options.count {
                counts += Array(repeating: 0, count: a.question.options.count - counts.count)
            }
            counts[chosen] += 1
            map[a.question.id] = counts
        }
        if map.count > telemetryCap { map = [:] }  // disposable foundation data; reset rather than evict
        defaults.set(map, forKey: telemetryKey)
    }

    /// Per-option local counts for a question (foundation for the future
    /// crowd reveal). nil until the question has been answered at least once.
    static func answerDistribution(forQuestion id: String) -> [Int]? {
        (UserDefaults.standard.dictionary(forKey: telemetryKey) as? [String: [Int]])?[id]
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
