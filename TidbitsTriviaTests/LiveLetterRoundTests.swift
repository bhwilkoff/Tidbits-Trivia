import Testing
import Foundation

/// G4 — the first-letter round. These pin the judgement calls a host would
/// otherwise have to explain to the room mid-night.
@Suite("Live first-letter rounds")
struct LiveLetterRoundTests {

    private func q(_ answer: String, id: String = "t1") -> Question {
        Question(id: id, prompt: "p", options: [answer, "x", "y", "z"], correctIndex: 0,
                 categoryID: "history", difficulty: 2, explanation: "",
                 sourceTitle: "", sourceURL: nil, templateID: "test")
    }

    @Test("a plain answer takes its own first letter")
    func plain() {
        #expect(LiveLetterRound.initial(of: "Budapest") == "B")
    }

    @Test("a leading article does not count — 'The Beatles' is a B")
    func article() {
        #expect(LiveLetterRound.initial(of: "The Beatles") == "B")
        #expect(LiveLetterRound.initial(of: "A Clockwork Orange") == "C")
        #expect(LiveLetterRound.initial(of: "An Inspector Calls") == "I")
    }

    @Test("an answer that is ONLY an article still resolves, rather than vanishing")
    func articleOnly() {
        #expect(LiveLetterRound.initial(of: "The") == "T")
    }

    @Test("diacritics fold — the host says E and the room writes E")
    func diacritics() {
        #expect(LiveLetterRound.initial(of: "Édith Piaf") == "E")
        #expect(LiveLetterRound.initial(of: "Ångström") == "A")
    }

    @Test("an answer with no letter belongs to no round")
    func noLetter() {
        #expect(LiveLetterRound.initial(of: "2001") == nil)
        #expect(LiveLetterRound.initial(of: "") == nil)
        #expect(LiveLetterRound.initial(of: "!!!") == nil)
    }

    @Test("punctuation before the first letter is skipped")
    func punctuation() {
        #expect(LiveLetterRound.initial(of: "'Round Midnight") == "R")
    }

    @Test("matching is case-insensitive on the requested letter")
    func caseInsensitive() {
        #expect(LiveLetterRound.matches(q("Berlin"), letter: "b"))
        #expect(LiveLetterRound.matches(q("Berlin"), letter: "B"))
    }

    @Test("violations name exactly the questions that break the theme")
    func violations() {
        let qs = [q("Berlin", id: "a"), q("Cairo", id: "b"), q("The Bahamas", id: "c")]
        let bad = LiveLetterRound.violations(in: qs, letter: "B")
        #expect(bad.map(\.id) == ["b"])
    }

    @Test("candidates respect the cap and keep pool order")
    func candidates() {
        let pool = [q("Berlin", id: "a"), q("Cairo", id: "b"),
                    q("Boston", id: "c"), q("Bogota", id: "d")]
        let got = LiveLetterRound.candidates(from: pool, letter: "B", limit: 2)
        #expect(got.map(\.id) == ["a", "c"])
    }

    @Test("a repeated ANSWER is not offered twice, even from different questions")
    func dedupe() {
        let pool = [q("Berlin", id: "a"), q("berlin", id: "b"), q("Boston", id: "c")]
        let got = LiveLetterRound.candidates(from: pool, letter: "B", limit: 3)
        #expect(got.map(\.id) == ["a", "c"])
    }

    @Test("availability counts what each letter could fill, so the builder can grey out the rest")
    func availability() {
        let pool = [q("Berlin", id: "a"), q("Boston", id: "b"), q("Cairo", id: "c"), q("2001", id: "d")]
        let counts = LiveLetterRound.availability(in: pool)
        #expect(counts["B"] == 2)
        #expect(counts["C"] == 1)
        #expect(counts["Z"] == nil)
    }

    @Test("the banner tells the room the rule in one line")
    func banner() {
        #expect(LiveLetterRound.banner(for: "b") == "EVERY ANSWER BEGINS WITH B")
    }
}
