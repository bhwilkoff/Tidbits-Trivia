import Foundation
import Testing
@testable import TidbitsTriviaTests

/// A saved quiz is the first user-authored object in Tidbits and it is shareable,
/// so it outlives the app version that wrote it and must decode identically on six
/// platforms. These pin docs/QUIZ-CONTRACT.md; the same cases exist in the Windows
/// suite and the shared fixture in tools/quiz-wire/golden/.
@Suite("Saved quiz")
struct SavedQuizTests {

    private func q(_ id: String, template: String = "src") -> Question {
        Question(id: id, prompt: "prompt \(id)", options: ["a", "b", "c", "d"],
                 correctIndex: 1, categoryID: "arts", difficulty: 3,
                 explanation: "why \(id)", sourceTitle: "title \(id)",
                 sourceURL: URL(string: "https://example.org/\(id)"), templateID: template)
    }

    private func sample() -> SavedQuiz {
        SavedQuiz.from(questions: [q("src:desc:Q1"), q("live:abc", template: "live"), q("pic:0007")],
                       topic: "Jazz", title: "Jazz Legends", creatorID: "uid-1",
                       creatorName: "Ben", id: "k7m3qp9x2r",
                       createdAt: Date(timeIntervalSince1970: 1_753_900_000))
    }

    // MARK: Refs vs inline

