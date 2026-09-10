import Testing
import Foundation

/// A3.11 — the night read back from the answer sheet.
@Suite("Live night report")
struct LiveNightReportTests {
    private func rec(_ qid: String, round: Int, n: Int, answer: String = "A", points: [Int]) -> LiveAnswerRecord {
        LiveAnswerRecord(qid: qid, round: round, number: n, prompt: "Q \(qid)", answer: answer,
                         lines: points.enumerated().map { .init(uid: "u\($0.offset)", team: "T\($0.offset)", submitted: "x", points: $0.element) })
    }

    @Test("hardest, easiest, per-round accuracy and participation come from the sheet")
    func shape() {
        let log = [rec("r0q0", round: 1, n: 1, points: [1, 1, 0, 0]),      // 50%
                   rec("r0q1", round: 1, n: 2, points: [1, 1, 1, 0]),      // 75%
                   rec("r1q2", round: 2, n: 1, points: [0, 0, 0]),         // 0%, one table silent
                   rec("r1q3", round: 2, n: 2, answer: "(poll)", points: [0, 0, 0, 0])]   // a poll is not a question
        let r = LiveNightReport.from(log, teams: 4)
        #expect(r.questions.count == 3)
        #expect(r.hardest?.qid == "r1q2")
        #expect(r.easiest?.qid == "r0q1")
        #expect(r.rounds.map(\.round) == [1, 2])
        #expect(LiveNightReport.percent(r.rounds[0].accuracy) == "63%")
        #expect(r.rounds[1].accuracy == 0)
        #expect(abs(r.participation - (11.0 / 3.0) / 4.0) < 0.001)
        #expect(LiveNightReport.percent(r.overallAccuracy) == "45%")
    }

    @Test("an empty sheet is an empty report, and a question nobody answered is neither hardest nor easiest")
    func edges() {
        #expect(LiveNightReport.from([], teams: 3).isEmpty)
        let r = LiveNightReport.from([rec("r0q0", round: 1, n: 1, points: []), rec("r0q1", round: 1, n: 2, points: [1])], teams: 1)
        #expect(r.hardest?.qid == "r0q1" && r.easiest?.qid == "r0q1")
        #expect(r.participation == 0.5)
    }
}
