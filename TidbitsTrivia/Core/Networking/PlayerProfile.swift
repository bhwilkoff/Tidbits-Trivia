import Foundation
import CryptoKit

/// The portable Tidbits player identity — the wire contract for the shared, cross-platform
/// profile that spans solo play AND live events, on the $0 data plane (Firebase RTDB Spark;
/// see `docs/PLAYER-IDENTITY-CONTRACT.md`). ONE profile so a cross-venue leaderboard can
/// span an iPhone + Android + web pub crowd — but each platform SIGNS IN through its own
/// native system (Sign in with Apple + Game Center on Apple; Play Games on Android;
/// federated on web) and links that native player to this shared `uid`.
///
/// Two RTDB paths, split by sensitivity (RTDB read rules cascade and can't be revoked
/// deeper, so public and private data live under separate roots):
///   - `players/{uid}`         — PUBLIC display + stats (leaderboard-readable, owner-write)
///   - `playersPrivate/{uid}`  — owner-only (contact opt-in, linked native IDs, place graph)
///
/// Additive-only evolution: never repurpose a key; add new optional ones. Web (`js/`) and
/// Android (`FirebaseNet.kt`) mirror these EXACT keys.
enum PlayerIdentity {
    static let publicPath = "players"
    static let privatePath = "playersPrivate"
    static func publicPath(_ uid: String) -> String { "\(publicPath)/\(uid)" }
    static func privatePath(_ uid: String) -> String { "\(privatePath)/\(uid)" }

