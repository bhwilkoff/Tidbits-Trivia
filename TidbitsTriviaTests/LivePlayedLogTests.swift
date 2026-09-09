import Testing
import Foundation

/// A2.6 — a re-run night must be able to name what the room already heard.
@Suite("Live played log")
@MainActor
struct LivePlayedLogTests {

    private func fresh() -> LivePlayedLog {
        let suite = "test.played.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        return LivePlayedLog(defaults: d, key: "played")
    }

    @Test("a hosted question is remembered with its night and date, and re-asking moves the date forward")
    func recordAndUpdate() {
        let log = fresh()
        let t1 = Date(timeIntervalSince1970: 1_000_000), t2 = Date(timeIntervalSince1970: 2_000_000)
        log.record(["q1", "q2"], night: "Friday Pub Quiz", at: t1)
        log.record(["q2"], night: "Tuesday Special", at: t2)
        #expect(log.ids == ["q1", "q2"])
        #expect(log.entry("q1") == LivePlayedEntry(at: t1, night: "Friday Pub Quiz"))
        #expect(log.entry("q2") == LivePlayedEntry(at: t2, night: "Tuesday Special"))
        #expect(log.entry("q3") == nil)
    }

    @Test("blank ids are ignored and clear empties the log")
    func blanksAndClear() {
        let log = fresh()
        log.record(["", "q1"], night: "N")
        #expect(log.ids == ["q1"])
        log.clear()
        #expect(log.ids.isEmpty)
    }

    @Test("the badge reads like a person: today, yesterday, days, weeks, then a date")
    func askedLine() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        func line(_ daysAgo: Double, _ night: String = "Pub Quiz") -> String {
            LivePlayedLog.askedLine(LivePlayedEntry(at: now.addingTimeInterval(-daysAgo * 86_400), night: night), now: now)
        }
        #expect(line(0) == "Asked today · Pub Quiz")
        #expect(line(1) == "Asked yesterday · Pub Quiz")
        #expect(line(6) == "Asked 6 days ago · Pub Quiz")
        #expect(line(21) == "Asked 3 weeks ago · Pub Quiz")
        #expect(line(90).hasPrefix("Asked ") && !line(90).contains("ago"))
        #expect(line(2, "  ") == "Asked 2 days ago")
    }
}
