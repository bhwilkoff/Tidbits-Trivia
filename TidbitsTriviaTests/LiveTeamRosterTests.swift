import Testing
import Foundation

/// G7 — several phones, one team. These pin the calls that decide whether a
/// table's night is scored as one team or three.
@Suite("Live team roster")
struct LiveTeamRosterTests {

    private func m(_ uid: String, _ team: String, _ at: Int) -> LiveMember {
        LiveMember(uid: uid, teamName: team, joinedAt: at)
    }

    @Test("the same name typed differently is ONE team")
    func folding() {
        let members = [m("a", "The Quizzinators", 100),
                       m("b", "the  quizzinators ", 200),
                       m("c", "THE QUIZZINATORS", 300)]
        let teams = LiveTeamRoster.teams(members)
        #expect(teams.count == 1)
        #expect(teams[0].size == 3)
    }

    @Test("the display name is the LEADER's spelling, not the latest joiner's")
    func leaderSpelling() {
        let teams = LiveTeamRoster.teams([m("a", "The Quizzinators", 100),
                                          m("b", "the quizzinators", 200)])
        #expect(teams[0].name == "The Quizzinators")
    }

    @Test("punctuation is NOT folded — two plausible tables stay two teams")
    func punctuationKept() {
        // Merging is destructive in a way splitting is not: a host can merge two
        // rows, but cannot un-merge a night's scoring.
        let teams = LiveTeamRoster.teams([m("a", "St. Elmo", 100), m("b", "St Elmo", 200)])
        #expect(teams.count == 2)
    }

    @Test("the earliest joiner leads")
    func leader() {
        let teams = LiveTeamRoster.teams([m("late", "Table 4", 900), m("early", "Table 4", 100)])
        #expect(teams[0].leader?.uid == "early")
    }

    @Test("a same-millisecond tie breaks on uid, so every stack agrees who leads")
    func tie() {
        let a = LiveTeamRoster.teams([m("zeta", "T", 500), m("alpha", "T", 500)])
        let b = LiveTeamRoster.teams([m("alpha", "T", 500), m("zeta", "T", 500)])
        #expect(a[0].leader?.uid == "alpha")
        #expect(b[0].leader?.uid == "alpha")   // input order must not matter
    }

    @Test("an empty or whitespace-only team name joins nothing")
    func blank() {
        #expect(LiveTeamRoster.teams([m("a", "   ", 100), m("b", "", 200)]).isEmpty)
    }

    @Test("the FIRST answer stands — a teammate cannot overwrite it")
    func firstAnswerWins() {
        let team = LiveTeamRoster.teams([m("a", "T", 100), m("b", "T", 200)])[0]
        // b answered first even though a joined first: the ANSWER stamp decides,
        // not the join order.
        let who = LiveTeamRoster.answeringMember(team: team, answeredAt: ["b": 10, "a": 40])
        #expect(who == "b")
    }

    @Test("a team nobody answered for has no answer")
    func noAnswer() {
        let team = LiveTeamRoster.teams([m("a", "T", 100)])[0]
        #expect(LiveTeamRoster.answeringMember(team: team, answeredAt: [:]) == nil)
    }

    @Test("answers from OTHER teams never count for this one")
    func foreignAnswer() {
        let teams = LiveTeamRoster.teams([m("a", "Ours", 100), m("x", "Theirs", 100)])
        let ours = teams.first { $0.name == "Ours" }!
        #expect(LiveTeamRoster.answeringMember(team: ours, answeredAt: ["x": 5]) == nil)
    }

    @Test("when the leader leaves the next member leads — the table plays on")
    func promotion() {
        let team = LiveTeamRoster.teams([m("a", "T", 100), m("b", "T", 200), m("c", "T", 300)])[0]
        #expect(LiveTeamRoster.leaderAfterDepartures(team: team, gone: ["a"])?.uid == "b")
        #expect(LiveTeamRoster.leaderAfterDepartures(team: team, gone: ["a", "b"])?.uid == "c")
        #expect(LiveTeamRoster.leaderAfterDepartures(team: team, gone: ["a", "b", "c"]) == nil)
    }

    @Test("a team with two members answering is scored ONCE")
    func scoredOnce() {
        // The host scores by walking answers per uid. Two phones on one team would
        // be awarded twice for one question — or, under negative marking,
        // penalised twice for one wrong answer.
        let members = [m("a", "T", 100), m("b", "T", 200)]
        let keep = LiveTeamRoster.scorableUIDs(members: members, answeredAt: ["a": 5, "b": 9])
        #expect(keep == ["a"])
    }

    @Test("two DIFFERENT teams are both scored")
    func bothTeamsScored() {
        let members = [m("a", "Ours", 100), m("x", "Theirs", 100)]
        let keep = LiveTeamRoster.scorableUIDs(members: members, answeredAt: ["a": 5, "x": 9])
        #expect(keep == ["a", "x"])
    }

    @Test("an answer from a uid the host has no join for still scores")
    func unknownUID() {
        // A device that answered before its join landed. Dropping it silently
        // loses a real answer, which is worse than the duplicate this guards.
        let keep = LiveTeamRoster.scorableUIDs(members: [m("a", "T", 100)],
                                               answeredAt: ["a": 5, "ghost": 7])
        #expect(keep == ["a", "ghost"])
    }

    @Test("nobody answering scores nobody")
    func noneScored() {
        #expect(LiveTeamRoster.scorableUIDs(members: [m("a", "T", 100)], answeredAt: [:]).isEmpty)
    }

    @Test("a uid resolves to its own team")
    func lookup() {
        let members = [m("a", "Ours", 100), m("x", "Theirs", 100)]
        #expect(LiveTeamRoster.team(of: "x", in: members)?.name == "Theirs")
        #expect(LiveTeamRoster.team(of: "nobody", in: members) == nil)
    }
}
