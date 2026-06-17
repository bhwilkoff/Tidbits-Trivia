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
    ]
    // 'oneliner' dropped — description-as-clue routinely leaked the answer's words.
    static let shapeRotation = ["identify", "cloze", "jeopardy", "categorize", "identify",
                                "cloze", "jeopardy", "identify", "categorize", "cloze"]

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
                // Never ship a redacted question whose answer leaks into the
                // prompt — fall through to the next shape. (Mirror of the
                // Python corpus gate.)
                if ["identify", "jeopardy", "cloze"].contains(shape) && leaks(answer, in: prompt) { continue }
                if prompt.count > 320 || hasForeignScript(prompt) { continue }
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
        default: return nil
        }
    }

    // MARK: Distractors (typed siblings; length-normalized for prose)

    // Type-matched distractors (mirror of generate_corpus.py): same TYPE as the
    // answer only, derived from the short description's head noun. [] (→ drop)
    // when fewer than 3 same-type siblings — never widen to a wrong type.
    static let typeLeading: Set<String> = Set("american english british french german italian spanish russian chinese japanese korean indian european african asian north south east west northern southern eastern western central ancient modern medieval former national international royal imperial classical contemporary professional famous notable major minor large small great greater lesser old new young senior junior fictional mythological historical traditional popular official public private federal scottish irish welsh dutch swedish norwegian danish polish turkish greek roman egyptian persian arab arabic jewish canadian australian mexican brazilian argentine chilean austrian swiss belgian portuguese finnish hungarian czech romanian indonesian filipino vietnamese thai largest smallest oldest".split(separator: " ").map(String.init))
    static let typeStop: Set<String> = ["in", "of", "from", "for", "by", "on", "at", "near", "during", "between", "that", "which", "who", "known", "with", "to", "and", "or", "located", "based", "set"]
    static let typeFold: [String: String] = ["singer": "musician", "songwriter": "musician", "singer-songwriter": "musician", "rapper": "musician", "guitarist": "musician", "pianist": "musician", "drummer": "musician", "bassist": "musician", "vocalist": "musician", "band": "musician", "duo": "musician", "composer": "musician", "actress": "actor", "filmmaker": "director", "novelist": "writer", "author": "writer", "poet": "writer", "playwright": "writer", "screenwriter": "writer", "essayist": "writer", "journalist": "writer", "physicist": "scientist", "chemist": "scientist", "biologist": "scientist", "mathematician": "scientist", "astronomer": "scientist", "geologist": "scientist", "economist": "scientist", "psychologist": "scientist", "inventor": "scientist", "footballer": "athlete", "player": "athlete", "cyclist": "athlete", "swimmer": "athlete", "boxer": "athlete", "wrestler": "athlete", "sprinter": "athlete", "runner": "athlete", "golfer": "athlete", "village": "settlement", "town": "settlement", "city": "settlement", "municipality": "settlement", "commune": "settlement", "capital": "settlement", "mountain": "peak", "volcano": "peak"]

    static func typeKey(_ s: WikipediaClient.Summary) -> String? {
        var d = (s.description ?? "").replacingOccurrences(of: #"\([^)]*\)"#, with: "", options: .regularExpression)
        d = (d.split(separator: ",").first.map(String.init) ?? d).trimmingCharacters(in: CharacterSet(charactersIn: " .")).lowercased()
        var toks: [String] = []
        for w in d.split(whereSeparator: { !$0.isLetter && $0 != "-" }).map(String.init) {
            if typeStop.contains(w) { break }
            toks.append(w)
        }
        while let f = toks.first, typeLeading.contains(f) { toks.removeFirst() }
        guard let last = toks.last else { return nil }
        return typeFold[last] ?? last
    }

    private static func typedDistractors(_ s: WikipediaClient.Summary, _ pool: [WikipediaClient.Summary], _ rng: inout SeededRNG, value: (WikipediaClient.Summary) -> String?, exclude: String, lengthMatch: Int?) -> [String] {
        guard let kt = typeKey(s) else { return [] }
        var seen = Set<String>()
        let cands = pool.compactMap { c -> (Int, String)? in
            guard c.title != s.title, typeKey(c) == kt,
                  let v0 = value(c)?.trimmingCharacters(in: .whitespaces),
                  !v0.isEmpty, v0.caseInsensitiveCompare(exclude) != .orderedSame,
                  seen.insert(v0.lowercased()).inserted else { return nil }
            return (lengthMatch.map { -abs(v0.count - $0) } ?? 0, v0)
        }.sorted { $0.0 > $1.0 }
        guard cands.count >= 3 else { return [] }
        return Array(Array(cands.prefix(max(9, 8)).map(\.1)).shuffled(using: &rng).prefix(3))
    }

    private static func titleDistractors(_ s: WikipediaClient.Summary, _ pool: [WikipediaClient.Summary], _ rng: inout SeededRNG) -> [String] {
        typedDistractors(s, pool, &rng, value: { displayTitle($0.title) }, exclude: displayTitle(s.title), lengthMatch: nil)
    }
    private static func descDistractors(_ s: WikipediaClient.Summary, _ pool: [WikipediaClient.Summary], _ rng: inout SeededRNG) -> [String] {
        typedDistractors(s, pool, &rng, value: { $0.description }, exclude: s.description ?? "", lengthMatch: (s.description ?? "").count)
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

    static let functionWords: Set<String> = ["the", "of", "and", "a", "an", "in", "on", "at", "to", "for", "by", "with", "from", "as", "or", "de", "von", "van", "al"]
    static let commonWords: Set<String> = ["empire", "battle", "war", "wars", "kingdom", "dynasty", "republic", "treaty", "river", "mountain", "mountains", "lake", "island", "islands", "city", "town", "county", "state", "states", "united", "nation", "national", "american", "english", "british", "french", "german", "italian", "spanish", "russian", "chinese", "japanese", "korean", "indian", "european", "african", "asian", "north", "south", "east", "west", "northern", "southern", "eastern", "western", "great", "greater", "new", "saint", "university", "college", "school", "company", "group", "band", "series", "film", "movie", "novel", "book", "award", "club", "team", "teams", "league", "party", "system", "century", "world", "people", "region", "province", "district", "area", "force", "army", "navy", "air", "language", "family", "order", "house", "song", "album", "season", "game", "games", "sport", "sports", "festival", "prize", "federal", "royal", "international", "association", "federation", "union", "organization", "museum", "park", "station", "bridge", "building", "tower", "palace", "castle", "church", "cathedral", "temple", "championship", "cup", "first", "second"]

    static func hasForeignScript(_ s: String) -> Bool {
        // Non-Latin scripts + math symbols that make a clue unreadable. Accented
        // Latin (é, ñ) is fine and excluded.
        s.unicodeScalars.contains { v in
            let n = v.value
            return (0x0370...0x06FF).contains(n) || (0x3040...0x9FFF).contains(n)
                || (0xAC00...0xD7AF).contains(n) || (0x2200...0x22FF).contains(n)
                || (0x27E8...0x27EF).contains(n)
        }
    }

    static func leaks(_ answer: String, in prompt: String) -> Bool {
        let p = prompt.lowercased()
        let toks = Set(answer.lowercased().split { !$0.isLetter }.map(String.init).filter { $0.count >= 4 }).subtracting(commonWords)
        return toks.contains { p.contains($0) }
    }

    static func redact(_ text: String, title: String) -> String {
        var out = text
        let bareTitle = title.replacingOccurrences(of: #"\s*\([^)]*\)"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        // 1. Whole-title phrase(s).
        for needle in [title, bareTitle] where !needle.isEmpty {
            out = out.replacingOccurrences(of: needle, with: "—————", options: .caseInsensitive)
        }
        // 2. Leading proper-noun run (≥2 words) — catches full-name variants.
        out = out.replacingOccurrences(
            of: #"^(The |A |An )?((?:[A-Z][\w’'.\-]*)(?:[ \-]+(?:of |the |and |de |von |van |al-)?[A-Z][\w’'.\-]*)+)"#,
            with: "$1—————", options: .regularExpression)
        // 3. Each CONTENT title word wherever it appears.
        for w in bareTitle.split(whereSeparator: { !$0.isLetter && $0 != "'" && $0 != "’" && $0 != "-" }).map(String.init) {
            if w.count < 3 || functionWords.contains(w.lowercased()) { continue }
            let pat = #"\b"# + NSRegularExpression.escapedPattern(for: w) + #"(?:’s|'s|s|es)?\b"#
            out = out.replacingOccurrences(of: pat, with: "—————", options: [.regularExpression, .caseInsensitive])
        }
        // 4. Collapse adjacent blanks (with connectors) into one.
        out = out.replacingOccurrences(of: #"—————(?:[\s,’'.\–\-]+(?:of|the|and)?\s*—————)+"#, with: "—————", options: [.regularExpression, .caseInsensitive])
        out = out.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        return out
    }
    private static func difficulty(for s: WikipediaClient.Summary) -> Int {
        let len = s.extract?.count ?? 0
        return len >= 600 ? 2 : (len >= 300 ? 3 : 4)
    }
    static let abbrev: Set<String> = ["lit", "e.g", "i.e", "approx", "no", "vs", "etc", "st", "mt", "mr", "mrs", "ms", "dr", "fl", "ca", "jr", "sr", "col", "gen", "gov", "sen", "rep", "prof", "rev", "inc", "ltd", "co", "u.s", "u.k"]

    private static func firstSentence(of text: String) -> String {
        // Paren/abbreviation-aware so 'lit.' / '(…; lit. …)' / middle initials
        // don't truncate the clue mid-phrase.
        let t = Array(text.trimmingCharacters(in: .whitespacesAndNewlines))
        var depth = 0
        var i = 0
        while i < t.count {
            let ch = t[i]
            if ch == "(" || ch == "[" { depth += 1 }
            else if (ch == ")" || ch == "]") && depth > 0 { depth -= 1 }
            else if ch == "." && depth == 0 && i + 1 < t.count && t[i + 1] == " " {
                let nxt2: Character? = i + 2 < t.count ? t[i + 2] : nil
                if nxt2 == nil || nxt2!.isUppercase || "“”\"'‘’".contains(nxt2!) {
                    var j = i - 1
                    while j >= 0, t[j].isLetter || t[j].isNumber || t[j] == "." || t[j] == "'" || t[j] == "-" { j -= 1 }
                    let tok = String(t[(j + 1)..<i])
                    let letters = tok.filter { $0.isLetter }
                    let isAbbrev = !letters.isEmpty && (letters.count <= 1 || abbrev.contains(tok.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))))
                    if !isAbbrev { return String(t[0...i]) }
                }
            }
            i += 1
        }
        return String(t)
    }
    private static func displayTitle(_ t: String) -> String {
        t.replacingOccurrences(of: #"\s*\([^)]*\)"#, with: "", options: .regularExpression)
    }
    private static func capitalize(_ c: String) -> String {
        guard let first = c.first else { return c }
        return first.uppercased() + c.dropFirst()
    }
}
