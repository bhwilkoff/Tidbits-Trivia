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
            var pool = CorpusDatabase.shared.questions(categoryID: "mixed", excluding: seen, limit: 80)
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
        do {
            let titles = try await WikipediaClient.shared.search(topic, limit: 35)
            guard !titles.isEmpty else { return [] }
            let summaries = await WikipediaClient.shared.summaries(for: titles)
            // Apple Intelligence (Foundation Models) writes delightful, grounded
            // questions on-device when available; otherwise fall back to the
            // template engine so Create works on every platform/device.
            if DelightfulQuizGenerator.isAvailable {
                let ai = await DelightfulQuizGenerator.generate(
                    topic: topic, summaries: summaries, categoryID: category.id, count: count)
                if ai.count >= min(count, 3) { return ai }
            }
            return TemplateEngine.makeQuestions(
                pool: summaries, categoryID: category.id, count: count, seed: topic.stableSeed)
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
