#if os(macOS)
import SwiftUI

// MARK: - Tidbits Live event model (macOS-DESIGN Part A §A1-A2)

/// One round of a live event: a named block of questions of a single format.
/// (v1 stores the questions inline; the Library-≠-Project reference-document
/// evolution — §A1.3 — is a tracked follow-up.)
struct LiveRound: Identifiable, Codable, Hashable {
    var id = UUID()
    var title: String
    var format: GameMode
    var categoryID: String
    var questions: [Question]
    var timerSeconds: Int? = nil   // Wave A: per-question countdown for this round (nil/0 = off) — optional so saved events still decode
    var hostNote: String? = nil    // Wave A: the host's prep note for this round, shown in the cockpit (never published)
    var isWager: Bool? = nil       // Wave A: a wager round — teams stake points on each question (correct +stake, wrong −stake)
    var audioBookmarks: [Data]? = nil   // Wave B: security-scoped bookmarks to each question's audio clip (audio round; parallel to questions)
    var isSpeed: Bool? = nil            // Wave B: a speed round — correct answers earn a fastest-first bonus
    var videoBookmarks: [Data]? = nil   // Wave B: security-scoped bookmarks to each question's video clip (video round; parallel to questions)

    var symbol: String { format.symbol }
}

/// A Tidbits Live event: an ordered list of named rounds. A weekly night is a
/// duplicated event.
struct LiveEvent: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    /// Venue branding (§A-Phase-B): shown on the big screen + printed sheets.
    var venue: String = ""
    var rounds: [LiveRound] = []
    var createdAt: Date = .now

    var totalQuestions: Int { rounds.reduce(0) { $0 + $1.questions.count } }
    /// The full question stream, round-tagged, for play/host (mirrors a Night).
    var questionStream: [Question] {
        var out: [Question] = []
        for (ri, round) in rounds.enumerated() {
            for var q in round.questions { q.roundIndex = ri; out.append(q) }
        }
        return out
    }
    var nightPlan: NightPlan {
        NightPlan(rounds: rounds.map { NightRound(kind: $0.format, count: $0.questions.count) })
    }
}

/// Persistent store for the host's saved events (UserDefaults JSON for v1; the
/// `.package` reference-document is the §A1.3 evolution).
@Observable
@MainActor
final class LiveEventStore {
    private static let key = "tidbits.liveEvents"
    var events: [LiveEvent] = LiveEventStore.load()

    static func load() -> [LiveEvent] {
        guard let d = UserDefaults.standard.data(forKey: key),
              let list = try? JSONDecoder().decode([LiveEvent].self, from: d) else { return [] }
        return list.sorted { $0.createdAt > $1.createdAt }
    }
    private func persist() {
        if let d = try? JSONEncoder().encode(events) { UserDefaults.standard.set(d, forKey: Self.key) }
    }
    func upsert(_ event: LiveEvent) {
        if let i = events.firstIndex(where: { $0.id == event.id }) { events[i] = event }
        else { events.insert(event, at: 0) }
        persist()
    }
    func delete(_ event: LiveEvent) { events.removeAll { $0.id == event.id }; persist() }

    /// Build a round for a format+category by pulling questions from the shared
    /// corpus/engine (the host then edits — §A2.2 no-auto-edit gate).
    static func buildRound(format: GameMode, category: TriviaCategory, count: Int) async -> LiveRound {
        let qs = await QuestionProvider.shared.questions(mode: format, category: category)
        return LiveRound(title: format.nightRoundTitle, format: format, categoryID: category.id,
                         questions: Array(qs.prefix(count)))
    }
}
#endif
