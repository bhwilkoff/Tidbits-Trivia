import Foundation

/// A3.14 — what a room on a break is told. Pure and shared so the big screen, the
/// cockpit and all five joiners say the SAME thing: a break announced two different
/// ways on the projector and the phone is a room asking the host which is right.
/// Mirrored in C# as `LiveBreak`.
nonisolated enum LiveBreak {
    /// The headline. A promised return time counts down in whole minutes and never
    /// goes negative — "Back in 0 min" is worse than saying nothing.
    static func headline(until: Int?, now: Date = .now) -> String {
        guard let mins = minutesLeft(until: until, now: now), mins > 0 else { return "Back in a moment" }
        return mins == 1 ? "Back in a minute" : "Back in \(mins) minutes"
    }

    /// Whole minutes left, to the NEAREST minute (half up). A host who says ten is not
    /// immediately shown nine — and, just as important, a device whose clock runs a few
    /// seconds slow is not shown ELEVEN: rounding up turned every slow clock in the room
    /// into a different number, which is exactly what one shared function is here to
    /// prevent (measured on the bench, tick 32: the projector said 10 and the Windows
    /// joiner said 11). Under 30 seconds it falls through to "Back in a moment".
    /// nil when no return time was promised or it has passed.
    static func minutesLeft(until: Int?, now: Date = .now) -> Int? {
        guard let until else { return nil }
        let secs = Double(until) / 1000 - now.timeIntervalSince1970
        guard secs > 0 else { return nil }
        let mins = Int((secs / 60).rounded(.toNearestOrAwayFromZero))
        return mins > 0 ? mins : nil
    }

    /// "back at 9:15" — the clock time, which is what a room actually acts on when
    /// people wander to the bar. Empty when no return time was promised.
    static func clockLine(until: Int?, now: Date = .now) -> String {
        guard let until, minutesLeft(until: until, now: now) != nil else { return "" }
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        return "back at \(f.string(from: Date(timeIntervalSince1970: Double(until) / 1000)))"
    }

    /// The epoch-ms a break of `minutes` from now ends.
    static func until(minutes: Int, now: Date = .now) -> Int {
        Int((now.timeIntervalSince1970 + Double(minutes) * 60) * 1000)
    }

    /// The minute choices a host is offered — a pub break is five, ten or fifteen.
    static let choices = [5, 10, 15]
}
