import Testing
import Foundation

/// Tick 33 — every countdown the room shares is an ABSOLUTE deadline, so a device whose
/// clock is off counts down to the wrong moment. Measured on the bench: the Windows box
/// runs 101 s behind the Mac, and the same 10-minute break read 10 on the web and 12
/// there. The host stamps its clock; the client corrects by the offset.
@Suite("Live clock")
struct LiveClockTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private var nowMS: Int { Int(now.timeIntervalSince1970 * 1000) }

    @Test func anOlderHostThatDoesNotStampLeavesTheClockAlone() {
        // Additive field: a host from before this tick sends no `now`, and the joiner must
        // behave exactly as it did — not jump to 1970.
        #expect(LiveClock.offsetMS(pubNow: nil, receivedAt: now) == 0)
        #expect(LiveClock.secondsRemaining(deadlineMS: nowMS + 30_000, offsetMS: 0, now: now) == 30)
    }

    @Test func aDeviceRunningBehindStillCountsTheHostsSeconds() {
        // The bench case: this device's clock is 101 s BEHIND the host's.
        let deviceNow = now.addingTimeInterval(-101)
        let offset = LiveClock.offsetMS(pubNow: nowMS, receivedAt: deviceNow)
        #expect(Int(offset / 1000) == 101)
        // A 30-second question is 30 seconds here too — uncorrected it would read 131.
        let deadline = nowMS + 30_000
        #expect(LiveClock.secondsRemaining(deadlineMS: deadline, offsetMS: offset, now: deviceNow) == 30)
        #expect(LiveClock.secondsRemaining(deadlineMS: deadline, offsetMS: 0, now: deviceNow) == 131)
    }

    @Test func aDeviceRunningAheadIsCorrectedToo() {
        let deviceNow = now.addingTimeInterval(45)
        let offset = LiveClock.offsetMS(pubNow: nowMS, receivedAt: deviceNow)
        #expect(Int(offset / 1000) == -45)
        #expect(LiveClock.secondsRemaining(deadlineMS: nowMS + 30_000, offsetMS: offset, now: deviceNow) == 30)
    }

    @Test func anExpiredDeadlineIsZeroNotNegative() {
        #expect(LiveClock.secondsRemaining(deadlineMS: nowMS - 5_000, offsetMS: 0, now: now) == 0)
        #expect(LiveClock.secondsRemaining(deadlineMS: nil, offsetMS: 0, now: now) == nil)
    }

    @Test func theBreakCountdownAgreesAcrossSkewedDevices() {
        // The exact bench symptom: a 10-minute break, read on a device 101 s behind.
        let until = LiveBreak.until(minutes: 10, now: now)
        let deviceNow = now.addingTimeInterval(-101)
        let offset = LiveClock.offsetMS(pubNow: nowMS, receivedAt: deviceNow)
        let corrected = LiveClock.hostNow(offsetMS: offset, now: deviceNow)
        #expect(LiveBreak.headline(until: until, now: corrected) == "Back in 10 minutes")
        // …and this is what the room actually saw before the fix.
        #expect(LiveBreak.headline(until: until, now: deviceNow) == "Back in 12 minutes")
    }
}
