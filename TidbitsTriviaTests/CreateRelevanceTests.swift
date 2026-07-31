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
