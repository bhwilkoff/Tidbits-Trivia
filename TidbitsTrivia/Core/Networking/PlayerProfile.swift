import Foundation

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

    /// `players/{uid}` — the public profile (anyone signed-in can read it for leaderboards;
    /// only the owner can write). Non-sensitive display + aggregate stats only.
    struct Profile: Codable, Equatable {
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
    struct Rating: Codable, Equatable {
        var value: Double           // current rating
        var games: Int              // rated games so far
        var provisional: Bool       // games < establishedAt
        static let start = 1000.0
        static let establishedAt = 15
    }

    /// The cross-context streak — kept alive by a solo game OR a live night, making the
    /// sparse event and daily solo play the SAME habit. Forgiving by design (freezes +
    /// restartable) — punishing streaks tank reviews (Duolingo lesson).
    struct Streak: Codable, Equatable {
        var current: Int
        var longest: Int
        var lastPlayedDay: String   // "yyyy-MM-dd" in the player's local zone
        var freezes: Int            // streak-protection tokens (auto-earned; a live night grants one)
    }

    /// Lifetime aggregate stats (the "deep stats" surface, and leaderboard tie-breakers).
    struct Stats: Codable, Equatable {
        var gamesPlayed: Int
        var questionsAnswered: Int
        var correct: Int
        var liveNights: Int         // live events attended (presence = joined the room)
        var venuesVisited: Int      // distinct venues (count only; the list is private)
    }

    /// `playersPrivate/{uid}` — owner-only. Contact is opt-in (lead capture); the linked
    /// native IDs map platform sign-ins to this shared uid; the venue list is the place
    /// graph (sensitive — where/when you play; private by default, shared by choice).
    struct Private: Codable, Equatable {
        var email: String? = nil            // opt-in only; never harvested silently
        var appleUserID: String? = nil      // Sign in with Apple
        var gameCenterID: String? = nil     // Game Center player (Apple)
        var playGamesID: String? = nil      // Google Play Games (Android)
        var googleUserID: String? = nil     // Google Sign-In (Android/web)
        var venues: [String]? = nil         // venue ids visited (place graph)
    }

    /// A single row a device writes after an event/game for the cross-venue leaderboard
    /// (`standings/{season}/{venue}/{uid}`). The cron aggregates these into static JSON.
    struct Standing: Codable, Equatable {
        var name: String            // display name snapshot (so the cron needn't join)
        var score: Int              // this player's season score at this venue
        var nights: Int             // nights attended at this venue (the "Regular" track)
        var updatedAt: Int          // epoch ms
    }

    /// Season id, e.g. "2026-S3". Kept coarse so standings partition cleanly.
    static func standingPath(season: String, venue: String, uid: String) -> String {
        "standings/\(season)/\(venue)/\(uid)"
    }
}
