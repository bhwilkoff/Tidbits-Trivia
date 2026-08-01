import Foundation

/// The single source of questions for any game. Decides between the
/// bundled corpus (fast, offline, never-repeat) and live Wikipedia
/// generation (infinite, any topic), tracks what the player has seen so
/// they "never see the same question twice," and seeds the Daily puzzle
/// deterministically. Views never touch CorpusDatabase or the engine
/// directly — same rule as APIClient.
@MainActor
final class QuestionProvider {
    static let shared = QuestionProvider()

    private let seenKey = "tidbits.seenQuestionIDs"
    private(set) var seen: Set<String>

    private init() {
        let stored = UserDefaults.standard.stringArray(forKey: seenKey) ?? []
        seen = Set(stored)
    }

    var corpusCount: Int { CorpusDatabase.shared.count }

    func markSeen(_ ids: [String]) {
        seen.formUnion(ids)
        // Cap the persisted set so it can't grow unbounded; once we near
        // the corpus size, recycling is fine (the player has seen most).
        if seen.count > 9000 { seen.removeAll() }
        UserDefaults.standard.set(Array(seen), forKey: seenKey)
    }

    func resetSeen() {
        seen.removeAll()
        UserDefaults.standard.removeObject(forKey: seenKey)
    }

    // MARK: Question sourcing

    /// Questions for a standard game. Tries the corpus first; if it can't
    /// supply enough fresh questions, tops up with live generation.
    func questions(mode: GameMode, category: TriviaCategory, dailyDay: String? = nil) async -> [Question] {
        let need = min(mode.questionCount, mode == .timeAttack ? 25 : mode.questionCount)
        if mode == .daily { return await dailyQuestions(category: category, day: dailyDay ?? Self.dayKey()) }
        // Enrichment-built modes ride their own bundled JSON source (E1).
        if mode == .pictureId {
            return filled(.picture, category: category, need: need, excluding: seen)
        }
        if mode == .thisOrThat {
            return filled(.thisOrThat, category: category, need: need, excluding: seen)
        }
        if mode == .closestCall {
            return filled(.closestCall, category: category, need: need, excluding: seen)
        }
        if mode == .ordering {
            return filled(.ordering, category: category, need: need, excluding: seen)
        }
        if mode == .matching {
            return filled(.matching, category: category, need: need, excluding: seen)
        }
        if mode == .typeAnswer {
            return filled(.typeAnswer, category: category, need: need, excluding: seen)
        }
        if mode == .oddOneOut {
            // Every category now has odd-one-out coverage — honor the picked
            // category (filled() relaxes to the whole pool for safety).
            return filled(.oddOneOut, category: category, need: need, excluding: seen)
        }
        if mode == .enumerate {
            // Enumeration is a REPLAYABLE recall drill — naming the countries of
            // Asia again is the point, not a spoiler — so ignore the seen-set
            // (pass []). filled() honors the category with a mixed fallback.
            return filled(.enumerate, category: category, need: need, excluding: [])
        }
        if mode == .ladder {
            // Pull a pool, sort by the F3 derived difficulty, then span easy→hard.
            // The pool has to come from the PICKED category: this asked for "mixed"
            // regardless, so a Ladder run in Geography delivered whatever share of
            // the mixed corpus happens to be geography — measured over 800 Ladder
            // questions, 13% of them matched the category the player chose.
            var pool = CorpusDatabase.shared.questions(categoryID: category.id, excluding: seen, limit: 80)
            pool.sort { DifficultyOverlay.shared.difficulty(for: $0) < DifficultyOverlay.shared.difficulty(for: $1) }
            guard pool.count >= need else { return pool }
            return (0..<need).map { pool[$0 * (pool.count - 1) / max(1, need - 1)] }
        }

        var pulled = CorpusDatabase.shared.questions(
            categoryID: category.id, excluding: seen, limit: need)

        if pulled.count < need {
            // Corpus exhausted or thin → live top-up (infinite supply).
            let topic = category.id == "mixed" ? "popular" : category.name
            let live = await liveQuestions(topic: topic, category: category, count: need - pulled.count)
            pulled.append(contentsOf: live)
        }
        return Array(pulled.prefix(need))
    }

    /// The bundled source a mode draws from, or nil when it rides the corpus.
    static func source(for mode: GameMode) -> JSONQuestionSource? {
        switch mode {
        case .pictureId:   return .picture
        case .thisOrThat:  return .thisOrThat
        case .closestCall: return .closestCall
        case .ordering:    return .ordering
        case .matching:    return .matching
        case .typeAnswer:  return .typeAnswer
        case .oddOneOut:   return .oddOneOut
        case .enumerate:   return .enumerate
        default:           return nil
        }
    }

