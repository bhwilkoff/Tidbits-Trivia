import Foundation

/// A quiz the player created and kept — the first user-authored object in Tidbits,
/// so it is a wire contract before it is a screen (docs/QUIZ-CONTRACT.md).
///
/// A quiz stores question REFERENCES, not question text: every platform already
/// ships the corpus, so a 20-question quiz is under 1KB and costs nothing to sync,
/// host, or put in a URL. Only live-generated questions (always plain MCQ, because
/// the corpus was thin on that topic) travel inline, in the exact `corpus.json` row
/// shape every stack already decodes.
///
/// Mirrored by Kotlin `SavedQuiz.kt`, C# `SavedQuiz.cs` and JS `quiz.js`; pinned by
/// the shared fixture in `tools/quiz-wire/golden/`.
nonisolated struct SavedQuiz: Identifiable, Hashable, Sendable {

    /// One entry in the ordered question list.
    ///
    /// - `ref`     — a CORPUS question ID (a bare string on the wire; the common case)
    /// - `setRef`  — a BUNDLED-SET question, carrying which set it came from
    /// - `inline`  — a live-generated MCQ, in `corpus.json` row shape
    ///
    /// `setRef` exists because a bare ID is genuinely ambiguous: the bundled sets
    /// share the corpus `src:` namespace, and 166 of 200 sampled Picture ID rows
    /// have an ID that ALSO exists in the corpus as a different question shape. A
    /// saved picture question therefore came back as a text question with the same
    /// four options — the exact silent substitution §1 forbids. Caught on the
    /// simulator by replaying a quiz and seeing question 1 lose its photograph.
    enum Entry: Hashable, Sendable {
        case ref(String)
        case setRef(set: String, id: String)
        case inline(InlineQuestion)
    }

    let id: String
    var title: String
    let topic: String
    let creatorID: String
    let creatorName: String
    let createdAt: Date
    var mode: String
    var entries: [Entry]

    var questionCount: Int { entries.count }

    // MARK: Creating

    /// The ID alphabet: Crockford-style, with 0/o, 1/l/i and u removed so an ID read
    /// aloud in a pub or typed off a projector is unambiguous (u also keeps a random
    /// ID from spelling something unfortunate). 30 chars: 30^10 ~= 5.9e14.
    static let idAlphabet = Array("23456789abcdefghjkmnpqrstvwxyz")
    static let idLength = 10

    /// Random, never derived from content: two people who both make a "Jazz" quiz
    /// must get different IDs, and an ID must not leak what is inside it. The random
    /// source is injectable so the codec can be tested deterministically.
    static func makeID(using rng: inout some RandomNumberGenerator) -> String {
        String((0..<idLength).map { _ in idAlphabet.randomElement(using: &rng)! })
    }

    static func makeID() -> String {
        var rng = SystemRandomNumberGenerator()
        return makeID(using: &rng)
    }

    /// Build from a played/generated set. Questions already in a bundled source
    /// become refs; anything else (a live Wikipedia MCQ) is inlined.
    static func from(questions: [Question], topic: String, title: String? = nil,
                     mode: String = "mix", creatorID: String, creatorName: String,
                     id: String? = nil, createdAt: Date = Date()) -> SavedQuiz {
        SavedQuiz(
            id: id ?? makeID(),
            title: Self.cleanTitle(title ?? topic),
            topic: topic,
            creatorID: creatorID,
            creatorName: creatorName,
            createdAt: createdAt,
            mode: mode,
            entries: questions.map { q in
                if q.isLiveGenerated { return .inline(InlineQuestion(q)) }
                if let set = q.bundledSetName { return .setRef(set: set, id: q.id) }
                return .ref(q.id)
            }
        )
    }

    /// Titles ride in share cards and list rows, so they are trimmed and capped
    /// rather than rejected — a long paste should still save.
    static func cleanTitle(_ raw: String) -> String {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = t.isEmpty ? "Untitled quiz" : t
        return fallback.count <= 60 ? fallback : String(fallback.prefix(60))
    }

    // MARK: Resolving

    /// What a reader got back after resolving refs against the local corpus.
    /// Refs go missing legitimately (older build, retired row, a bundled set a
    /// platform doesn't ship), so this reports the shortfall instead of hiding it.
    struct Resolution: Sendable {
        let questions: [Question]
        let missing: Int
        var isPlayable: Bool { questions.count >= SavedQuiz.minimumPlayable }
        var isComplete: Bool { missing == 0 }
    }

    /// Below this a quiz isn't worth playing; above it we play and say so.
    static let minimumPlayable = 3

    /// Resolve in order, keeping inline questions verbatim. `lookup` returns nil for
    /// an ID this build can't resolve. Never substitutes a different question — a
    /// shared quiz that quietly changes content is worse than an incomplete one.
    func resolve(lookup: (String) -> Question?,
                 setLookup: (String, String) -> Question? = { _, _ in nil }) -> Resolution {
        var out: [Question] = []
        var missing = 0
        for entry in entries {
            switch entry {
            case .ref(let id):
                if let q = lookup(id) { out.append(q) } else { missing += 1 }
            case .setRef(let set, let id):
                // Deliberately does NOT fall back to the corpus: the corpus holds a
                // DIFFERENT question under this ID, and serving it would be the
                // silent substitution the contract forbids. Better to be one short.
                if let q = setLookup(set, id) { out.append(q) } else { missing += 1 }
            case .inline(let i):
                out.append(i.question())
            }
        }
        return Resolution(questions: out, missing: missing)
    }
}

