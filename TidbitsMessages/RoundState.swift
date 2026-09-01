import Foundation

/// The entire game, encoded into an `MSMessage.url`.
///
/// There is no server and no shared database: the conversation IS the store. Every
/// device reconstructs the round from the message it received, applies its own
/// player's answer, and sends the result back as a replacement message in the same
/// `MSSession`. That means this type is a **wire format**, and the moment two app
/// versions exist in one thread it is a compatibility surface — hence `v`, and hence
/// `RoundStateTests` pinning the encoding with golden strings.
///
/// **The 5,000-character budget is the hard constraint of the whole feature.**
/// `MSMessage.url` throws `MSMessageErrorCode.urlExceedsMaxSize` past it, and there is
/// no server-free way around it — the cap exists so messages stay end-to-end
/// encrypted. So this carries question IDs, never question text: each device looks the
/// questions up in its own bundled pack. Carrying prompts and options would blow the
/// budget at roughly the second question.
struct RoundState: Equatable {
    /// Wire version. Bump ONLY with a matching decode path for the old value — a
    /// thread can contain messages from several app versions at once.
    static let version = 1

    /// Exactly `questionCount` pack ids, in play order.
    var questionIDs: [String]
    var players: [Player]
    /// 0-based index of the question currently being answered.
    var index: Int

    static let questionCount = 5
    /// Names are the one free-text field on the wire. Capped hard: a 200-character
    /// name from one prankster would eat the budget for everyone else in the thread.
    static let maxNameLength = 12

    struct Player: Equatable {
        /// First 8 chars of the participant UUID. Full UUIDs are 36 characters each
        /// and eight of them would spend 288 characters on identity alone; 8 is ample
        /// to disambiguate within one conversation.
        var id: String
        var name: String
        /// One character per question: "0"–"3" for a chosen option, "-" for unanswered.
        var answers: [Int?]

        var score: Int { 0 }   // scoring needs the pack; see RoundState.score(_:against:)
    }

    // MARK: - Encoding

    /// `https://tidbitstrivia.com/r?v=1&i=2&q=<id>~<id>…&p=<id8>:<name>:<answers>|…`
    ///
    /// **HTTPS, not a custom scheme.** This was `tidbits://round?…` and it did not
    /// work: the message arrived with `url` NIL, so every tap opened the start screen
    /// as though no round were attached. `MSMessage.url` is contracted to be a
    /// UNIVERSAL LINK — a URL that opens the app, and that Safari can fall back to
    /// when the recipient does not have it installed. An unregistered custom scheme is
    /// neither, and the system drops it in transit rather than erroring at send.
    ///
    /// tidbitstrivia.com is already an associated domain of the app, so this also
    /// gives the right behaviour for someone in the thread without Tidbits: the tap
    /// opens the site instead of doing nothing.
    ///
    /// Deliberately hand-rolled rather than JSON: JSON's braces, quotes and keys are
    /// all percent-encoded in a URL query, which roughly doubles the payload for data
    /// this simple. The budget is the point.
    func encoded() -> String {
        var c = URLComponents()
        c.scheme = "https"
        c.host = "tidbitstrivia.com"
        c.path = "/r"
        c.queryItems = [
            .init(name: "v", value: String(Self.version)),
            .init(name: "i", value: String(index)),
            .init(name: "q", value: questionIDs.joined(separator: "~")),
            .init(name: "p", value: players.map { p in
                let a = p.answers.map { $0.map(String.init) ?? "-" }.joined()
                return "\(p.id):\(Self.sanitize(p.name)):\(a)"
            }.joined(separator: "|")),
        ]
        return c.url?.absoluteString ?? ""
    }

