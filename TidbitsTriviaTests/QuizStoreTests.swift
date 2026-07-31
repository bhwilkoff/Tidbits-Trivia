import Foundation
import SwiftData
import Testing
@testable import TidbitsTriviaTests

/// Local persistence is the source of truth for a player's own quizzes — they must
/// work offline and before sign-in (docs/QUIZ-CONTRACT.md §4). These run against the
/// REAL container schema, so a model that wouldn't migrate on a device fails here.
@MainActor
@Suite("Quiz store")
struct QuizStoreTests {

    private func quiz(_ id: String, title: String = "Jazz Legends",
                      questions: Int = 5, at: Date = Date(timeIntervalSince1970: 1_753_900_000)) -> SavedQuiz {
        SavedQuiz.from(questions: (0..<questions).map { TestStore.question("src:desc:Q\($0)") },
                       topic: "Jazz", title: title, creatorID: "uid-1", creatorName: "Ben",
                       id: id, createdAt: at)
    }

    @Test func savingThenLoadingReturnsAnIdenticalQuiz() throws {
        let ctx = try TestStore.context()
        let original = quiz("aaaaaaaaaa")
        #expect(QuizStore.save(original, in: ctx))
        let loaded = try #require(QuizStore.quiz(id: "aaaaaaaaaa", in: ctx))
        #expect(loaded.id == original.id)
        #expect(loaded.title == original.title)
        #expect(loaded.topic == original.topic)
        #expect(loaded.entries == original.entries)
    }

    /// Saving the same quiz twice is normal (replay, then save again). It must
    /// update in place rather than growing a second copy in the player's list.
    @Test func savingTheSameQuizTwiceUpdatesRatherThanDuplicating() throws {
        let ctx = try TestStore.context()
        QuizStore.save(quiz("aaaaaaaaaa", title: "First"), in: ctx)
        QuizStore.save(quiz("aaaaaaaaaa", title: "Second"), in: ctx)
        #expect(QuizStore.count(in: ctx) == 1)
        #expect(QuizStore.quiz(id: "aaaaaaaaaa", in: ctx)?.title == "Second")
    }

    /// A quiz you just made should be at the top of your list, not the bottom.
    @Test func listingIsNewestFirst() throws {
        let ctx = try TestStore.context()
        let old = Date(timeIntervalSince1970: 1_000_000)
        let new = Date(timeIntervalSince1970: 2_000_000)
        QuizStore.save(quiz("aaaaaaaaaa", title: "Older", at: old), in: ctx)
        QuizStore.save(quiz("bbbbbbbbbb", title: "Newer", at: new), in: ctx)
        #expect(QuizStore.all(in: ctx).map(\.title) == ["Newer", "Older"])
    }

    @Test func deletingRemovesOnlyThatQuiz() throws {
        let ctx = try TestStore.context()
        QuizStore.save(quiz("aaaaaaaaaa"), in: ctx)
        QuizStore.save(quiz("bbbbbbbbbb"), in: ctx)
        QuizStore.delete(id: "aaaaaaaaaa", in: ctx)
        #expect(QuizStore.count(in: ctx) == 1)
        #expect(QuizStore.quiz(id: "aaaaaaaaaa", in: ctx) == nil)
        #expect(QuizStore.quiz(id: "bbbbbbbbbb", in: ctx) != nil)
    }

    @Test func deletingSomethingThatIsNotThereIsHarmless() throws {
        let ctx = try TestStore.context()
        QuizStore.save(quiz("aaaaaaaaaa"), in: ctx)
        QuizStore.delete(id: "zzzzzzzzzz", in: ctx)
        #expect(QuizStore.count(in: ctx) == 1)
    }

    /// Play counts are LOCAL metadata, not part of the quiz — replaying must not
    /// rewrite the payload, or the contract's "created or deleted, never edited in
    /// place" merge guard stops holding.
    @Test func playingDoesNotRewriteTheQuizPayload() throws {
        let ctx = try TestStore.context()
        QuizStore.save(quiz("aaaaaaaaaa"), in: ctx)
        let before = try #require(QuizStore.record(id: "aaaaaaaaaa", in: ctx)).wireJSON
        QuizStore.markPlayed(id: "aaaaaaaaaa", at: Date(timeIntervalSince1970: 9_000_000), in: ctx)
        QuizStore.markPlayed(id: "aaaaaaaaaa", at: Date(timeIntervalSince1970: 9_100_000), in: ctx)
        let r = try #require(QuizStore.record(id: "aaaaaaaaaa", in: ctx))
        #expect(r.playCount == 2)
        #expect(r.lastPlayedAt == Date(timeIntervalSince1970: 9_100_000))
        #expect(r.wireJSON == before)
    }

    @Test func aNewQuizHasNeverBeenPlayedOrShared() throws {
        let ctx = try TestStore.context()
        QuizStore.save(quiz("aaaaaaaaaa"), in: ctx)
        let r = try #require(QuizStore.record(id: "aaaaaaaaaa", in: ctx))
        #expect(r.playCount == 0)
        #expect(r.lastPlayedAt == nil)
        #expect(r.isShared == false)
        #expect(r.questionCount == 5)
    }

    /// Renaming is the ONLY post-creation edit. The questions stay fixed, so a quiz
    /// someone else already has can never change under them.
    @Test func renamingChangesTheTitleButNotTheQuestions() throws {
        let ctx = try TestStore.context()
        QuizStore.save(quiz("aaaaaaaaaa"), in: ctx)
        let before = try #require(QuizStore.quiz(id: "aaaaaaaaaa", in: ctx)).entries
        QuizStore.rename(id: "aaaaaaaaaa", to: "  Bebop Deep Cuts  ", in: ctx)
        let after = try #require(QuizStore.quiz(id: "aaaaaaaaaa", in: ctx))
        #expect(after.title == "Bebop Deep Cuts")
        #expect(after.entries == before)
        #expect(QuizStore.record(id: "aaaaaaaaaa", in: ctx)?.title == "Bebop Deep Cuts")
    }

    @Test func renamingToNothingFallsBackRatherThanBlanking() throws {
        let ctx = try TestStore.context()
        QuizStore.save(quiz("aaaaaaaaaa"), in: ctx)
        QuizStore.rename(id: "aaaaaaaaaa", to: "   ", in: ctx)
        #expect(QuizStore.quiz(id: "aaaaaaaaaa", in: ctx)?.title == "Untitled quiz")
    }

    @Test func recentIsCappedAndNewestFirst() throws {
        let ctx = try TestStore.context()
        for (i, letter) in "abcdef".enumerated() {
            QuizStore.save(quiz(String(repeating: letter, count: 10), title: "Q\(i)",
                                at: Date(timeIntervalSince1970: Double(1_000_000 + i * 1000))), in: ctx)
        }
        let recent = QuizStore.recent(in: ctx, limit: 3)
        #expect(recent.count == 3)
        #expect(recent.map(\.title) == ["Q5", "Q4", "Q3"])
    }

    /// An empty shelf is a real state, not an error — the list must survive it.
    @Test func anEmptyStoreListsNothingRatherThanFailing() throws {
        let ctx = try TestStore.context()
        #expect(QuizStore.all(in: ctx).isEmpty)
        #expect(QuizStore.count(in: ctx) == 0)
        #expect(QuizStore.quiz(id: "nope", in: ctx) == nil)
    }
}
