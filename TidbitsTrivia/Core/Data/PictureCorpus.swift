import Foundation

/// Read-only source for Picture ID (Q7) — the bundled `picture.json` built by
/// `tools/corpus/gen_picture.py` from the corpus + E1 enrichment. Same compact
/// array shape as corpus.json plus a 10th element (the Commons image URL).
/// Held in memory (816 small rows); iOS/tvOS bundle this alongside corpus.sqlite
/// since their corpus is SQLite, not JSON.
nonisolated final class PictureCorpus: @unchecked Sendable {
    static let shared = PictureCorpus()

    private let all: [Question]

    private init() {
        guard let url = Bundle.main.url(forResource: "picture", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rows = root["questions"] as? [[Any]] else {
            all = []
            return
        }
        all = rows.compactMap(Self.parse)
    }

    var isAvailable: Bool { !all.isEmpty }
    var count: Int { all.count }

    /// Random picture questions in a category (mixed spans all), excluding seen.
    func questions(categoryID: String, excluding seen: Set<String>, limit: Int) -> [Question] {
        let pool = all.filter {
            (categoryID == "mixed" || $0.categoryID == categoryID) && !seen.contains($0.id)
        }
        return Array(pool.shuffled().prefix(limit))
    }

    private static func parse(_ r: [Any]) -> Question? {
        guard r.count >= 10,
              let id = r[0] as? String,
              let prompt = r[1] as? String,
              let options = r[2] as? [String], options.count == 4,
              let correct = r[3] as? Int,
              let cat = r[4] as? String,
              let image = r[9] as? String, let imageURL = URL(string: image)
        else { return nil }
        let diff = r[5] as? Int ?? 3
        let expl = r[6] as? String ?? ""
        let title = r[7] as? String ?? ""
        let urlStr = r[8] as? String ?? ""
        return Question(
            id: id, prompt: prompt, options: options, correctIndex: correct,
            categoryID: cat, difficulty: diff, explanation: expl,
            sourceTitle: title, sourceURL: URL(string: urlStr),
            templateID: "picture", imageURL: imageURL)
    }
}
