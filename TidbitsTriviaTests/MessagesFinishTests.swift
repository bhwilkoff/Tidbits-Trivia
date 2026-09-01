import Foundation
import Testing

/// How an iMessage round ENDS.
///
/// The end of a round used to render as "question 5, still". No result, no winner, and
/// none of the earlier explanations — which in a message thread have long scrolled
/// away. The results screen is new; these pin the logic behind it.
///
/// The winner rule itself is `StandingsOutcome`, shared with the other five surfaces
/// rather than reimplemented here. What these tests cover is that the extension feeds
/// it correctly, and the degenerate finishes (a tie, a 0–0 board, a lone player, a
/// late joiner) that a happy-path check would sail past.
struct MessagesFinishTests {

    private let ids = ["q1", "q2", "q3", "q4", "q5"]

    /// Answer key for the fake questions: question N's correct index is N % 4.
    private let key: (String) -> Int? = { id in
        guard let n = Int(id.dropFirst()) else { return nil }
        return n % 4
    }

    private func player(_ id: String, _ name: String, _ answers: [Int?]) -> RoundState.Player {
        RoundState.Player(id: id, name: name, answers: answers)
    }

    private func entries(_ s: RoundState) -> [(name: String, score: Int)] {
        s.players.map { (name: $0.name, score: s.score($0, correctIndexFor: key)) }
    }

    // MARK: - When a round is over

    @Test func aRoundIsNotFinishedUntilTheLastQuestionIsAnsweredByEveryone() {
        // Ada has answered all five; Ben has answered four. Index is on the last
        // question. The round is NOT over — showing results here would lock Ben out
        // of a question he never saw.
        let s = RoundState(questionIDs: ids, players: [
            player("a", "Ada", [1, 2, 3, 0, 1]),
            player("b", "Ben", [1, 2, 3, 0, nil]),
        ], index: 4)
        #expect(!s.isFinished)
    }

    @Test func aRoundIsFinishedOnceTheLastAnswerLands() {
        let s = RoundState(questionIDs: ids, players: [
            player("a", "Ada", [1, 2, 3, 0, 1]),
            player("b", "Ben", [1, 2, 3, 0, 2]),
        ], index: 4)
        #expect(s.isFinished)
    }

    @Test func anEarlierQuestionCompletedByEveryoneDoesNotFinishTheRound() {
        let s = RoundState(questionIDs: ids, players: [
            player("a", "Ada", [1, nil, nil, nil, nil]),
            player("b", "Ben", [2, nil, nil, nil, nil]),
        ], index: 0)
        #expect(!s.isFinished)
    }

    @Test func aSoloRoundFinishes() {
        // One person playing alone in a thread is a real case, not an edge case.
        let s = RoundState(questionIDs: ids,
                           players: [player("a", "Ada", [1, 2, 3, 0, 1])], index: 4)
        #expect(s.isFinished)
        #expect(StandingsOutcome.headline(entries(s), empty: "That's a round!") == "Ada wins!")
    }

    // MARK: - Who won

    @Test func aClearLeaderIsNamed() {
        // Key: q1->1, q2->2, q3->3, q4->0, q5->1. Ada gets all five, Ben none.
        let s = RoundState(questionIDs: ids, players: [
            player("a", "Ada", [1, 2, 3, 0, 1]),
            player("b", "Ben", [0, 0, 0, 1, 0]),
        ], index: 4)
        #expect(s.score(s.players[0], correctIndexFor: key) == 5)
        #expect(s.score(s.players[1], correctIndexFor: key) == 0)
        #expect(StandingsOutcome.headline(entries(s), empty: "That's a round!") == "Ada wins!")
    }

    @Test func everyoneLevelIsATieRatherThanAnArbitraryWinner() {
        let s = RoundState(questionIDs: ids, players: [
            player("a", "Ada", [1, 2, 3, 0, 1]),
            player("b", "Ben", [1, 2, 3, 0, 1]),
        ], index: 4)
        #expect(StandingsOutcome.headline(entries(s), empty: "That's a round!") == "It's a tie!")
    }

