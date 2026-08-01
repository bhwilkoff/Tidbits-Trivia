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

/// The relevance FLOOR, measured by play-testing the 984 most-viewed Wikipedia
/// articles through the shipped assembly on the iOS simulator. 49.8% of every
/// question Create served was about something other than what the player typed.
/// Each test below is one of the measured failures. Mirrored by Kotlin, C# and JS.
@Suite("Create topic drift")
struct CreateTopicDriftTests {

    private func tier(_ title: String, prompt: String = "", tags: [String] = [],
                      topic: String, guardNames: Bool = false) -> Int? {
        CorpusDatabase.tier(title: title, prompt: prompt, tags: tags,
                            tokens: CorpusDatabase.topicTokens(topic),
                            phrase: CorpusDatabase.topicPhrase(topic),
                            guardNames: guardNames,
                            requirePhrase: CorpusDatabase.phraseIsRequired(topic))
    }

    /// The single most common failure: the typed word inside a longer word.
    @Test func aWordInsideALongerWordIsNotAMatch() {
        #expect(CorpusDatabase.containsWord("art deco", "art"))
        #expect(!CorpusDatabase.containsWord("mozart", "art"))
        #expect(!CorpusDatabase.containsWord("hansel and gretel", "ansel"))
        #expect(!CorpusDatabase.containsWord("spokane washington", "kane"))
        #expect(!CorpusDatabase.containsWord("indianapolis", "india"))
    }

    /// "Harry Kane" must not return Spokane, Butane or Harry Potter. Nothing in
    /// the corpus is about him, and the honest answer is nothing.
    @Test func aTopicTheCorpusDoesNotKnowIsRejectedRatherThanApproximated() {
        #expect(tier("Spokane, Washington", topic: "Harry Kane") == nil)
        #expect(tier("Butane", topic: "Harry Kane") == nil)
        #expect(tier("Harry Potter and the Cursed Child", topic: "Harry Kane") == nil)
    }

    /// The owner's example. The guard applies only when the typed word is itself
    /// a subject here — "Denver" is a place, so "Bob Denver" is someone else.
    @Test func aDifferentPersonWhoseNameContainsThePlaceIsRejected() {
        #expect(tier("Bob Denver", topic: "Denver", guardNames: true) == nil)
        #expect(tier("Denver Pyle", topic: "Denver", guardNames: true) == nil)
        #expect(tier("Denver International Airport", topic: "Denver", guardNames: true) != nil)
    }

    /// …and only then. "Potter" is not a subject in its own right, so a player
    /// typing it means Harry Potter and must not be left with nothing.
    @Test func theSurnameGuardDoesNotFireWhenTheWordIsNotItsOwnSubject() {
        #expect(tier("Harry Potter", topic: "Potter", guardNames: false) != nil)
    }

