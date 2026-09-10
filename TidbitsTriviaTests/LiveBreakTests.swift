import Testing
import Foundation

/// A3.14 — the break text is pure and shared, so the big screen, the cockpit and all
/// five joiners say the same thing. A break announced two ways is a room asking the
/// host which is right.
@Suite("Live break")
struct LiveBreakTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func noPromiseIsBackInAMoment() {
        #expect(LiveBreak.headline(until: nil, now: now) == "Back in a moment")
        #expect(LiveBreak.clockLine(until: nil, now: now) == "")
        #expect(LiveBreak.minutesLeft(until: nil, now: now) == nil)
    }

    @Test func minutesRoundToTheNearestSoTenReadsTenEverywhere() {
        // 9m30s is still "10 minutes" — a host who said ten is not contradicted a second later.
        let up = Int((now.timeIntervalSince1970 + 9 * 60 + 30) * 1000)
        #expect(LiveBreak.minutesLeft(until: up, now: now) == 10)
        #expect(LiveBreak.headline(until: up, now: now) == "Back in 10 minutes")
        // …and 10m05s is TEN, not eleven. Rounding up made every slightly-slow clock in
        // the room show a different number: measured on the bench, the projector said 10
        // and the Windows joiner said 11 for the same break.
        let skewed = Int((now.timeIntervalSince1970 + 10 * 60 + 5) * 1000)
        #expect(LiveBreak.minutesLeft(until: skewed, now: now) == 10)
    }

    @Test func underHalfAMinuteIsAMomentRatherThanAMinute() {
        let soon = Int((now.timeIntervalSince1970 + 10) * 1000)
        #expect(LiveBreak.minutesLeft(until: soon, now: now) == nil)
        #expect(LiveBreak.headline(until: soon, now: now) == "Back in a moment")
    }

    @Test func oneMinuteIsSingular() {
        let until = Int((now.timeIntervalSince1970 + 70) * 1000)
        #expect(LiveBreak.headline(until: until, now: now) == "Back in a minute")
    }

    @Test func aPassedPromiseFallsBackRatherThanCountingNegative() {
        // "Back in -2 minutes" is worse than saying nothing.
        let past = Int((now.timeIntervalSince1970 - 120) * 1000)
        #expect(LiveBreak.minutesLeft(until: past, now: now) == nil)
        #expect(LiveBreak.headline(until: past, now: now) == "Back in a moment")
        #expect(LiveBreak.clockLine(until: past, now: now) == "")
    }

    @Test func untilIsMinutesFromNowAndRoundTrips() {
        let until = LiveBreak.until(minutes: 15, now: now)
        #expect(LiveBreak.minutesLeft(until: until, now: now) == 15)
        #expect(LiveBreak.clockLine(until: until, now: now).hasPrefix("back at "))
    }
}