    /// The finish nobody designs for. Two players, nobody right, and a naive
    /// "sort and crown element 0" reports a victory that did not happen.
    @Test func aZeroZeroBoardTiesRatherThanCrowning() {
        let s = RoundState(questionIDs: ids, players: [
            player("a", "Ada", [0, 0, 0, 1, 0]),
            player("b", "Ben", [0, 0, 0, 1, 0]),
        ], index: 4)
        #expect(entries(s).allSatisfy { $0.score == 0 })
        #expect(StandingsOutcome.headline(entries(s), empty: "That's a round!") == "It's a tie!")
    }

    @Test func aPartialTieNamesEveryLeader() {
        let s = RoundState(questionIDs: ids, players: [
            player("a", "Ada", [1, 2, 3, 0, 1]),
            player("b", "Ben", [1, 2, 3, 0, 1]),
            player("c", "Cal", [0, 0, 0, 1, 0]),
        ], index: 4)
        let headline = StandingsOutcome.headline(entries(s), empty: "That's a round!")
        #expect(headline == "Tie — Ada & Ben")
        // EVERY leader is highlighted, not just whichever the sort put first.
        #expect(StandingsOutcome.isTop(5, in: entries(s)))
        #expect(!StandingsOutcome.isTop(0, in: entries(s)))
    }

    @Test func aRoundWithNoPlayersUsesTheFallbackRatherThanCrowningNobody() {
        let s = RoundState(questionIDs: ids, players: [], index: 4)
        #expect(!s.isFinished, "an empty round cannot be complete")
        #expect(StandingsOutcome.headline(entries(s), empty: "That's a round!") == "That's a round!")
    }

    // MARK: - Ragged answer arrays

    /// A late joiner is seeded with a full-length answers array, but the WIRE is not
    /// obliged to be well-formed: decoding takes whatever characters arrived. The
    /// results screen indexes per question, so a short array must not be a crash —
    /// and a crash here happens inside Messages.
    @Test func aShortAnswerArrayFromTheWireIsSurvivable() throws {
        let url = try #require(URL(string:
            "https://tidbitstrivia.com/r?v=1&i=4&q=q1~q2~q3~q4~q5&p=a:Ada:12|b:Ben:1"))
        let s = try #require(RoundState(url: url))

        #expect(s.questionIDs.count == 5)
        #expect(s.players[0].answers.count == 2, "the wire carried only two answers")
        #expect(s.players[1].answers.count == 1)

        // Scoring zips, so it stops at the shorter side rather than reading past it.
        #expect(s.score(s.players[0], correctIndexFor: key) == 2)
        #expect(s.score(s.players[1], correctIndexFor: key) == 1)

        // And the per-question lookup the results screen does must be bounds-safe for
        // every question in the round, not just the ones that have an answer.
        for i in 0..<s.questionIDs.count {
            let a = s.players[0].answers.indices.contains(i) ? s.players[0].answers[i] : nil
            #expect(a != nil || i >= 2)
        }
    }

    @Test func aLateJoinerScoresOnlyWhatTheyAnswered() {
        var s = RoundState(questionIDs: ids,
                           players: [player("a", "Ada", [1, 2, 3, 0, nil])], index: 4)
        s.upsert(playerID: "z", name: "Zoe")
        #expect(s.players[1].answers.count == 5, "a joiner is seeded to the round length")
        #expect(s.score(s.players[1], correctIndexFor: key) == 0)

        s.answer(playerID: "z", choice: 1)      // q5 correct
        s.answer(playerID: "a", choice: 1)
        #expect(s.isFinished)
        #expect(s.score(s.players[1], correctIndexFor: key) == 1)
        #expect(StandingsOutcome.headline(entries(s), empty: "x") == "Ada wins!")
    }
}