// MARK: - Inline questions

/// A live-generated MCQ carried inside a quiz, in the `corpus.json` row shape:
/// `[id, prompt, [o0,o1,o2,o3], correctIndex, category, difficulty, explanation,
///   sourceTitle, sourceURL]`. Reusing the corpus row is the whole point — every
/// stack already decodes it, so the six implementations cannot drift.
nonisolated struct InlineQuestion: Hashable, Sendable {
    let id: String
    let prompt: String
    let options: [String]
    let correctIndex: Int
    let categoryID: String
    let difficulty: Int
    let explanation: String
    let sourceTitle: String
    let sourceURL: String

    init(_ q: Question) {
        id = q.id
        prompt = q.prompt
        options = q.options
        correctIndex = q.correctIndex
        categoryID = q.categoryID
        difficulty = q.difficulty
        explanation = q.explanation
        sourceTitle = q.sourceTitle
        sourceURL = q.sourceURL?.absoluteString ?? ""
    }

    init?(row: [Any]) {
        guard row.count >= 9,
              let id = row[0] as? String,
              let prompt = row[1] as? String,
              let options = row[2] as? [String], options.count == 4,
              let correctIndex = row[3] as? Int,
              let categoryID = row[4] as? String,
              let difficulty = row[5] as? Int,
              let explanation = row[6] as? String,
              let sourceTitle = row[7] as? String else { return nil }
        self.id = id
        self.prompt = prompt
        self.options = options
        self.correctIndex = correctIndex
        self.categoryID = categoryID
        self.difficulty = difficulty
        self.explanation = explanation
        self.sourceTitle = sourceTitle
        self.sourceURL = row[8] as? String ?? ""
    }

    var row: [Any] {
        [id, prompt, options, correctIndex, categoryID, difficulty, explanation,
         sourceTitle, sourceURL]
    }

    func question() -> Question {
        Question(id: id, prompt: prompt, options: options, correctIndex: correctIndex,
                 categoryID: categoryID, difficulty: difficulty, explanation: explanation,
                 sourceTitle: sourceTitle, sourceURL: URL(string: sourceURL),
                 templateID: id.split(separator: ":").first.map(String.init) ?? "live")
    }
}