    /// How many questions this mode can draw from the player's OWN picked category.
    ///
    /// `filled()` deliberately relaxes to the whole pool rather than strand a
    /// player mid-round, which is the right behaviour — but it is silent, and
    /// silence here reads as a lie: measured over 1,260 games, picking Business
    /// with any of the seven bundled-shape modes returned a round with ZERO
    /// business questions in it, because none of those sources has a single
    /// business row. The picker uses this to say so before the player commits.
    static func coverage(mode: GameMode, categoryID: String) -> Int {
        guard categoryID != "mixed" else { return .max }
        if let src = source(for: mode) { return src.count(categoryID: categoryID) }
        return CorpusDatabase.shared.count(categoryID: categoryID)
    }

    /// Whether a round of `mode` in `categoryID` can actually be filled from that
    /// category. False means the round will be assembled from other categories.
    static func canFill(mode: GameMode, categoryID: String) -> Bool {
        coverage(mode: mode, categoryID: categoryID) >= mode.questionCount
    }

    /// Build a Trivia Night ("bar trivia") question stream from a plan: for each
    /// round, pull `count` questions of that round's TYPE (reusing the same
    /// per-type sourcing the standard game uses), tag them with the round index,
    /// and concatenate. The mixed list runs through the shape-routing engine, so
    /// one night naturally exercises every question type (the whole point).
    func nightQuestions(plan: NightPlan, category: TriviaCategory) async -> [Question] {
        var all: [Question] = []
        var picked = Set<String>()   // avoid intra-night repeats across rounds
        for (ri, round) in plan.rounds.enumerated() {
            let qs = await sourced(type: round.kind, category: category,
                                   count: round.count, excluding: seen.union(picked))
            for var q in qs {
                q.roundIndex = ri
                all.append(q)
                picked.insert(q.id)
            }
        }
        markSeen(all.map(\.id))
        return all
    }

    /// Never-empty per-type pull for the category-filtered special types: try the
    /// picked category, then relax to the whole type pool ("mixed") to top up
    /// short/empty combos (e.g. sports×matching → 0 rows), then — only if the type
    /// file failed to load entirely — a Classic corpus backstop so the player is
    /// never stranded. Keeps the MODE pure (a Match Up round stays Match Up).
    private func filled(_ source: JSONQuestionSource, category: TriviaCategory, need: Int, excluding: Set<String>) -> [Question] {
        var qs = source.questions(categoryID: category.id, excluding: excluding, limit: need)
        if qs.count < need && category.id != "mixed" {
            let have = excluding.union(qs.map(\.id))
            qs.append(contentsOf: source.questions(categoryID: "mixed", excluding: have, limit: need - qs.count))
        }
        if qs.isEmpty {
            qs = CorpusDatabase.shared.questions(categoryID: category.id, excluding: excluding, limit: need)
        }
        return qs
    }

    /// Source `count` questions of one TYPE, the same way `questions(mode:)`
    /// does per mode — factored out so the night builder reuses it exactly.
    private func sourced(type: GameMode, category: TriviaCategory, count: Int, excluding: Set<String>) async -> [Question] {
        switch type {
        case .pictureId:   return filled(.picture, category: category, need: count, excluding: excluding)
        case .thisOrThat:  return filled(.thisOrThat, category: category, need: count, excluding: excluding)
        case .closestCall: return filled(.closestCall, category: category, need: count, excluding: excluding)
        case .ordering:    return filled(.ordering, category: category, need: count, excluding: excluding)
        case .matching:    return filled(.matching, category: category, need: count, excluding: excluding)
        case .typeAnswer:  return filled(.typeAnswer, category: category, need: count, excluding: excluding)
        case .oddOneOut:   return filled(.oddOneOut, category: category, need: count, excluding: excluding)
        case .enumerate:   return filled(.enumerate, category: category, need: count, excluding: [])
        default:
            // General-knowledge MCQ round — corpus first (offline), live top-up if thin.
            var pulled = CorpusDatabase.shared.questions(categoryID: category.id, excluding: excluding, limit: count)
            if pulled.count < count {
                let topic = category.id == "mixed" ? "popular" : category.name
                let live = await liveQuestions(topic: topic, category: category, count: count - pulled.count)
                pulled.append(contentsOf: live)
            }
            return Array(pulled.prefix(count))
        }
    }

