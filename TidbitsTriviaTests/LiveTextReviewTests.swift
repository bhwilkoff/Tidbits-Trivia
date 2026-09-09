import Testing
import Foundation

/// §A3.3 "accept this answer from everyone" — the ruling has to reach exactly
/// the teams the scorer refused for THAT answer, and each of them once.
@Suite("Live free-text review")
struct LiveTextReviewTests {

    private func a(_ text: String) -> LiveRoom.Answer { LiveRoom.Answer(text: text, ts: 1) }

    @Test("everyone who typed the same thing, under the scorer's own normalisation")
    func alike() {
        let answers = ["t1": a("Keanu Reeves"), "t2": a("keanu reeves"), "t3": a("The Keanu Reeves!"),
                       "t4": a("Keanu Reaves"), "t5": a("Kenau Reeves")]
        let got = LiveNightHost.typedAlike("Keanu Reeves", answers: answers, accepted: ["Reeves"], already: [])
        #expect(got == ["t1", "t2", "t3"])
    }

    @Test("a team the matcher already credited is not paid again")
    func alreadyCorrect() {
        let answers = ["t1": a("Reeves"), "t2": a("reeves")]
        #expect(LiveNightHost.typedAlike("Reeves", answers: answers, accepted: ["Reeves"], already: []).isEmpty)
    }

    @Test("a team accepted by hand earlier is not paid twice")
    func alreadyAccepted() {
        let answers = ["t1": a("Keanu"), "t2": a("keanu")]
        #expect(LiveNightHost.typedAlike("Keanu", answers: answers, accepted: ["Reeves"], already: ["t1"]) == ["t2"])
    }

    @Test("blank rulings and non-text answers match nobody")
    func blanks() {
        let answers = ["t1": a("   "), "t2": LiveRoom.Answer(choice: 1, ts: 1)]
        #expect(LiveNightHost.typedAlike("  ", answers: answers, accepted: [], already: []).isEmpty)
        #expect(LiveNightHost.typedAlike("x", answers: answers, accepted: [], already: []).isEmpty)
    }
}
