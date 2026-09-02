import Foundation

/// G5 — the pick-your-category board, QuizXpress's Jeopardy-style round: a grid of
/// categories across and point tiers down, and the ROOM chooses which cell to play
/// next. Nothing else in Tidbits lets the room choose; every other format marches
/// through a list the host fixed in advance.
///
/// The whole thing is a pure value + pure transitions so all six stacks can agree
/// on what the board looks like after a pick, and so the rules that decide whether
/// a night stalls are testable without a UI.
struct LiveBoardCell: Codable, Hashable, Identifiable {
    var categoryID: String
    var tier: Int            // 1…5, the difficulty row
    var questionID: String
    var taken: Bool = false

    var id: String { "\(categoryID):\(tier)" }
    /// Points come from the TIER, not from the question, so the room can see what
    /// it is risking before it picks. A question's own difficulty may be adjusted
    /// later; the board's promise to the room must not move with it.
    var points: Int { tier * 100 }
}

struct LiveBoard: Codable, Hashable {
    var categories: [String] = []     // column order, left to right
    var tiers: [Int] = []             // row order, top to bottom
    var cells: [LiveBoardCell] = []

    static let defaultTiers = [1, 2, 3, 4, 5]

    func cell(_ categoryID: String, _ tier: Int) -> LiveBoardCell? {
        cells.first { $0.categoryID == categoryID && $0.tier == tier }
    }
    var remaining: [LiveBoardCell] { cells.filter { !$0.taken } }
    var isComplete: Bool { remaining.isEmpty }
    /// The points still on the board — what the host tells the room is left to play for.
    var pointsRemaining: Int { remaining.reduce(0) { $0 + $1.points } }

    /// Mark a cell played. Returns false when the cell does not exist or was
    /// ALREADY taken — the caller must not advance on a double-pick, which is what
    /// happens when two host clicks land on one cell.
    mutating func take(_ categoryID: String, _ tier: Int) -> Bool {
        guard let i = cells.firstIndex(where: {
            $0.categoryID == categoryID && $0.tier == tier && !$0.taken
        }) else { return false }
        cells[i].taken = true
        return true
    }
}

enum LiveBoardBuilder {

    /// Build a board from a question pool.
    ///
    /// A cell is only created when the pool actually holds a question for that
    /// (category, tier). A board with a cell nothing can fill is worse than a
    /// smaller board: the room picks it, the host has nothing to read, and the
    /// night stalls in front of everyone. So an unfillable cell is ABSENT, and the
    /// surfaces render a hole rather than a dead button.
    ///
    /// No question is used twice, even across categories — a repeat mid-board reads
    /// as a mistake to the room whichever cell it came from.
    static func build(from pool: [Question], categories: [String],
                      tiers: [Int] = LiveBoard.defaultTiers) -> LiveBoard {
        var used = Set<String>()
        var cells: [LiveBoardCell] = []
        for c in categories {
            for t in tiers {
                let match = pool.first {
                    $0.categoryID == c && $0.difficulty == t && !used.contains($0.id)
                }
                guard let q = match else { continue }
                used.insert(q.id)
                cells.append(LiveBoardCell(categoryID: c, tier: t, questionID: q.id))
            }
        }
        return LiveBoard(categories: categories, tiers: tiers, cells: cells)
    }

    /// Which category columns the pool can fill COMPLETELY — what a host should be
    /// offered, so they do not build a board that is mostly holes.
    static func fillableCategories(in pool: [Question],
                                   tiers: [Int] = LiveBoard.defaultTiers) -> [String] {
        var byCategory: [String: Set<Int>] = [:]
        for q in pool where tiers.contains(q.difficulty) {
            byCategory[q.categoryID, default: []].insert(q.difficulty)
        }
        return byCategory.filter { $0.value.count == tiers.count }.keys.sorted()
    }

    /// Who picks the next cell.
    ///
    /// The team that just answered correctly picks, which is the Jeopardy rule and
    /// the one a room already understands. When NOBODY got it right the pick would
    /// otherwise stay with whoever holds it and one table would drive the whole
    /// board, so it rotates instead.
    static func nextChooser(current: String?, correct: String?, teams: [String]) -> String? {
        guard !teams.isEmpty else { return nil }
        if let correct, teams.contains(correct) { return correct }
        guard let current, let i = teams.firstIndex(of: current) else { return teams.first }
        return teams[(i + 1) % teams.count]
    }
}
