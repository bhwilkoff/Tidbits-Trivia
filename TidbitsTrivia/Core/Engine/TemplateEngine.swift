import Foundation

/// Turns Wikipedia article summaries into trivia questions. The product's
/// moat is the FILTER, not the fetch. v2 rotates among FIVE question shapes
/// (identify / Jeopardy-inversion / cloze / categorize / one-liner) with a
/// bank of stems so no single phrasing dominates ("best described" is now a
/// capped minority), and normalizes distractor surface form so the answer
/// can't be guessed from how options are written. Mirrors
/// `tools/corpus/generate_corpus.py` (Decision 019).
nonisolated struct TemplateEngine: Sendable {

    // MARK: Quality gates

    static func isUsable(_ s: WikipediaClient.Summary) -> Bool {
        guard s.type != "disambiguation" else { return false }
        guard let d = s.description, d.count >= 6, d.count <= 90 else { return false }
        guard let e = s.extract, e.count >= 40 else { return false }
        let lowerTitle = s.title.lowercased()
        if lowerTitle.hasPrefix("list of") || lowerTitle.contains("(disambiguation)") { return false }
        if (e).lowercased().contains("may refer to") { return false }
        return true
    }

    // MARK: Rotating stems (≤ ~1/N share each; categorize a minority)

    static let stems: [String: [String]] = [
        "identify": [
            "Which subject does this describe? \u{201C}%@\u{201D}",
            "Name it — \u{201C}%@\u{201D}",
            "What is being described here? \u{201C}%@\u{201D}",
            "Identify the subject: \u{201C}%@\u{201D}",
            "These clues point to one thing. What is it? \u{201C}%@\u{201D}",
            "Guess the article: \u{201C}%@\u{201D}",
        ],
        "jeopardy": [
            "%@ — what is it?",
            "%@ Name the subject.",
            "%@ What are we describing?",
        ],
        "cloze": [
            "Fill in the blank: \u{201C}%@\u{201D}",
            "Complete the sentence: \u{201C}%@\u{201D}",
            "Which name completes this? \u{201C}%@\u{201D}",
        ],
        "categorize": [
            "What kind of thing is %@?",
            "What is %@ best known as?",
            "In a few words, what is %@?",
            "Which description fits %@?",
        ],
        "oneliner": [
            "Which one is \u{201C}%@\u{201D}?",
            "\u{201C}%@\u{201D} — which subject is that?",
            "Which subject matches: \u{201C}%@\u{201D}?",
        ],
    ]
    static let shapeRotation = ["identify", "cloze", "jeopardy", "categorize", "oneliner",
                                "cloze", "identify", "categorize", "jeopardy", "cloze"]

    // MARK: Generation

    static func makeQuestions(
        pool: [WikipediaClient.Summary], categoryID: String, count: Int, seed: UInt64
    ) -> [Question] {
        let usable = pool.filter(isUsable)
        guard usable.count >= 4 else { return [] }
        var rng = SeededRNG(seed: seed)
        let subjects = usable.shuffled(using: &rng)
        var questions: [Question] = []
        var gi = 0
        for subject in subjects {
            if questions.count >= count { break }
            if let q = build(subject, pool: usable, categoryID: categoryID, gi: gi, rng: &rng) {
                questions.append(q)
            }
            gi += 1
        }
        return questions
    }

    private static func build(
        _ s: WikipediaClient.Summary, pool: [WikipediaClient.Summary],
        categoryID: String, gi: Int, rng: inout SeededRNG
    ) -> Question? {
        let n = shapeRotation.count
        for off in 0..<n {
            let shape = shapeRotation[(gi + off) % n]
            let bank = stems[shape]!
            let stem = bank[(gi / n) % bank.count]
            if let (prompt, options, answer) = builder(shape, s, pool, stem, &rng) {
                var opts = options
                opts.shuffle(using: &rng)
                let ci = opts.firstIndex(of: answer) ?? 0
                return Question(
                    id: "live:\(shape):\(s.title)".replacingOccurrences(of: " ", with: "_"),
                    prompt: prompt, options: opts, correctIndex: ci, categoryID: categoryID,
                    difficulty: difficulty(for: s), explanation: cleanClue(firstSentence(of: s.extract ?? s.description ?? "")),
                    sourceTitle: s.title, sourceURL: s.pageURL, templateID: shape)
            }
        }
        return nil
    }

    private static func builder(
        _ shape: String, _ s: WikipediaClient.Summary, _ pool: [WikipediaClient.Summary],
        _ stem: String, _ rng: inout SeededRNG
    ) -> (String, [String], String)? {
        switch shape {
        case "identify":
            let clue = redact(cleanClue(firstSentence(of: s.extract ?? s.description ?? "")), title: s.title)
            guard clue.count >= 25 else { return nil }
            let ds = titleDistractors(s, pool, &rng); guard ds.count == 3 else { return nil }
            let ans = displayTitle(s.title)
            return (String(format: stem, clue), [ans] + ds, ans)
        case "jeopardy":
            let sent = cleanClue(firstSentence(of: s.extract ?? ""))
            guard sent.count >= 25 else { return nil }
            let bare = displayTitle(s.title)
            var clue: String
            if sent.lowercased().hasPrefix(s.title.lowercased()) {
                clue = "This" + sent.dropFirst(s.title.count)
            } else if sent.lowercased().hasPrefix(bare.lowercased()) {
                clue = "This" + sent.dropFirst(bare.count)
            } else {
                clue = redact(sent, title: s.title)
            }
            clue = capitalize(clue.trimmingCharacters(in: .whitespaces))
            let ds = titleDistractors(s, pool, &rng); guard ds.count == 3 else { return nil }
            return (String(format: stem, clue), [bare] + ds, bare)
        case "cloze":
            let sent = cleanClue(firstSentence(of: s.extract ?? ""))
            let bare = displayTitle(s.title)
            var clozed: String?
            for needle in [s.title, bare] where !needle.isEmpty && sent.range(of: needle, options: .caseInsensitive) != nil {
                clozed = sent.replacingOccurrences(of: needle, with: "_____", options: .caseInsensitive)
                break
            }
            guard let cz = clozed, cz.count >= 25 else { return nil }
            let ds = titleDistractors(s, pool, &rng); guard ds.count == 3 else { return nil }
            return (String(format: stem, cz), [bare] + ds, bare)
        case "categorize":
            guard let correct = s.description else { return nil }
            let ds = descDistractors(s, pool, &rng); guard ds.count == 3 else { return nil }
            let ans = capitalize(correct)
            return (String(format: stem, displayTitle(s.title)), [ans] + ds.map(capitalize), ans)
        case "oneliner":
            guard let correct = s.description else { return nil }
            // Skip generic descriptions ("American writer") — unanswerable as a clue.
            if correct.split(separator: " ").count < 4 && !correct.contains(where: { ",(0123456789".contains($0) }) { return nil }
            let ds = titleDistractors(s, pool, &rng); guard ds.count == 3 else { return nil }
            let ans = displayTitle(s.title)
            return (String(format: stem, capitalize(correct)), [ans] + ds, ans)
        default: return nil
        }
    }

    // MARK: Distractors (typed siblings; length-normalized for prose)

    private static func rankedSiblings(
        _ s: WikipediaClient.Summary, _ pool: [WikipediaClient.Summary],
        value: (WikipediaClient.Summary) -> String?, exclude: String, lengthMatch: Int?
    ) -> [String] {
        let subjWords = Set((s.description ?? "").lowercased().split(separator: " ").map(String.init))
        var seen = Set<String>()
        let cands = pool.compactMap { c -> (Int, Int, String)? in
            guard c.title != s.title, let v0 = value(c)?.trimmingCharacters(in: .whitespaces),
                  !v0.isEmpty, v0.caseInsensitiveCompare(exclude) != .orderedSame,
                  seen.insert(v0.lowercased()).inserted else { return nil }
            let words = Set((c.description ?? "").lowercased().split(separator: " ").map(String.init))
            let overlap = subjWords.intersection(words).count
            let lenPen = lengthMatch.map { -abs(v0.count - $0) } ?? 0
            return (overlap, lenPen, v0)
        }.sorted { ($0.0, $0.1) > ($1.0, $1.1) }
        return cands.map(\.2)
    }

    private static func titleDistractors(_ s: WikipediaClient.Summary, _ pool: [WikipediaClient.Summary], _ rng: inout SeededRNG) -> [String] {
        let ranked = rankedSiblings(s, pool, value: { displayTitle($0.title) }, exclude: displayTitle(s.title), lengthMatch: nil)
        return Array(Array(ranked.prefix(8)).shuffled(using: &rng).prefix(3))
    }
    private static func descDistractors(_ s: WikipediaClient.Summary, _ pool: [WikipediaClient.Summary], _ rng: inout SeededRNG) -> [String] {
        let ranked = rankedSiblings(s, pool, value: { $0.description }, exclude: s.description ?? "", lengthMatch: (s.description ?? "").count)
        return Array(Array(ranked.prefix(8)).shuffled(using: &rng).prefix(3))
    }

    // MARK: Helpers

    // Strip parenthetical clutter (foreign scripts, pronunciations, empty
    // parens, leading ALL-CAPS acronyms that leak the answer). Fixpoint loop
    // handles nested parens. Mirrors generate_corpus.py clean_clue.
    private static let groupREs = [
        try! NSRegularExpression(pattern: #"\s*\(([^()]*)\)"#),     // ( … )
        try! NSRegularExpression(pattern: #"\s*\[([^\[\]]*)\]"#),   // [ … ]  IPA / CJK glosses
    ]
    static func cleanClue(_ text: String) -> String {
        var out = text, prev = ""
        while out != prev {
            prev = out
            for re in groupREs {
                let ns = out as NSString
                var result = ""; var last = 0
                for m in re.matches(in: out, range: NSRange(location: 0, length: ns.length)) {
                    result += ns.substring(with: NSRange(location: last, length: m.range.location - last))
                    let inner = ns.substring(with: m.range(at: 1))
                    if !shouldDropParen(inner) { result += ns.substring(with: m.range) }
                    last = m.range.location + m.range.length
                }
                result += ns.substring(from: last)
                out = result
            }
        }
        while out.contains("  ") { out = out.replacingOccurrences(of: "  ", with: " ") }
        return out.replacingOccurrences(of: " ,", with: ",").replacingOccurrences(of: " .", with: ".")
            .trimmingCharacters(in: .whitespaces)
    }
    private static func shouldDropParen(_ inner: String) -> Bool {
        let t = inner.trimmingCharacters(in: .whitespaces)
        if t.isEmpty { return true }
        if t.unicodeScalars.contains(where: { $0.value > 127 }) { return true }
        let langs = ["romaniz", "pronounc", "ipa", "listen", "lit.", "russian", "greek", "latin",
                     "arabic", "chinese", "japanese", "hebrew", "hindi", "persian", "german",
                     "french", "spanish", "italian", "korean", "portuguese", "turkish", "polish", "dutch", "sanskrit"]
        let lower = t.lowercased()
        if langs.contains(where: { lower.contains($0) }) { return true }
        let firstChunk = t.split(separator: ";").first.map(String.init) ?? t
        let tok = (firstChunk.split(separator: " ").first.map(String.init) ?? "").filter { $0.isLetter }
        if tok.count >= 2 && tok.count <= 6 && tok == tok.uppercased() && tok != tok.lowercased() { return true }
        return false
    }

    static func redact(_ text: String, title: String) -> String {
        var out = text
        let bareTitle = title.replacingOccurrences(of: #"\s*\([^)]*\)"#, with: "", options: .regularExpression)
        for needle in [title, bareTitle] where !needle.isEmpty {
            out = out.replacingOccurrences(of: needle, with: "—————", options: .caseInsensitive)
        }
        return out
    }
    private static func difficulty(for s: WikipediaClient.Summary) -> Int {
        let len = s.extract?.count ?? 0
        return len >= 600 ? 2 : (len >= 300 ? 3 : 4)
    }
    private static func firstSentence(of text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let range = trimmed.range(of: ". ") { return String(trimmed[..<range.lowerBound]) + "." }
        return trimmed
    }
    private static func displayTitle(_ t: String) -> String {
        t.replacingOccurrences(of: #"\s*\([^)]*\)"#, with: "", options: .regularExpression)
    }
    private static func capitalize(_ c: String) -> String {
        guard let first = c.first else { return c }
        return first.uppercased() + c.dropFirst()
    }
}
