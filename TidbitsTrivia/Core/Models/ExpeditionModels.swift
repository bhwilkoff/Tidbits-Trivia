import Foundation
import SwiftData

// MARK: - Data shape (portable — the load-bearing shared piece other
// platforms mirror, docs/CLUB-FEATURES-BUILD.md "Feature 5").

/// One themed stage inside an Expedition — a normal category/difficulty-band
/// round the EXISTING engine already plays (`.classic`, via `Expeditions.
/// startStage`). NOT a new game mode. The taxonomy (`TriviaCategory.all`) is
/// FLAT — no sub-domain like "1920s" or "South America" — so stages within
/// one Expedition differentiate by DIFFICULTY BAND, not sub-category (same
/// constraint the Knowledge Atlas hit; see docs/CLUB-FEATURES-BUILD.md).
nonisolated struct ExpeditionStage: Identifiable, Sendable, Hashable {
    let index: Int
    let title: String
    let blurb: String
    let categoryID: String
    let difficultyRange: ClosedRange<Int>
    let questionCount: Int
    /// Correct answers needed (out of `questionCount`) to advance.
    let passBar: Int

    var id: Int { index }
}

/// A curated multi-stage campaign through one domain — the portable shape
/// other platforms mirror. Adding an expedition is additive: append to
/// `all`; no client changes needed.
nonisolated struct Expedition: Identifiable, Sendable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    /// `TriviaCategory.id` this expedition is themed around (icon/color only —
    /// stages carry their own `categoryID`, usually the same domain).
    let domain: String
    let symbol: String
    let stages: [ExpeditionStage]

    var stageCount: Int { stages.count }

    static func named(_ id: String) -> Expedition? { all.first { $0.id == id } }

    /// Start with 2–3 hand-defined expeditions (design spec). The shape
    /// allows adding more without any client change.
    static let all: [Expedition] = [
        Expedition(
            id: "20th-century",
            title: "The 20th Century",
            subtitle: "A hundred years, decade by decade — from the Great War to the dot-com boom.",
            domain: "history", symbol: "scroll.fill",
            stages: [
                ExpeditionStage(index: 0, title: "Turn of the Century",
                                 blurb: "Where it all began — the basics of a hundred years.",
                                 categoryID: "history", difficultyRange: 1...2, questionCount: 10, passBar: 6),
                ExpeditionStage(index: 1, title: "The Great Wars",
                                 blurb: "Two wars that reshaped the century.",
                                 categoryID: "history", difficultyRange: 1...3, questionCount: 10, passBar: 6),
                ExpeditionStage(index: 2, title: "The Cold War Era",
                                 blurb: "A world split in two.",
                                 categoryID: "history", difficultyRange: 2...3, questionCount: 10, passBar: 6),
                ExpeditionStage(index: 3, title: "Movements & Milestones",
                                 blurb: "Civil rights, independence, revolutions.",
                                 categoryID: "history", difficultyRange: 2...4, questionCount: 10, passBar: 6),
                ExpeditionStage(index: 4, title: "Leaders & Turning Points",
                                 blurb: "The decisions that moved history.",
                                 categoryID: "history", difficultyRange: 3...4, questionCount: 10, passBar: 6),
                ExpeditionStage(index: 5, title: "The Wider Century",
                                 blurb: "Everything else the timeline holds.",
                                 categoryID: "history", difficultyRange: 3...5, questionCount: 10, passBar: 6),
                ExpeditionStage(index: 6, title: "The Historian's Final Exam",
                                 blurb: "The century's hardest corners.",
                                 categoryID: "history", difficultyRange: 4...5, questionCount: 10, passBar: 6),
            ]),
        Expedition(
            id: "around-the-world",
            title: "Around the World",
            subtitle: "A geography trek from the basics of the map to its far corners.",
            domain: "geography", symbol: "globe.americas.fill",
            stages: [
                ExpeditionStage(index: 0, title: "The Basics of the Map",
                                 blurb: "Continents, oceans, and the big picture.",
                                 categoryID: "geography", difficultyRange: 1...2, questionCount: 10, passBar: 6),
                ExpeditionStage(index: 1, title: "Capitals & Borders",
                                 blurb: "Where the lines are drawn.",
                                 categoryID: "geography", difficultyRange: 1...3, questionCount: 10, passBar: 6),
                ExpeditionStage(index: 2, title: "Rivers, Ranges & Deserts",
                                 blurb: "The planet's physical geography.",
                                 categoryID: "geography", difficultyRange: 2...3, questionCount: 10, passBar: 6),
                ExpeditionStage(index: 3, title: "Nations & Peoples",
                                 blurb: "Who lives where, and why.",
                                 categoryID: "geography", difficultyRange: 2...4, questionCount: 10, passBar: 6),
                ExpeditionStage(index: 4, title: "Cities of the World",
                                 blurb: "The places everyone's heard of.",
                                 categoryID: "geography", difficultyRange: 3...4, questionCount: 10, passBar: 6),
                ExpeditionStage(index: 5, title: "The Far Corners",
                                 blurb: "The places most people haven't.",
                                 categoryID: "geography", difficultyRange: 3...5, questionCount: 10, passBar: 6),
                ExpeditionStage(index: 6, title: "World-Class",
                                 blurb: "Geography's hardest questions.",
                                 categoryID: "geography", difficultyRange: 4...5, questionCount: 10, passBar: 6),
            ]),
        Expedition(
            id: "scientific-record",
            title: "The Scientific Record",
            subtitle: "From first principles to the frontier — the story of how we know what we know.",
            domain: "science", symbol: "atom",
            stages: [
                ExpeditionStage(index: 0, title: "First Principles",
                                 blurb: "The fundamentals everyone starts with.",
                                 categoryID: "science", difficultyRange: 1...2, questionCount: 10, passBar: 6),
                ExpeditionStage(index: 1, title: "Matter & Energy",
                                 blurb: "Physics and chemistry, from the ground up.",
                                 categoryID: "science", difficultyRange: 1...3, questionCount: 10, passBar: 6),
                ExpeditionStage(index: 2, title: "Life Itself",
                                 blurb: "Biology's big ideas.",
                                 categoryID: "science", difficultyRange: 2...3, questionCount: 10, passBar: 6),
                ExpeditionStage(index: 3, title: "The Great Discoveries",
                                 blurb: "The breakthroughs that changed everything.",
                                 categoryID: "science", difficultyRange: 2...4, questionCount: 10, passBar: 6),
                ExpeditionStage(index: 4, title: "The Scientists Behind It",
                                 blurb: "The people who did the work.",
                                 categoryID: "science", difficultyRange: 3...4, questionCount: 10, passBar: 6),
                ExpeditionStage(index: 5, title: "The Frontier",
                                 blurb: "Where the science is still being written.",
                                 categoryID: "science", difficultyRange: 3...5, questionCount: 10, passBar: 6),
                ExpeditionStage(index: 6, title: "The Comprehensive Exam",
                                 blurb: "Science's deepest cuts.",
                                 categoryID: "science", difficultyRange: 4...5, questionCount: 10, passBar: 6),
            ]),
    ]
}