    /// No Wikipedia category admits a row on its own any more — not the incidental
    /// kind ("Actresses from Denver", which put a Kristin Cavallari birth-year
    /// question in a Denver quiz), and not the agentive kind either, which was the
    /// last measurable source of drift.
    @Test func noCategoryTagAdmitsARowOnItsOwn() {
        #expect(tier("Thriller (album)", tags: ["Albums produced by Michael Jackson"],
                     topic: "Michael Jackson") == nil)
        #expect(tier("Kristin Cavallari", tags: ["Actresses from Denver"],
                     topic: "Denver") == nil)
        #expect(tier("Neil Sedaka", tags: ["Abraham Lincoln High School (Brooklyn) alumni"],
                     topic: "Abraham Lincoln") == nil)
    }

    /// A tag connection is real but INVISIBLE — the question never says so — so it
    /// no longer admits a row at all. It was the last measurable source of drift:
    /// "Rod Stewart" produced Britt Ekland's height off a "Partners of Rod
    /// Stewart" tag, and "Vajiralongkorn" produced seven questions about his wives
    /// and daughters, none of which name him.
    @Test func anAgentiveTagAloneNoLongerAdmitsARow() {
        #expect(tier("Bad (album)", tags: ["Albums produced by Michael Jackson"],
                     topic: "Michael Jackson") == nil)
        #expect(tier("Britt Ekland", tags: ["Partners of Rod Stewart"],
                     topic: "Rod Stewart") == nil)
    }

    /// …while the same album still comes through when the question NAMES him.
    @Test func theSameRowSurvivesWhenThePromptNamesTheTopic() {
        #expect(tier("Bad (album)", prompt: "Michael Jackson's seventh studio album",
                     topic: "Michael Jackson") == 0)
    }

    /// A Wikipedia disambiguator is not part of what the player means.
    @Test func aDisambiguatorIsNotATopicWord() {
        #expect(CorpusDatabase.topicPhrase("Masters of the Universe (2026 film)")
                == "masters of the universe")
        #expect(!CorpusDatabase.topicTokens("Backrooms (film)").contains("film"))
    }

    /// The phrase keeps its stopwords and its order — the significant-token list
    /// can never reconstruct "masters of the universe".
    @Test func thePhraseSurvivesStopwordRemoval() {
        #expect(CorpusDatabase.topicPhrase("World War II") == "world war ii")
        #expect(tier("Masters of the Universe", topic: "Masters of the Universe (2026 film)") == 3)
    }

    /// A regnal numeral is short but not insignificant. "George VI" reduced to the
    /// single token `george` and returned George Martin, George Mallory, George
    /// Eliot and Paul George; "O. J. Simpson" reduced to `simpson` and returned
    /// Homer, Bart and Marge. Found by sweeping topics 301–984, which the first
    /// 300 never contained.
    @Test func aRegnalNumeralOrInitialForcesAPhraseMatch() {
        #expect(CorpusDatabase.phraseIsRequired("George VI"))
        #expect(CorpusDatabase.phraseIsRequired("O. J. Simpson"))
        #expect(tier("George Martin", topic: "George VI") == nil)
        #expect(tier("Paul George", topic: "George VI") == nil)
        #expect(tier("Homer Simpson", topic: "O. J. Simpson") == nil)
        #expect(tier("George VI", topic: "George VI") == 3)
        #expect(tier("O. J. Simpson", topic: "O. J. Simpson") == 3)
    }

    /// …and it must NOT fire when the dropped word is a mere stopword, or "The
    /// Beatles" would stop matching every Beatles question that isn't titled with
    /// the full phrase.
    @Test func aDroppedStopwordDoesNotForceAPhraseMatch() {
        #expect(!CorpusDatabase.phraseIsRequired("The Beatles"))
        #expect(!CorpusDatabase.phraseIsRequired("Denver"))
        #expect(tier("Abbey Road", prompt: "the beatles recorded it here",
                     topic: "The Beatles") != nil)
    }

    /// A prompt occurrence inside a DIFFERENT proper name is not a match. Typing
    /// "Denver" matched "Written by Bill Danoff, Taffy Nivert and John Denver";
    /// typing "Michael Jackson" matched a Glenda Jackson biopic and a film
    /// starring Samuel L. Jackson.
    @Test func aNameInsideSomeoneElsesNameIsNotAMatch() {
        let denver = CorpusDatabase.topicTokens("Denver")
        #expect(!CorpusDatabase.promptHasWord(
            "Written by Bill Danoff and John Denver", "denver", topic: denver))
        #expect(CorpusDatabase.promptHasWord(
            "before Denver drafted him in 2024", "denver", topic: denver))
        #expect(CorpusDatabase.promptHasWord(
            "this Denver-based budget carrier", "denver", topic: denver))
        let mj = CorpusDatabase.topicTokens("Michael Jackson")
        #expect(!CorpusDatabase.promptHasWord(
            "marked Glenda Jackson's final role", "jackson", topic: mj))
        #expect(CorpusDatabase.promptHasWord(
            "Michael Jackson's seventh studio album", "jackson", topic: mj))
    }

    /// The second half of the rule: a capitalised predecessor the player TYPED is
    /// fine, or "John Lennon and Paul McCartney" would stop matching McCartney.
    @Test func aCapitalisedPredecessorTheUserTypedIsStillAMatch() {
        #expect(CorpusDatabase.promptHasWord(
            "Written by John Lennon and Paul McCartney", "mccartney",
            topic: CorpusDatabase.topicTokens("Paul McCartney")))
    }

    /// Identity ignores the disambiguator. The corpus titles the rapper "Drake
    /// (musician)", so nothing was titled plainly "Drake", the topic was never its
    /// own subject, the different-person guard never armed — and typing "Drake"
    /// returned Nick Drake, Tim Drake and Drake & Josh.
    @Test func aDisambiguatedTitleStillCountsAsTheSubject() {
        #expect(tier("Drake (musician)", topic: "Drake") == 3)
        #expect(tier("Nick Drake", topic: "Drake", guardNames: true) == nil)
        #expect(tier("Drake & Josh", topic: "Drake", guardNames: true) == nil)
    }

    /// …while CONTAINMENT still reads the full title, where the parenthetical
    /// carries real meaning.
    @Test func containmentStillSeesTheDisambiguator() {
        #expect(tier("Dangerous (Michael Jackson album)", topic: "Michael Jackson") == 2)
    }

    /// A row whose title is exactly the topic outranks one that merely contains it.
    @Test func theSubjectItselfOutranksAContainingTitle() {
        #expect(tier("Denver", topic: "Denver") == 3)
        #expect(tier("Denver International Airport", topic: "Denver") == 2)
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
