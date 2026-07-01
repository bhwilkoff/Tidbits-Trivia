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
    func questions(mode: GameMode, category: TriviaCategory) async -> [Question] {
        let need = min(mode.questionCount, mode == .timeAttack ? 25 : mode.questionCount)
        if mode == .daily { return await dailyQuestions(category: category) }
        // Enrichment-built modes ride their own bundled JSON source (E1).
        if mode == .pictureId {
            return JSONQuestionSource.picture.questions(categoryID: category.id, excluding: seen, limit: need)
        }
        if mode == .thisOrThat {
            return JSONQuestionSource.thisOrThat.questions(categoryID: category.id, excluding: seen, limit: need)
        }
        if mode == .closestCall {
            return JSONQuestionSource.closestCall.questions(categoryID: category.id, excluding: seen, limit: need)
        }
        if mode == .ordering {
            return JSONQuestionSource.ordering.questions(categoryID: category.id, excluding: seen, limit: need)
        }
        if mode == .matching {
            return JSONQuestionSource.matching.questions(categoryID: category.id, excluding: seen, limit: need)
        }
        if mode == .typeAnswer {
            return JSONQuestionSource.typeAnswer.questions(categoryID: category.id, excluding: seen, limit: need)
        }
        if mode == .oddOneOut {
            // Odd-one-out is geography-only data; ignore the picked category.
            return JSONQuestionSource.oddOneOut.questions(categoryID: "mixed", excluding: seen, limit: need)
        }
        if mode == .enumerate {
            // A few list puzzles per round; curated sets span categories, so don't
            // filter by the picked category (the set IS the topic). The pool is
            // small (≈11) and enumeration is a REPLAYABLE recall drill — naming
            // the countries of Asia again is the point, not a spoiler — so ignore
            // the seen-set (like Daily) rather than exhaust it after a few rounds.
            return JSONQuestionSource.enumerate.questions(categoryID: "mixed", excluding: [], limit: need)
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

    /// Source `count` questions of one TYPE, the same way `questions(mode:)`
    /// does per mode — factored out so the night builder reuses it exactly.
    private func sourced(type: GameMode, category: TriviaCategory, count: Int, excluding: Set<String>) async -> [Question] {
        switch type {
        case .pictureId:   return JSONQuestionSource.picture.questions(categoryID: category.id, excluding: excluding, limit: count)
        case .thisOrThat:  return JSONQuestionSource.thisOrThat.questions(categoryID: category.id, excluding: excluding, limit: count)
        case .closestCall: return JSONQuestionSource.closestCall.questions(categoryID: category.id, excluding: excluding, limit: count)
        case .ordering:    return JSONQuestionSource.ordering.questions(categoryID: category.id, excluding: excluding, limit: count)
        case .matching:    return JSONQuestionSource.matching.questions(categoryID: category.id, excluding: excluding, limit: count)
        case .typeAnswer:  return JSONQuestionSource.typeAnswer.questions(categoryID: category.id, excluding: excluding, limit: count)
        case .oddOneOut:   return JSONQuestionSource.oddOneOut.questions(categoryID: "mixed", excluding: excluding, limit: count)
        case .enumerate:   return JSONQuestionSource.enumerate.questions(categoryID: "mixed", excluding: [], limit: count)
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

    /// The Daily puzzle: deterministic for the calendar day so every
    /// player gets the same 7 questions (shareable result, fair ladder).
    func dailyQuestions(category: TriviaCategory) async -> [Question] {
        let day = Self.dayKey()
        // Per-day AND per-category, so each category has its own daily set.
        let seed = "\(day):\(category.id)".stableSeed
        var rng = SeededRNG(seed: seed)
        // Deterministic pool: STABLE id order → seeded shuffle → the SAME slice
        // for everyone all day. (The old path used `ORDER BY RANDOM()`, so the
        // seeded shuffle reordered a fresh random pool each open — the questions
        // changed every time. Determinism must start at the pool, not the shuffle.)
        let ids = CorpusDatabase.shared.orderedIDs(categoryID: category.id)
        let count = GameMode.daily.questionCount
        guard ids.count >= count else {
            return await liveQuestions(topic: "On this day", category: category, count: count)
        }
        let picked = Array(ids.shuffled(using: &rng).prefix(count))
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
