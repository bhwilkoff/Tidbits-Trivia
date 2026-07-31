import Testing

/// A shared question set makes ties ordinary, not exotic: identical play earns
/// identical scores. Announcing element 0 of a score-sort as "the winner" turned
/// an arbitrary tiebreak into a declared victory (QA-SWEEP-LOG Q23), so the rule
/// is pinned here. Mirrors windows/Tidbits.HeadlessTests/StandingsOutcomeTest.cs.
@Suite("Standings outcome")
struct StandingsOutcomeTests {

    @Test func singleLeaderWins() {
        #expect(StandingsOutcome.headline([("Ana", 900), ("Bo", 400)], empty: "none") == "Ana wins!")
    }

    @Test func everyoneLevelIsATie() {
        #expect(StandingsOutcome.headline([("Ana", 900), ("Bo", 900)], empty: "none") == "It's a tie!")
    }

    @Test func partialTieNamesTheLeaders() {
        #expect(StandingsOutcome.headline([("Ana", 900), ("Bo", 900), ("Cy", 100)], empty: "none")
                == "Tie — Ana & Bo")
    }

    @Test func emptyBoardUsesTheFallback() {
        #expect(StandingsOutcome.headline([], empty: "That's a night!") == "That's a night!")
    }

    @Test func everyTiedLeaderIsHighlighted() {
        let e = [("Ana", 900), ("Bo", 900), ("Cy", 100)]
        #expect(StandingsOutcome.isTop(900, in: e))
        #expect(!StandingsOutcome.isTop(100, in: e))
        #expect(StandingsOutcome.winners(e).count == 2)
    }

    /// Nobody scoring is still a tie, not a crowning — the all-wrong Pass & Play run.
    @Test func zeroZeroBoardTiesRatherThanCrowning() {
        #expect(StandingsOutcome.headline([("Ana", 0), ("Bo", 0)], empty: "none") == "It's a tie!")
    }
}
