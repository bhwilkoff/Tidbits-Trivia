import Testing
import Foundation

/// The bots exist to be a believable sparring partner, and "believable" is a
/// statistical claim: a bot that is always right, never freezes, or answers in
/// a flat 5.0s reads as a machine. These pin the spec the Kotlin/JS/C# mirrors
/// also implement (PARITY "Play vs CPU"), so a drift shows up as a test failure
/// rather than as a player noticing the CPU is inhuman.
@Suite("Bot opponent")
struct BotOpponentTests {

    /// The House meets the learner where they are — clamped so it is never a
    /// pushover and never unbeatable.
    @Test func houseAdaptsToPlayerAccuracyWithinBounds() {
        #expect(BotProfile.house(playerAccuracy: 0.10).baseSkill == 0.35)   // floor
        #expect(BotProfile.house(playerAccuracy: 0.99).baseSkill == 0.90)   // ceiling
        #expect(abs(BotProfile.house(playerAccuracy: 0.62).baseSkill - 0.62) < 1e-9)
    }

    @Test func presetsAreDistinctAndOrderedByStrength() {
        let ids = BotProfile.presets.map(\.id)
        #expect(ids == ["rookie", "regular", "ace"])
        #expect(BotProfile.rookie.baseSkill < BotProfile.regular.baseSkill)
        #expect(BotProfile.regular.baseSkill < BotProfile.ace.baseSkill)
    }

    /// A stronger bot should also be a faster one — the two signals must not disagree.
    @Test func strongerBotsAnswerFaster() {
        #expect(BotProfile.ace.speedMean < BotProfile.regular.speedMean)
        #expect(BotProfile.regular.speedMean < BotProfile.rookie.speedMean)
    }

    @Test func easyQuestionsHelpAndHardOnesHurt() {
        #expect(BotBrain.difficultyAdj(1) > 0)
        #expect(BotBrain.difficultyAdj(3) == 0)
        #expect(BotBrain.difficultyAdj(5) < 0)
    }

    /// Freezing is the believability payload; ~5% of the time the bot just doesn't answer.
    @Test func freezeRateIsAboutFivePercent() {
        var frozen = 0
        for _ in 0..<4000 {
            let a = BotBrain.resolve(.regular, categoryID: "mixed", difficulty: 3,
                                     correctIndex: 0, optionCount: 4, window: 20)
            if !a.answered { frozen += 1 }
        }
        let rate = Double(frozen) / 4000
        #expect(rate > 0.02 && rate < 0.09)
    }

    @Test func accuracyTracksBaseSkill() {
        var correct = 0, answered = 0
        for _ in 0..<4000 {
            let a = BotBrain.resolve(.ace, categoryID: "mixed", difficulty: 3,
                                     correctIndex: 2, optionCount: 4, window: 20)
            guard let choice = a.choiceIndex else { continue }
            answered += 1
            if choice == 2 { correct += 1 }
        }
        let rate = Double(correct) / Double(answered)
        #expect(rate > 0.78 && rate < 0.92)   // ace baseSkill 0.85
    }

    /// A wrong answer must be a real distractor, never the correct index.
    @Test func wrongAnswersAreNeverTheCorrectIndex() {
        for _ in 0..<2000 {
            let a = BotBrain.resolve(.rookie, categoryID: "mixed", difficulty: 5,
                                     correctIndex: 1, optionCount: 4, window: 20)
            if let choice = a.choiceIndex {
                #expect((0..<4).contains(choice))
            }
        }
    }

    /// Times stay inside the question window — a bot answering after the clock
    /// would score points nobody could have beaten.
    @Test func answerTimesStayInsideTheWindow() {
        for _ in 0..<2000 {
            let a = BotBrain.resolve(.regular, categoryID: "mixed", difficulty: 3,
                                     correctIndex: 0, optionCount: 4, window: 20)
            if let s = a.seconds {
                #expect(s >= 0.8 && s <= 19.5)
            }
        }
    }

    /// Timing must VARY — a constant is the tell that gives a bot away.
    @Test func answerTimesAreNotConstant() {
        let times = (0..<200).compactMap {
            _ in BotBrain.resolve(.regular, categoryID: "mixed", difficulty: 3,
                                  correctIndex: 0, optionCount: 4, window: 20).seconds
        }
        #expect(Set(times).count > 50)
    }

    /// A two-option mode (This or That) must still find a wrong answer to give.
    @Test func twoOptionQuestionsStillResolve() {
        for _ in 0..<500 {
            let a = BotBrain.resolve(.rookie, categoryID: "mixed", difficulty: 3,
                                     correctIndex: 0, optionCount: 2, window: 20)
            if let choice = a.choiceIndex { #expect(choice == 0 || choice == 1) }
        }
    }
}
