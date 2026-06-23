import Foundation
import CryptoKit

/// Phase-1 phone-as-buzzer wire protocol — shared by the tvOS host and the iOS
/// buzzer client (Decision 030). This file is pure value-logic: messages, room
/// code → PSK derivation, and the authoritative buzz arbiter. It imports NO
/// Network.framework, so it compiles for every os() target AND can be exercised
/// by an offline harness (the arbiter is the load-bearing fairness piece).
///
/// The transport that carries these messages (NWListener on tvOS, NWBrowser /
/// NWConnection on iOS) lives in BuzzerHost.swift / BuzzerClient.swift.
enum Buzzer {

    /// Bonjour service type the host advertises and the client browses for.
    /// The host is always an Apple TV (or an iPhone in dev); phones are clients.
    static let serviceType = "_tidbits-buzz._tcp"

    /// Wire framing: each message is a length-prefixed JSON blob. A single
    /// UInt32 big-endian byte count precedes the JSON so a stream read can
    /// reassemble whole messages (raw NWConnection receive is byte-oriented).
    static let headerBytes = 4
    static let maxMessageBytes = 64 * 1024
}

// MARK: - Messages

/// One frame on the wire. `Codable` both directions; `kind` keeps it
/// self-describing and forward-compatible (an unknown future kind decodes to
/// `.unknown` instead of failing the whole stream).
struct BuzzerMessage: Codable, Sendable, Equatable {
    enum Kind: String, Codable, Sendable {
        // client → host
        case join          // a phone asks to take a seat (carries displayName)
        case buzz          // a phone buzzes in (carries the client send stamp)
        case answer        // the buzz-winner's chosen option (carries chosenIndex)
        case pong          // round-trip probe reply (carries the host + client stamps)
        // host → client
        case welcome       // seat granted (carries seat + room display name)
        case roster        // the current player list (carries players)
        case question      // the active question to render on phones (prompt + options)
        case armed         // buzzing is now open for this question (carries questionIndex)
        case awarded       // someone won the buzz (carries winnerSeat) — they now answer
        case result        // the winner's answer was judged (carries correct + correctIndex)
        case locked        // buzzing closed; wait for the next question
        case ping          // round-trip probe (carries the host stamp)
        case unknown       // forward-compat: an unrecognized kind
    }

    var kind: Kind
    var displayName: String?
    /// A stable per-device id the phone generates once and persists. The host
    /// keys seats by this, so a reconnecting DEVICE resumes its seat + score
    /// regardless of the name typed (Decision 030 reconnection-by-identity).
    var deviceID: String?
    var seat: Int?
    var roomName: String?
    var questionIndex: Int?
    var winnerSeat: Int?
    var players: [BuzzerPlayer]?
    // Question streaming (host → phones) + answering (phone → host).
    var prompt: String?
    var options: [String]?
    var chosenIndex: Int?      // the buzz-winner's tapped option (phone → host)
    var correctIndex: Int?     // revealed with `result` so phones can highlight the answer
    var correct: Bool?         // whether the winner's answer was right
    var points: Int?           // points awarded for a correct answer (every device shows it)
    var timedOut: Bool?        // a no-winner reveal: true = clock ran out, false = everyone answered wrong
    /// Monotonic milliseconds from the *sender's* clock — never compared across
    /// machines (clocks are unsynchronized); used only to measure round-trip on
    /// the host so it can RTT-compensate buzz arrival (see BuzzArbiter).
    var stampMillis: Double?
    var hostStampMillis: Double?

    init(_ kind: Kind) { self.kind = kind }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Tolerate a future/unknown kind rather than tearing down the stream.
        self.kind = (try? c.decode(Kind.self, forKey: .kind)) ?? .unknown
        displayName = try c.decodeIfPresent(String.self, forKey: .displayName)
        deviceID = try c.decodeIfPresent(String.self, forKey: .deviceID)
        seat = try c.decodeIfPresent(Int.self, forKey: .seat)
        roomName = try c.decodeIfPresent(String.self, forKey: .roomName)
        questionIndex = try c.decodeIfPresent(Int.self, forKey: .questionIndex)
        winnerSeat = try c.decodeIfPresent(Int.self, forKey: .winnerSeat)
        players = try c.decodeIfPresent([BuzzerPlayer].self, forKey: .players)
        prompt = try c.decodeIfPresent(String.self, forKey: .prompt)
        options = try c.decodeIfPresent([String].self, forKey: .options)
        chosenIndex = try c.decodeIfPresent(Int.self, forKey: .chosenIndex)
        correctIndex = try c.decodeIfPresent(Int.self, forKey: .correctIndex)
        correct = try c.decodeIfPresent(Bool.self, forKey: .correct)
        points = try c.decodeIfPresent(Int.self, forKey: .points)
        timedOut = try c.decodeIfPresent(Bool.self, forKey: .timedOut)
        stampMillis = try c.decodeIfPresent(Double.self, forKey: .stampMillis)
        hostStampMillis = try c.decodeIfPresent(Double.self, forKey: .hostStampMillis)
    }
}

