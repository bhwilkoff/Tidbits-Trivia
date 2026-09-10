import Testing
import Foundation

/// The wrap recap: nailed is decided by the SCORE, once per question, with a
/// late score write still settling the last one.
@Suite("Live recap")
struct LiveRecapTests {
    private func pub(_ qid: String, _ phase: String, answer: String? = nil, difficulty: Int? = nil) -> LiveRoom.Pub {
        var p = LiveRoom.Pub(round: 1, roundTitle: "R", qid: qid, qNum: 1, qTotal: 2, phase: phase,
                             prompt: "Q \(qid)", options: nil, format: "typeAnswer", answerIndex: nil)
        p.answer = answer; p.difficulty = difficulty
        return p
    }

    @Test("a credited hard question is a tough one; an uncredited one is to remember")
    func creditDecides() {
        var b = LiveRecapBook()
        b.observe(pub("r0q0", "question"), score: 0)
        b.observe(pub("r0q0", "reveal", answer: "Keanu Reeves", difficulty: 4), score: 0)
        b.observe(pub("r0q1", "question"), score: 3)          // the host paid 3 for q0
        b.observe(pub("r0q1", "reveal", answer: "Warner Bros.", difficulty: 2), score: 3)
        b.observe(pub("end", "ended"), score: 3)
        b.finish(score: 3)
        #expect(b.entries.count == 2)
        #expect(b.tough.map(\.qid) == ["r0q0"])
        #expect(b.toRemember.map(\.qid) == ["r0q1"])
        #expect(b.toRemember[0].answer == "Warner Bros.")
    }

    @Test("a reveal republished twice is one entry, and an easy credited question is neither list")
    func onceAndEasy() {
        var b = LiveRecapBook()
        b.observe(pub("r0q0", "question"), score: 0)
        b.observe(pub("r0q0", "reveal", answer: "A", difficulty: 2), score: 0)
        b.observe(pub("r0q0", "reveal", answer: "A", difficulty: 2), score: 1)   // e.g. a media cue republish
        b.finish(score: 1)
        #expect(b.entries.count == 1)
        #expect(b.entries[0].nailed)
        #expect(b.tough.isEmpty && b.toRemember.isEmpty)
    }

    @Test("a late score write at the wrap settles the last question")
    func lateScore() {
        var b = LiveRecapBook()
        b.observe(pub("r0q0", "question"), score: 0)
        b.observe(pub("r0q0", "reveal", answer: "A", difficulty: 5), score: 0)
        b.observe(pub("end", "ended"), score: 0)   // the ended frame arrives before the score write
        b.finish(score: 0)
        #expect(b.tough.isEmpty)
        b.finish(score: 2)                          // the client re-finishes on every score write at the wrap
        #expect(b.tough.count == 1)
        #expect(b.toRemember.isEmpty)
    }
}
