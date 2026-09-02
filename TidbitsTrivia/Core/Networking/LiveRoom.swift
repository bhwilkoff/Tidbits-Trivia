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
        var options: [String]?  // present for MCQ; nil/empty for non-MCQ
        var format: String      // GameMode.rawValue — the joiner switches its answer UI on this
        var answerIndex: Int?   // correct option — ONLY populated in `reveal`
        // Non-MCQ payloads (additive; only the relevant one is set per `format`).
        // NONE of these leak the answer — the host auto-scores on reveal from its
        // own local Question (accepted lists / correct order / sets never ship).
        var imageURL: String? = nil       // pictureId
        var numeric: Numeric? = nil       // closestCall — bounds only, not the answer
        var orderItems: [String]? = nil   // ordering — items to arrange (correct order withheld)
        var matchKeys: [String]? = nil    // matching — the keys
        var matchValues: [String]? = nil  // matching — SHUFFLED values (correct pairing withheld)
        var enumTarget: Int? = nil        // enumerate — how many are in the set
        var locked: Bool? = nil           // cheating deterrence (§A5.3): "pencils down" — no more answers
        var story: String? = nil          // Wave A: the "story behind the answer" — the learning payoff, shown ONLY on reveal
        var deadline: Int? = nil          // Wave A: epoch-ms countdown deadline for a timed question (nil = no timer)
        var wager: Bool? = nil            // Wave A: this is a wager question — the joiner shows a wager stepper (0…their score)
        /// G1: this is a BUZZ question — the joiner shows one big BUZZ button
        /// instead of the answer UI, and the first team the SERVER sees wins the
        /// buzz. Published so a joiner knows without being told; nil on every
        /// non-buzz question, so an older client simply never sees it.
        var buzz: Bool? = nil
        /// G4: this round's FIRST-LETTER theme — every answer in it begins with
        /// this letter. Published so a player who joined mid-round still knows the
        /// rule instead of relying on having heard the host say it once; nil on
        /// every unthemed round, so an older client simply never sees it.
        var letter: String? = nil
    }

    /// Closest Call bounds a joiner needs to render a number input (the answer +
    /// tolerance stay on the host for reveal-time proximity scoring).
    struct Numeric: Codable, Equatable {
        var min: Double; var max: Double; var step: Double; var unit: String
    }

    /// A team as the joining player writes it (`teams/{uid}`). The running score
    /// lives separately in `scores/{uid}` (host-owned) so the host can adjust it.
    struct Team: Codable, Equatable {
        var name: String
        var joinedAt: Int
    }

    /// A player's submission for the current question (`answers/{qid}/{uid}`).
    /// The shape depends on the question `format`; only the relevant field is set.
    struct Answer: Codable, Equatable {
        var choice: Int? = nil  // MCQ / picture / this-or-that / odd-one-out
        var text: String? = nil // type-the-answer (free text)
        var number: Double? = nil // closest call (numeric estimate)
        var order: [Int]? = nil // ordering — the player's arrangement as indices into orderItems
        var pairs: [Int]? = nil // matching — for key i, the chosen matchValues index
        var list: [String]? = nil // enumerate — the names the player entered
        var wager: Int? = nil   // Wave A: points staked on this question (host clamps to the team's score at reveal)
        var blurred: Bool? = nil // Wave C: the player left the app/tab during this question before submitting (soft cheat signal)
        var ts: Int             // epoch ms from the PLAYER'S OWN device — what their screen shows them
        /// Epoch ms stamped by the SERVER when the write landed. Ordering must not
        /// depend on five different handset clocks: "fastest correct answer" was
        /// decided by `ts`, so a table whose phone ran three seconds fast collected
        /// the speed bonus every round without answering faster. Written as the RTDB
        /// server value `{".sv":"timestamp"}`; nil from a client that predates it,
        /// which is why every reader falls back to `ts`.
        var sv: Int? = nil
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
