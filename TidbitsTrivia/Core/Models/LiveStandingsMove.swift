import Foundation

/// A2.15 — how far a table MOVED since the last round's scoreboard.
///
/// The between-rounds scoreboard is the ritual moment of a pub quiz, and a bare list
/// of scores throws away the half of it people actually react to: not "we have 14"
/// but "we were fifth and now we're second". Movement is what makes a table cheer
/// at a slide with no question on it.
///
/// Pure, because six stacks have to agree on it.
nonisolated enum LiveStandingsMove {
    nonisolated enum Move: Equatable, Sendable {
        case new          // not on the previous scoreboard
        case same
        case up(Int)
        case down(Int)
    }

    /// Movement per team NAME, from two rank-ordered name lists (index 0 = first).
    /// Names, not uids, because a table may be several phones (G7) and a paper team
    /// has no uid at all.
    static func moves(previous: [String], current: [String]) -> [String: Move] {
        var was: [String: Int] = [:]
        for (i, n) in previous.enumerated() where was[n] == nil { was[n] = i }
        var out: [String: Move] = [:]
        for (now, n) in current.enumerated() {
            guard let before = was[n] else { out[n] = .new; continue }
            // A SMALLER index is a better rank, so moving from 4 to 1 is up 3.
            let delta = before - now
            out[n] = delta == 0 ? .same : (delta > 0 ? .up(delta) : .down(-delta))
        }
        return out
    }

    /// The chip the big screen draws. `nil` on the FIRST scoreboard of the night —
    /// everyone would read "NEW", which is noise, not news.
    static func label(_ m: Move?) -> String? {
        switch m {
        case .none: return nil
        case .some(.new): return "NEW"
        case .some(.same): return "—"
        case .some(.up(let n)): return "▲\(n)"
        case .some(.down(let n)): return "▼\(n)"
        }
    }

    /// One line the host can read out: the biggest climb of the round, when there was
    /// one worth naming. A round where nobody moved says nothing.
    static func biggestClimb(_ moves: [String: Move]) -> String? {
        let climbs = moves.compactMap { (name, m) -> (String, Int)? in
            if case .up(let n) = m, n > 0 { return (name, n) }
            return nil
        }
        guard let best = climbs.max(by: { $0.1 == $1.1 ? $0.0 > $1.0 : $0.1 < $1.1 }) else { return nil }
        return "Biggest climb: \(best.0) up \(best.1)"
    }
}
