#if os(macOS)
import Foundation
import Testing
@testable import TidbitsTriviaTests

/// G1 buzz round — the first team to buzz answers out loud.
///
/// The whole feature is the ORDERING, so that is what is pinned. A buzzer decided
/// by whose handset clock runs fast is not a buzzer, and the speed bonus shipped
/// with exactly that bug: `sv` is stamped by the server when the write lands, and
/// `ts` is only the fallback for a client that predates it.
@Suite("Buzz round")
struct BuzzRoundTests {

    private func answer(ts: Int, sv: Int? = nil) -> LiveRoom.Answer {
        LiveRoom.Answer(ts: ts, sv: sv)
    }

    @Test("the server stamp decides, not the phone")
    func serverStampWins() {
        // The unfair case made concrete: "fast" has a handset three seconds ahead,
        // but the server saw "honest" first.
        let answers = ["fast":   answer(ts: 1_000, sv: 5_002),
                       "honest": answer(ts: 4_000, sv: 5_001)]
        #expect(LiveNightHost.firstBuzz(answers) == "honest")
    }

    @Test("falls back to the device clock for a client without the stamp")
    func fallsBack() {
        let answers = ["a": answer(ts: 9_000), "b": answer(ts: 8_000)]
        #expect(LiveNightHost.firstBuzz(answers) == "b")
    }

    @Test("a wrong buzz reopens it to the rest")
    func wrongBuzzReopens() {
        // The pub rule: the first team gets it wrong and the question goes BACK to
        // the room, rather than ending. Ruling one team out promotes the next.
        let answers = ["first":  answer(ts: 0, sv: 100),
                       "second": answer(ts: 0, sv: 200),
                       "third":  answer(ts: 0, sv: 300)]
        #expect(LiveNightHost.firstBuzz(answers) == "first")
        #expect(LiveNightHost.firstBuzz(answers, excluding: ["first"]) == "second")
        #expect(LiveNightHost.firstBuzz(answers, excluding: ["first", "second"]) == "third")
        #expect(LiveNightHost.firstBuzz(answers, excluding: ["first", "second", "third"]) == nil)
    }

    @Test("nobody buzzed")
    func empty() {
        #expect(LiveNightHost.firstBuzz([:]) == nil)
    }

    @Test("a buzz round survives the event file")
    func roundTrips() throws {
        // LIVE-EVENT-FILE §2.4: additive, no version bump. A host who marks a round
        // as a buzz round and reopens the file must still have a buzz round.
        var event = LiveEvent(name: "Friday")
        event.rounds = [LiveRound(title: "Buzz", format: .classic, categoryID: "mixed",
                                  questions: [], isBuzz: true)]
        let back = try LiveEventFile.decode(try LiveEventFile.encode(event))
        #expect(back.rounds.first?.isBuzz == true)
    }
}
#endif
