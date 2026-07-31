import Testing
import SwiftData
@testable import TidbitsTriviaTests

/// Weak-Spot Arena's whole claim is "these are questions YOU missed" — a round
/// that quietly padded itself with questions the player never saw would break the
/// promise invisibly. Play-testing confirmed it redraws a real miss
/// (QA-SWEEP-LOG round 7); these pin the rule so it stays true.
@Suite("Weak-Spot Arena")
@MainActor
struct WeakSpotArenaTests {

    @Test func anEmptyHistoryProducesNoPreviewLine() throws {
        let ctx = try TestStore.context()
        #expect(WeakSpotArena.previewLine(in: ctx) == nil)
    }

    @Test func aRoundBuiltFromNoMissesIsEmptyRatherThanFabricated() throws {
        let ctx = try TestStore.context()
        let round = WeakSpotArena.build(in: ctx)
        #expect(round.questions.isEmpty)
    }

    @Test func recordedMissesBecomeArenaQuestions() throws {
        let ctx = try TestStore.context()
        for i in 1...6 { ctx.insert(MissedFact(question: TestStore.question("q\(i)"))) }
        let round = WeakSpotArena.build(in: ctx)
        #expect(!round.questions.isEmpty)
        #expect(round.questions.count <= WeakSpotArena.roundSize)
    }

    /// A resolved miss is learned — re-asking it forever would punish improvement.
    @Test func resolvedMissesAreNotDrawnAheadOfUnresolvedOnes() throws {
        let ctx = try TestStore.context()
        let stale = MissedFact(question: TestStore.question("resolved"))
        stale.resolved = true
        ctx.insert(stale)
        for i in 1...6 { ctx.insert(MissedFact(question: TestStore.question("open\(i)"))) }
        let round = WeakSpotArena.build(in: ctx)
        let ids = round.questions.map(\.id)
        #expect(!ids.isEmpty)
        if ids.contains("resolved") { #expect(ids.count > 1) }
    }

    @Test func aRoundNeverExceedsItsDeclaredSize() throws {
        let ctx = try TestStore.context()
        for i in 1...80 { ctx.insert(MissedFact(question: TestStore.question("q\(i)"))) }
        let round = WeakSpotArena.build(in: ctx)
        #expect(round.questions.count <= WeakSpotArena.roundSize)
    }

    @Test func questionsInARoundAreDistinct() throws {
        let ctx = try TestStore.context()
        for i in 1...40 { ctx.insert(MissedFact(question: TestStore.question("q\(i)"))) }
        let round = WeakSpotArena.build(in: ctx)
        #expect(Set(round.questions.map(\.id)).count == round.questions.count)
    }

    /// A MissedFact must be able to rebuild the full MCQ it came from, or the
    /// arena would have nothing to ask.
    @Test func missedFactsRoundTripBackIntoAQuestion() throws {
        let original = TestStore.question("rt")
        let rebuilt = MissedFact(question: original).question
        #expect(rebuilt?.id == original.id)
        #expect(rebuilt?.options == original.options)
        #expect(rebuilt?.correctIndex == original.correctIndex)
        #expect(rebuilt?.correctAnswer == original.correctAnswer)
    }
}
