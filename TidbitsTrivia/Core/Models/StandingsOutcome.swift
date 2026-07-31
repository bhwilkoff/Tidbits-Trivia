import Foundation

/// How a finished board is announced.
///
/// Every scoreboard in the app used to sort by score and call element 0 "the
/// winner". On a tie that reports an arbitrary sort order as a victory — and
/// ties are not an edge case here: Pass & Play deals ONE shared question set,
/// so two players who answer identically genuinely finish level, and a hosted
/// Trivia Night settles real stakes in a room where a wrong call is visible.
///
/// One helper so all six surfaces (iOS/tvOS/macOS Night + Pass & Play) agree;
/// `js/night.js` and `Party.kt`/`NightHost.kt` mirror the same rule.
nonisolated enum StandingsOutcome {

    /// Every entry sharing the top score. Empty when `entries` is empty.
    static func winners(_ entries: [(name: String, score: Int)]) -> [String] {
        guard let top = entries.map(\.score).max() else { return [] }
        return entries.filter { $0.score == top }.map(\.name)
    }

    /// True when `score` ties the leader — use it to highlight EVERY leading
    /// row, not just the first one the sort happened to put on top.
    static func isTop(_ score: Int, in entries: [(name: String, score: Int)]) -> Bool {
        guard let top = entries.map(\.score).max() else { return false }
        return score == top
    }

    /// The announcement. `empty` is the no-players copy the caller already uses
    /// ("That's a night!"), so this drops into existing sites unchanged.
    static func headline(_ entries: [(name: String, score: Int)], empty: String) -> String {
        let won = winners(entries)
        if won.isEmpty { return empty }
        if won.count == 1 { return "\(won[0]) wins!" }
        if won.count == entries.count { return "It's a tie!" }
        return "Tie — \(won.joined(separator: " & "))"
    }
}
