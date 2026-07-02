import Foundation
import CryptoKit

/// Trivia Night local-multiplayer wire protocol — shared by EVERY Apple device
/// (Decision 033). Any device can host a night or join one; there is no special
/// "TV host" / "phone client" split anymore. This file is pure value-logic:
/// messages, the room code → PSK derivation, and the seat/player model. It
/// imports NO Network.framework, so it compiles for every os() target and can be
/// exercised offline.
///
/// The transport that carries these messages (NWListener to host, NWBrowser /
/// NWConnection to join) lives in NightTransport / NightHost / NightClient — all
/// platform-agnostic, because hosting is no longer TV-only.
enum Night {

    /// Bonjour service type the host advertises and a joiner browses for.
    static let serviceType = "_tidbits-night._tcp"

    /// Wire framing: a 4-byte big-endian length prefix + JSON body. The night
    /// payload (plan + the whole question list) rides one message, so the cap is
    /// generous — a "Works" night is ~40 KB of JSON; 1 MB leaves wide headroom.
    static let headerBytes = 4
    static let maxMessageBytes = 1 << 20

    /// The fixed "room code" for Game Center matches (Decision 039): GameKit
    /// has no human-relayed code and its link is already authenticated, so
    /// both sides key the wire's GCM with this constant — the crypto becomes
    /// plain framing and the wire stays byte-identical to the local night.
    static let gameKitCode = "GKQM"
}

// MARK: - Messages

/// One frame on the wire. `Codable` both directions; `kind` keeps it
/// self-describing and forward-compatible (an unknown future kind decodes to
/// `.unknown` instead of failing the whole stream).
struct NightMessage: Codable, Sendable {
    enum Kind: String, Codable, Sendable {
        // joiner → host
        case join          // ask for a seat (carries displayName + deviceID)
        case answered      // I locked an answer this question (carries index, total score, correct)
        case leave         // I'm leaving the room
        // host → joiner
        case welcome       // seat granted (carries seat + room display name)
        case roster        // the current standings (carries players, with live scores)
        case night         // the whole night: plan + the full question list (sent once on start / rejoin)
        case begin         // everyone go to this question now (carries questionIndex)
        case reveal        // everyone reveal the answer now (carries questionIndex)
        case finished      // the night is over — show the final standings
        case unknown       // forward-compat: an unrecognized kind
    }

    var kind: Kind
    var displayName: String?
    /// A stable per-device id the joiner generates once and persists. The host
    /// keys seats by this, so a reconnecting DEVICE resumes its seat + score
    /// regardless of the name typed (Decision 030 reconnection-by-identity).
    var deviceID: String?
    var seat: Int?
    var roomName: String?
    var players: [NightPlayer]?
    var questionIndex: Int?
    /// The night content — only present on a `.night` message. Both are `Codable`,
    /// so they embed directly; every device runs its OWN engine over this exact
    /// list and scores itself locally (Decision 033 — host trusts self-reports).
    var plan: NightPlan?
    /// Id-based night (future corpus-parity optimization) — the resolver prefers
    /// ids, falling back to the canonical `questions` below for any it can't find.
    var questionIds: [String]?
    /// The night content as canonical cross-platform wire questions, so a Kotlin
    /// or Swift peer renders it without canonicalizing each other's Question type.
    var questions: [WireQuestion]?
    /// On `.answered`: the joiner's running TOTAL score and whether THIS question
    /// was correct, so the host can update the standings without re-judging.
    var score: Int?
    var correct: Bool?

    init(_ kind: Kind) { self.kind = kind }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.kind = (try? c.decode(Kind.self, forKey: .kind)) ?? .unknown
        displayName = try c.decodeIfPresent(String.self, forKey: .displayName)
        deviceID = try c.decodeIfPresent(String.self, forKey: .deviceID)
        seat = try c.decodeIfPresent(Int.self, forKey: .seat)
        roomName = try c.decodeIfPresent(String.self, forKey: .roomName)
        players = try c.decodeIfPresent([NightPlayer].self, forKey: .players)
        questionIndex = try c.decodeIfPresent(Int.self, forKey: .questionIndex)
        plan = try c.decodeIfPresent(NightPlan.self, forKey: .plan)
        questionIds = try c.decodeIfPresent([String].self, forKey: .questionIds)
        questions = try c.decodeIfPresent([WireQuestion].self, forKey: .questions)
        score = try c.decodeIfPresent(Int.self, forKey: .score)
        correct = try c.decodeIfPresent(Bool.self, forKey: .correct)
    }
}

