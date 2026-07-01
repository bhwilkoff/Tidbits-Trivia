import Foundation

/// Trivia Night — the configurable "bar trivia" mode. A night is a sequence of
/// themed **rounds**, each round drawing a fixed count of one question TYPE from
/// the existing corpus / enrichment sets. This mirrors a real pub quiz: the round
/// is the unit of pacing and theme (GAME-MODES-RESEARCH Part A's load-bearing
/// idea), and pulling from every question type is the whole point — one night
/// exercises recall, estimation, ordering, categorization, and picture ID, each
/// still ending on the shared "Learn the fact" reveal.
///
/// Bar Trivia is a CLIENT meta-mode (like Stake/Sweep): it composes existing
/// question sources into one mixed list and runs it through the shape-routing
/// `GameEngine` — no new question type, no corpus change (Decisions 025/031).
/// How the configured night is played (Decision 033). `solo` runs on this one
/// device (pass-and-play); `host` opens a room any other Apple device can join.
enum NightStartMode: Hashable, Sendable { case solo, host }

struct NightRound: Identifiable, Hashable, Sendable, Codable {
    /// The question TYPE this round draws from — a `GameMode` whose questions
    /// have a distinct shape the engine already renders.
    var kind: GameMode
    var count: Int
    var id: String { kind.rawValue }
    var title: String { kind.nightRoundTitle }
    var symbol: String { kind.symbol }

    enum CodingKeys: String, CodingKey { case kind, count }
}

/// `Codable` because a host serializes the plan over the wire to every joiner so
/// each device builds the SAME night (Decision 033).
struct NightPlan: Hashable, Sendable, Codable {
    var rounds: [NightRound]
    /// Empty = solo / networked-everyone-plays. Two or more = pass-and-play teams
    /// (one device handed around).
    var teams: [String] = []

    var totalQuestions: Int { rounds.reduce(0) { $0 + $1.count } }
    var isTeam: Bool { teams.count >= 2 }

    enum CodingKeys: String, CodingKey { case rounds, teams }

    /// The question types a night can be built from — every shape the engine
    /// renders, in a sensible default running order.
    static let allKinds: [GameMode] = [
        .classic, .pictureId, .thisOrThat, .closestCall,
        .ordering, .matching, .typeAnswer, .oddOneOut, .enumerate,
    ]

    // MARK: Presets (the host's starting points; counts are tunable)

    /// A short night — three quick rounds, ~12 questions.
    static let quick = NightPlan(rounds: [
        NightRound(kind: .classic, count: 5),
        NightRound(kind: .pictureId, count: 4),
        NightRound(kind: .closestCall, count: 3),
    ])

    /// The canonical pub night — five varied rounds, ~22 questions.
    static let pub = NightPlan(rounds: [
        NightRound(kind: .classic, count: 6),
        NightRound(kind: .pictureId, count: 4),
        NightRound(kind: .thisOrThat, count: 4),
        NightRound(kind: .closestCall, count: 4),
        NightRound(kind: .oddOneOut, count: 4),
    ])

    /// The works — one round of every question type, ~28 questions.
    static let works = NightPlan(rounds: allKinds.map {
        NightRound(kind: $0, count: $0 == .enumerate ? 2 : 4)
    })

    static let presets: [(name: String, blurb: String, plan: NightPlan)] = [
        ("Quick Night", "3 rounds · ~12 questions", quick),
        ("Pub Night", "5 rounds · ~22 questions", pub),
        ("The Works", "Every question type · ~28", works),
    ]
}

extension NightPlan {
    // Lenient decode: an Android host omits `teams` when empty (kotlinx
    // encodeDefaults=false). Tolerate it so a `night` from Android decodes →
    // otherwise the joiner never gets the questions and hangs on "waiting".
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        rounds = try c.decode([NightRound].self, forKey: .rounds)
        teams = (try? c.decode([String].self, forKey: .teams)) ?? []
    }
}
