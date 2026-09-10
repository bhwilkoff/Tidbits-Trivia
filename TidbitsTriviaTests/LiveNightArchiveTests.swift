import Testing
import Foundation

/// A2.12 — the night is kept after the cockpit closes: newest first, capped, and
/// the report regenerates from the archived sheet rather than being stored.
@Suite("Live night archive")
@MainActor
struct LiveNightArchiveTests {
    private func store() -> LiveNightArchive {
        let d = UserDefaults(suiteName: "tidbits.tests.nights.\(UUID().uuidString)")!
        return LiveNightArchive(defaults: d, key: "tidbits.liveNights")
    }

    private func record(_ q: String, right: Int, wrong: Int) -> LiveAnswerRecord {
        var lines: [LiveAnswerRecord.Line] = []
        for i in 0..<right { lines.append(.init(uid: "r\(i)", team: "Right \(i)", submitted: "Keanu Reeves", points: 1)) }
        for i in 0..<wrong { lines.append(.init(uid: "w\(i)", team: "Wrong \(i)", submitted: "Neo", points: 0)) }
        return LiveAnswerRecord(qid: q, round: 1, number: 1, prompt: q, answer: "Keanu Reeves", lines: lines)
    }

    @Test func nightsAreKeptNewestFirstWithAHeadline() {
        let a = store()
        a.record(name: "Tuesday", venue: "The Anchor",
                 standings: [.init(name: "The Quizzards", score: 14, paper: false), .init(name: "Table 2", score: 9, paper: true)],
                 log: [record("q1", right: 2, wrong: 0)])
        a.record(name: "Wednesday", venue: "The Anchor", standings: [.init(name: "Solo", score: 3, paper: false)], log: [])
        #expect(a.nights.map(\.name) == ["Wednesday", "Tuesday"])
        #expect(a.nights[1].headline == "2 teams · The Quizzards won with 14")
        #expect(a.nights[0].headline == "1 team · Solo won with 3")
        #expect(a.nights[1].winner?.name == "The Quizzards")
    }

    @Test func anEmptyNightSaysSoRatherThanNamingAWinner() {
        let a = store()
        let n = a.record(name: "Nobody came", venue: "", standings: [], log: [])
        #expect(n.headline == "No teams were scored")
        #expect(n.winner == nil)
    }

    /// audit-the-degenerate-outcome: a night where the host never revealed pays nobody.
    /// Crowning whoever sorted first — "Table 2 won with 0" — is a lie the host has to
    /// explain to the room. Found on the glass, tick 31.
    @Test func nobodyWinsANightWhereNobodyScored() {
        let a = store()
        let n = a.record(name: "Unrevealed", venue: "",
                         standings: [.init(name: "Table 1", score: 0, paper: false), .init(name: "Table 2", score: 0, paper: false)],
                         log: [])
        #expect(n.headline == "2 teams · nobody scored")
        #expect(n.winner == nil)
    }

    @Test func theReportRegeneratesFromTheArchivedSheet() {
        let a = store()
        let n = a.record(name: "N", venue: "",
                         standings: [.init(name: "A", score: 1, paper: false), .init(name: "B", score: 0, paper: false)],
                         log: [record("q1", right: 1, wrong: 1)])
        // Nothing about the report is stored: an archived night and a live one cannot disagree.
        #expect(!n.report.isEmpty)
        #expect(n.report.questions.count == 1)
        #expect(LiveNightReport.percent(n.report.overallAccuracy) == "50%")
    }

    @Test func theArchiveIsCappedAndSurvivesARelaunch() {
        let d = UserDefaults(suiteName: "tidbits.tests.nights.\(UUID().uuidString)")!
        let a = LiveNightArchive(defaults: d, key: "k")
        for i in 0...(LiveNightArchive.cap + 3) { a.record(name: "N\(i)", venue: "", standings: [], log: []) }
        #expect(a.nights.count == LiveNightArchive.cap)
        #expect(a.nights.first?.name == "N\(LiveNightArchive.cap + 3)")   // newest kept
        // A fresh instance reads the same defaults — the host's archive outlives the launch.
        let again = LiveNightArchive(defaults: d, key: "k")
        #expect(again.nights.count == LiveNightArchive.cap)
        #expect(again.nights.first?.name == a.nights.first?.name)
    }

    @Test func deleteForgetsOneNight() {
        let a = store()
        a.record(name: "Keep", venue: "", standings: [], log: [])
        let gone = a.record(name: "Gone", venue: "", standings: [], log: [])
        a.delete(gone.id)
        #expect(a.nights.map(\.name) == ["Keep"])
    }

    @Test func aRunawaySheetIsTrimmedNotDropped() {
        let a = store()
        let huge = (0..<(LiveNightArchive.logCap + 50)).map { record("q\($0)", right: 1, wrong: 0) }
        let n = a.record(name: "Long", venue: "", standings: [.init(name: "A", score: 1, paper: false)], log: huge)
        #expect(n.log.count == LiveNightArchive.logCap)
        #expect(a.nights.count == 1)
    }
}