// MARK: - Persistence (mirrors the Marathon pattern — see MarathonModels.swift)

/// One stage's outcome inside an in-progress Expedition — the progress JSON unit.
nonisolated struct ExpeditionStageResult: Codable, Sendable {
    let stageIndex: Int
    let passed: Bool
    let correct: Int
    let total: Int
}

/// One in-progress Expedition. Unlike Marathon's at-most-one run, a player can
/// pursue SEVERAL campaigns at once — this is keyed by `expeditionID`, not a
/// singleton. Persisted after every stage attempt so a player can leave and
/// come back over days or weeks.
@Model
final class ExpeditionProgress {
    var expeditionID: String
    var currentStageIndex: Int
    /// JSON-encoded `[ExpeditionStageResult]`, one entry per stage attempted.
    var perStageResultsData: Data?
    var startedAt: Date
    var lastPlayedAt: Date

    init(expeditionID: String, date: Date = .now) {
        self.expeditionID = expeditionID
        self.currentStageIndex = 0
        self.perStageResultsData = nil
        self.startedAt = date
        self.lastPlayedAt = date
    }

    var perStageResults: [ExpeditionStageResult] {
        guard let perStageResultsData else { return [] }
        return (try? JSONDecoder().decode([ExpeditionStageResult].self, from: perStageResultsData)) ?? []
    }

    /// Record one stage attempt. A pass advances `currentStageIndex` (never
    /// backwards); a fail leaves it where it was — the player stays on the
    /// same stage and can try again.
    func recordStage(_ result: ExpeditionStageResult, date: Date = .now) {
        var r = perStageResults
        r.removeAll { $0.stageIndex == result.stageIndex }
        r.append(result)
        perStageResultsData = try? JSONEncoder().encode(r)
        lastPlayedAt = date
        if result.passed { currentStageIndex = max(currentStageIndex, result.stageIndex + 1) }
    }
}

/// A completed Expedition — permanent (docs/CLUB-FEATURES-BUILD.md
/// "Feature 5"). Written once the LAST stage passes; the in-progress
/// `ExpeditionProgress` row is deleted at the same time (mirrors Marathon's
/// finish → history + clear-the-run).
@Model
final class ExpeditionCertificate {
    var expeditionID: String
    var domain: String
    var title: String
    var completedAt: Date
    var totalScore: Int
    var stagesCompleted: Int

    init(expeditionID: String, domain: String, title: String,
         totalScore: Int, stagesCompleted: Int, date: Date = .now) {
        self.expeditionID = expeditionID
        self.domain = domain
        self.title = title
        self.completedAt = date
        self.totalScore = totalScore
        self.stagesCompleted = stagesCompleted
    }
}