/// One seat at the night — a connected (or recently-dropped) device. `answered`
/// is the per-question flag the host resets each `begin`, so the host UI can show
/// "k of n answered" before it reveals.
struct NightPlayer: Codable, Sendable, Equatable, Identifiable {
    var seat: Int
    var name: String
    var score: Int = 0
    var answered: Bool = false
    /// True for the device that is hosting — its row gets a quiet "Host" tag.
    var isHost: Bool = false
    var id: Int { seat }
}

extension NightPlayer {
    // Lenient decode: an Android host (kotlinx encodeDefaults=false) omits fields
    // equal to their default (score=0, answered=false, isHost=false). Tolerate them
    // so a `roster` from Android doesn't fail to decode → "0 in the room".
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        seat = try c.decode(Int.self, forKey: .seat)
        name = (try? c.decode(String.self, forKey: .name)) ?? "Player \(seat)"
        score = (try? c.decode(Int.self, forKey: .score)) ?? 0
        answered = (try? c.decode(Bool.self, forKey: .answered)) ?? false
        isHost = (try? c.decode(Bool.self, forKey: .isHost)) ?? false
    }
}

// MARK: - Room code → PSK

/// A short, human-shareable room code the host shows. Excludes ambiguous glyphs
/// (0/O, 1/I) so a code read across the room is unambiguous.
enum RoomCode {
    static let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
    static let length = 4

    /// Generate a fresh code using the system CSPRNG (not seedable RNG — this is
    /// a uniqueness boundary, not deterministic game content).
    static func generate() -> String {
        String((0..<length).map { _ in alphabet[Int.random(in: 0..<alphabet.count)] })
    }

    /// Derive the TLS pre-shared key from the room code. Both sides compute the
    /// same key from the same code — so a device that can read the host's code
    /// can pair, and one that can't, can't. Salted + domain-separated so the code
    /// alone (low entropy) isn't the raw key material.
    static func presharedKey(for code: String) -> SymmetricKey {
        let salted = Data("tidbits-night-v1:\(code.uppercased())".utf8)
        return SymmetricKey(data: SHA256.hash(data: salted))
    }

    /// The PSK as Data, for Network.framework's `sec_protocol_options` API.
    static func presharedKeyData(for code: String) -> Data {
        presharedKey(for: code).withUnsafeBytes { Data($0) }
    }

    /// A short identity tag (kept for reference; v2 uses the key for AES-GCM, not TLS).
    static let pskIdentity = "tidbits-night"
}

// MARK: - Canonical wire question (cross-platform)

/// The night ships questions in this shape — field names match the Android
/// `WireQuestion` exactly (docs/CROSS-PLATFORM-MULTIPLAYER.md) so a Swift host's
/// night renders on a Kotlin joiner and vice versa. It's a transport DTO, not the
/// app's `Question`: `categoryId`/`sourceUrl` (not `categoryID`/`sourceURL`), and
/// no `templateID`. The custom decoder tolerates keys Android omits when a value
/// equals its default (kotlinx `encodeDefaults = false`).
struct WireClosest: Codable, Sendable { let answer, min, max, step, tolerance: Double; let unit: String }
struct WireMatch: Codable, Sendable { let keys: [String]; let values: [String] }
struct WireEnum: Codable, Sendable { let groups: [[String]] }

struct WireQuestion: Codable, Sendable {
    var id: String
    var prompt: String
    var options: [String]
    var correctIndex: Int
    var categoryId: String
    var difficulty: Int
    var explanation: String
    var sourceTitle: String
    var sourceUrl: String
    var imageUrl: String?
    var closest: WireClosest?
    var ordering: [String]?
    var matching: WireMatch?
    var accepted: [String]?
    var enumerate: WireEnum?
    var roundIndex: Int?

