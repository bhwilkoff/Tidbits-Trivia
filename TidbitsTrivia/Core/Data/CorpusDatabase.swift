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
            templateID: text(stmt, 12)
        )
    }
}