    /// A fixed-size question set for a party game — the SAME questions for
    /// every player (fairness), pulled once and marked seen.
    func questions(category: TriviaCategory, count: Int) async -> [Question] {
        var pulled = CorpusDatabase.shared.questions(
            categoryID: category.id, excluding: seen, limit: count)
        if pulled.count < count {
            let topic = category.id == "mixed" ? "popular" : category.name
            let live = await liveQuestions(topic: topic, category: category, count: count - pulled.count)
            pulled.append(contentsOf: live)
        }
        let set = Array(pulled.prefix(count))
        markSeen(set.map(\.id))
        return set
    }

    /// Live generation from any Wikipedia topic — powers "create a quiz on
    /// the fly" and the corpus fallback.
    func liveQuestions(topic: String, category: TriviaCategory, count: Int) async -> [Question] {
        let diag = ProcessInfo.processInfo.environment["TIDBITS_CREATE_DIAG"] == "1"
        do {
            let titles = try await WikipediaClient.shared.search(topic, limit: 35)
            guard !titles.isEmpty else {
                if diag { print("DIAG\t\(topic)\tsearch=0") }
                return []
            }
            // Wikipedia's search returns what is RELATED to the topic, not what is
            // about it: "Zendaya" brings back Tom Holland, Law Roach and Dune. A
            // question about Dune in a Zendaya quiz is the same unintended-question
            // failure the corpus ranker was just fixed for, so an article earns its
            // place only if it actually names the topic. There is no fallback to
            // the unfiltered set: a short quiz about the right subject is the
            // point, and the whole set is what produced Tom Holland questions in a
            // Zendaya quiz. The article the player asked for always qualifies —
            // its own title is part of the haystack.
            let all = await WikipediaClient.shared.summaries(for: titles)
            let tokens = CorpusDatabase.topicTokens(topic)
            let phrase = CorpusDatabase.topicPhrase(topic)
            // The whole PHRASE, not each word separately. Requiring only the words
            // let "Albert Einstein" through Bob Einstein, whose summary happens to
            // name his brother Albert; and the same different-person guard the
            // corpus ranker uses is needed here too, or "Denver" fetches John
            // Denver straight from Wikipedia after the corpus correctly refused him.
            let selfSubject = all.contains { CorpusDatabase.flattened($0.title) == phrase }
            let guardNames = tokens.count == 1 && selfSubject
            let summaries = all.filter { s in
                let subject = CorpusDatabase.flattened(s.title)
                if guardNames, subject != phrase, subject.split(separator: " ").count == 2,
                   CorpusDatabase.containsWord(subject, phrase) {
                    return false
                }
                let hay = CorpusDatabase.fold(s.title + " " + (s.extract ?? "") + " " + (s.description ?? ""))
                return CorpusDatabase.containsWord(hay, phrase)
            }
            if diag {
                print("DIAG\t\(topic)\tontopic=\(summaries.count)/\(all.count)")
                let usable = summaries.filter { TemplateEngine.isUsable($0, relaxed: true) }
                var types: [String: Int] = [:]
                for u in usable { types[TemplateEngine.typeKey(u) ?? "nil", default: 0] += 1 }
                print("DIAG\t\(topic)\tsearch=\(titles.count)\tsummaries=\(summaries.count)"
                      + "\tusable=\(usable.count)\tai=\(DelightfulQuizGenerator.isAvailable)"
                      + "\ttypes=\(types.sorted { $0.value > $1.value }.prefix(4).map { "\($0.key):\($0.value)" }.joined(separator: ","))")
            }
            // Apple Intelligence (Foundation Models) writes delightful, grounded
            // questions on-device when available; otherwise fall back to the
            // template engine so Create works on every platform/device.
            if DelightfulQuizGenerator.isAvailable {
                let ai = await DelightfulQuizGenerator.generate(
                    topic: topic, summaries: summaries, categoryID: category.id, count: count)
                if diag { print("DIAG\t\(topic)\tai_questions=\(ai.count)") }
                if ai.count >= min(count, 3) { return ai }
            }
            let templated = TemplateEngine.makeQuestions(
                pool: summaries, categoryID: category.id, count: count,
                seed: topic.stableSeed, relaxed: true, distractors: all)
            if diag { print("DIAG\t\(topic)\ttemplate_questions=\(templated.count)") }
            return templated
        } catch {
            return []
        }
    }

