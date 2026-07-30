import Foundation

/// The screened question set used by store-screenshot runs (docs/STORE-SCREENSHOTS.md,
/// rule R-SHOT-3: **a store frame is never a random draw**).
///
/// Why: a random corpus draw put a Holocaust question into the reveal slot — the single
/// most-viewed frame in a store listing. **The owner has ruled that question fine in the app**
/// (2026-07-30), and it is: the corpus covers hard history on purpose and that is not a
/// content problem. This is purely a *listing* decision — a storefront thumbnail is seen
/// out of context by people who have not chosen to play, so the set is curated rather than
/// rolled. Nothing here implies the underlying question should change.
///
/// Screening alone wasn't enough either, so the selection also:
///  - requires a Wikipedia-lead-style explanation, because a restatement ("The elevation of
///    X is about 313 m.") differentiates nothing in the slot whose whole job is showing that
///    you learn something; and
///  - takes at most one question per category and per prompt-shape, because an id-ordered
///    pool produced ten near-identical "which of these was born first?" questions, which
///    advertises a one-note app.
///
/// Deterministic: the same build picks the same questions every run, so a re-capture is
/// reproducible rather than a fresh roll of the dice.
///
/// Kept in Core so the Kotlin/C# mirrors screen against the SAME word list — the whole point
/// is that no platform's listing can regress independently.
enum ScreenshotQuestions {
    /// Terms that keep a question out of a STORE SCREENSHOT (not out of the app). Broad on
    /// purpose: a false positive costs one candidate out of thousands, and the whole point is
    /// that a thumbnail is seen without context.
    static let disqualifying = [
        "nazi", "holocaust", "genocide", "massacre", "atrocit", "murder", "killed", "killing",
        "war crime", "execut", "slaver", "slave", "rape", "assassin", "terror", "suicide",
        "famine", "lynch", "torture", "concentration camp", "ethnic cleansing", "bomb",
        "casualt", "died", "death", "deaths", "fatal", "shot dead", "abuse",
    ]

    static func isSafe(_ q: Question) -> Bool {
        let haystack = ([q.prompt] + q.options + [q.explanation])
            .joined(separator: " ")
            .lowercased()
        return !disqualifying.contains { haystack.contains($0) }
    }

    /// True when the explanation actually teaches something (a Wikipedia lead sentence)
    /// rather than restating the prompt.
    private static func hasStory(_ q: Question) -> Bool {
        let e = q.explanation
        guard e.count >= 80 else { return false }
        return e.contains(" is a ") || e.contains(" was a ")
    }

    /// `count` screened, varied questions in a stable order. Returns fewer only if the corpus
    /// genuinely cannot supply them (the caller should treat that as a failure, not fall back
    /// to a random draw).
    static func pick(from pool: [Question], count: Int) -> [Question] {
        let candidates = pool
            .filter(isSafe)
            .filter(hasStory)
            .filter { $0.prompt.count >= 70 }                        // the narrative prompts read best
            .filter { !$0.prompt.lowercased().hasPrefix("in what year") }
            .sorted { $0.id < $1.id }                                 // stable across runs

        var chosen: [Question] = []
        var usedCategories = Set<String>()
        var usedShapes = Set<String>()
        // Two passes: one-per-category first for maximum spread, then fill by shape only.
        for spreadPass in [true, false] {
            for q in candidates where chosen.count < count {
                if chosen.contains(where: { $0.id == q.id }) { continue }
                let shape = String(q.prompt.prefix(24)).lowercased()
                if usedShapes.contains(shape) { continue }
                if spreadPass && usedCategories.contains(q.categoryID) { continue }
                usedShapes.insert(shape)
                usedCategories.insert(q.categoryID)
                chosen.append(q)
            }
        }
        return chosen
    }
}
