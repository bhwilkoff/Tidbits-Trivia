import Foundation

/// Derived knowledge-cartography over the player's game history — the data
/// behind **Topic Levels** (depth: an XP level per domain, QuizUp's best idea)
/// and **The Pie** (breadth: a wedge per domain, Trivial Pursuit). Both are pure
/// derivations of `GameRecord` aggregates — no new persistence — so every
/// platform computes them identically from the same per-game (category, correct,
/// total) rows (SOLO-BACKLOG M3 + M4).
enum ProgressMath {

    /// The seven knowledge domains the Pie is filled from — every category
    /// except "mixed" (a mixed game isn't a single domain, so it earns no
    /// wedge; this is what nudges players toward specific subjects they avoid —
    /// the breadth incentive that fights corpus bias).
    static let domainIDs = ["history", "science", "geography", "arts", "screen", "music", "sports"]

    /// A domain earns its Pie wedge at a small mastery bar: enough cumulative
    /// correct answers AND a non-lucky accuracy. Adds-only — a wedge, once
    /// earned, is yours to keep (never a streak that resets, Decision 022).
    static let wedgeCorrect = 15
    static let wedgeAccuracy = 0.60

    /// Level curve: level L is reached at cumulative correct ≥ 5·L·(L+1)/2
    /// (L1=5, L2=15, L3=30, L4=50, L5=75, …) — a gentle triangular ramp so
    /// early levels come fast and later ones reward sustained study.
    static func threshold(forLevel level: Int) -> Int { 5 * level * (level + 1) / 2 }

    static func level(forCorrect correct: Int) -> Int {
        var l = 0
        while threshold(forLevel: l + 1) <= correct { l += 1 }
        return l
    }

    /// Fraction (0–1) from the current level toward the next — drives the XP bar.
    static func levelProgress(forCorrect correct: Int) -> Double {
        let l = level(forCorrect: correct)
        let lo = threshold(forLevel: l), hi = threshold(forLevel: l + 1)
        return hi == lo ? 1 : min(1, max(0, Double(correct - lo) / Double(hi - lo)))
    }
}

/// One domain's standing — depth (level/XP) and whether it has earned its wedge.
struct DomainProgress: Identifiable, Sendable, Hashable {
    let categoryID: String
    let correct: Int
    let total: Int

    var id: String { categoryID }
    var accuracy: Double { total == 0 ? 0 : Double(correct) / Double(total) }
    var level: Int { ProgressMath.level(forCorrect: correct) }
    var levelProgress: Double { ProgressMath.levelProgress(forCorrect: correct) }
    var nextLevelCorrect: Int { ProgressMath.threshold(forLevel: level + 1) }
    var hasWedge: Bool { correct >= ProgressMath.wedgeCorrect && accuracy >= ProgressMath.wedgeAccuracy }

    /// Aggregate per-game (category, correct, total) rows into one row per
    /// domain, in the canonical domain order. Rows for "mixed" or unknown
    /// categories are ignored (they don't map to a single domain).
    static func summarize(_ rows: [(categoryID: String, correct: Int, total: Int)]) -> [DomainProgress] {
        ProgressMath.domainIDs.map { domain in
            let mine = rows.filter { $0.categoryID == domain }
            return DomainProgress(
                categoryID: domain,
                correct: mine.reduce(0) { $0 + $1.correct },
                total: mine.reduce(0) { $0 + $1.total })
        }
    }

    /// How many of the seven wedges are earned (the Pie's completion count).
    static func wedgesEarned(_ domains: [DomainProgress]) -> Int {
        domains.filter(\.hasWedge).count
    }
}
