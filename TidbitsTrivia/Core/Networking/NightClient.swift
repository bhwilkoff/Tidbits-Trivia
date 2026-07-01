import Foundation
import Network
import Observation
import CryptoKit

/// The joiner side of a Trivia Night (Decision 033) — runs on ANY Apple device.
/// Browses for the host's Bonjour service, connects with the room-code PSK (so
/// only a device that can read the code pairs), receives the whole night, and
/// then follows the host's pacing signals. It plays on its OWN screen and scores
/// itself locally, reporting only its running total back to the host.
///
/// The actual game (rendering questions, capturing answers) is driven by
/// `LiveNight`, which wires these callbacks to a local `GameEngine`.
///
/// Build-verified, NOT yet two-device-verified — see NightTransport's note.
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

    private var browser: NWBrowser?
    private var connection: NWConnection?
    private var key = RoomCode.presharedKey(for: "")
    private var framer = NightFramer(key: RoomCode.presharedKey(for: ""))
    private var code = ""
    private let deviceID = NightClient.loadDeviceID()
    private var intentionalLeave = false
    private var reconnectAttempts = 0

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
        startBrowsing()
    }

    private func startBrowsing() {
        teardownSockets()
        status = .searching
        let browser = NWBrowser(for: .bonjour(type: Night.serviceType, domain: nil),
                                using: NightTransport.parameters())
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            Task { @MainActor in self?.consider(results) }
        }
        browser.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in if case .failed = state { self?.attemptReconnect() } }
        }
        self.browser = browser
        browser.start(queue: .main)
    }

    /// A drop mid-game silently re-discovers the room and rejoins (the host
    /// replays the night + current question) — no tap, no re-entering the code.
    private func attemptReconnect() {
        guard !intentionalLeave, !code.isEmpty, reconnectAttempts < 8 else {
            if !intentionalLeave { status = .failed("Lost the room — tap to rejoin") }
            return
        }
        reconnectAttempts += 1
        startBrowsing()
    }

    func leave() {
        intentionalLeave = true
        if let c = connection { NightTransport.send(NightMessage(.leave), over: c, key: key) }
        teardownSockets()
        status = .idle; seat = nil; roomName = nil; players = []
    }

    private func teardownSockets() {
        browser?.cancel(); browser = nil
        connection?.cancel(); connection = nil
    }

    // MARK: Reporting

    /// Tell the host this device locked an answer this question, with the running
    /// total + whether it was right — the host folds it into the standings.
    func reportAnswer(score: Int, correct: Bool) {
        guard let c = connection else { return }
        var m = NightMessage(.answered)
        m.score = score; m.correct = correct
        NightTransport.send(m, over: c, key: key)
    }

    // MARK: Discovery → connection

    private func consider(_ results: Set<NWBrowser.Result>) {
        guard connection == nil else { return }
        for r in results {
            if case let .service(name, _, _, _) = r.endpoint, name.uppercased().hasSuffix(code) {
                connect(to: r.endpoint)
                return
            }
        }
    }

    private func connect(to endpoint: NWEndpoint) {
        status = .connecting
        let conn = NWConnection(to: endpoint, using: NightTransport.parameters())
        conn.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                switch state {
                case .ready:  self?.onConnected()
                case .failed: self?.attemptReconnect()
                default:      break
                }
            }
        }
        connection = conn
        conn.start(queue: .main)
        receive()
    }

    private func onConnected() {
        browser?.cancel(); browser = nil
        guard let c = connection else { return }
        var join = NightMessage(.join)
        join.displayName = displayName.isEmpty ? nil : displayName
        join.deviceID = deviceID
        NightTransport.send(join, over: c, key: key)
    }

    private func receive() {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: Night.maxMessageBytes) { [weak self] data, _, isComplete, error in
            Task { @MainActor in
                guard let self else { return }
                if let data, !data.isEmpty {
                    for m in self.framer.ingest(data) { self.handle(m) }
                }
                if isComplete || error != nil { self.attemptReconnect(); return }
                self.receive()
            }
        }
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