    /// A name safe to put in the query: separators stripped, length capped.
    ///
    /// `:` and `|` are the field and record separators — a name containing either
    /// would silently corrupt every player after it, which is the kind of bug that
    /// only shows up when someone in the group is called "A|B".
    static func sanitize(_ name: String) -> String {
        let cleaned = name
            .replacingOccurrences(of: ":", with: " ")
            .replacingOccurrences(of: "|", with: " ")
            .replacingOccurrences(of: "~", with: " ")
            .replacingOccurrences(of: "&", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(cleaned.prefix(maxNameLength))
    }

    // MARK: - Decoding

    init(questionIDs: [String], players: [Player], index: Int = 0) {
        self.questionIDs = questionIDs
        self.players = players
        self.index = index
    }

    /// Returns nil for anything this build cannot interpret — a newer wire version, a
    /// truncated payload, a URL from some other app. A half-decoded round rendered as
    /// a real one is worse than an honest "this needs a newer Tidbits".
    init?(url: URL) {
        guard let c = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let items = c.queryItems else { return nil }
        func value(_ n: String) -> String? { items.first { $0.name == n }?.value }

        guard let v = value("v"), Int(v) == Self.version else { return nil }
        guard let q = value("q"), !q.isEmpty else { return nil }
        let ids = q.components(separatedBy: "~").filter { !$0.isEmpty }
        guard !ids.isEmpty else { return nil }

        let idx = Int(value("i") ?? "0") ?? 0
        var parsed: [Player] = []
        for record in (value("p") ?? "").components(separatedBy: "|") where !record.isEmpty {
            let f = record.components(separatedBy: ":")
            guard f.count == 3 else { continue }
            let answers = f[2].map { ch -> Int? in
                guard let n = Int(String(ch)), (0...3).contains(n) else { return nil }
                return n
            }
            parsed.append(Player(id: f[0], name: f[1], answers: answers))
        }

        self.init(questionIDs: ids, players: parsed,
                  index: min(max(0, idx), max(0, ids.count - 1)))
    }

    // MARK: - Play

    /// Whether this round still fits the wire budget if one more player joins.
    ///
    /// Checked BEFORE inserting a player rather than after encoding, because the
    /// failure mode otherwise is that the message send throws and the player's answer
    /// vanishes with no explanation.
    var hasRoomForAnotherPlayer: Bool {
        let projected = encoded().count
            + Self.maxNameLength + 8 + Self.questionCount + 3
        return projected < 4_500      // headroom under the 5,000 cap
    }

    mutating func upsert(playerID: String, name: String) {
        if let i = players.firstIndex(where: { $0.id == playerID }) {
            players[i].name = Self.sanitize(name)
        } else {
            players.append(Player(id: playerID, name: Self.sanitize(name),
                                  answers: Array(repeating: nil, count: questionIDs.count)))
        }
    }

    mutating func answer(playerID: String, choice: Int) {
        guard let i = players.firstIndex(where: { $0.id == playerID }),
              index < players[i].answers.count else { return }
        // First answer stands. Without this, tapping again after the reveal would let
        // a player correct themselves once they have seen everyone else's pick.
        guard players[i].answers[index] == nil else { return }
        players[i].answers[index] = choice
    }

    func hasAnswered(playerID: String) -> Bool {
        guard let p = players.first(where: { $0.id == playerID }),
              index < p.answers.count else { return false }
        return p.answers[index] != nil
    }

    /// Everyone in the round has answered the current question.
    var currentQuestionComplete: Bool {
        !players.isEmpty && players.allSatisfy {
            index < $0.answers.count && $0.answers[index] != nil
        }
    }

    var isFinished: Bool { index >= questionIDs.count - 1 && currentQuestionComplete }

    /// Score a player against the answer key. Kept out of `Player` because scoring
    /// needs the pack and the wire format deliberately does not carry answers.
    func score(_ player: Player, correctIndexFor: (String) -> Int?) -> Int {
        zip(questionIDs, player.answers).reduce(into: 0) { total, pair in
            let (qid, given) = pair
            if let given, let key = correctIndexFor(qid), given == key { total += 1 }
        }
    }
}
