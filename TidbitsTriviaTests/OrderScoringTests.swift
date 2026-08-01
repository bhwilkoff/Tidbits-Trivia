import Testing

/// In Order pays partial credit, and partial credit is only fair if it is
/// measured against the right zero.
///
/// The board is dealt SHUFFLED, and a shuffled list of four items already has
/// about half its pairs in the right relative order. Paying
/// `40 * (1 - inversions/max)` therefore started every round at half marks —
/// measured by playing all 126 mode x category combinations to lose
/// (`TIDBITS_PLAYTHROUGH_STYLE=timeout`), a player who never touched the board
/// scored a mean of 119 out of 240, with a floor of 87. That is more than most
/// modes pay for playing well, and it made In Order scores incomparable with
/// every other mode's.
@Suite("Order scoring")
struct OrderScoringTests {

    @Test func aPerfectArrangementPaysFull() {
        #expect(GameEngine.orderPoints(inversions: 0, maxInversions: 6) == 40)
    }

    @Test func aChanceArrangementPaysNothing() {
        // Half the pairs right is what shuffling gives you for free.
        #expect(GameEngine.orderPoints(inversions: 3, maxInversions: 6) == 0)
    }

    @Test func aCompletelyReversedArrangementPaysNothing() {
        #expect(GameEngine.orderPoints(inversions: 6, maxInversions: 6) == 0)
    }

    /// Adds-only (Decision 022): worse than chance is 0, never negative.
    @Test func worseThanChanceNeverGoesNegative() {
        for inv in 3...6 {
            #expect(GameEngine.orderPoints(inversions: inv, maxInversions: 6) >= 0)
        }
    }

    @Test func betterThanChanceScalesUpToFull() {
        // One inversion left of six is 5/6 right = well above chance, and should
        // pay most of the 40 — partial credit still has to feel like credit.
        let almost = GameEngine.orderPoints(inversions: 1, maxInversions: 6)
        #expect(almost > 20 && almost < 40)
        // Monotonic: fewer inversions never pays less.
        for inv in 0..<6 {
            #expect(GameEngine.orderPoints(inversions: inv, maxInversions: 6)
                    >= GameEngine.orderPoints(inversions: inv + 1, maxInversions: 6))
        }
    }

    @Test func aDegenerateBoardScoresZeroRatherThanDividingByZero() {
        #expect(GameEngine.orderPoints(inversions: 0, maxInversions: 0) == 0)
    }
}
