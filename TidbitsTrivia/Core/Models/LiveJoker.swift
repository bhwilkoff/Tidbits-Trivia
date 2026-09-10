import Foundation

/// A2.14 — the joker. The oldest trick in the pub quiz: before a round starts each
/// table names ONE round of the night as its joker, and every point it scores in
/// that round counts double. It is the one decision of the night the TABLE makes
/// rather than the host — a small act of strategy that makes a table talk.
///
/// Pure, because six stacks have to agree: which rounds a joker can still be played
/// on, whose joker locks when a round starts, and what a locked joker is worth.
nonisolated enum LiveJoker {
    /// The rounds a joker can still be played on: every round AFTER the one in
    /// progress (`current` is its 0-based index; -1 before the night starts), minus
    /// the wager round — a table already stakes its own points there.
    static func playable(current: Int, titles: [String], wager: Int? = nil) -> [LiveRoom.JokerRound] {
        titles.enumerated().compactMap { i, t in
            guard i > current, i != wager else { return nil }
            return LiveRoom.JokerRound(index: i, title: t.isEmpty ? "Round \(i + 1)" : t)
        }
    }

    /// Lock the picks for the round that is starting: the TEAMS (by name, because a
    /// table may be several phones — G7) whose joker is on `round`. Picks for any
    /// other round are simply not in the set, which is the whole rule: a joker names
    /// a round before it starts, and a pick made after that names nothing.
    static func played(on round: Int, picks: [String: Int], teamOf: (String) -> String?) -> Set<String> {
        Set(picks.compactMap { uid, r in r == round ? teamOf(uid) : nil })
    }

    /// What a team's points are worth this round.
    static func multiplier(team: String, played: Set<String>) -> Int {
        played.contains(team) ? 2 : 1
    }

    /// The big-screen line on the first question of a round — nil when nobody played
    /// one, so a quiet round says nothing (A8.7).
    static func line(played: Set<String>) -> String? {
        guard !played.isEmpty else { return nil }
        let names = played.sorted()
        return (names.count == 1 ? "Joker played: " : "Jokers played: ") + names.joined(separator: ", ")
    }
}
