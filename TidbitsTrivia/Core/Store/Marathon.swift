import Foundation
import SwiftData

/// Generates and resumes the Club-only Marathon run — a 200-question graded
/// endurance test whose value is measured mastery, not volume
/// (docs/CLUB-FEATURES-BUILD.md "Feature 3"). The load-bearing new mechanic
/// is **resume across sessions**: at most one `MarathonRun` exists at a time,
/// its 200 question ids are fixed at creation from a stored seed (mirroring
/// `DailyPick`'s deterministic rank-and-slice), and every answer is persisted
/// immediately so a crash/quit never loses progress.
@MainActor
enum Marathon {

    nonisolated static let defaultLength = 200

    /// TIDBITS_MARATHON_LEN=<n> shortens a run for testing (so one can be
    /// played to completion in the simulator). Production always sees 200 —
    /// this only ever narrows the count, never widens it. `nonisolated` so
    /// `GameMode.questionCount` (not actor-isolated) can read it directly.
    nonisolated static var runLength: Int {
        guard let raw = ProcessInfo.processInfo.environment["TIDBITS_MARATHON_LEN"],
              let n = Int(raw), n > 0 else { return defaultLength }
        return n
    }

    /// The in-progress run, if any (at most one).
    static func inProgress(in context: ModelContext) -> MarathonRun? {
        (try? context.fetch(FetchDescriptor<MarathonRun>()))?.first
    }

    /// Start a fresh run, discarding any stale in-progress one first ("Start
    /// Over"). The 200 ids are drawn once from a fresh seed and fixed forever
    /// — a resume rebuilds the exact same set from the corpus.
    @discardableResult
    static func startNew(in context: ModelContext) -> MarathonRun {
        if let existing = inProgress(in: context) { context.delete(existing) }
        let seed = UUID().uuidString
        let allIDs = CorpusDatabase.shared.orderedIDs(categoryID: "mixed")
        let count = min(runLength, allIDs.count)
        let ids = pickIDs(from: allIDs, seed: seed, count: count)
        let run = MarathonRun(seed: seed, questionIDs: ids)
        context.insert(run)
        try? context.save()
        return run
    }

    /// The remaining questions for a run, from `currentIndex` to the end —
    /// what a resumed (or fresh) session actually loads into the engine.
    static func resumeQuestions(_ run: MarathonRun) -> [Question] {
        let remainingIDs = Array(run.questionIDs.suffix(from: min(run.currentIndex, run.questionIDs.count)))
        return CorpusDatabase.shared.questions(ids: remainingIDs)
    }

    /// Persist one answer immediately — called after every submit so a
    /// crash/quit never loses progress. Deleting the app or the corpus
    /// changing doesn't matter: the record captures everything the scorecard
    /// needs (category + difficulty + correctness) at answer-time.
    static func record(_ answer: AnsweredQuestion, run: MarathonRun, in context: ModelContext) {
        let rec = MarathonAnswerRecord(
            questionID: answer.question.id, categoryID: answer.question.categoryID,
            difficulty: answer.question.difficulty, correct: answer.isCorrect)
        run.append(rec)
        try? context.save()
    }

    /// The run just reached its full length — write the permanent
    /// `MarathonScore` and clear the in-progress run.
    static func finish(run: MarathonRun, in context: ModelContext) -> MarathonScore {
        let results = run.results
        let correct = results.filter(\.correct).count
        // A plain difficulty-weighted score (10 pts × difficulty per correct
        // answer) — transparent by construction, no hidden model.
        let score = results.filter(\.correct).reduce(0) { $0 + $1.difficulty * 10 }
        let duration = Date.now.timeIntervalSince(run.startedAt)
        let domainBreakdown = ProgressMath.domainIDs.map { domain -> MarathonDomainStat in
            let rows = results.filter { $0.categoryID == domain }
            return MarathonDomainStat(categoryID: domain, correct: rows.filter(\.correct).count, total: rows.count)
        }
        let entry = MarathonScore(score: score, correct: correct, total: results.count,
                                  durationSeconds: duration, domainBreakdown: domainBreakdown)
        context.insert(entry)
        context.delete(run)
        try? context.save()
        return entry
    }

    /// Past completed runs, most recent first — the permanent Marathon history.
    static func history(in context: ModelContext) -> [MarathonScore] {
        (try? context.fetch(FetchDescriptor<MarathonScore>(sortBy: [SortDescriptor(\.date, order: .reverse)]))) ?? []
    }

    /// Deterministic id pick from a seed — the same rank-and-slice `DailyPick`
    /// uses for the Daily, just keyed by a per-run seed instead of a calendar day.
    private static func pickIDs(from ids: [String], seed: String, count: Int) -> [String] {
        ids.map { (id: $0, rank: "marathon:\(seed):\($0)".stableSeed) }
            .sorted {
                $0.rank != $1.rank ? $0.rank < $1.rank
                                   : $0.id.utf8.lexicographicallyPrecedes($1.id.utf8)
            }
            .prefix(count)
            .map(\.id)
    }
}
