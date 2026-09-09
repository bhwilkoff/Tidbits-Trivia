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
        /// G5: the pick-a-category grid, published so the room can read what is
        /// left from their own phones — a table at the back cannot always see the
        /// projector. Present ONLY during `Phase.board`; nil otherwise, so an
        /// older client never sees it.
        var board: BoardPub? = nil
        /// Decision 060: the clip attached to this question, offered to every
        /// joiner — the audio of a name-that-tune round or the video of a video
        /// question, which until now played ONLY on the host's PA and projector.
        /// nil on a question without a clip, so an older client never sees it.
        var media: Media? = nil
    }

    /// Decision 060: a clip as the joiners are given it. `url` is an https file
    /// URL when the media has one, otherwise `room:<id>` — a reference to the
    /// once-written `live/{code}/media/{id}` node (`RoomMedia`) that the joiner
    /// fetches ONCE and caches by id. Never a `tidbits-media:` reference: a phone
    /// cannot open the host's package.
    nonisolated struct Media: Codable, Equatable {
        var kind: String          // "audio" | "video"
        var url: String           // https://… | room:<id>
        var mime: String          // audio/mpeg, video/mp4, …
        var name: String? = nil   // the clip's display name (never the host's path)
        var bytes: Int? = nil     // size of the file behind `url`, so a joiner can say "1.2 MB" before fetching
        /// Epoch ms when the host pressed Play. A joiner that may autoplay starts
        /// from the matching offset; one that may not shows its Play control. nil
        /// until the host plays, so a clip is always an OFFER first.
        var startedAt: Int? = nil
    }

    /// Decision 060: the once-written media node, `live/{code}/media/{id}`.
    /// Base64 of the file, capped (`mediaMaxBytes`) so a room of forty phones on
    /// venue Wi-Fi can fetch it and the RTDB free tier never meters it. The host
    /// writes it BEFORE publishing the `pub` that references it, and only once per
    /// room per id.
    nonisolated struct RoomMedia: Codable, Equatable {
        var kind: String
        var mime: String
        var bytes: Int
        var b64: String
    }
    /// The largest file a host will publish as a room node (raw bytes; the base64
    /// is 4/3 of this and the rules validate that length).
    nonisolated static let mediaMaxBytes = 3_000_000
    nonisolated static let mediaScheme = "room"
    static func mediaPath(_ code: String, id: String) -> String { "\(path(code))/media/\(id)" }
    /// `room:<id>` → id; anything else → nil.
    nonisolated static func mediaID(from url: String) -> String? {
        guard url.hasPrefix(mediaScheme + ":") else { return nil }
        let id = String(url.dropFirst(mediaScheme.count + 1))
        return id.isEmpty ? nil : id
    }

    /// G5: the grid as the joiners see it. Deliberately NOT the host's LiveBoard:
    /// that carries the question id of every cell, and shipping those to a phone
    /// hands the room a map of the night's content.
    struct BoardPub: Codable, Equatable {
        var categories: [String]      // display names, column order
        var tiers: [Int]
        /// "columnIndex:tier" of every played cell — positional, NOT the category
        /// id. The joiner has only the display names, and keying on ids would both
        /// force it to carry the id list and leak the host's category slugs.
        var taken: [String]
        var chooser: String? = nil    // whose turn it is to pick
        var remaining: Int = 0
        var points: Int = 0
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
        /// G5: the pick-a-category GRID is up and no cell has been chosen yet.
        /// A distinct phase because there is no live question during it — leaving
        /// the joiners on `question` left the PREVIOUS question on their phones,
        /// with its answer buttons still live, while the room was picking.
        static let board = "board"
    }

    /// Stable per-question id used to key answers (survives reveal/advance).
    static func qid(round: Int, question: Int) -> String { "r\(round)q\(question)" }
}
