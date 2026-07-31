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
    private static let stopwords: Set<String> = [
        "the", "and", "for", "with", "from", "that", "this", "his", "her", "its",
        "was", "were", "are", "who", "what", "which", "how", "why", "all", "any",
    ]

    func search(topic: String, limit: Int) -> [Question] {
        // Stopwords are dropped, not merely short words: the >=3 rule kept "the",
        // which matches nearly every row and so GUARANTEED the pre-filter cap below
        // to fill with noise for any topic containing it ("The Beatles", "The
        // Simpsons"). Falls back to the raw tokens if a topic is nothing but
        // stopwords, so a query is never left empty.
        let rawTokens = topic.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init).filter { $0.count >= 3 }
        let kept = rawTokens.filter { !Self.stopwords.contains($0) }
        let tokens = kept.isEmpty ? rawTokens : kept
        guard !tokens.isEmpty else { return [] }
        return queue.sync {
            guard let db else { return [] }
            let clause = tokens.map { _ in "(lower(prompt) LIKE ? OR lower(source_title) LIKE ? OR lower(explanation) LIKE ? OR lower(tags) LIKE ?)" }.joined(separator: " OR ")
            // The cap applies BEFORE the ranking below, so it must be generous
            // enough to contain the genuine matches. At 400 it did not: "van gogh"
            // OR-matches 3,310 rows holding 20 real ones, and exactly ZERO of the
            // 20 survived the cut — typing "Vincent van Gogh" returned none of the
            // real van Gogh questions. 4000 covers the measured worst case; the
            // ranking still trims to `limit`.
            let sql = "SELECT * FROM questions WHERE \(clause) LIMIT 4000"
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
            var idx: Int32 = 1
            for t in tokens {
                let like = "%\(t)%"
                sqlite3_bind_text(stmt, idx, like, -1, Self.transientDestructor); idx += 1
                sqlite3_bind_text(stmt, idx, like, -1, Self.transientDestructor); idx += 1
                sqlite3_bind_text(stmt, idx, like, -1, Self.transientDestructor); idx += 1
                sqlite3_bind_text(stmt, idx, like, -1, Self.transientDestructor); idx += 1
            }
            var scored: [(Question, Int, Int)] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                guard let q = Self.row(stmt) else { continue }
                // The player typed the topic, so a question whose ANSWER is (or
                // contains) the topic is a giveaway ("Chicago" → answer "Chicago").
                // Keep only questions that are ABOUT the topic but answer with
                // something else.
                let answer = q.correctAnswer.lowercased()
                if tokens.contains(where: { answer.contains($0) }) { continue }
                // Diversity (owner): drop the "which continent is X on" template —
                // easy, repetitive, non-educational — and the trivially-easy tier.
                if q.id.hasPrefix("src:continent:") { continue }
                if q.difficulty <= 1 { continue }
                let title = q.sourceTitle.lowercased(), prompt = q.prompt.lowercased(), explanation = q.explanation.lowercased()
                let tags = q.tags.map { $0.lowercased() }
                let score = tokens.reduce(0) { acc, token in
                    acc + (tags.contains { $0.contains(token) } ? 3 : 0)
                    + (title.contains(token) ? 2 : 0) + (prompt.contains(token) ? 1 : 0) + (explanation.contains(token) ? 1 : 0)
                }
                // How many of the typed words this row matched AT ALL. The SQL
                // clause is an OR (a row need match only one token), so for a
                // multi-word topic this is what separates "about the subject"
                // from "shares a common word with it".
                let matched = tokens.filter { token in
                    tags.contains { $0.contains(token) } || title.contains(token)
                        || prompt.contains(token) || explanation.contains(token)
                }.count
                scored.append((q, score, matched))
            }
            // Keep only the rows matching the MOST of the typed words, then rank
            // and diversify within that tier.
            //
            // Without this, `diversify` round-robins by CATEGORY over the whole
            // OR-matched pool, so a one-word coincidence gets PROMOTED to fill a
            // category lane. Measured on the shipping corpus: "Marie Curie" has
            // 15 genuine two-word matches (all science) but 211 one-word hits
            // across 7 categories, 189 of which never mention Curie — so the
            // generated quiz led with "In what year was Marie de' Medici born?".
            // Single-word topics are unaffected (every row ties at 1).
            let bestMatched = scored.map(\.2).max() ?? 0
            let relevant = scored.filter { $0.2 == bestMatched }
            let ranked = relevant.sorted { $0.1 > $1.1 }.map { $0.0 }
            return Self.diversify(ranked, limit: limit)
        }
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
