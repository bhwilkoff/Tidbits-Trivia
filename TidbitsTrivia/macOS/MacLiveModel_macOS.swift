#if os(macOS)
import SwiftUI

// MARK: - Tidbits Live event model (macOS-DESIGN Part A §A1-A2)

/// One team in a live event. Score is authoritative on the host's Mac.
///
/// It lives here, with the other Live model types, rather than in the 1,250-line
/// cockpit view it used to sit in — the printable results sheet needs it, and a
/// data type should not require pulling a whole view file into the test target.
struct LiveTeam: Identifiable, Hashable {
    let id = UUID()
    var name: String
    var score: Int = 0
}

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
    /// G1: a BUZZ round — the room races to buzz and the FIRST team gets to answer
    /// out loud; the host marks it right or wrong and a wrong buzz reopens it to the
    /// rest (SpeedQuizzing's signature format). A flag rather than a GameMode
    /// because it changes how a round is PLAYED, not what a question IS, and
    /// GameMode is a wire enum pinned by goldens on both stacks.
    var isBuzz: Bool? = nil
    /// G4: a FIRST-LETTER round — every answer in it begins with this letter, which
    /// the host announces and the big screen states. Same reasoning as `isBuzz`: it
    /// constrains which questions the round may HOLD, it does not change what a
    /// question IS, so it is a field rather than a GameMode (which both stacks pin
    /// with wire goldens). Optional so every saved event still decodes.
    var letter: String? = nil
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
    var weekday: Int? = nil   // Wave D: recurring-series scheduling — 1=Sun…7=Sat (nil = one-off); optional so saved events decode
    var sponsor: String = ""  // Wave D: sponsor kit — "brought to you by …" in the lobby + between rounds + a per-question tag
    var leadCaptureURL: String = ""  // Wave D: lead capture — the host's mailing-list signup URL, shown as a QR at the end of the night
    var brandHex: String = ""        // Wave D: white-label — the host's brand accent (hex), applied to the big-screen event title

    var totalQuestions: Int { rounds.reduce(0) { $0 + $1.questions.count } }
    /// Wave D: the day-name of a recurring series (nil for a one-off).
    var weekdayName: String? {
        guard let weekday, (1...7).contains(weekday) else { return nil }
        return Calendar.current.weekdaySymbols[weekday - 1]
    }
    /// Wave D: the next calendar date this series lands on (nil for a one-off) — the app
    /// surfaces "this week's night" so the host reuses the template instead of rebuilding it.
    var nextOccurrence: Date? {
        guard let weekday, (1...7).contains(weekday) else { return nil }
        return Calendar.current.nextDate(after: .now, matching: DateComponents(weekday: weekday),
                                         matchingPolicy: .nextTime)
    }
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

    /// G4: questions whose ANSWER begins with `letter`, for a first-letter round.
    ///
    /// Separate from `buildRound` because the letter filter runs over the pool
    /// BEFORE the count is applied — taking the first N and then filtering is how
    /// a themed round comes back with two questions in it (the same
    /// truncate-then-select ordering that Decision 052 was written about).
    static func letterQuestions(format: GameMode, category: TriviaCategory,
                                letter: Character, count: Int) async -> [Question] {
        let pool = await QuestionProvider.shared.questions(mode: format, category: category)
        return LiveLetterRound.candidates(from: pool, letter: letter, limit: count)
    }
}
#endif
