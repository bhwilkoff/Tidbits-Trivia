#if os(macOS)
import Foundation

// macOS-only: `LiveEvent` (the authored night) is a Mac host type; the iOS/tvOS
// builds compile Core too and have no host cockpit to resume.

/// A2.13 — a night the host was in the MIDDLE of, kept so a crash or a closed lid is
/// not the end of the evening.
///
/// Everything the room can see already survives on the wire: the phones' scores live in
/// `live/{code}/scores`, which the host owns. What died with the app was everything the
/// HOST held — where in the night they were, the paper teams and their scores, the names
/// they had hidden, the manual adjustments, the answer sheet. A host standing in front of
/// sixty people cannot reconstruct that.
///
/// The snapshot is written as the night moves and cleared when it ends properly, so a
/// night that finished normally never offers to resume.
nonisolated struct LiveNightSnapshot: Codable, @unchecked Sendable {
    var code: String
    var event: LiveEvent
    var index: Int
    var revealed: Bool
    var scoredIndices: [Int]
    var paperTeams: [Team]
    var blockedTeams: [String]
    var pointsPerCorrect: Int
    var wrongAnswerPenalty: Int
    var answerLog: [LiveAnswerRecord]
    var savedAt: Date
    /// A2.14: the jokers locked per round (key = round index), and the paper tables'
    /// jokers by team name. Optional so a snapshot from before the joker decodes.
    var jokersPlayed: [String: [String]]? = nil
    var paperJokers: [String: Int]? = nil

    nonisolated struct Team: Codable, Equatable, Sendable {
        var name: String
        var score: Int
    }

    /// "Question 4 of 12" — what the resume card says, so the host knows what they are
    /// walking back into before they commit.
    var positionLine: String {
        let total = event.rounds.reduce(0) { $0 + $1.questions.count }
        return total > 0 ? "question \(min(index + 1, total)) of \(total)" : "not started"
    }
}

@MainActor
final class LiveNightResume {
    static let shared = LiveNightResume()

    /// A night older than this is not "in progress" — it is last week's, and offering to
    /// resume it would re-open a room the room has long left.
    static let maxAge: TimeInterval = 6 * 60 * 60

    private let defaults: UserDefaults
    private let key: String
    private(set) var snapshot: LiveNightSnapshot?

    init(defaults: UserDefaults = .standard, key: String = "tidbits.liveResume") {
        self.defaults = defaults
        self.key = key
        snapshot = (defaults.data(forKey: key)).flatMap { try? JSONDecoder().decode(LiveNightSnapshot.self, from: $0) }
    }

    /// The night worth offering to resume, if there is one.
    func pending(now: Date = .now) -> LiveNightSnapshot? {
        guard let s = snapshot, now.timeIntervalSince(s.savedAt) < Self.maxAge else { return nil }
        return s
    }

    func save(_ s: LiveNightSnapshot) {
        snapshot = s
        if let data = try? JSONEncoder().encode(s) { defaults.set(data, forKey: key) }
    }

    /// The night ended properly (or the host discarded it) — stop offering it.
    func clear() {
        snapshot = nil
        defaults.removeObject(forKey: key)
    }
}
#endif
