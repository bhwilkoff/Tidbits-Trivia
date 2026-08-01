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
    static let ordering = JSONQuestionSource(resource: "order")
    static let matching = JSONQuestionSource(resource: "match")
    static let typeAnswer = JSONQuestionSource(resource: "typeanswer")
    static let oddOneOut = JSONQuestionSource(resource: "oddoneout")
    static let enumerate = JSONQuestionSource(resource: "enumerate")

    private let all: [Question]
    private let byID: [String: Question]

    init(resource: String) {
        guard let url = Bundle.main.url(forResource: resource, withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rows = root["questions"] as? [[Any]] else {
            all = []
            byID = [:]
            return
        }
        all = rows.compactMap(Self.parse)
        byID = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    }

    var isAvailable: Bool { !all.isEmpty }
    var count: Int { all.count }

    /// Look up by ID — what a saved quiz needs to turn its refs back into questions
    /// (docs/QUIZ-CONTRACT.md). Built once in `init` rather than cached lazily: these
    /// sources are shared `static let` singletons, so a mutable cache would be
    /// exactly the nonisolated global shared state Swift 6 rejects.
    func question(id: String) -> Question? { byID[id] }

    func questions(categoryID: String, excluding seen: Set<String>, limit: Int) -> [Question] {
        let pool = all.filter {
            (categoryID == "mixed" || $0.categoryID == categoryID) && !seen.contains($0.id)
        }
        return Array(pool.shuffled().prefix(limit))
    }

    /// Topic-matched pull (Create shape variety): questions whose prompt/title
    /// mention a topic token but whose answer doesn't give it away.
    func searchMatch(topic: String, limit: Int) -> [Question] {
        let tokens = CorpusDatabase.topicTokens(topic)
        guard !tokens.isEmpty else { return [] }
        // Same rule as the corpus search: a topic that is nothing but stopwords
        // ("From") matches everything containing that word, and a picture round
        // showing the wrong subject is worse than no picture round.
        guard tokens.contains(where: { !CorpusDatabase.isStopword($0) }) else { return [] }
        let phrase = CorpusDatabase.topicPhrase(topic)
        // The SAME relevance floor the corpus search uses, for the same reason: a
        // picture round that shows the wrong subject is worse than no picture
        // round. Substring matching alone surfaced "In what year did Jean-Marie
        // Le Pen die?" for "Marie Curie", and the shape sources have no live
        // fallback to dilute a bad hit — the whole round is one question.
        let scored: [(Question, Int)] = all.compactMap { q in
            let ans = CorpusDatabase.fold(q.correctAnswer)
            if tokens.contains(where: { CorpusDatabase.containsWord(ans, $0) }) { return nil }
            guard let tier = CorpusDatabase.tier(
                title: q.sourceTitle, prompt: q.prompt, tags: q.tags,
                tokens: tokens, phrase: phrase, guardNames: false) else { return nil }
            return (q, tier)
        }
        guard let best = scored.map(\.1).max() else { return [] }
        return Array(scored.filter { $0.1 == best }.map(\.0).shuffled().prefix(limit))
    }

    private static func num(_ v: Any) -> Double? { (v as? NSNumber)?.doubleValue }

    private static func parse(_ r: [Any]) -> Question? {
        guard r.count >= 6, let id = r[0] as? String, let prompt = r[1] as? String else { return nil }
        let template = id.split(separator: ":").first.map(String.init) ?? "json"

        // Enumeration (Q8): [id, prompt, groups([[String]]), cat, seconds, url].
        // Branch first: only 6 columns, and r[2] is an array-of-arrays.
        if let groups = r[2] as? [[String]] {
            guard let cat = r[3] as? String, !groups.isEmpty else { return nil }
            let url = (r.count > 5) ? (r[5] as? String).flatMap(URL.init(string:)) : nil
            return Question(
                id: id, prompt: prompt, options: [], correctIndex: 0,
                categoryID: cat, difficulty: 3,
                explanation: "", sourceTitle: "", sourceURL: url,
                templateID: template, enumerate: EnumSpec(groups: groups))
        }

        guard r.count >= 8 else { return nil }

        // index 2 is an array → MCQ (corpus/picture/thisorthat) or Ordering.
        if let arr2 = r[2] as? [String] {
            if let correct = r[3] as? Int {
                // MCQ
                guard arr2.count >= 2, arr2.indices.contains(correct), let cat = r[4] as? String else { return nil }
                let image = (r.count >= 10) ? (r[9] as? String).flatMap(URL.init(string:)) : nil
                return Question(
                    id: id, prompt: prompt, options: arr2, correctIndex: correct,
                    categoryID: cat, difficulty: r[5] as? Int ?? 3,
                    explanation: r[6] as? String ?? "",
                    sourceTitle: r[7] as? String ?? "",
                    sourceURL: (r[8] as? String).flatMap(URL.init(string:)),
                    templateID: template, imageURL: image)
            }
            // Matching: r[3] is a STRING array (the values). Ordering: r[3] is an INT array (years).
            guard arr2.count >= 2, r.count >= 8, let cat = r[4] as? String else { return nil }
            if let values = r[3] as? [String] {
                return Question(
                    id: id, prompt: prompt, options: arr2, correctIndex: 0,
                    categoryID: cat, difficulty: 3,
                    explanation: r[5] as? String ?? "", sourceTitle: "", sourceURL: nil,
                    templateID: template, matching: MatchSpec(keys: arr2, values: values))
            }
            return Question(
                id: id, prompt: prompt, options: arr2, correctIndex: 0,
                categoryID: cat, difficulty: 3,
                explanation: r[5] as? String ?? "",
                sourceTitle: r[6] as? String ?? "",
                sourceURL: (r[7] as? String).flatMap(URL.init(string:)),
                templateID: template, ordering: arr2)
        }

        // Type-the-answer: [id, prompt, answer(string), accepted(strings), cat, expl, title, url].
        if let answer = r[2] as? String, let accepted = r[3] as? [String] {
            guard r.count >= 8, let cat = r[4] as? String else { return nil }
            return Question(
                id: id, prompt: prompt, options: [answer], correctIndex: 0,
                categoryID: cat, difficulty: 3,
                explanation: r[5] as? String ?? "",
                sourceTitle: r[6] as? String ?? "",
                sourceURL: (r[7] as? String).flatMap(URL.init(string:)),
                templateID: template, accepted: accepted)
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
