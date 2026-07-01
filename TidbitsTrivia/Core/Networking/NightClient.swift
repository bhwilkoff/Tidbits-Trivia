import Foundation
import Observation
import CryptoKit

/// The joiner side of a Trivia Night (Decision 033) — runs on ANY Apple device.
/// Discovers the host's room by code, connects, receives the whole night, and
/// then follows the host's pacing signals. It plays on its OWN screen and scores
/// itself locally, reporting only its running total back to the host.
///
/// The actual game (rendering questions, capturing answers) is driven by
/// `LiveNight`, which wires these callbacks to a local `GameEngine`.
///
/// Link-layer-agnostic: discovery + byte transport live behind
/// `NightClientTransport` (Bonjour mDNS+TCP by default; Wi-Fi Aware / BLE
/// later). This class owns the protocol, the crypto, and the retry policy.
@Observable
@MainActor
final class NightClient {
    enum Status: Equatable { case idle, searching, connecting, joined, failed(String) }

    private(set) var status: Status = .idle
    private(set) var seat: Int?
    private(set) var roomName: String?
    private(set) var players: [NightPlayer] = []
    var displayName = ""

    // One-shot signals the coordinator wires to the local engine.
    var onNight: ((NightPlan, [Question]) -> Void)?
    var onBegin: ((Int) -> Void)?
    var onReveal: ((Int) -> Void)?
    var onFinished: (() -> Void)?

    private let transport: any NightClientTransport
    private var link: (any NightPeerLink)?
    private var key = RoomCode.presharedKey(for: "")
    private var framer = NightFramer(key: RoomCode.presharedKey(for: ""))
    private var code = ""
    private let deviceID = NightClient.loadDeviceID()
    private var intentionalLeave = false
    private var reconnectAttempts = 0

    init(transport: any NightClientTransport = BonjourClientTransport()) {
        self.transport = transport
    }

    /// The last room this device joined — pre-filled next time so a recognized
    /// device doesn't have to retype the code.
    static var lastCode: String { UserDefaults.standard.string(forKey: "tidbits.night.lastCode") ?? "" }
    static var lastName: String { UserDefaults.standard.string(forKey: "tidbits.night.lastName") ?? "" }

    private static func loadDeviceID() -> String {
        let key = "tidbits.night.deviceID"
        if let id = UserDefaults.standard.string(forKey: key) { return id }
        let id = UUID().uuidString
        UserDefaults.standard.set(id, forKey: key)
        return id
    }

    // MARK: Join / leave

    func join(code: String, name: String) {
        intentionalLeave = false
        reconnectAttempts = 0
        self.code = code.uppercased()
        key = RoomCode.presharedKey(for: self.code)
        framer = NightFramer(key: key)
        displayName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        UserDefaults.standard.set(self.code, forKey: "tidbits.night.lastCode")
        UserDefaults.standard.set(displayName, forKey: "tidbits.night.lastName")
        startConnect()
    }

    private func startConnect() {
        link = nil
        status = .searching
        transport.connect(
            roomCode: code,
            onConnected: { [weak self] link in self?.onConnected(link) },
            onFrame: { [weak self] bytes in
                guard let self else { return }
                for m in self.framer.ingest(bytes) { self.handle(m) }
            },
            onDropped: { [weak self] in self?.attemptReconnect() },
            onStatus: { [weak self] s in
                switch s {
                case .searching:  self?.status = .searching
                case .connecting: self?.status = .connecting
                }
            })
    }

    /// A drop mid-game silently re-discovers the room and rejoins (the host
    /// replays the night + current question) — no tap, no re-entering the code.
    private func attemptReconnect() {
        guard !intentionalLeave, !code.isEmpty, reconnectAttempts < 8 else {
            if !intentionalLeave { status = .failed("Lost the room — tap to rejoin") }
            return
        }
        reconnectAttempts += 1
        startConnect()
    }

    func leave() {
        intentionalLeave = true
        if let link, let frame = NightTransport.encode(NightMessage(.leave), key: key) {
            link.send(frame)
        }
        transport.disconnect()
        link = nil
        status = .idle; seat = nil; roomName = nil; players = []
    }

    // MARK: Reporting

    /// Tell the host this device locked an answer this question, with the running
    /// total + whether it was right — the host folds it into the standings.
    func reportAnswer(score: Int, correct: Bool) {
        guard let link else { return }
        var m = NightMessage(.answered)
        m.score = score; m.correct = correct
        guard let frame = NightTransport.encode(m, key: key) else { return }
        link.send(frame)
    }

    // MARK: Connection → join handshake

    private func onConnected(_ link: any NightPeerLink) {
        self.link = link
        var join = NightMessage(.join)
        join.displayName = displayName.isEmpty ? nil : displayName
        join.deviceID = deviceID
        guard let frame = NightTransport.encode(join, key: key) else { return }
        link.send(frame)
    }

    private func handle(_ m: NightMessage) {
        switch m.kind {
        case .welcome:
            seat = m.seat; roomName = m.roomName; status = .joined; reconnectAttempts = 0
        case .roster:
            players = m.players ?? players
        case .night:
            // Resolve the canonical wire questions to local Questions (an id-based
            // corpus lookup is a future optimization; we ship full questions today).
            if let plan = m.plan, let wire = m.questions {
                let qs = wire.map { $0.toQuestion() }
                if !qs.isEmpty { onNight?(plan, qs) }
            }
        case .begin:
            if let i = m.questionIndex { onBegin?(i) }
        case .reveal:
            if let i = m.questionIndex { onReveal?(i) }
        case .finished:
            onFinished?()
        default:
            break
        }
    }
}
