import Foundation
import SwiftData

/// Persisted outcome of one day's Link Wall (Club Feature 6, Stage 2 —
/// docs/CLUB-FEATURES-BUILD.md). `DailyLog` (UserDefaults) is enough for the
/// free Daily because a day only ever needs one Int; Link Wall needs richer
/// state (mistakes, solve order, and a per-guess "color" row for the share
/// grid), so it's a `@Model`, mirroring `MarathonRun`/`MarathonScore`'s
/// JSON-blob pattern. One row per day (`day` is unique) — reopening a
/// completed or in-progress day resumes THIS row, never a fresh board.
@Model
final class LinkWallResult {
    @Attribute(.unique) var day: String
    var mistakes: Int
    var completed: Bool
    var won: Bool
    var date: Date
    /// JSON-encoded `[[Int]]` — one row per guess, IN ORDER, each the 4
    /// tapped tiles' TRUE group difficulty (1 yellow ... 4 purple) at guess
    /// time. This is exactly what the share grid renders — independent of
    /// whether the guess was correct, so a wrong guess still gets its row.
    private var guessHistoryData: Data?
    /// The solved group labels, in SOLVE order (a player can clear purple
    /// before yellow) — drives the collapsed-row order and which groups
    /// still remain on the board.
    private var solvedLabelsJoined: String

    init(day: String, date: Date = .now) {
        self.day = day
        self.mistakes = 0
        self.completed = false
        self.won = false
        self.date = date
        self.guessHistoryData = nil
        self.solvedLabelsJoined = ""
    }

    var guessHistory: [[Int]] {
        guessHistoryData.flatMap { try? JSONDecoder().decode([[Int]].self, from: $0) } ?? []
    }

    var solvedLabels: [String] {
        solvedLabelsJoined.isEmpty ? [] : solvedLabelsJoined.components(separatedBy: "\u{1}")
    }

    /// Appends one guess row, correct or not — called immediately on every
    /// submit so a crash/quit never loses progress (same discipline as
    /// `Marathon.record`).
    func recordGuess(difficulties: [Int]) {
        var rows = guessHistory
        rows.append(difficulties)
        guessHistoryData = try? JSONEncoder().encode(rows)
    }

    func recordSolvedGroup(_ label: String) {
        guard !solvedLabels.contains(label) else { return }
        solvedLabelsJoined = (solvedLabels + [label]).joined(separator: "\u{1}")
    }
}

/// Fetch/create helpers, mirroring `DailyLog`'s call shape but against the
/// SwiftData store (see `LinkWallResult` doc for why this one needs a model).
@MainActor
enum LinkWallLog {
    static func result(for day: String, in context: ModelContext) -> LinkWallResult? {
        var descriptor = FetchDescriptor<LinkWallResult>(predicate: #Predicate { $0.day == day })
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }

    /// Fetch today's row, or insert a fresh one — never a second row for the
    /// same day (`day` is `.unique` too, so this is belt-and-suspenders).
    static func resultOrCreate(for day: String, in context: ModelContext) -> LinkWallResult {
        if let existing = result(for: day, in: context) { return existing }
        let fresh = LinkWallResult(day: day)
        context.insert(fresh)
        try? context.save()
        return fresh
    }
}