    /// The core of the contract: corpus questions are REFS (tiny, portable), and
    /// only a live-generated question travels inline.
    @Test func corpusQuestionsBecomeRefsAndLiveOnesInline() {
        let quiz = sample()
        #expect(quiz.entries.count == 3)
        if case .ref(let r) = quiz.entries[0] { #expect(r == "src:desc:Q1") } else { Issue.record("entry 0 should be a ref") }
        if case .inline = quiz.entries[1] {} else { Issue.record("entry 1 should be inline (live-generated)") }
        if case .ref(let r) = quiz.entries[2] { #expect(r == "pic:0007") } else { Issue.record("entry 2 should be a ref") }
    }

    /// A quiz must stay small enough to sync and share for free — refs are what
    /// make that true. A 20-question quiz has to fit comfortably under 1KB.
    @Test func aRefOnlyQuizIsUnderAKilobyte() {
        let quiz = SavedQuiz.from(questions: (0..<20).map { q("src:desc:Q\($0)") },
                                  topic: "Space", creatorID: "uid-1", creatorName: "Ben")
        #expect(quiz.jsonData()!.count < 1024)
    }

    // MARK: Wire round trip

    @Test func wireRoundTripsEveryField() throws {
        let original = sample()
        let data = try #require(original.jsonData())
        let decoded = try #require(SavedQuiz(jsonData: data))
        #expect(decoded.id == original.id)
        #expect(decoded.title == original.title)
        #expect(decoded.topic == original.topic)
        #expect(decoded.creatorID == original.creatorID)
        #expect(decoded.creatorName == original.creatorName)
        #expect(decoded.mode == original.mode)
        #expect(decoded.entries == original.entries)
        #expect(Int(decoded.createdAt.timeIntervalSince1970) == Int(original.createdAt.timeIntervalSince1970))
    }

    /// Two devices writing the same quiz must produce identical bytes — that is
    /// what makes the "created or deleted, never edited in place" merge guard
    /// checkable rather than aspirational.
    @Test func encodingIsDeterministic() throws {
        let quiz = sample()
        #expect(quiz.jsonData() == quiz.jsonData())
    }

    /// These names ride in share URLs and stored records. Renaming one silently
    /// breaks every quiz already in the wild.
    @Test func wireKeysAreExactlyTheContract() {
        let keys = Set(sample().wire().keys)
        #expect(keys == ["v", "id", "t", "tp", "by", "bn", "at", "m", "qs"])
        #expect(sample().wire()["v"] as? Int == 1)
    }

    // MARK: Leniency — these objects outlive the app version that wrote them

    @Test func unknownKeysAreIgnoredRatherThanFailing() {
        var wire = sample().wire()
        wire["somethingFromV2"] = ["nested": true]
        let decoded = SavedQuiz(wire: wire)
        #expect(decoded != nil)
        #expect(decoded?.entries.count == 3)
    }

    @Test func aMalformedEntryIsSkippedNotFatal() {
        var wire = sample().wire()
        wire["qs"] = ["src:desc:Q1", 42, ["too", "short"], "pic:0007"]
        let decoded = SavedQuiz(wire: wire)
        #expect(decoded?.entries.count == 2)
    }

    @Test func aQuizWithNoIdOrQuestionsIsRejected() {
        #expect(SavedQuiz(wire: ["by": "uid", "qs": ["a"]]) == nil)
        #expect(SavedQuiz(wire: ["id": "abc", "by": "uid"]) == nil)
    }

    // MARK: Resolving — the degrade path

    /// Refs go missing legitimately (older build, retired row). The quiz still
    /// plays and reports the shortfall; it never substitutes a different question.
    @Test func missingRefsAreReportedNotSubstituted() {
        let quiz = SavedQuiz.from(questions: (0..<8).map { q("src:desc:Q\($0)") },
                                  topic: "Space", creatorID: "uid-1", creatorName: "Ben")
        let known = Set(["src:desc:Q0", "src:desc:Q1", "src:desc:Q2", "src:desc:Q3", "src:desc:Q4"])
        let r = quiz.resolve { known.contains($0) ? self.q($0) : nil }
        #expect(r.questions.count == 5)
        #expect(r.missing == 3)
        #expect(r.isPlayable)
        #expect(!r.isComplete)
    }

    @Test func tooFewResolvedRefsIsNotPlayable() {
        let quiz = SavedQuiz.from(questions: (0..<8).map { q("src:desc:Q\($0)") },
                                  topic: "Space", creatorID: "uid-1", creatorName: "Ben")
        let r = quiz.resolve { $0 == "src:desc:Q0" ? self.q($0) : nil }
        #expect(r.questions.count == 1)
        #expect(!r.isPlayable)
    }

    /// An inline question needs no lookup at all — that is the point of carrying it.
    @Test func inlineQuestionsSurviveWithoutTheCorpus() {
        let quiz = sample()
        let r = quiz.resolve { _ in nil }
        #expect(r.questions.count == 1)
        #expect(r.questions[0].prompt == "prompt live:abc")
        #expect(r.questions[0].options == ["a", "b", "c", "d"])
        #expect(r.missing == 2)
    }

    @Test func aFullyResolvableQuizIsComplete() {
        let quiz = SavedQuiz.from(questions: (0..<5).map { q("src:desc:Q\($0)") },
                                  topic: "Space", creatorID: "uid-1", creatorName: "Ben")
        let r = quiz.resolve { self.q($0) }
        #expect(r.isComplete)
        #expect(r.isPlayable)
        #expect(r.questions.count == 5)
    }

    // MARK: IDs

    /// The alphabet drops 0/o, 1/l/i and u so an ID read aloud in a pub or typed
    /// off a projector is unambiguous.
    @Test func idsAvoidAmbiguousCharacters() {
        var rng = SeededRNG(seed: 99)
        for _ in 0..<200 {
            let id = SavedQuiz.makeID(using: &rng)
            #expect(id.count == 10)
            #expect(id.allSatisfy { SavedQuiz.idAlphabet.contains($0) })
            #expect(!id.contains(where: { "01loiu".contains($0) }))
        }
    }

    /// Random, never derived from content: two people who both make a "Jazz" quiz
    /// must get different IDs, and an ID must not leak what is inside it.
    @Test func idsAreRandomNotDerivedFromContent() {
        var rng = SeededRNG(seed: 7)
        let ids = (0..<500).map { _ in SavedQuiz.makeID(using: &rng) }
        #expect(Set(ids).count == ids.count)
    }

    // MARK: Titles

    @Test func titlesAreTrimmedCappedAndNeverEmpty() {
        #expect(SavedQuiz.cleanTitle("  Jazz  ") == "Jazz")
        #expect(SavedQuiz.cleanTitle("") == "Untitled quiz")
        #expect(SavedQuiz.cleanTitle("   ") == "Untitled quiz")
        #expect(SavedQuiz.cleanTitle(String(repeating: "x", count: 200)).count == 60)
    }

    @Test func aQuizWithNoTitleFallsBackToItsTopic() {
        let quiz = SavedQuiz.from(questions: [q("src:desc:Q1")], topic: "Volcanoes",
                                  creatorID: "uid-1", creatorName: "Ben")
        #expect(quiz.title == "Volcanoes")
    }
}

/// The shared wire golden. Every stack decodes `tools/quiz-wire/golden/quiz-v1.json`
/// and must agree — a drift here is a share link that opens a different quiz on
/// another platform. Read from the repo (not a copy) via `#filePath`, so there is
/// exactly one fixture and no chance of a stale duplicate passing.
@Suite("Saved quiz wire golden")
struct SavedQuizGoldenTests {

    private static var fixtureURL: URL {
        URL(fileURLWithPath: #filePath)                 // TidbitsTriviaTests/SavedQuizTests.swift
            .deletingLastPathComponent()                // TidbitsTriviaTests/
            .deletingLastPathComponent()                // repo root
            .appendingPathComponent("tools/quiz-wire/golden/quiz-v1.json")
    }

    @Test func theSharedFixtureDecodesToTheExpectedQuiz() throws {
        let data = try Data(contentsOf: Self.fixtureURL)
        let quiz = try #require(SavedQuiz(jsonData: data))
        #expect(quiz.id == "k7m3qp9x2r")
        #expect(quiz.title == "Jazz Legends")
        #expect(quiz.topic == "Jazz")
        #expect(quiz.creatorID == "uid-1")
        #expect(quiz.creatorName == "Ben")
        #expect(quiz.mode == "mix")
        #expect(Int(quiz.createdAt.timeIntervalSince1970 * 1000) == 1_753_900_000_000)
        #expect(quiz.entries.count == 3)
        #expect(quiz.entries[0] == .ref("src:desc:Q1"))
        #expect(quiz.entries[2] == .ref("pic:0007"))
        guard case .inline(let inline) = quiz.entries[1] else {
            Issue.record("entry 1 must be inline"); return
        }
        #expect(inline.prompt == "Which Texan city did the group form in?")
        #expect(inline.options == ["Houston", "Dallas", "Austin", "El Paso"])
        #expect(inline.correctIndex == 0)
    }

    /// Re-encoding must reproduce the fixture byte for byte. Two devices saving the
    /// same quiz produce identical bytes, which is what makes the "created or
    /// deleted, never edited in place" merge guard checkable.
    @Test func reEncodingReproducesTheFixtureExactly() throws {
        let data = try Data(contentsOf: Self.fixtureURL)
        let quiz = try #require(SavedQuiz(jsonData: data))
        let reEncoded = try #require(quiz.jsonData())
        let original = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(String(decoding: reEncoded, as: UTF8.self) == original)
    }

    /// The inline entry carries an apostrophe and a URL precisely so escaping is
    /// covered — a quiz about "Destiny's Child" must survive the round trip.
    @Test func escapingSurvivesTheRoundTrip() throws {
        let data = try Data(contentsOf: Self.fixtureURL)
        let quiz = try #require(SavedQuiz(jsonData: data))
        guard case .inline(let inline) = quiz.entries[1] else { return }
        #expect(inline.sourceTitle == "Destiny's Child")
        #expect(inline.sourceURL.contains("Destiny's_Child"))
    }
}

/// The bundled sets share the corpus `src:` namespace — 166 of 200 sampled Picture
/// ID rows have an ID that ALSO exists in the corpus as a different question shape.
/// A bare ref is therefore ambiguous, and resolving it corpus-first silently served
/// a text question in place of a saved picture question. Found by replaying a quiz
/// on the simulator and watching question 1 lose its photograph.
@Suite("Set-qualified refs")
struct QuizSetRefTests {

    private func corpusQ(_ id: String) -> Question {
        Question(id: id, prompt: "text form of \(id)", options: ["a", "b", "c", "d"],
                 correctIndex: 0, categoryID: "music", difficulty: 3, explanation: "e",
                 sourceTitle: "t", sourceURL: nil, templateID: "src")
    }

    private func pictureQ(_ id: String) -> Question {
        var q = corpusQ(id)
        q = Question(id: id, prompt: "Who is this?", options: ["a", "b", "c", "d"],
                     correctIndex: 0, categoryID: "music", difficulty: 3, explanation: "e",
                     sourceTitle: "t", sourceURL: nil, templateID: "src",
                     tags: [], imageURL: URL(string: "https://example.org/p.jpg"))
        return q
    }

    /// A question's SHAPE identifies its set, so provenance survives without being
    /// threaded through every call site.
    @Test func aQuestionsShapeIdentifiesItsBundledSet() {
        #expect(pictureQ("src:describe:X").bundledSetName == "picture")
        #expect(corpusQ("src:describe:X").bundledSetName == nil)
    }

    @Test func aBundledQuestionIsSavedAsASetRefNotABareRef() {
        let quiz = SavedQuiz.from(questions: [pictureQ("src:describe:Tito"), corpusQ("src:desc:Q1")],
                                  topic: "Jazz", creatorID: "u", creatorName: "B")
        #expect(quiz.entries[0] == .setRef(set: "picture", id: "src:describe:Tito"))
        #expect(quiz.entries[1] == .ref("src:desc:Q1"))
    }

    /// The regression itself: the corpus holds a DIFFERENT question under the same
    /// ID, and it must never be served in the bundled question's place.
    @Test func aSetRefNeverFallsBackToTheCollidingCorpusRow() {
        let id = "src:describe:Tito"
        let quiz = SavedQuiz.from(questions: [pictureQ(id)], topic: "Jazz",
                                  creatorID: "u", creatorName: "B")
        // Corpus has the id; the picture set does not. Being one short is CORRECT.
        let r = quiz.resolve(lookup: { _ in self.corpusQ(id) }, setLookup: { _, _ in nil })
        #expect(r.questions.isEmpty)
        #expect(r.missing == 1)
    }

    @Test func aSetRefResolvesFromItsOwnSet() {
        let id = "src:describe:Tito"
        let quiz = SavedQuiz.from(questions: [pictureQ(id)], topic: "Jazz",
                                  creatorID: "u", creatorName: "B")
        let r = quiz.resolve(lookup: { _ in self.corpusQ(id) },
                             setLookup: { set, qid in set == "picture" ? self.pictureQ(qid) : nil })
        #expect(r.questions.count == 1)
        #expect(r.questions[0].prompt == "Who is this?")
        #expect(r.questions[0].imageURL != nil)
        #expect(r.isComplete)
    }

    @Test func setRefsRoundTripThroughTheWire() throws {
        let quiz = SavedQuiz.from(questions: [pictureQ("src:describe:Tito"), corpusQ("src:desc:Q1")],
                                  topic: "Jazz", creatorID: "u", creatorName: "B", id: "aaaaaaaaaa")
        let data = try #require(quiz.jsonData())
        let decoded = try #require(SavedQuiz(jsonData: data))
        #expect(decoded.entries == quiz.entries)
    }

    /// The bare-string form stays the common case, so a corpus-only quiz is still
    /// the compact thing the contract promises.
    @Test func corpusRefsRemainBareStringsOnTheWire() throws {
        let quiz = SavedQuiz.from(questions: [corpusQ("src:desc:Q1")], topic: "Jazz",
                                  creatorID: "u", creatorName: "B", id: "aaaaaaaaaa")
        let data = try #require(quiz.jsonData())
        let json = String(decoding: data, as: UTF8.self)
        #expect(json.contains("\"qs\":[\"src:desc:Q1\"]"))
    }
}
