import Testing
import Foundation

/// G6 — the host's phone remote. These pin the three rules that keep a
/// player-to-host command channel from wrecking a night.
@Suite("Live host remote")
struct LiveRemoteTests {

    private func cmd(_ id: Int, _ verb: String, _ pin: String = "123456") -> RemoteCommand {
        RemoteCommand(id: id, verb: verb, pin: pin)
    }

    @Test("a valid command is accepted")
    func valid() {
        #expect(LiveRemote.accepted(cmd(1, "next"), pin: "123456", lastExecutedID: 0))
    }

    @Test("the wrong PIN is refused — the room code is not authorisation")
    func wrongPIN() {
        // The code is printed on the projector; every player has it. Without a
        // separate PIN any table could reveal the answer.
        #expect(!LiveRemote.accepted(cmd(1, "next", "000000"), pin: "123456", lastExecutedID: 0))
    }

    @Test("a host with NO pin set accepts nothing")
    func noPIN() {
        // Not-yet-paired must fail closed, not open.
        #expect(!LiveRemote.accepted(cmd(1, "next", ""), pin: "", lastExecutedID: 0))
    }

    @Test("a REPLAYED command is refused, so a retry cannot skip a question")
    func replay() {
        #expect(LiveRemote.accepted(cmd(5, "next"), pin: "123456", lastExecutedID: 4))
        // The same command arriving again after it ran.
        #expect(!LiveRemote.accepted(cmd(5, "next"), pin: "123456", lastExecutedID: 5))
    }

    @Test("an out-of-order command from a stale remote is refused")
    func stale() {
        #expect(!LiveRemote.accepted(cmd(3, "next"), pin: "123456", lastExecutedID: 7))
    }

    @Test("an unknown verb is refused rather than guessed at")
    func unknownVerb() {
        #expect(!LiveRemote.accepted(cmd(1, "endnight"), pin: "123456", lastExecutedID: 0))
        #expect(!LiveRemote.accepted(cmd(1, ""), pin: "123456", lastExecutedID: 0))
    }

    @Test("the remote is a clicker, not a second cockpit")
    func verbSet() {
        // Anything that EDITS the night stays on the laptop, where it can be read
        // before it is changed.
        #expect(LiveRemote.verbs == ["reveal", "next", "skip", "scores", "board"])
        for v in ["setscore", "removeteam", "editquestion", "endnight"] {
            #expect(!LiveRemote.verbs.contains(v))
        }
    }

    @Test("a reconnecting remote resumes from the host's counter")
    func resume() {
        // A phone that lost its counter must not restart at 1 — every command
        // would be refused forever.
        #expect(LiveRemote.nextID(lastExecutedID: 9) == 10)
        #expect(LiveRemote.accepted(cmd(LiveRemote.nextID(lastExecutedID: 9), "reveal"),
                                    pin: "123456", lastExecutedID: 9))
    }

    @Test("a PIN is six digits")
    func pin() {
        for _ in 0..<50 {
            let p = LiveRemote.makePIN()
            #expect(p.count == 6)
            #expect(p.allSatisfy { $0.isNumber })
        }
    }
}
