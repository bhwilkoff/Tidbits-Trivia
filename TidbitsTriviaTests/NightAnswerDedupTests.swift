import Foundation
import Testing
@testable import TidbitsTrivia

/// A night must not give the same ANSWER twice.
///
/// Apple deduped a night by question ID only, which is weaker than it sounds:
/// 4,261 (prompt, answer) pairs sit on more than one corpus row, so two DIFFERENT
/// ids can be the identical question to the room. Beyond that, "United States" is
/// the answer to 1,025 rows and 23,159 answers are used more than once —
/// simulated over the real corpus a 40-question night repeated an answer 17.1% of
/// the time, an 80-question night 48.1%.
///
/// This pins the RULE rather than a sampled draw. A night-level test cannot fail
/// reliably here — the Windows equivalent passes with the fix reverted, because a
/// fixture draw rarely collides — and an assertion that cannot fail is not an
/// assertion. This one fails the moment the key stops being the answer.
@Suite("Night answer dedup")
struct NightAnswerDedupTests {

    private func q(_ id: String, _ prompt: String, _ answer: String) -> Question {
        Question(id: id, prompt: prompt, options: [answer, "x", "y", "z"],
                 correctIndex: 0, categoryID: "mixed", difficulty: 3,
                 explanation: "", sourceTitle: "", sourceURL: nil, templateID: "t")
    }

    @Test("two wordings of the same answer collapse to one key")
    func sameAnswerSameKey() {
        let a = q("a", "Which of these four came first?", "Asia")
        let b = q("b", "Which one below is the oldest?", "  asia ")
        #expect(QuestionProvider.askedKey(a) == QuestionProvider.askedKey(b))
    }

    @Test("different answers stay distinct")
    func differentAnswersDiffer() {
        let a = q("a", "Which of these four came first?", "Asia")
        let c = q("c", "Which of these four came first?", "Europe")
        #expect(QuestionProvider.askedKey(a) != QuestionProvider.askedKey(c))
    }

    @Test("the id is NOT the identity")
    func idIsNotIdentity() {
        // The exact case the old guard missed: same question, two corpus rows.
        let a = q("row-1", "Who was the Flying Finn?", "Matti Nykänen")
        let b = q("row-2", "Who was the Flying Finn?", "Matti Nykänen")
        #expect(a.id != b.id)
        #expect(QuestionProvider.askedKey(a) == QuestionProvider.askedKey(b))
    }
}
