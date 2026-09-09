import Foundation

/// What a room has already been asked (macOS-DESIGN A2.6). A saved night is
/// meant to be re-run "next week" — and re-run verbatim it asks the same
/// questions to the same regulars. The log remembers every question a HOSTED
/// night showed (not what the builder pulled: pulling is not asking), when, and
/// which night, so the builder can name a repeat and the corpus draw can skip it.
nonisolated struct LivePlayedEntry: Codable, Sendable, Equatable {
    var at: Date
    var night: String
}

@MainActor
final class LivePlayedLog {
    static let shared = LivePlayedLog()
    private let defaults: UserDefaults
    private let key: String
    private(set) var entries: [String: LivePlayedEntry]

    init(defaults: UserDefaults = .standard, key: String = "tidbits.livePlayed") {
        self.defaults = defaults
        self.key = key
        entries = (defaults.data(forKey: key)).flatMap { try? JSONDecoder().decode([String: LivePlayedEntry].self, from: $0) } ?? [:]
    }

    var ids: Set<String> { Set(entries.keys) }
    func entry(_ id: String) -> LivePlayedEntry? { entries[id] }

    /// The night showed these questions. Re-asking updates the date (the LAST
    /// time is what a host wants to know). Capped like the seen set: a log the
    /// size of the corpus is not telling anyone anything.
    func record(_ ids: [String], night: String, at: Date = .now) {
        for id in ids where !id.isEmpty { entries[id] = LivePlayedEntry(at: at, night: night) }
        if entries.count > 9000 { entries = [:] }
        if let d = try? JSONEncoder().encode(entries) { defaults.set(d, forKey: key) }
    }

    func clear() { entries = [:]; defaults.removeObject(forKey: key) }

    /// "Asked 6 days ago · Friday Pub Quiz" — the badge under a repeat.
    nonisolated static func askedLine(_ e: LivePlayedEntry, now: Date = .now) -> String {
        let days = max(0, Int(now.timeIntervalSince(e.at) / 86_400))
        let when: String
        switch days {
        case 0: when = "today"
        case 1: when = "yesterday"
        case 2...13: when = "\(days) days ago"
        case 14...59: when = "\(days / 7) weeks ago"
        default: when = e.at.formatted(.dateTime.month(.abbreviated).day())
        }
        let n = e.night.trimmingCharacters(in: .whitespacesAndNewlines)
        return n.isEmpty ? "Asked \(when)" : "Asked \(when) · \(n)"
    }

    /// The questions of `list` the room has heard, in order.
    nonisolated static func repeats(in list: [Question], played: Set<String>) -> [Question] {
        list.filter { played.contains($0.id) }
    }
}
