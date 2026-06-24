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
    var questions: [Question]?
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
        questions = try c.decodeIfPresent([Question].self, forKey: .questions)
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

    /// A short identity tag the TLS handshake binds the PSK to (the "hint").
    static let pskIdentity = "tidbits-night"
}
