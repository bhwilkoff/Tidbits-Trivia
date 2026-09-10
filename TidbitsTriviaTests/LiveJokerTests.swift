import Testing
import Foundation

/// A2.14 — the joker: one round per table, named before it starts, worth double.
@Suite("Live joker")
struct LiveJokerTests {
    @Test func aJokerCanOnlyBePlayedOnARoundStillAhead() {
        let titles = ["General", "Music", "Pictures", "Final"]
        #expect(LiveJoker.playable(current: -1, titles: titles).map(\.index) == [0, 1, 2, 3])   // before the night
        #expect(LiveJoker.playable(current: 0, titles: titles).map(\.index) == [1, 2, 3])
        #expect(LiveJoker.playable(current: 3, titles: titles).isEmpty)
        // The wager round stakes a table's own points already — no joker on top.
        #expect(LiveJoker.playable(current: 0, titles: titles, wager: 3).map(\.index) == [1, 2])
        #expect(LiveJoker.playable(current: 0, titles: ["", "x"]).first?.title == "Round 2")
    }

    @Test func lockingARoundKeepsOnlyThePicksForThatRoundByTeam() {
        let picks = ["u1": 2, "u2": 1, "u3": 2, "u4": 2]
        let team: (String) -> String? = { ["u1": "The Bar", "u2": "Corner", "u3": "The Bar", "u4": nil][$0] ?? nil }
        // u1 and u3 are two phones on one table (G7) — one team, once.
        #expect(LiveJoker.played(on: 2, picks: picks, teamOf: team) == ["The Bar"])
        #expect(LiveJoker.played(on: 1, picks: picks, teamOf: team) == ["Corner"])
        #expect(LiveJoker.played(on: 0, picks: picks, teamOf: team).isEmpty)
    }

    @Test func aPlayedJokerDoublesAndNothingElseDoes() {
        #expect(LiveJoker.multiplier(team: "The Bar", played: ["The Bar"]) == 2)
        #expect(LiveJoker.multiplier(team: "Corner", played: ["The Bar"]) == 1)
        #expect(LiveJoker.multiplier(team: "Corner", played: []) == 1)
    }

    @Test func theBigScreenNamesWhoPlayedOrSaysNothing() {
        #expect(LiveJoker.line(played: []) == nil)
        #expect(LiveJoker.line(played: ["The Bar"]) == "Joker played: The Bar")
        #expect(LiveJoker.line(played: ["Corner", "The Bar"]) == "Jokers played: Corner, The Bar")
    }

    @Test("the wire keys every joiner reads: pub.jokerRounds[].index/title and jokers/{uid}.round")
    func wireKeys() throws {
        var p = LiveRoom.Pub(round: 1, roundTitle: "R1", qid: "r0q0", qNum: 1, qTotal: 2, phase: "question",
                             prompt: "?", options: nil, format: "classic", answerIndex: nil)
        p.jokerRounds = [.init(index: 1, title: "Music")]
        let obj = try JSONSerialization.jsonObject(with: JSONEncoder().encode(p)) as! [String: Any]
        let jr = (obj["jokerRounds"] as! [[String: Any]])[0]
        #expect(jr["index"] as? Int == 1)
        #expect(jr["title"] as? String == "Music")
        let j = try JSONSerialization.jsonObject(with: JSONEncoder().encode(LiveRoom.Joker(round: 2, ts: 5))) as! [String: Any]
        #expect(j["round"] as? Int == 2)
        // A pub without the joker carries no key at all — older clients never see it.
        var quiet = p; quiet.jokerRounds = nil
        let q = try JSONSerialization.jsonObject(with: JSONEncoder().encode(quiet)) as! [String: Any]
        #expect(q["jokerRounds"] == nil)
    }
}
