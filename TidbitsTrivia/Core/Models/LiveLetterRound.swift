import Foundation

/// G4 — the first-letter round, pub trivia's most common themed format and
/// SpeedQuizzing's "First Letter of the Answer": the host announces a letter and
/// EVERY answer in the round begins with it.
///
/// The whole format is a constraint on which questions the round may hold, so it
/// lives here as a pure function over `Question` rather than in any one platform's
/// builder. Six stacks have to agree on which answers count as a "B", and the only
/// way that stays true is if the rule is written once and tested.
enum LiveLetterRound {

    /// Leading articles do not count. A pub quiz that announces "B" accepts
    /// "The Beatles", and a host who has to explain otherwise has lost the room.
    private static let articles: Set<String> = ["the", "a", "an"]

    /// The letter an answer counts as, or nil when it has no letter to offer
    /// (a number, a symbol, an empty string) and so can never belong to a
    /// letter round.
    ///
    /// Diacritics fold: "Édith Piaf" is an E, because the host says "E" and the
    /// room writes E. Comparing raw Characters would put É in a bucket of its own
    /// and silently drop the question from every letter.
    static func initial(of answer: String) -> Character? {
        let folded = answer.folding(options: [.diacriticInsensitive, .caseInsensitive],
                                    locale: Locale(identifier: "en_US"))
        var words = folded.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" })
        // Drop leading articles, but never ALL the words: an answer that is only
        // the word "The" still has to resolve to T rather than to nothing.
        while words.count > 1, let first = words.first, articles.contains(String(first)) {
            words.removeFirst()
        }
        guard let word = words.first else { return nil }
        // The first letter, not the first character: "'Round Midnight" is an R and
        // "2001" is not any letter at all.
        guard let ch = word.first(where: { $0.isLetter }) else { return nil }
        return Character(ch.uppercased())
    }

    /// Whether a question may sit in a round themed on `letter`.
    static func matches(_ question: Question, letter: Character) -> Bool {
        guard let want = initial(of: String(letter)) else { return false }
        return initial(of: question.correctAnswer) == want
    }

    /// The questions in a round that BREAK its letter theme.
    ///
    /// The builder shows these rather than refusing the edit: a host mid-build has
    /// a half-built round, and a format that fights them is a format they abandon.
    static func violations(in questions: [Question], letter: Character) -> [Question] {
        questions.filter { !matches($0, letter: letter) }
    }

    /// Questions from `pool` that fit the letter, in pool order, capped at `limit`.
    /// Duplicate answers are dropped: a round that asks for the same answer twice
    /// reads as a mistake even when both questions are fair.
    static func candidates(from pool: [Question], letter: Character, limit: Int) -> [Question] {
        var seen = Set<String>()
        var out: [Question] = []
        for q in pool where matches(q, letter: letter) {
            let key = q.correctAnswer.lowercased()
            if seen.insert(key).inserted {
                out.append(q)
                if out.count == limit { break }
            }
        }
        return out
    }

    /// How many questions the pool could supply for each letter — what the builder
    /// needs to grey out the letters it cannot fill.
    static func availability(in pool: [Question]) -> [Character: Int] {
        var counts: [Character: Int] = [:]
        for q in pool {
            if let c = initial(of: q.correctAnswer) { counts[c, default: 0] += 1 }
        }
        return counts
    }

    /// The line the room reads off the big screen.
    static func banner(for letter: Character) -> String {
        "EVERY ANSWER BEGINS WITH \(Character(letter.uppercased()))"
    }
}