struct BuzzerPlayer: Codable, Sendable, Equatable, Identifiable {
    var seat: Int
    var name: String
    var score: Int = 0
    var id: Int { seat }
}

// MARK: - Room code → PSK

/// A short, human-shareable room code shown on the TV. Excludes ambiguous
/// glyphs (0/O, 1/I) so a code read across the room is unambiguous.
enum RoomCode {
    static let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
    static let length = 4

    /// Generate a fresh code using the system CSPRNG (not seedable RNG — this
    /// is a security/uniqueness boundary, not deterministic game content).
    static func generate() -> String {
        String((0..<length).map { _ in alphabet[Int.random(in: 0..<alphabet.count)] })
    }

    /// Derive the TLS pre-shared key from the room code. Both sides compute the
    /// same key from the same code — so a phone that can read the TV's code can
    /// pair, and one that can't, can't. Salted + domain-separated so the code
    /// alone (low entropy) isn't the raw key material.
    static func presharedKey(for code: String) -> SymmetricKey {
        let salted = Data("tidbits-buzz-v1:\(code.uppercased())".utf8)
        return SymmetricKey(data: SHA256.hash(data: salted))
    }

    /// The PSK as Data, for Network.framework's `sec_protocol_options` API.
    static func presharedKeyData(for code: String) -> Data {
        presharedKey(for: code).withUnsafeBytes { Data($0) }
    }

    /// A short identity tag the TLS handshake binds the PSK to (the "hint").
    static let pskIdentity = "tidbits-buzz"
}

// MARK: - Authoritative buzz arbiter

/// The single source of truth for "who buzzed first" — owned by the host, the
/// one clock everyone is measured against (Decision 030; Part C fairness rule:
/// never compare client timestamps, they're unsynchronized and spoofable).
///
/// For each buzz the host stamps the *arrival* time on its own clock, then
/// subtracts a per-seat one-way delay estimate (½ the measured round-trip) so a
/// player on a slower link whose finger was actually first still wins. First
/// effective time after `arm()` takes it; later buzzes are ignored until the
/// next `arm()`. Pure and Sendable so it can be unit-exercised offline.
struct BuzzArbiter: Sendable {
    private(set) var armed = false
    private(set) var winner: Int?
    private var bestEffective = Double.greatestFiniteMagnitude
    /// seat → estimated one-way delay (ms). Seeded from ping/pong round-trips.
    private var oneWayDelayMillis: [Int: Double] = [:]

    /// Record a round-trip sample for a seat (from a ping→pong exchange). Stores
    /// half the RTT as the one-way estimate, smoothed toward the new sample.
    mutating func observeRoundTrip(seat: Int, rttMillis: Double) {
        let oneWay = max(0, rttMillis / 2)
        if let prior = oneWayDelayMillis[seat] {
            oneWayDelayMillis[seat] = prior * 0.6 + oneWay * 0.4   // light EWMA
        } else {
            oneWayDelayMillis[seat] = oneWay
        }
    }

    /// Open buzzing for a new question — clears the prior winner.
    mutating func arm() {
        armed = true
        winner = nil
        bestEffective = .greatestFiniteMagnitude
    }

    /// Close buzzing (timeout, or after a wrong buzz fully resolves).
    mutating func disarm() { armed = false }

    /// Register a buzz. `arrivalMillis` is the host-clock arrival time. Returns
    /// the current winning seat if this buzz won (else nil — too late or closed).
    @discardableResult
    mutating func registerBuzz(seat: Int, arrivalMillis: Double) -> Int? {
        guard armed else { return nil }
        let effective = arrivalMillis - (oneWayDelayMillis[seat] ?? 0)
        guard effective < bestEffective else { return nil }
        bestEffective = effective
        winner = seat
        return seat
    }
}
