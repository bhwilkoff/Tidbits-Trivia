import Testing
@testable import TidbitsTriviaTests

/// Create's promise is "pick any subject and we build you a quiz about it".
/// `diversify` round-robins by CATEGORY, so before the matched-token tier existed
/// a one-word coincidence in an under-filled category got PROMOTED over a genuine
/// hit — typing "Marie Curie" led with "In what year was Marie de' Medici born?"
/// (measured: 15 real two-word matches, all science, against 211 one-word hits
/// across 7 categories). Mirrors windows/.../CreateRelevanceTest.cs.
@Suite("Create relevance")
struct CreateRelevanceTests {

    private func q(_ id: String, _ category: String) -> Question {
        Question(id: id, prompt: "prompt \(id)",
                 options: ["zzz", "a", "b", "c"], correctIndex: 0,
                 categoryID: category, difficulty: 3, explanation: "why \(id)",
                 sourceTitle: "title \(id)", sourceURL: nil, templateID: "t")
    }

    /// The per-category cap must not throttle a genuinely single-domain result
    /// set — this is what turned a requested 8-question quiz into 4.
    @Test func diversifyFillsTheLimitEvenWhenEveryHitIsOneCategory() {
        let ranked = (0..<20).map { q("s\($0)", "science") }
        let got = CorpusDatabase.diversify(ranked, limit: 8)
        #expect(got.count == 8)
        #expect(Set(got.map(\.id)).count == 8)
    }

    /// With several categories available it still spreads — the anti-monopoly
    /// rule the top-up must not undo.
    @Test func diversifyStillSpreadsAcrossCategoriesWhenItCan() {
        var ranked: [Question] = []
        for cat in ["science", "history", "music"] {
            ranked.append(contentsOf: (0..<10).map { q("\(cat)\($0)", cat) })
        }
        let got = CorpusDatabase.diversify(ranked, limit: 9)
        #expect(got.count == 9)
        #expect(Set(got.map(\.categoryID)).count >= 3)
    }

    @Test func diversifyReturnsEverythingWhenThePoolIsSmallerThanTheLimit() {
        let got = CorpusDatabase.diversify([q("a", "science"), q("b", "history")], limit: 8)
        #expect(got.count == 2)
    }

    @Test func diversifyOfAnEmptyPoolIsEmpty() {
        #expect(CorpusDatabase.diversify([], limit: 8).isEmpty)
    }

    @Test func diversifyNeverDuplicatesAfterToppingUp() {
        var ranked = (0..<12).map { q("s\($0)", "science") }
        ranked.append(contentsOf: (0..<2).map { q("h\($0)", "history") })
        let got = CorpusDatabase.diversify(ranked, limit: 10)
        #expect(Set(got.map(\.id)).count == got.count)
    }
}

/// Diacritic folding is a CROSS-STACK contract: the corpus build writes a folded
/// `search_text` column, and Swift/Kotlin/C#/JS each fold at compare time. If any
/// one of them disagrees, the same topic returns different questions per platform.
/// Before this existed, "Beyonce" matched 0 of the 22 Beyoncé rows, "Bjork" 0 of 8,
/// "Dvorak" 0 of 10 — a whole class of subjects was invisible to Create.
@Suite("Diacritic folding")
struct FoldingTests {

    @Test func accentsAreStrippedAndCaseIsLowered() {
        #expect(CorpusDatabase.fold("Beyoncé") == "beyonce")
        #expect(CorpusDatabase.fold("Björk") == "bjork")
        #expect(CorpusDatabase.fold("Antonín Dvořák") == "antonin dvorak")
        #expect(CorpusDatabase.fold("Zürich") == "zurich")
        #expect(CorpusDatabase.fold("Chloë") == "chloe")
    }

    /// Folding must be idempotent and a no-op on plain ASCII — the 91% fast path
    /// the web reader relies on to avoid caching a second copy of the corpus.
    @Test func plainAsciiIsUnchangedApartFromCase() {
        #expect(CorpusDatabase.fold("The Beatles") == "the beatles")
        #expect(CorpusDatabase.fold(CorpusDatabase.fold("Beyoncé")) == "beyonce")
    }

    /// Both directions must work: the player may type the accent or omit it, and
    /// the corpus may carry it or not.
    @Test func foldingMatchesInEitherDirection() {
        #expect(CorpusDatabase.fold("Beyoncé").contains(CorpusDatabase.fold("beyonce")))
        #expect(CorpusDatabase.fold("BEYONCÉ") == CorpusDatabase.fold("beyoncé"))
    }
}
