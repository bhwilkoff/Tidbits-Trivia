import Foundation

/// The Daily's global board — the $0 layer that ranks everyone who played today's Daily
/// (docs/DAILY-BOARD-CONTRACT.md). A LAYER on the Daily, never a separate mode: the same
/// 7-question set, the same streak. On finishing today's Daily the client writes one row
/// to `dailyBoard/{day}/{authUid}`; an hourly GitHub-Actions cron ranks the field and
/// publishes static JSON that every client reads — never the live DB (R-NET-1).
///
/// The READ side is a static-JSON fetch (mirror of `LeaderboardAPI`); the WRITE side is a
/// single authed RTDB put and lives on `PlayerIdentityStore.submitDailyBoard` (it needs
/// the authed client + the profile snapshot).
nonisolated enum DailyBoard {
    static let base = "https://tidbitstrivia.com/data/dailyboard"

    /// The published board for a day, or nil if the cron hasn't published it yet (nobody
    /// has played, or it's the current in-progress hour). Never surface an error — an
    /// absent board just means "check back after the hourly refresh".
    static func results(day: String) async -> Board? {
        await fetch("\(base)/\(day).json")
    }

    /// Your percentile from the published histogram: the share of players you strictly
    /// beat. Pure + tiny, so a player outside the top board still sees "you beat 83%".
    /// nil when the histogram is empty (you'd be the only/first player).
    static func percentile(hist: [String: Int], myScore: Int) -> Int? {
        var below = 0, total = 0
        for (score, count) in hist {
            total += count
            if (Int(score) ?? 0) < myScore { below += count }
        }
        return total > 0 ? Int((Double(below) / Double(total) * 100).rounded()) : nil
    }

    /// Build the 7-char `0/1` marks string aligned to the SHARED `pickDaily` order (by
    /// qid), NOT the play order — so per-question accuracy is comparable across players.
    static func marks(answered: [AnsweredQuestion], qids: [String]) -> String {
        let correctByID = Dictionary(answered.map { ($0.question.id, $0.isCorrect) },
                                     uniquingKeysWith: { a, _ in a })
        return qids.map { (correctByID[$0] ?? false) ? "1" : "0" }.joined()
    }

    private static func fetch<T: Decodable>(_ urlString: String) async -> T? {
        guard let url = URL(string: urlString),
              let (data, _) = try? await URLSession.shared.data(from: url) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    // MARK: - Wire (matches the cron's published shape)

    struct Board: Decodable, Sendable {
        let day: String
        let qids: [String]
        let n: Int
        let hist: [String: Int]
        let perQ: [Double]
        let top: [Row]
    }

    struct Row: Decodable, Sendable, Identifiable {
        let name: String
        let avatarSeed: String
        let score: Int
        let correct: Int
        var id: String { "\(name)-\(score)-\(correct)" }
    }

    /// The row a client writes to `dailyBoard/{day}/{uid}`.
    struct Entry: Encodable, Sendable {
        let name: String
        let avatarSeed: String
        let score: Int
        let correct: Int
        let marks: String
        let ms: Int
        let at: Int
    }
}
