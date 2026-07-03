import Foundation

/// The Tidbits Live room wire contract over Firebase RTDB (path: `live/{code}`).
/// Shared by the Mac host (writes `meta`/`pub`/`scores`) and the iOS join surface
/// (writes `teams/{uid}` + `answers/{qid}/{uid}`). Web (`js/live.js`) and Android
/// (`FirebaseNet.kt`) mirror these EXACT keys — this is the cross-platform
/// contract. Security: see `database.rules.json` (`live` block); the host owns
/// meta/pub/scores, players own their own team + answers.
///
/// Additive-only evolution: never repurpose a key; add new optional ones.
enum LiveRoom {
    static let basePath = "live"
    static func path(_ code: String) -> String { "\(basePath)/\(code)" }

    /// Room identity + lifecycle (host-owned).
    struct Meta: Codable, Equatable {
        var host: String        // host uid — the rules key writes off this
        var createdAt: Int      // epoch ms
        var name: String
        var venue: String
        var state: String       // "lobby" | "live" | "ended"
    }

    /// The host-published live state — what every joined player renders. The host
    /// overwrites this as it advances; players stream it.
    struct Pub: Codable, Equatable {
        var round: Int          // 1-based round number
        var roundTitle: String
        var qid: String         // stable id for answer keying, e.g. "r0q3"
        var qNum: Int           // 1-based question number within the round
        var qTotal: Int
        var phase: String       // Phase.*
        var prompt: String
        var options: [String]?  // present for MCQ; nil/empty for free-text
        var format: String      // GameMode.rawValue of the round
        var answerIndex: Int?   // correct option — ONLY populated in `reveal`
    }

    /// A team as the joining player writes it (`teams/{uid}`). The running score
    /// lives separately in `scores/{uid}` (host-owned) so the host can adjust it.
    struct Team: Codable, Equatable {
        var name: String
        var joinedAt: Int
    }

    /// A player's submission for the current question (`answers/{qid}/{uid}`).
    struct Answer: Codable, Equatable {
        var choice: Int?        // selected option index (MCQ)
        var text: String?       // free-text answer (typed formats)
        var ts: Int             // epoch ms — first-submission ordering / speed
    }

    enum Phase {
        static let intro = "intro"          // round card, no question yet
        static let question = "question"    // question shown, accepting answers
        static let reveal = "reveal"        // answer shown, answers locked
        static let ended = "ended"          // night over → final standings
    }

    /// Stable per-question id used to key answers (survives reveal/advance).
    static func qid(round: Int, question: Int) -> String { "r\(round)q\(question)" }
}