    init(id: String, prompt: String, options: [String], correctIndex: Int, categoryId: String,
         difficulty: Int, explanation: String, sourceTitle: String, sourceUrl: String, imageUrl: String?,
         closest: WireClosest?, ordering: [String]?, matching: WireMatch?, accepted: [String]?,
         enumerate: WireEnum?, roundIndex: Int?) {
        self.id = id; self.prompt = prompt; self.options = options; self.correctIndex = correctIndex
        self.categoryId = categoryId; self.difficulty = difficulty; self.explanation = explanation
        self.sourceTitle = sourceTitle; self.sourceUrl = sourceUrl; self.imageUrl = imageUrl
        self.closest = closest; self.ordering = ordering; self.matching = matching
        self.accepted = accepted; self.enumerate = enumerate; self.roundIndex = roundIndex
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        prompt = (try? c.decode(String.self, forKey: .prompt)) ?? ""
        options = (try? c.decode([String].self, forKey: .options)) ?? []
        correctIndex = (try? c.decode(Int.self, forKey: .correctIndex)) ?? 0
        categoryId = (try? c.decode(String.self, forKey: .categoryId)) ?? "mixed"
        difficulty = (try? c.decode(Int.self, forKey: .difficulty)) ?? 3
        explanation = (try? c.decode(String.self, forKey: .explanation)) ?? ""
        sourceTitle = (try? c.decode(String.self, forKey: .sourceTitle)) ?? ""
        sourceUrl = (try? c.decode(String.self, forKey: .sourceUrl)) ?? ""
        imageUrl = try? c.decodeIfPresent(String.self, forKey: .imageUrl)
        closest = try? c.decodeIfPresent(WireClosest.self, forKey: .closest)
        ordering = try? c.decodeIfPresent([String].self, forKey: .ordering)
        matching = try? c.decodeIfPresent(WireMatch.self, forKey: .matching)
        accepted = try? c.decodeIfPresent([String].self, forKey: .accepted)
        enumerate = try? c.decodeIfPresent(WireEnum.self, forKey: .enumerate)
        roundIndex = try? c.decodeIfPresent(Int.self, forKey: .roundIndex)
    }
}

extension Question {
    func toWire() -> WireQuestion {
        WireQuestion(
            id: id, prompt: prompt, options: options, correctIndex: correctIndex,
            categoryId: categoryID, difficulty: difficulty, explanation: explanation,
            sourceTitle: sourceTitle, sourceUrl: sourceURL?.absoluteString ?? "",
            imageUrl: imageURL?.absoluteString,
            closest: closest.map { WireClosest(answer: $0.answer, min: $0.min, max: $0.max, step: $0.step, tolerance: $0.tolerance, unit: $0.unit) },
            ordering: ordering,
            matching: matching.map { WireMatch(keys: $0.keys, values: $0.values) },
            accepted: accepted,
            enumerate: enumerate.map { WireEnum(groups: $0.groups) },
            roundIndex: roundIndex)
    }
}

extension WireQuestion {
    func toQuestion() -> Question {
        Question(
            id: id, prompt: prompt, options: options, correctIndex: correctIndex,
            categoryID: categoryId, difficulty: difficulty, explanation: explanation,
            sourceTitle: sourceTitle, sourceURL: URL(string: sourceUrl), templateID: "wire",
            imageURL: imageUrl.flatMap { URL(string: $0) },
            closest: closest.map { ClosestSpec(answer: $0.answer, min: $0.min, max: $0.max, step: $0.step, tolerance: $0.tolerance, unit: $0.unit) },
            ordering: ordering,
            matching: matching.map { MatchSpec(keys: $0.keys, values: $0.values) },
            accepted: accepted,
            enumerate: enumerate.map { EnumSpec(groups: $0.groups) },
            roundIndex: roundIndex)
    }
}