    /// Custom Mix (multi-select Customize): pull from EVERY selected mode and
    /// shuffle them together — one game, many shapes, no rounds. The engine's
    /// shape-driven clock/guards (built for Trivia Night) render each question
    /// by its own shape, so this is a pure sourcing concern.
    func mixQuestions(modes: [GameMode], category: TriviaCategory, count: Int) async -> [Question] {
        guard !modes.isEmpty else { return [] }
        let perMode = max(2, Int((Double(count) / Double(modes.count)).rounded(.up)) + 1)
        var pool: [Question] = []
        for mode in modes {
            let qs = await questions(mode: mode, category: category)
            pool.append(contentsOf: qs.prefix(perMode).map { q in
                var q = q; q.roundIndex = nil; return q   // no round banners in a mix
            })
        }
        markSeen(pool.map(\.id))
        return Array(pool.shuffled().prefix(count))
    }

    /// The Daily puzzle: deterministic for the calendar day so every
    /// player gets the same 7 questions (shareable result, fair ladder).
    /// `day` defaults to today; the Previous Tidbits archive (R-DAILY-1)
    /// passes an earlier key and gets that day's exact set back.
    func dailyQuestions(category: TriviaCategory, day: String = QuestionProvider.dayKey()) async -> [Question] {
        // Canonical hash-rank selection (Decision 037) — the SAME 7 on every
        // platform. The previous per-platform seeded shuffles never agreed
        // (different shuffle algorithms + pools + seed strings); DailyPick is
        // order-independent, so only the shared id set matters.
        let ids = CorpusDatabase.shared.orderedIDs(categoryID: category.id)
        let count = GameMode.daily.questionCount
        guard ids.count >= count else {
            return await liveQuestions(topic: "On this day", category: category, count: count)
        }
        let picked = DailyPick.pick(ids: ids, day: day, categoryID: category.id, count: count)
        return CorpusDatabase.shared.questions(ids: picked)
    }

    static func dayKey(_ date: Date = .now) -> String {
        let f = DateFormatter()
        f.calendar = .current
        f.locale = .current
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
}

// MARK: - Create: one assembly path for every Apple surface

extension QuestionProvider {

    /// Build a Create set for `topic`, targeting `count` questions.
    ///
    /// This lived three times over (iOS, macOS, tvOS) with the same logic copied by
    /// hand, which is how a fix lands on one surface and not the others. It also
    /// carried a real bug: live generation only kicked in when the corpus returned
    /// FEWER THAN THREE, so a topic with six corpus questions silently delivered six
    /// and said nothing — the six thin topics in `coverage.py` were all in that band.
    ///
    /// Now the corpus is used first (it's vetted and instant) and live generation
    /// TOPS UP the shortfall rather than only rescuing a near-total miss.
    /// Run the REAL Create assembly over a file of topics and print each set.
    ///
    /// The corpus can be interrogated from a script; what the player receives
    /// cannot — it is the bundled database, the shape sources and the assembly
    /// order acting together. This drives all of that on a simulator or device and
    /// prints one line per question, which is how the "Denver returns John Denver"
    /// class of bug gets caught at the scale of a thousand topics rather than the
    /// handful anyone would type by hand.
    /// Play `games` real games across every mode x category and print each question
    /// as JSON, so the whole delivered experience can be audited off-device.
    ///
    /// This calls the SAME `questions(mode:category:)` the game engine calls and
    /// marks the results seen exactly as `GameEngine.start` does — so the pool
    /// depletes across the run the way it does for a real player, and a mode that
    /// only under-fills once you have played a while shows up here rather than in
    /// a review. The Create sweep proved the point for one surface; this is the
    /// same instrument pointed at the modes themselves.
    @MainActor
    func sweepPlay(games: Int, modes: [GameMode], categories: [TriviaCategory]) async {
        print("PLAY-BEGIN games=\(games) modes=\(modes.count) cats=\(categories.count) corpus=\(corpusCount)")
        for g in 0..<games {
            // Odometer order: the category advances once the mode list wraps, so
            // `modes.count * categories.count` consecutive games cover every
            // combination exactly once. An earlier version added `g` to the
            // category index intending to decorrelate the two, and instead made the
            // stride 15 against a 9-long list — gcd 3, so each mode only ever saw
            // three of the nine categories and 84 of the 126 combinations were
            // never played at all.
            let mode = modes[g % modes.count]
            let cat = categories[(g / modes.count) % categories.count]
            let qs = await questions(mode: mode, category: cat)
            markSeen(qs.map(\.id))
            print("PLAY-GAME\t\(g)\t\(mode.rawValue)\t\(cat.id)\t\(qs.count)\t\(mode.questionCount)")
            for (i, q) in qs.enumerated() {
                print("PLAY-Q\t\(Self.playJSON(game: g, mode: mode, cat: cat, index: i, q: q))")
            }
        }
        print("PLAY-END")
    }

