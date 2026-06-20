import Foundation

/// Read-only source for a bundled JSON question set — the enrichment-built modes
/// (Picture ID, This-or-That, …) that ride alongside the SQLite corpus on
/// iOS/tvOS. Same compact array shape as corpus.json, optionally with a 10th
/// element (an image URL). One generic loader so each new E1-built mode is a
/// one-line static instance, not another near-duplicate reader.
nonisolated final class JSONQuestionSource: @unchecked Sendable {
    static let picture = JSONQuestionSource(resource: "picture")
    static let thisOrThat = JSONQuestionSource(resource: "thisorthat")
    static let closestCall = JSONQuestionSource(resource: "closest")

    private let all: [Question]

    init(resource: String) {
        guard let url = Bundle.main.url(forResource: resource, withExtension: "json"),
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

    func questions(categoryID: String, excluding seen: Set<String>, limit: Int) -> [Question] {
        let pool = all.filter {
            (categoryID == "mixed" || $0.categoryID == categoryID) && !seen.contains($0.id)
        }
        return Array(pool.shuffled().prefix(limit))
    }

    private static func num(_ v: Any) -> Double? { (v as? NSNumber)?.doubleValue }

    private static func parse(_ r: [Any]) -> Question? {
        guard r.count >= 9, let id = r[0] as? String, let prompt = r[1] as? String else { return nil }
        let template = id.split(separator: ":").first.map(String.init) ?? "json"

        // MCQ rows (corpus / picture / thisorthat): index 2 is the options array.
        if let options = r[2] as? [String] {
            guard options.count >= 2, let correct = r[3] as? Int,
                  options.indices.contains(correct), let cat = r[4] as? String else { return nil }
            let image = (r.count >= 10) ? (r[9] as? String).flatMap(URL.init(string:)) : nil
            return Question(
                id: id, prompt: prompt, options: options, correctIndex: correct,
                categoryID: cat, difficulty: r[5] as? Int ?? 3,
                explanation: r[6] as? String ?? "",
                sourceTitle: r[7] as? String ?? "",
                sourceURL: (r[8] as? String).flatMap(URL.init(string:)),
                templateID: template, imageURL: image)
        }

        // Numeric (Closest Call): [id, prompt, answer, min, max, step, tol, unit,
        // category, explanation, title, url].
        guard r.count >= 12,
              let answer = num(r[2]), let mn = num(r[3]), let mx = num(r[4]),
              let step = num(r[5]), let tol = num(r[6]),
              let unit = r[7] as? String, let cat = r[8] as? String else { return nil }
        let spec = ClosestSpec(answer: answer, min: mn, max: mx, step: step, tolerance: tol, unit: unit)
        return Question(
            id: id, prompt: prompt, options: [], correctIndex: 0,
            categoryID: cat, difficulty: 3,
            explanation: r[9] as? String ?? "",
            sourceTitle: r[10] as? String ?? "",
            sourceURL: (r[11] as? String).flatMap(URL.init(string:)),
            templateID: template, closest: spec)
    }
}