    /// Stable, non-reversible profile key from the verified email — Apple + Google with
    /// the same email land on the SAME profile. Mirror of the JS/Kotlin sha256Hex(email).
    static func accountKey(forEmail email: String) -> String {
        let norm = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return SHA256.hash(data: Data(norm.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// `players/{uid}` — the public profile (anyone signed-in can read it for leaderboards;
    /// only the owner can write). Non-sensitive display + aggregate stats only.
    nonisolated struct Profile: Codable, Equatable {
        var name: String            // chosen display name (NOT real identity)
        var createdAt: Int          // epoch ms
        var avatarSeed: String      // deterministic avatar (seed → generated art)
        var rating: Rating
        var streak: Streak
        var stats: Stats
    }

    /// The Tidbits Rating — an Elo-style skill number updated by EVERY game, solo and live
    /// (live weighted higher: real opponents, higher stakes). Provisional until `games`
    /// reaches `establishedAt`, so the number is honest from cold-start and stable long-term.
    /// (Update algorithm lands with the rating logic — see the identity-spine loop.)
    nonisolated struct Rating: Codable, Equatable {
        var value: Double           // current rating
        var games: Int              // rated games so far
        var provisional: Bool       // games < establishedAt
        static let start = 1000.0
        static let establishedAt = 15
    }

    /// The cross-context streak — kept alive by a solo game OR a live night, making the
    /// sparse event and daily solo play the SAME habit. Forgiving by design (freezes +
    /// restartable) — punishing streaks tank reviews (Duolingo lesson).
    nonisolated struct Streak: Codable, Equatable {
        var current: Int
        var longest: Int
        var lastPlayedDay: String   // "yyyy-MM-dd" in the player's local zone
        var freezes: Int            // streak-protection tokens (auto-earned; a live night grants one)
    }

    /// Lifetime aggregate stats (the "deep stats" surface, and leaderboard tie-breakers).
    nonisolated struct Stats: Codable, Equatable {
        var gamesPlayed: Int
        var questionsAnswered: Int
        var correct: Int
        var liveNights: Int         // live events attended (presence = joined the room)
        var venuesVisited: Int      // distinct venues (count only; the list is private)
    }

    /// `playersPrivate/{uid}` — owner-only. Contact is opt-in (lead capture); the linked
    /// native IDs map platform sign-ins to this shared uid; the venue list is the place
    /// graph (sensitive — where/when you play; private by default, shared by choice).
    nonisolated struct Private: Codable, Equatable {
        var email: String? = nil            // opt-in only; never harvested silently
        var appleUserID: String? = nil      // Sign in with Apple
        var gameCenterID: String? = nil     // Game Center player (Apple)
        var playGamesID: String? = nil      // Google Play Games (Android)
        var googleUserID: String? = nil     // Google Sign-In (Android/web)
        var venues: [String]? = nil         // venue ids visited (place graph)
    }

    /// A single row a device writes after an event/game for the cross-venue leaderboard
    /// (`standings/{season}/{venue}/{uid}`). The cron aggregates these into static JSON.
    nonisolated struct Standing: Codable, Equatable {
        var name: String            // display name snapshot (so the cron needn't join)
        var score: Int              // this player's season score at this venue
        var nights: Int             // nights attended at this venue (the "Regular" track)
        var updatedAt: Int          // epoch ms
    }

    /// Season id, e.g. "2026-S3". Kept coarse so standings partition cleanly.
    static func standingPath(season: String, venue: String, uid: String) -> String {
        "standings/\(season)/\(venue)/\(uid)"
    }

    /// The current season id — calendar quarter, e.g. "2026-S3". Byte-identical across
    /// Swift/Kotlin/JS so every platform writes to the same partition.
    static func currentSeason(now: Date = Date()) -> String {
        let c = Calendar(identifier: .gregorian).dateComponents([.year, .month], from: now)
        let quarter = (((c.month ?? 1) - 1) / 3) + 1
        return "\(c.year ?? 2026)-S\(quarter)"
    }

    /// A venue key safe for an RTDB path — ASCII a-z0-9 kept, every other run collapsed to a
    /// single "-", edges trimmed. Byte-identical to the JS/Kotlin `[^a-z0-9]+`→`-` regex.
    static func venueKey(_ venue: String) -> String {
        let lowered = venue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var out = "", lastDash = false
        for ch in lowered {
            if ("a"..."z").contains(ch) || ("0"..."9").contains(ch) { out.append(ch); lastDash = false }
            else if !lastDash { out.append("-"); lastDash = true }
        }
        while out.hasPrefix("-") { out.removeFirst() }
        while out.hasSuffix("-") { out.removeLast() }
        return out
    }

    /// Up-to-two initials for the seeded avatar (shared by every platform's profile UI).
    nonisolated static func initials(_ name: String) -> String {
        let parts = name.split(separator: " ").prefix(2)
        let s = parts.compactMap { $0.first }.map(String.init).joined()
        return s.isEmpty ? "?" : s.uppercased()
    }

    /// Deterministic avatar hue (0–1) from the seed — djb2, matching iOS/Android/web.
    nonisolated static func avatarHue(_ seed: String) -> Double {
        let stable = seed.utf8.reduce(5381) { ($0 &* 33) &+ Int($1) }
        return Double(abs(stable) % 360) / 360.0
    }

    /// Today in the player's local zone, "yyyy-MM-dd" (the streak day key).
    nonisolated static func todayString() -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    /// Whole-day gap between two "yyyy-MM-dd" strings (empty `from` → 1 = a fresh start).
    nonisolated static func dayGap(from: String, to: String) -> Int {
        guard !from.isEmpty else { return 1 }
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
        guard let a = f.date(from: from), let b = f.date(from: to) else { return 99 }
        return Calendar.current.dateComponents([.day], from: a, to: b).day ?? 99
    }
}

extension PlayerIdentity {
    nonisolated static func isDefaultName(_ n: String) -> Bool { n.hasPrefix("Player ") }

    /// LOSSLESS merge of a local anon profile into an `account` profile (the survivor)
    /// when a sign-in resolves to an existing account. Stats are summed and are
    /// order-independent; see `docs/PLAYER-IDENTITY-CONTRACT.md`.
    nonisolated static func merge(local a: Profile, account b: Profile) -> Profile {
        let name = !isDefaultName(b.name) ? b.name : (!isDefaultName(a.name) ? a.name : b.name)
        let rGames = a.rating.games + b.rating.games
        let rating = Rating(value: max(a.rating.value, b.rating.value), games: rGames,
                            provisional: rGames < Rating.establishedAt)
        let streak = Streak(current: a.streak.lastPlayedDay >= b.streak.lastPlayedDay ? a.streak.current : b.streak.current,
                            longest: max(a.streak.longest, b.streak.longest),
                            lastPlayedDay: max(a.streak.lastPlayedDay, b.streak.lastPlayedDay),
                            freezes: max(a.streak.freezes, b.streak.freezes))
        let stats = Stats(gamesPlayed: a.stats.gamesPlayed + b.stats.gamesPlayed,
                          questionsAnswered: a.stats.questionsAnswered + b.stats.questionsAnswered,
                          correct: a.stats.correct + b.stats.correct,
                          liveNights: a.stats.liveNights + b.stats.liveNights,
                          venuesVisited: max(a.stats.venuesVisited, b.stats.venuesVisited))
        return Profile(name: name, createdAt: min(a.createdAt, b.createdAt),
                       avatarSeed: b.avatarSeed, rating: rating, streak: streak, stats: stats)
    }
}

extension PlayerIdentity.Rating {
    /// Elo-style update after a game. `accuracy` (0…1) is the score; `field` is the
    /// implied opponent/difficulty rating (solo = a fixed field; live can pass the real
    /// average opponent rating). Provisional games move faster (higher K); `weight`
    /// boosts live games. Self-correcting + bounded: a consistent-accuracy player
    /// converges to the rating where `expected == their accuracy`.
    nonisolated func updated(accuracy: Double, field: Double = 1200, weight: Double = 1) -> PlayerIdentity.Rating {
        let expected = 1.0 / (1.0 + pow(10, (field - value) / 400))
        let k = (provisional ? 64.0 : 24.0) * weight
        let n = games + 1
        let newValue = max(100, (value + k * (accuracy - expected)).rounded())
        return PlayerIdentity.Rating(value: newValue, games: n, provisional: n < PlayerIdentity.Rating.establishedAt)
    }
}

extension PlayerIdentity.Streak {
    /// Register play on `today` ("yyyy-MM-dd"). Same day = unchanged; a consecutive day
    /// = +1; a ONE-day gap consumes a freeze (streak preserved); a bigger gap resets to 1
    /// (forgiving restart — never punishing). A live night grants a freeze token (cap 3).
    nonisolated func played(today: String, liveNight: Bool = false) -> PlayerIdentity.Streak {
        var s = self
        if today != lastPlayedDay {
            let gap = PlayerIdentity.dayGap(from: lastPlayedDay, to: today)
            if lastPlayedDay.isEmpty || gap == 1 {
                s.current += 1
            } else if gap == 2 && s.freezes > 0 {
                s.freezes -= 1; s.current += 1            // a freeze covers one missed day
            } else {
                s.current = 1                             // gap too big → forgiving restart
            }
            s.longest = max(s.longest, s.current)
            s.lastPlayedDay = today
        }
        if liveNight { s.freezes = min(s.freezes + 1, 3) }
        return s
    }
}

// MARK: - Wave E: leaderboard (read the static JSON the cron commits — never RTDB)

/// One ranked row in a venue or cross-venue leaderboard (decoded from data/leaderboard/*.json).
nonisolated struct LeaderboardRow: Codable, Identifiable, Sendable {
    var uid: String
    var name: String
    var score: Int
    var nights: Int
    var venues: Int?
    var id: String { uid }
}

/// Reads the static leaderboard JSON from Pages (free/cacheable). The hourly cron produces it
/// from the standings devices write; clients never hit RTDB for this.
nonisolated enum LeaderboardAPI {
    static let base = "https://tidbitstrivia.com/data/leaderboard"

    /// {season: [venue, …]}, newest season first is the caller's job.
    static func index() async -> [String: [String]] {
        await fetch("\(base)/index.json") ?? [:]
    }
    static func overall(season: String) async -> [LeaderboardRow] {
        await fetch("\(base)/\(season)/_overall.json") ?? []
    }
    static func venue(season: String, venue: String) async -> [LeaderboardRow] {
        let v = venue.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? venue
        return await fetch("\(base)/\(season)/\(v).json") ?? []
    }

    private static func fetch<T: Decodable>(_ urlString: String) async -> T? {
        guard let url = URL(string: urlString),
              let (data, _) = try? await URLSession.shared.data(from: url) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}
