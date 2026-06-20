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
        let seed = "\(day)".stableSeed
        // Pull a deterministic slice from the corpus (no seen-exclusion —
        // the Daily is the same for everyone, by design).
        var rng = SeededRNG(seed: seed)
        let pool = CorpusDatabase.shared.questions(
            categoryID: "mixed", excluding: [], limit: 60)
        guard pool.count >= GameMode.daily.questionCount else {
            return await liveQuestions(topic: "On this day", category: category, count: GameMode.daily.questionCount)
        }
        return Array(pool.shuffled(using: &rng).prefix(GameMode.daily.questionCount))
    }

    static func dayKey(_ date: Date = .now) -> String {
        let f = DateFormatter()
        f.calendar = .current
        f.locale = .current
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
}
