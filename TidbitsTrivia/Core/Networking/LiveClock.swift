import Foundation

/// Tick 33 — speak in the HOST's clock, not this device's.
///
/// Every countdown the room shares is an absolute epoch-ms deadline (`pub.deadline`,
/// `pub.breakUntil`), so each client evaluates it against its own clock. Measured
/// 2026-09-10 on the bench: the Windows box runs 101 SECONDS behind the Mac, and the
/// same 10-minute break read "10 minutes" on the web and "12 minutes" there. On a 30 s
/// question a skew like that is not a wobble — the timer is nonsense.
///
/// The host stamps `pub.now` when it publishes; a client keeps the offset that implies
/// and adds it to its own clock before comparing. Pure and mirrored in C# as `LiveClock`.
nonisolated enum LiveClock {
    /// How far this device's clock is BEHIND the host's, in ms (negative when ahead).
    /// Nil `pubNow` means an older host that does not stamp — offset 0, the old behaviour.
    static func offsetMS(pubNow: Int?, receivedAt: Date = .now) -> Double {
        guard let pubNow else { return 0 }
        return Double(pubNow) - receivedAt.timeIntervalSince1970 * 1000
    }

    /// Whole seconds left on a deadline, in the host's frame. Never negative; nil when
    /// there is no deadline. Rounded UP, so a timer shows "1" for its final tick rather
    /// than sitting on "0" while the room can still answer.
    static func secondsRemaining(deadlineMS: Int?, offsetMS: Double, now: Date = .now) -> Int? {
        guard let deadlineMS else { return nil }
        let hostNowMS = now.timeIntervalSince1970 * 1000 + offsetMS
        return max(0, Int(((Double(deadlineMS) - hostNowMS) / 1000).rounded(.up)))
    }

    /// This device's clock, expressed in the host's frame — what every deadline and the
    /// break countdown must be compared against.
    static func hostNow(offsetMS: Double, now: Date = .now) -> Date {
        now.addingTimeInterval(offsetMS / 1000)
    }
}
