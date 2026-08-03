import Foundation

/// Resolving a shared single question (`tidbits://item/<id>`, DEEP_LINKS.md).
///
/// An id can name a corpus row OR a row in any bundled shape set, and the two share the
/// `src:` namespace — so the corpus is asked first and the sets are a fallback, the same
/// order `SavedQuiz.resolveAgainstBundle` uses. Kept in Core because iOS, macOS and tvOS
/// all present the same thing and only the sheet differs.
enum SharedItem {

    private static let bundledSets: [JSONQuestionSource] = [
        .picture, .thisOrThat, .closestCall, .ordering,
        .matching, .typeAnswer, .oddOneOut, .enumerate,
    ]

    /// Prefixes that name exactly one shape set. `src:` and friends are deliberately
    /// absent — Picture ID shares the corpus namespace, so those ids have to try both.
    private static let setByIDPrefix: [String: JSONQuestionSource] = [
        "tot": .thisOrThat, "biztot": .thisOrThat,
        "odd": .oddOneOut, "oddrel": .oddOneOut,
        "closest": .closestCall,
        "order": .ordering, "bizorder": .ordering,
        "match": .matching, "type": .typeAnswer,
        "enum": .enumerate, "enumrel": .enumerate,
    ]

    /// The question behind a shared id, or nil when it no longer ships. Nil is a real
    /// answer, not a failure: rows are retired, and telling someone their link is dead
    /// beats showing them an empty card.
    @MainActor
    static func question(id: String) -> Question? {
        guard !id.isEmpty else { return nil }
        // Ask the set the prefix names first. Same policy as the Kotlin and JS twins,
        // where it is what keeps a cold-start deep link off the corpus entirely.
        if let set = setByIDPrefix[String(id.prefix(while: { $0 != ":" }))],
           let q = set.question(id: id) { return q }
        if let q = CorpusDatabase.shared.questions(ids: [id]).first { return q }
        for set in bundledSets {
            if let q = set.question(id: id) { return q }
        }
        return nil
    }
}
