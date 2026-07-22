import Foundation
import SwiftData

/// One question's outcome inside a Marathon run — enough to rebuild the
/// domain scorecard without re-fetching the corpus (docs/CLUB-FEATURES-BUILD.md
/// "Feature 3"). Captured at answer-time, same spirit as `AnswerDetail`.
nonisolated struct MarathonAnswerRecord: Codable, Sendable {
    let questionID: String
    let categoryID: String
    let difficulty: Int
    let correct: Bool
}

/// The AT-MOST-ONE in-progress Marathon run — the load-bearing new mechanic
/// (resume across sessions). A fixed, ordered 200-question id list is drawn
/// once (deterministic from `seed`, mirroring `DailyPick`'s rank-and-slice) so
/// a resume always continues into the SAME set. Persisted after every single
/// answer (`Marathon.record`) so a crash/quit never loses progress.
@Model
final class MarathonRun {
    var seed: String
    /// The fixed ordered 200 (or debug-shortened) question ids, "\u{1}"-joined.
    var questionIDsJoined: String
    /// How many of `questionIDsJoined` have been answered so far.
    var currentIndex: Int
    /// JSON-encoded `[MarathonAnswerRecord]`, one per answered question so far.
    var resultsData: Data?
    var startedAt: Date
    var lastPlayedAt: Date

    init(seed: String, questionIDs: [String], date: Date = .now) {
        self.seed = seed
        self.questionIDsJoined = questionIDs.joined(separator: "\u{1}")
        self.currentIndex = 0
        self.resultsData = nil
        self.startedAt = date
        self.lastPlayedAt = date
    }

    var questionIDs: [String] {
        questionIDsJoined.isEmpty ? [] : questionIDsJoined.components(separatedBy: "\u{1}")
    }
    var total: Int { questionIDs.count }
    var results: [MarathonAnswerRecord] {
        guard let resultsData else { return [] }
        return (try? JSONDecoder().decode([MarathonAnswerRecord].self, from: resultsData)) ?? []
    }

    /// Append one answer and advance — called once per submitted answer so
    /// progress survives a crash/quit mid-run (the whole point of Marathon).
    func append(_ record: MarathonAnswerRecord, date: Date = .now) {
        var r = results
        r.append(record)
        resultsData = try? JSONEncoder().encode(r)
        currentIndex = r.count
        lastPlayedAt = date
    }
}

/// One domain's tally inside a completed Marathon — the scorecard's per-row
/// unit (mirrors `DomainProgress` but scoped to a single run, not lifetime).
nonisolated struct MarathonDomainStat: Codable, Sendable, Identifiable {
    let categoryID: String
    let correct: Int
    let total: Int
    var id: String { categoryID }
    var accuracy: Double { total == 0 ? 0 : Double(correct) / Double(total) }
}

/// A completed Marathon — permanent history (docs/CLUB-FEATURES-BUILD.md
/// "Feature 3"). The scorecard reads straight off this: score, correct/total,
/// and the per-domain breakdown, plus how it compares to the player's other runs.
@Model
final class MarathonScore {
    var date: Date
    var score: Int
    var correct: Int
    var total: Int
    var durationSeconds: Double
    /// JSON-encoded `[MarathonDomainStat]`.
    var domainBreakdownData: Data?

    init(date: Date = .now, score: Int, correct: Int, total: Int,
         durationSeconds: Double, domainBreakdown: [MarathonDomainStat]) {
        self.date = date
        self.score = score
        self.correct = correct
        self.total = total
        self.durationSeconds = durationSeconds
        self.domainBreakdownData = try? JSONEncoder().encode(domainBreakdown)
    }

    var accuracy: Double { total == 0 ? 0 : Double(correct) / Double(total) }
    var domainBreakdown: [MarathonDomainStat] {
        guard let domainBreakdownData else { return [] }
        return (try? JSONDecoder().decode([MarathonDomainStat].self, from: domainBreakdownData)) ?? []
    }
}
