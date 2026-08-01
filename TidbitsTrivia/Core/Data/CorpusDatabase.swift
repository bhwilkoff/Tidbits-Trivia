import Foundation
import SQLite3

/// Read-only reader over the bundled `corpus.sqlite` (10k+ pre-baked,
/// quality-gated questions). Raw SQLite3 C API — no third-party packages
/// (Apple-frameworks-only rule). Mirrors Android's bundled Room DB and
/// the web's IndexedDB seed: same corpus, three readers.
nonisolated final class CorpusDatabase: @unchecked Sendable {
    static let shared = CorpusDatabase()

    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "tidbits.corpus")
    static let transientDestructor = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private init() {
        guard let url = Bundle.main.url(forResource: "corpus", withExtension: "sqlite") else {
            db = nil; return
        }
        if sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil) != SQLITE_OK {
            db = nil
        }
    }

    var isAvailable: Bool { db != nil }

    var count: Int {
        queue.sync {
            guard let db else { return 0 }
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            guard sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM questions", -1, &stmt, nil) == SQLITE_OK,
                  sqlite3_step(stmt) == SQLITE_ROW else { return 0 }
            return Int(sqlite3_column_int(stmt, 0))
        }
    }

    /// Fetch up to `limit` random questions in a category, excluding ids
    /// the player has already seen. `categoryID == "mixed"` spans all.
    func questions(categoryID: String, excluding seen: Set<String>, limit: Int) -> [Question] {
        queue.sync {
            guard let db else { return [] }
            let overFetch = max(limit * 6, 60)
            let sql: String
            if categoryID == "mixed" {
                sql = "SELECT * FROM questions ORDER BY RANDOM() LIMIT ?"
            } else {
                sql = "SELECT * FROM questions WHERE category_id = ? ORDER BY RANDOM() LIMIT ?"
            }
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
            if categoryID == "mixed" {
                sqlite3_bind_int(stmt, 1, Int32(overFetch))
            } else {
                sqlite3_bind_text(stmt, 1, categoryID, -1, Self.transientDestructor)
                sqlite3_bind_int(stmt, 2, Int32(overFetch))
            }
            var out: [Question] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                guard let q = Self.row(stmt) else { continue }
                if seen.contains(q.id) { continue }
                out.append(q)
                if out.count >= limit { break }
            }
            return out
        }
    }

    /// All question IDs for a category in STABLE id order (no RANDOM()). The
    /// caller seed-shuffles for a deterministic-but-varied slice — this is what
    /// makes the Daily identical for everyone for the calendar day. "mixed"/""
    /// = the whole corpus.
    func orderedIDs(categoryID: String) -> [String] {
        queue.sync {
            guard let db else { return [] }
            let whole = categoryID == "mixed" || categoryID.isEmpty
            let sql = whole
                ? "SELECT id FROM questions ORDER BY id"
                : "SELECT id FROM questions WHERE category_id = ? ORDER BY id"
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
            if !whole { sqlite3_bind_text(stmt, 1, categoryID, -1, Self.transientDestructor) }
            var ids: [String] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let c = sqlite3_column_text(stmt, 0) { ids.append(String(cString: c)) }
            }
            return ids
        }
    }

    /// Topic search for the Create feature: real, already-vetted corpus questions
    /// whose prompt or Wikipedia source title match the topic's words. Ranked by
    /// how many topic words hit (source-title hits weighted). This is grounded
    /// generation's retrieval baseline — no live API, no hallucination, every
    /// device (docs/CREATE-QUESTION-GEN-PLAYBOOK.md).
    /// Words too common to narrow anything — they made the pre-filter match
    /// nearly the whole corpus, crowding out real hits before ranking.
    /// Lowercase + strip diacritics, so "beyonce" finds "Beyoncé". Mirrored by the
    /// corpus build (`search_text`), Kotlin, C# and JS — all four must agree or a
    /// topic returns different questions per platform.
    static func fold(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
    }

    nonisolated static func isStopword(_ w: String) -> Bool { stopwords.contains(w) }

    private static let stopwords: Set<String> = [
        "the", "and", "for", "with", "from", "that", "this", "his", "her", "its",
        "was", "were", "are", "who", "what", "which", "how", "why", "all", "any",
    ]

    /// Word-bounded containment — the single most load-bearing line in Create.
    ///
    /// Plain `contains` matched the typed word INSIDE longer words, which is how
    /// "Ansel Adams" returned Hansel and Gretel and Phil Anselmo, "Harry Kane"
    /// returned Spokane and Butane, and "India" returned Indianapolis. Measured
    /// across the 984 most-viewed Wikipedia articles, substring matching alone
    /// accounted for 1,444 off-topic questions.
    nonisolated static func containsWord(_ text: String, _ token: String) -> Bool {
        guard !token.isEmpty else { return false }
        var from = text.startIndex
        while let r = text.range(of: token, range: from..<text.endIndex) {
            let beforeOK = r.lowerBound == text.startIndex
                || !isWordChar(text[text.index(before: r.lowerBound)])
            let afterOK = r.upperBound == text.endIndex || !isWordChar(text[r.upperBound])
            if beforeOK && afterOK { return true }
            from = text.index(after: r.lowerBound)
        }
        return false
    }

    private static func isWordChar(_ c: Character) -> Bool { c.isLetter || c.isNumber }

    /// Fold + split into the significant words. Shared by the typed topic AND by
    /// row titles, so "A.I. Artificial Intelligence" and "Artificial intelligence"
    /// reduce to the same subject.
    nonisolated static func topicTokens(_ s: String) -> [String] {
        let raw = fold(stripParens(s)).split { !$0.isLetter && !$0.isNumber }
            .map(String.init).filter { $0.count >= 3 }
        let kept = raw.filter { !stopwords.contains($0) }
        return kept.isEmpty ? raw : kept
    }

    /// Wikipedia disambiguators are not part of what the player means. "Backrooms
    /// (film)" and "Masters of the Universe (2026 film)" are how the article is
    /// titled, not how anyone asks for it — and treating them as topic words made
    /// the phrase "masters universe 2026 film", which appears nowhere on earth.
    nonisolated static func stripParens(_ s: String) -> String {
        var out = ""
        var depth = 0
        for c in s {
            if c == "(" || c == "[" { depth += 1; continue }
            if c == ")" || c == "]" { depth = max(0, depth - 1); continue }
            if depth == 0 { out.append(c) }
        }
        return out.trimmingCharacters(in: .whitespaces)
    }

    /// Punctuation flattened to single spaces, nothing dropped. Phrase matching
    /// needs the STOPWORDS kept and in order — "masters of the universe" is the
    /// phrase; the significant-token list can never reconstruct it — and it needs
    /// the parenthetical kept on ROW titles, where it carries the meaning
    /// ("Dangerous (Michael Jackson album)" is how that row says whose album it is).
    nonisolated static func flattened(_ s: String) -> String {
        fold(s).split { !$0.isLetter && !$0.isNumber }.joined(separator: " ")
    }

    /// The typed topic as a matchable phrase: disambiguator removed, order kept.
    nonisolated static func topicPhrase(_ s: String) -> String { flattened(stripParens(s)) }

    /// Did the topic lose MEANINGFUL words to the ≥3-character rule?
    ///
    /// "George VI" reduces to the single token `george`, so every George in the
    /// corpus matched it — measured across the top 1,000, that topic returned
    /// George Martin, George Mallory, George Eliot and Paul George. "O. J.
    /// Simpson" reduces to `simpson` and returned Homer, Bart and Marge.
    ///
    /// A regnal numeral or an initial is short but not insignificant, and the tell
    /// is that the phrase still holds a non-stopword the token list threw away.
    /// When that happens the loose token match is worthless and only the phrase
    /// itself can be trusted. Crucially this does NOT fire for "The Beatles",
    /// where the dropped word is a stopword and the loose match is still right.
    nonisolated static func phraseIsRequired(_ topic: String) -> Bool {
        let significant = topicPhrase(topic).split(separator: " ")
            .map(String.init).filter { !stopwords.contains($0) }
        return significant.count > topicTokens(topic).count
    }

    /// Wikipedia categories are the row's `tags`, and only SOME of them mean the
    /// row is about the topic. "Albums produced by Michael Jackson" does.
    /// "Actresses from Denver" does not — it is where she happens to be from, and
    /// a Kristin Cavallari birth-year question in a Denver quiz is exactly the
    /// "questions the user didn't ask for" the owner reported.
    ///
    /// The preposition carries it: `by`/`of` are agentive or possessive, while
    /// `from`/`in`/`at` are incidental. A tag that merely BEGINS with the topic is
    /// not enough either — that admitted "Abraham Lincoln High School (Brooklyn)
    /// alumni" (a Lincoln quiz asking Neil Sedaka's birth year).
    nonisolated static func hasAgentiveTag(_ tags: [String], phrase: String) -> Bool {
        for t in tags {
            for prep in ["by ", "of "] {
                var from = t.startIndex
                while let r = t.range(of: prep, range: from..<t.endIndex) {
                    var rest = t[r.upperBound...]
                    if rest.hasPrefix("the ") { rest = rest.dropFirst(4) }
                    if rest.hasPrefix(phrase) {
                        let after = rest.dropFirst(phrase.count)
                        if after.isEmpty || !isWordChar(after[after.startIndex]) { return true }
                    }
                    from = r.upperBound
                }
            }
        }
        return false
    }

    /// How relevant one row is to the typed topic, or `nil` to REJECT it outright.
    ///
    /// This is a floor, not just a ranking. Before it existed the ranker kept the
    /// best of whatever the OR-prefilter dragged in, so a topic the corpus knows
    /// nothing about still produced eight confident, unrelated questions instead
    /// of deferring to live generation.
    ///
    ///  3  the row's subject IS the topic
    ///  2  the whole typed phrase appears, word-bounded, in the title
    ///  1  every typed word appears, word-bounded, in the title
    ///  0  every typed word appears in the prompt the player reads
    /// -1  an agentive tag only — a real connection the question never shows
    ///
    /// The OPTIONS are deliberately not consulted. Measured on the simulator over
    /// the 120 most-viewed articles, that one inclusion produced the worst results
    /// in the whole sweep: typing "Zlatan Ibrahimović" returned a picture of
    /// Neymar, "Zendaya" returned Michelle Yeoh, "Christian Pulisic" returned
    /// Peyton Manning. The topic was matching as a DISTRACTOR — and because the
    /// giveaway rule had already set aside every row where the topic was the
    /// correct answer, the only rows left were the ones where it was wrong.
    nonisolated static func tier(title: String, prompt: String, tags: [String],
                                 tokens: [String], phrase: String, guardNames: Bool,
                                 requirePhrase: Bool = false) -> Int? {
        let fTitle = fold(title)
        let subject = flattened(title)
        if subject == phrase { return 3 }
        if containsWord(subject, phrase) {
            // When the typed word is ITSELF a subject in this corpus, a bare
            // two-word title that merely contains it is a DIFFERENT named thing:
            // "Bob Denver", "Denver Pyle", "Samuel Adams". The player typed the
            // place; they did not type the actor.
            if guardNames, subject.split(separator: " ").count == 2 { return nil }
            return 2
        }
        // A numeral or an initial was dropped as "too short", so the surviving
        // tokens name the wrong thing — only the phrase above could be trusted.
        if requirePhrase { return containsWord(fold(prompt), phrase) ? 0 : nil }
        let need = tokens.count <= 2 ? tokens.count : tokens.count - 1
        if tokens.filter({ containsWord(fTitle, $0) }).count >= need { return 1 }
        let read = fTitle + " " + fold(prompt)
        if tokens.filter({ containsWord(read, $0) }).count >= need { return 0 }
        if hasAgentiveTag(tags.map(fold), phrase: phrase) { return -1 }
        return nil
    }

    func search(topic: String, limit: Int) -> [Question] {
        // Stopwords are dropped, not merely short words: the >=3 rule kept "the",
        // which matches nearly every row and so GUARANTEED the pre-filter cap below
        // to fill with noise for any topic containing it ("The Beatles", "The
        // Simpsons"). Falls back to the raw tokens if a topic is nothing but
        // stopwords, so a query is never left empty.
        let tokens = Self.topicTokens(topic)
        guard !tokens.isEmpty else { return [] }
        // A topic made of nothing but stopwords cannot be searched for. "From (TV
        // series)" reduces to the word `from`, which then matched every row
        // containing it — measured, that topic returned Notes from Underground,
        // Spider-Man: Far From Home and From Dusk till Dawn. The corpus has no way
        // to tell these apart, so it says so and live generation takes the topic,
        // where Wikipedia's own search does know what "From (TV series)" is.
        guard tokens.contains(where: { !Self.stopwords.contains($0) }) else { return [] }
        let phrase = Self.topicPhrase(topic)
        return queue.sync {
            guard let db else { return [] }
            // Is the typed word itself a subject here? That single fact is what
            // licenses the different-person guard below: "Denver" is a place in
            // this corpus, so "Bob Denver" is someone else. "Potter" is not a
            // subject, so "Harry Potter" is the best reading of it.
            let guardNames = tokens.count == 1 && Self.isOwnSubject(db, phrase: phrase)
            let requirePhrase = Self.phraseIsRequired(topic)
            // search_text is the folded mirror of the four text columns, populated
            // only where folding changes something. It is what makes "beyonce"
            // find "Beyoncé": SQL LIKE cannot strip diacritics, so without it every
            // accented subject was invisible to Create (measured: 0 results).
            let clause = tokens.map { _ in "(lower(prompt) LIKE ? OR lower(source_title) LIKE ? OR lower(explanation) LIKE ? OR lower(tags) LIKE ? OR search_text LIKE ?)" }.joined(separator: " OR ")
            // The cap applies BEFORE the ranking below, so it must be generous
            // enough to contain the genuine matches. At 400 it did not: "van gogh"
            // OR-matches 3,310 rows holding 20 real ones, and exactly ZERO of the
            // 20 survived the cut — typing "Vincent van Gogh" returned none of the
            // real van Gogh questions. 4,000 was not enough either once relevance
            // became strict: a common word like "art" OR-matches 19,509 rows and
            // the genuine `Art` ones sit past 4,000 in rowid order. The cap is now
            // only a runaway guard.
            let sql = "SELECT * FROM questions WHERE \(clause) LIMIT 25000"
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
            var idx: Int32 = 1
            for t in tokens {
                let like = "%\(t)%"
                for _ in 0..<5 {
                    sqlite3_bind_text(stmt, idx, like, -1, Self.transientDestructor); idx += 1
                }
            }
            var scored: [(Question, Int, Int)] = []
            var giveaways: [(Question, Int, Int)] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                guard let q = Self.row(stmt) else { continue }
                // Diversity (owner): drop the "which continent is X on" template —
                // easy, repetitive, non-educational — and the trivially-easy tier.
                if q.id.hasPrefix("src:continent:") { continue }
                if q.difficulty <= 1 { continue }
                // A relevance FLOOR, applied before any ranking. Rows that do not
                // clear it are gone, even if nothing better exists — a topic the
                // corpus does not know should fall through to live generation, not
                // be answered with eight confident strangers.
                guard let tier = Self.tier(title: q.sourceTitle, prompt: q.prompt,
                                           tags: q.tags, tokens: tokens, phrase: phrase,
                                           guardNames: guardNames,
                                           requirePhrase: requirePhrase) else { continue }
                // The player typed the topic, so a question whose ANSWER is (or
                // contains) the topic is a giveaway ("Chicago" → answer "Chicago").
                // Prefer questions that are ABOUT the topic but answer with
                // something else — but hold the giveaways in reserve rather than
                // dropping them. For a PERSON the rule is far too broad: of the 20
                // real van Gogh questions, 17 answer "Vincent van Gogh", so a
                // hard drop left 3 and the quiz could not be filled. Reserved rows
                // are only used when the clean pool would otherwise starve.
                let answer = Self.fold(q.correctAnswer)
                let isGiveaway = tokens.contains { Self.containsWord(answer, $0) }
                // Folded, not merely lowercased: the tokens are folded, so an
                // accented row would score 0 against them and be dropped — the
                // pre-filter would surface it and the ranker throw it away.
                let title = Self.fold(q.sourceTitle), prompt = Self.fold(q.prompt)
                let explanation = Self.fold(q.explanation)
                let tags = q.tags.map { Self.fold($0) }
                let score = tokens.reduce(0) { acc, token in
                    acc + (tags.contains { Self.containsWord($0, token) } ? 3 : 0)
                    + (Self.containsWord(title, token) ? 2 : 0)
                    + (Self.containsWord(prompt, token) ? 1 : 0)
                    + (Self.containsWord(explanation, token) ? 1 : 0)
                }
                if isGiveaway { giveaways.append((q, score, tier)) }
                else { scored.append((q, score, tier)) }
            }
            // Fill strictly by tier: exhaust the rows that ARE about the topic
            // before touching the ones merely connected to it, and diversify only
            // WITHIN a tier. Diversifying across tiers is what promoted a
            // one-word coincidence into a category lane — measured on the shipping
            // corpus, "Ansel Adams" returned exactly one row per category (Samuel
            // Adams, Hansel and Gretel, Phil Anselmo, Davante Adams…).
            var out = Self.fillByTier(scored, limit: limit)
            // Starvation top-up: a thin clean pool is worth less to the player than
            // a full quiz, so the reserved giveaways fill the tail.
            if out.count < limit {
                let taken = Set(out.map(\.id))
                out.append(contentsOf: Self.fillByTier(giveaways, limit: limit)
                    .filter { !taken.contains($0.id) }.prefix(limit - out.count))
            }
            return out
        }
    }

    /// Does some row's SUBJECT reduce to exactly this topic? Titles only, grouped,
    /// so it stays cheap — the pre-filter scan is the expensive part, not this.
    private static func isOwnSubject(_ db: OpaquePointer, phrase: String) -> Bool {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        let sql = "SELECT source_title FROM questions WHERE lower(source_title) LIKE ? GROUP BY source_title LIMIT 800"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return false }
        // The phrase can carry stopwords and spaces the stored title punctuates
        // differently, so bind the FIRST significant word and compare properly per
        // row — a LIKE on the whole phrase silently matched nothing.
        sqlite3_bind_text(stmt, 1, "%\(phrase.split(separator: " ").first.map(String.init) ?? phrase)%", -1, transientDestructor)
        while sqlite3_step(stmt) == SQLITE_ROW {
            let title = text(stmt, 0)
            if flattened(title) == phrase { return true }
        }
        return false
    }

    /// Take from the highest occupied relevance tier first, diversifying inside it.
    private static func fillByTier(_ scored: [(Question, Int, Int)], limit: Int) -> [Question] {
        var out: [Question] = []
        for tier in [3, 2, 1, 0, -1] {
            if out.count >= limit { break }
            let lane = scored.filter { $0.2 == tier }.sorted { $0.1 > $1.1 }.map { $0.0 }
            out.append(contentsOf: diversify(lane, limit: limit - out.count))
        }
        return Array(out.prefix(limit))
    }

    /// Round-robin a ranked list across categories, capping any one domain — the
    /// anti-monopoly rule for Create (owner: too many sports/geography questions
    /// when a topic is dense in one category).
    static func diversify(_ ranked: [Question], limit: Int) -> [Question] {
        let perCat = max(2, Int(ceil(Double(limit) / 3)))
        var lanes: [String: [Question]] = [:]
        var order: [String] = []
        for q in ranked {
            let c = q.categoryID
            if lanes[c] == nil { lanes[c] = []; order.append(c) }
            if lanes[c]!.count < perCat { lanes[c]!.append(q) }
        }
        var out: [Question] = []
        var progressed = true
        while out.count < limit && progressed {
            progressed = false
            for c in order {
                if !(lanes[c]?.isEmpty ?? true) {
                    out.append(lanes[c]!.removeFirst()); progressed = true
                    if out.count >= limit { break }
                }
            }
        }
        // The per-category cap is an ANTI-MONOPOLY rule, not a quota: when the
        // relevant pool is genuinely single-domain it must not starve the set.
        // ("Marie Curie" matches 15 questions, all science — capping at 3 turned
        // a requested 8-question quiz into 4.) Top up from the ranked remainder
        // so diversity is preferred where it exists and never costs length.
        if out.count < limit {
            let taken = Set(out.map(\.id))
            out.append(contentsOf: ranked.filter { !taken.contains($0.id) }.prefix(limit - out.count))
        }
        return out.shuffled()
    }

    /// Fetch specific questions by id, returned in the SAME order as `ids`.
    func questions(ids: [String]) -> [Question] {
        guard !ids.isEmpty else { return [] }
        return queue.sync {
            guard let db else { return [] }
            let placeholders = Array(repeating: "?", count: ids.count).joined(separator: ",")
            let sql = "SELECT * FROM questions WHERE id IN (\(placeholders))"
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
            for (i, id) in ids.enumerated() {
                sqlite3_bind_text(stmt, Int32(i + 1), id, -1, Self.transientDestructor)
            }
            var byId: [String: Question] = [:]
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let q = Self.row(stmt) { byId[q.id] = q }
            }
            return ids.compactMap { byId[$0] }
        }
    }

    private static func text(_ stmt: OpaquePointer?, _ col: Int32) -> String {
        guard let c = sqlite3_column_text(stmt, col) else { return "" }
        return String(cString: c)
    }

    private static func row(_ stmt: OpaquePointer?) -> Question? {
        // Column order matches the generator schema (tools/corpus).
        let id = text(stmt, 0)
        let prompt = text(stmt, 1)
        let options = [text(stmt, 2), text(stmt, 3), text(stmt, 4), text(stmt, 5)]
        let correctIndex = Int(sqlite3_column_int(stmt, 6))
        guard !id.isEmpty, !prompt.isEmpty, options.allSatisfy({ !$0.isEmpty }),
              options.indices.contains(correctIndex) else { return nil }
        return Question(
            id: id, prompt: prompt, options: options, correctIndex: correctIndex,
            categoryID: text(stmt, 7),
            difficulty: Int(sqlite3_column_int(stmt, 8)),
            explanation: text(stmt, 9),
            sourceTitle: text(stmt, 10),
            sourceURL: URL(string: text(stmt, 11)),
            templateID: text(stmt, 12),
            tags: text(stmt, 13).split(separator: "|").map(String.init)
        )
    }
}
