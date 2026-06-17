import Foundation

/// Turns Wikipedia article summaries into trivia questions. This is the
/// product's moat: the open API is a firehose of true-but-misleading
/// facts, so most of the value is in the FILTER, not the fetch
/// (competitive research §5). The same template shapes are mirrored by
/// the offline corpus generator (tools/corpus) so live and pre-baked
/// questions are indistinguishable to the game loop.
nonisolated struct TemplateEngine: Sendable {

    // MARK: Quality gates (the rulebook — see docs/QUESTION-QUALITY.md)

    /// A summary usable as a question subject.
    static func isUsable(_ s: WikipediaClient.Summary) -> Bool {
        guard s.type != "disambiguation" else { return false }
        guard let d = s.description, d.count >= 6, d.count <= 90 else { return false }
        guard let e = s.extract, e.count >= 40 else { return false }
        // Reject meta/list pages — they make ambiguous subjects.
        let lowerTitle = s.title.lowercased()
        if lowerTitle.hasPrefix("list of") || lowerTitle.contains("(disambiguation)") { return false }
        return true
    }

    /// Remove the answer (and parenthetical disambiguators) from any clue
    /// text so the prompt never leaks its own answer (research §5).
    static func redact(_ text: String, title: String) -> String {
        var out = text
        // Strip "(1932 film)"-style disambiguators that give away dates.
        let bareTitle = title.replacingOccurrences(of: #"\s*\([^)]*\)"#, with: "", options: .regularExpression)
        for needle in [title, bareTitle] where !needle.isEmpty {
            out = out.replacingOccurrences(of: needle, with: "—————", options: .caseInsensitive)
        }
        return out
    }

    // MARK: Generation

    /// Build up to `count` questions for a category/topic from a pool of
    /// summaries. Deterministic given the same pool + seed.
    static func makeQuestions(
        pool: [WikipediaClient.Summary],
        categoryID: String,
        count: Int,
        seed: UInt64
    ) -> [Question] {
        let usable = pool.filter(isUsable)
        guard usable.count >= 4 else { return [] }
        var rng = SeededRNG(seed: seed)
        let subjects = usable.shuffled(using: &rng)
        var questions: [Question] = []

        for subject in subjects {
            if questions.count >= count { break }
            // Alternate the two template shapes for variety.
            let useDescriptionOf = (questions.count % 2 == 0)
            let q = useDescriptionOf
                ? descriptionOfSubject(subject, pool: usable, categoryID: categoryID, rng: &rng)
                : subjectFromDescription(subject, pool: usable, categoryID: categoryID, rng: &rng)
            if let q { questions.append(q) }
        }
        return questions
    }

    // MARK: Template A — "What is <title>?" (options are descriptions)

    private static func descriptionOfSubject(
        _ s: WikipediaClient.Summary,
        pool: [WikipediaClient.Summary],
        categoryID: String,
        rng: inout SeededRNG
    ) -> Question? {
        guard let correct = s.description else { return nil }
        let distractors = pickDistractors(
            for: s, pool: pool, value: { $0.description }, exclude: correct, rng: &rng)
        guard distractors.count == 3 else { return nil }
        return assemble(
            subject: s, categoryID: categoryID,
            prompt: "How is \(displayTitle(s.title)) best described?",
            correct: capitalizedClue(correct), distractors: distractors.map(capitalizedClue),
            templateID: "descriptionOf", rng: &rng)
    }

    // MARK: Template B — "Which subject matches this clue?" (options are titles)

    private static func subjectFromDescription(
        _ s: WikipediaClient.Summary,
        pool: [WikipediaClient.Summary],
        categoryID: String,
        rng: inout SeededRNG
    ) -> Question? {
        guard let desc = s.description else { return nil }
        let clue = redact(firstSentence(of: s.extract ?? desc), title: s.title)
        guard clue.count >= 25 else { return nil }
        let distractors = pickDistractors(
            for: s, pool: pool, value: { $0.title }, exclude: s.title, rng: &rng)
        guard distractors.count == 3 else { return nil }
        return assemble(
            subject: s, categoryID: categoryID,
            prompt: "Which subject is this? \u{201C}\(clue)\u{201D}",
            correct: displayTitle(s.title), distractors: distractors.map(displayTitle),
            templateID: "subjectFrom", rng: &rng)
    }

    // MARK: Helpers

    private static func assemble(
        subject s: WikipediaClient.Summary, categoryID: String,
        prompt: String, correct: String, distractors: [String],
        templateID: String, rng: inout SeededRNG
    ) -> Question {
        var options = ([correct] + distractors)
        options.shuffle(using: &rng)
        let correctIndex = options.firstIndex(of: correct) ?? 0
        let explanation = (s.extract.map(firstSentence) ?? s.description ?? "")
        return Question(
            id: "live:\(templateID):\(s.title)".replacingOccurrences(of: " ", with: "_"),
            prompt: prompt,
            options: options,
            correctIndex: correctIndex,
            categoryID: categoryID,
            difficulty: difficulty(for: s),
            explanation: explanation,
            sourceTitle: s.title,
            sourceURL: s.pageURL,
            templateID: templateID
        )
    }

    /// Distractors: distinct, non-empty, and not equal to the answer.
    /// Prefers candidates that share a word with the subject's
    /// description so wrong answers stay plausible (research §1.9).
    private static func pickDistractors(
        for s: WikipediaClient.Summary,
        pool: [WikipediaClient.Summary],
        value: (WikipediaClient.Summary) -> String?,
        exclude: String,
        rng: inout SeededRNG
    ) -> [String] {
        let subjectWords = Set((s.description ?? "").lowercased().split(separator: " ").map(String.init))
        let candidates = pool
            .filter { $0.title != s.title }
            .compactMap { c -> (String, Int)? in
                guard let v = value(c)?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !v.isEmpty, v.caseInsensitiveCompare(exclude) != .orderedSame else { return nil }
                let words = Set((c.description ?? "").lowercased().split(separator: " ").map(String.init))
                return (v, subjectWords.intersection(words).count)
            }
        // De-dupe by value, prefer higher word-overlap, then shuffle ties.
        var seen = Set<String>()
        let ranked = candidates
            .sorted { $0.1 > $1.1 }
            .filter { seen.insert($0.0.lowercased()).inserted }
            .map(\.0)
        // Take a plausible top slice, then randomize which 3 we use.
        let slice = Array(ranked.prefix(8)).shuffled(using: &rng)
        return Array(slice.prefix(3))
    }

    private static func difficulty(for s: WikipediaClient.Summary) -> Int {
        // Proxy: longer, richer extracts tend to be more famous → easier.
        let len = s.extract?.count ?? 0
        switch len {
        case 600...: return 2
        case 300..<600: return 3
        default: return 4
        }
    }

    private static func firstSentence(of text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let range = trimmed.range(of: ". ") {
            return String(trimmed[..<range.lowerBound]) + "."
        }
        return trimmed
    }

    private static func displayTitle(_ t: String) -> String {
        t.replacingOccurrences(of: #"\s*\([^)]*\)"#, with: "", options: .regularExpression)
    }

    private static func capitalizedClue(_ c: String) -> String {
        guard let first = c.first else { return c }
        return first.uppercased() + c.dropFirst()
    }
}
