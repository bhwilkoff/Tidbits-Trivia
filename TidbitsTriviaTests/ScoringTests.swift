import Testing

/// Scoring is the number the player sees, so its edges matter more than its
/// middle: a wrong answer must never pay, the speed bonus must not go negative
/// on an overrun, and the streak multiplier is capped on purpose (a runaway
/// multiplier stops being a thrill and starts being noise).
@Suite("Scoring")
struct ScoringTests {

    @Test func wrongAnswersNeverScore() {
        #expect(Scoring.points(correct: false, secondsTaken: 0, budget: 20, streak: 99) == 0)
    }

    @Test func instantCorrectAnswerEarnsBasePlusFullSpeedBonus() {
        #expect(Scoring.points(correct: true, secondsTaken: 0, budget: 20, streak: 1)
                == Scoring.base + Scoring.maxSpeedBonus)
    }

    /// Using the entire budget still pays the base — speed is rewarded, never required.
    @Test func usingTheWholeBudgetStillPaysBase() {
        #expect(Scoring.points(correct: true, secondsTaken: 20, budget: 20, streak: 1) == Scoring.base)
    }

    /// An overrun clamps to zero bonus rather than subtracting from the base.
    @Test func overrunningTheBudgetDoesNotGoNegative() {
        #expect(Scoring.points(correct: true, secondsTaken: 999, budget: 20, streak: 1) == Scoring.base)
    }

    @Test func halfTheBudgetEarnsHalfTheSpeedBonus() {
        #expect(Scoring.points(correct: true, secondsTaken: 10, budget: 20, streak: 1)
                == Scoring.base + Scoring.maxSpeedBonus / 2)
    }

    /// Streaks 0 and 1 are both "no multiplier yet" — the bonus starts at the SECOND
    /// consecutive correct answer, so a first correct answer is never inflated.
    @Test func firstCorrectAnswerHasNoStreakMultiplier() {
        let atZero = Scoring.points(correct: true, secondsTaken: 20, budget: 20, streak: 0)
        let atOne  = Scoring.points(correct: true, secondsTaken: 20, budget: 20, streak: 1)
        #expect(atZero == Scoring.base)
        #expect(atOne == Scoring.base)
    }

    @Test func streakMultiplierGrowsTenPercentPerConsecutiveCorrect() {
        // streak 3 -> 1 + (3-1) * 0.1 = 1.2
        #expect(Scoring.points(correct: true, secondsTaken: 20, budget: 20, streak: 3) == 120)
    }

    /// The cap is the point: past it a longer streak must not keep paying more.
    @Test func streakMultiplierIsCapped() {
        let atCap = Scoring.points(correct: true, secondsTaken: 20, budget: 20, streak: 11)
        let wayPastCap = Scoring.points(correct: true, secondsTaken: 20, budget: 20, streak: 500)
        #expect(atCap == Int(Double(Scoring.base) * Scoring.maxStreakMultiplier))
        #expect(atCap == wayPastCap)
    }

    /// A zero budget would divide by zero; the guard keeps it finite.
    @Test func zeroBudgetDoesNotBlowUp() {
        let p = Scoring.points(correct: true, secondsTaken: 1, budget: 0, streak: 1)
        #expect(p >= 0)
    }

    @Test func scoreIsMonotonicInSpeed() {
        var previous = Int.max
        for taken in stride(from: 0.0, through: 20.0, by: 2.0) {
            let p = Scoring.points(correct: true, secondsTaken: taken, budget: 20, streak: 1)
            #expect(p <= previous)
            previous = p
        }
    }
}
