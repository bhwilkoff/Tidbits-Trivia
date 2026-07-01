import Foundation

/// Per-day Daily Tidbit results (rule R-DAILY-1, Decision 036): today's Daily
/// locks once played — the second run of a known set is memorization, not a
/// skill test — while previous days stay playable from the archive. The Daily
/// generator is deterministic by day key, so an old day's questions regenerate
/// from the date; only the outcome needs storing.
///
/// UserDefaults-backed, mirroring web localStorage and Android SharedPreferences
/// under the same conceptual key (four mirrors, one behavior).
enum DailyLog {
    private static let key = "tidbits.daily.results"

    /// How far back the archive reaches. Old enough to catch up a lapsed
    /// week or two; small enough that the list stays scannable.
    static let archiveDays = 30

    static func score(for day: String) -> Int? {
        (UserDefaults.standard.dictionary(forKey: key) as? [String: Int])?[day]
    }

    static func played(_ day: String) -> Bool { score(for: day) != nil }

    static var playedToday: Bool { played(QuestionProvider.dayKey()) }
    static var todayScore: Int? { score(for: QuestionProvider.dayKey()) }

    /// First completion wins — a locked day never re-records (play-once).
    static func record(day: String, score: Int) {
        var map = (UserDefaults.standard.dictionary(forKey: key) as? [String: Int]) ?? [:]
        guard map[day] == nil else { return }
        map[day] = score
        UserDefaults.standard.set(map, forKey: key)
    }

    /// The archive: today first, then the previous days, newest → oldest.
    static func recentDays(_ count: Int = archiveDays) -> [(day: String, score: Int?)] {
        let cal = Calendar.current
        return (0..<count).compactMap { offset in
            guard let d = cal.date(byAdding: .day, value: -offset, to: .now) else { return nil }
            let k = QuestionProvider.dayKey(d)
            return (day: k, score: score(for: k))
        }
    }
}