extension Question {
    /// Live Wikipedia generation is the only source that isn't addressable by ID
    /// from a bundled file, so it is the only thing a quiz has to carry inline.
    /// `nonisolated` because the project defaults to MainActor isolation and the
    /// codec runs off the main actor.
    nonisolated var isLiveGenerated: Bool { id.hasPrefix("live:") || templateID == "live" }

    /// Which bundled set this question came from, or nil for a plain corpus row.
    ///
    /// Derived from the question's SHAPE rather than threaded through from the call
    /// site, so it stays correct no matter which surface built the set. The shaped
    /// payloads are mutually exclusive by construction, and the two shapes with no
    /// payload of their own (This-or-That, Odd-one-out) own their ID prefix.
    nonisolated var bundledSetName: String? {
        if imageURL != nil { return "picture" }
        if closest != nil { return "closest" }
        if ordering != nil { return "order" }
        if matching != nil { return "match" }
        if accepted != nil { return "typeanswer" }
        if enumerate != nil { return "enumerate" }
        if id.hasPrefix("tot:") { return "thisorthat" }
        if id.hasPrefix("odd:") { return "oddoneout" }
        return nil
    }
}

// MARK: - Wire codec (docs/QUIZ-CONTRACT.md §2)

nonisolated extension SavedQuiz {

    /// Terse keys because this object rides in share URLs and RTDB. Renaming one is
    /// a breaking change; readers must ignore keys they don't know.
    func wire() -> [String: Any] {
        [
            "v": 1,
            "id": id,
            "t": title,
            "tp": topic,
            "by": creatorID,
            "bn": creatorName,
            "at": Int(createdAt.timeIntervalSince1970 * 1000),
            "m": mode,
            "qs": entries.map { entry -> Any in
                switch entry {
                case .ref(let r): return r
                case .setRef(let set, let id): return ["s": set, "i": id]
                case .inline(let i): return i.row
                }
            },
        ]
    }

    /// Lenient by contract: unknown keys are ignored and a malformed entry is
    /// skipped rather than failing the whole quiz, because these objects outlive
    /// the app version that wrote them.
    init?(wire: [String: Any]) {
        guard let id = wire["id"] as? String, !id.isEmpty,
              let by = wire["by"] as? String,
              let qs = wire["qs"] as? [Any] else { return nil }
        self.id = id
        self.title = SavedQuiz.cleanTitle(wire["t"] as? String ?? "")
        self.topic = wire["tp"] as? String ?? ""
        self.creatorID = by
        self.creatorName = wire["bn"] as? String ?? ""
        let ms = (wire["at"] as? Int) ?? (wire["at"] as? Double).map(Int.init) ?? 0
        self.createdAt = Date(timeIntervalSince1970: Double(ms) / 1000)
        self.mode = wire["m"] as? String ?? "mix"
        self.entries = qs.compactMap { raw in
            if let s = raw as? String { return s.isEmpty ? nil : .ref(s) }
            if let o = raw as? [String: Any], let set = o["s"] as? String, let id = o["i"] as? String {
                return set.isEmpty || id.isEmpty ? nil : .setRef(set: set, id: id)
            }
            if let row = raw as? [Any], let i = InlineQuestion(row: row) { return .inline(i) }
            return nil
        }
    }

    /// JSON for local files and RTDB. `sortedKeys` so two devices writing the same
    /// quiz produce byte-identical output — that is what makes the merge guard in
    /// QUIZ-CONTRACT §4 ("created or deleted, never edited in place") checkable.
    ///
    /// `withoutEscapingSlashes` is load-bearing for CROSS-STACK identity, not
    /// cosmetics: Foundation escapes `/` as `\/` by default and JS/Kotlin/C# do not,
    /// so every quiz carrying a Wikipedia URL would differ byte-for-byte between
    /// Apple and everyone else while decoding to exactly the same object.
    func jsonData() -> Data? {
        try? JSONSerialization.data(withJSONObject: wire(),
                                    options: [.sortedKeys, .withoutEscapingSlashes])
    }

    init?(jsonData: Data) {
        guard let obj = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else { return nil }
        self.init(wire: obj)
    }
}