    /// One question as a single JSON line. Built with JSONSerialization rather than
    /// string interpolation because prompts and options contain every quoting and
    /// punctuation character the corpus has ever seen.
    nonisolated static func playJSON(game: Int, mode: GameMode, cat: TriviaCategory,
                                     index: Int, q: Question) -> String {
        var obj: [String: Any] = [
            "game": game, "mode": mode.rawValue, "cat": cat.id, "i": index,
            "id": q.id, "prompt": q.prompt, "options": q.options,
            "correct": q.correctIndex, "answer": q.correctAnswer,
            "explanation": q.explanation, "difficulty": q.difficulty,
            "title": q.sourceTitle, "qcat": q.categoryID, "template": q.templateID,
        ]
        // The shape fields are what make a mode that mode — a Closest Call question
        // with no `closest` spec renders as a plain MCQ, which is the mode-purity bug
        // class this sweep exists to catch. Emit them so the auditor can check.
        if let c = q.closest {
            obj["closest"] = ["answer": c.answer, "min": c.min, "max": c.max,
                              "step": c.step, "tolerance": c.tolerance, "unit": c.unit]
        }
        if let o = q.ordering { obj["ordering"] = o }
        if let m = q.matching { obj["matching"] = ["keys": m.keys, "values": m.values] }
        if let a = q.accepted { obj["accepted"] = a }
        if let e = q.enumerate { obj["enumerate"] = e.groups }
        if let u = q.imageURL { obj["image"] = u.absoluteString }
        guard let data = try? JSONSerialization.data(withJSONObject: obj),
              let s = String(data: data, encoding: .utf8) else { return "{}" }
        return s
    }

    @MainActor
    func sweepCreate(path: String, corpusOnly: Bool) async {
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else {
            print("SWEEP-ERROR missing \(path)"); return
        }
        let topics = text.split(separator: "\n").map(String.init)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
        print("SWEEP-BEGIN topics=\(topics.count) corpus=\(corpusCount) corpusOnly=\(corpusOnly)")
        for topic in topics {
            // One pool per topic. `fold` bridges to NSString, so a long
            // back-to-back run accumulates autoreleased objects that never drain
            // inside an async loop — measured, the sweep began returning ZERO for
            // topics that return eight in isolation once it passed ~600 of them,
            // because SQLite could no longer allocate. The app searches once at a
            // time and never hit this; the measurement tool did, and a measurement
            // tool that silently under-reports is worse than none.
            let searchOnly = DebugHooks.createSweepSearchOnly
            let qs: [Question]
            if corpusOnly {
                qs = autoreleasepool {
                    let mcq = CorpusDatabase.shared.search(topic: topic, limit: 8)
                    guard !searchOnly else { return mcq }
                    return mcq + [JSONQuestionSource.picture, .thisOrThat, .closestCall]
                        .flatMap { $0.searchMatch(topic: topic, limit: 1) }
                }
            } else {
                qs = await createSet(topic: topic)
            }
            print("SWEEP-TOPIC\t\(topic)\t\(qs.count)")
            for q in qs {
                // Tab-separated so the reader can split without guessing where the
                // prompt ends — prompts contain every other punctuation mark.
                print("SWEEP-Q\t\(topic)\t\(q.id)\t\(q.sourceTitle)\t\(q.categoryID)\t\(q.prompt)\t\(q.correctAnswer)")
            }
        }
        print("SWEEP-END")
    }

    @MainActor
    func createSet(topic: String, count: Int = 8) async -> [Question] {
        // Shape variety first: a couple of topic-matched non-MCQ questions so the set
        // mixes kinds, not just categories.
        var shaped: [Question] = []
        for src in [JSONQuestionSource.picture, .thisOrThat, .closestCall] {
            shaped.append(contentsOf: src.searchMatch(topic: topic, limit: 1))
        }
        let mcq = CorpusDatabase.shared.search(topic: topic, limit: max(4, count - shaped.count))
        var result = mcq + shaped

        if result.count < count {
            // Top up from live Wikipedia. Deduped by id because a live question can
            // legitimately restate a corpus one for the same subject.
            let have = Set(result.map(\.id))
            let live = await liveQuestions(topic: topic, category: .named("mixed"),
                                           count: count - result.count + 2)
            result += live.filter { !have.contains($0.id) }
        }
        return Array(result.shuffled().prefix(count))
    }
}
