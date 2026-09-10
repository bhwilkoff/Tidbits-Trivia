import Foundation

/// A night the host actually ran, kept after the cockpit closes (macOS-DESIGN
/// A2.12, 2026-09-10). Until now a night existed only while it was happening:
/// the final standings and the A3.11 report were on screen for as long as the
/// host left the wrap up, and then they were gone. A pub host runs the same room
/// every week and is asked "who won last time?" — so the night is archived on the
/// machine that ran it (no backend, nothing leaves the host) and can be reopened,
/// re-read and re-exported.
nonisolated struct ArchivedNight: Codable, Equatable, Identifiable, Sendable {
    nonisolated struct Row: Codable, Equatable, Sendable {
        var name: String
        var score: Int
        var paper: Bool
    }
    var id: String
    var name: String
    var venue: String
    var endedAt: Date
    var standings: [Row]          // best first, as the wrap showed them
    var log: [LiveAnswerRecord]   // the answer sheet, so the report AND the CSV regenerate

    /// The night read back (A3.11) — recomputed from the sheet rather than stored,
    /// so an archived night and a live one can never disagree.
    var report: LiveNightReport { LiveNightReport.from(log, teams: standings.count) }

    /// The top team, but only if it actually scored: a night where nobody was paid has
    /// no winner, and crowning whoever sorted first is a lie the host has to explain.
    var winner: Row? { standings.first.flatMap { $0.score > 0 ? $0 : nil } }

    /// "3 teams · The Quizzards won with 14" — the card's one line.
    var headline: String {
        if standings.isEmpty { return "No teams were scored" }
        let teams = standings.count == 1 ? "1 team" : "\(standings.count) teams"
        guard let w = winner else { return "\(teams) · nobody scored" }
        return "\(teams) · \(w.name) won with \(w.score)"
    }
}

/// The host's archive of run nights, newest first. UserDefaults-backed like
/// `LivePlayedLog` — no new file I/O to get wrong inside the sandbox — and capped,
/// because an unbounded archive of answer sheets is a slow leak rather than a
/// feature.
@MainActor
final class LiveNightArchive {
    static let shared = LiveNightArchive()

    /// Twenty nights is about five months of a weekly room; past that a host is
    /// looking for a season, not last week.
    static let cap = 20
    /// A single night's sheet is bounded too: 40 questions x 12 tables is already
    /// past what any pub runs, and a runaway log must not evict the whole archive.
    static let logCap = 600

    private let defaults: UserDefaults
    private let key: String
    private(set) var nights: [ArchivedNight]

    init(defaults: UserDefaults = .standard, key: String = "tidbits.liveNights") {
        self.defaults = defaults
        self.key = key
        nights = (defaults.data(forKey: key)).flatMap { try? JSONDecoder().decode([ArchivedNight].self, from: $0) } ?? []
    }

    /// Archive a finished night. Returns the record so a caller can show it at once.
    @discardableResult
    func record(name: String, venue: String, standings: [ArchivedNight.Row],
                log: [LiveAnswerRecord], at: Date = .now, id: String = UUID().uuidString) -> ArchivedNight {
        let night = ArchivedNight(id: id, name: name, venue: venue, endedAt: at,
                                  standings: standings, log: Array(log.prefix(Self.logCap)))
        nights.insert(night, at: 0)
        if nights.count > Self.cap { nights = Array(nights.prefix(Self.cap)) }
        persist()
        return night
    }

    func delete(_ id: String) {
        nights.removeAll { $0.id == id }
        persist()
    }

    func clear() {
        nights = []
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(nights) { defaults.set(data, forKey: key) }
    }
}
