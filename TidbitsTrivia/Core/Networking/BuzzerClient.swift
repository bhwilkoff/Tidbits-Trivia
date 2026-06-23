#if os(iOS)
import Foundation
import Network
import Observation

/// The iPhone side of the Phase-1 buzzer (Decision 030). Browses for the TV's
/// Bonjour service, connects with the room-code PSK (so only a phone that can
/// read the code pairs), then sends a single `buzz` per armed question. Replies
/// to the host's pings so the host can RTT-compensate fairly.
///
/// Build-verified, NOT yet two-device-verified — see BuzzerTransport's note.
@Observable
@MainActor
final class BuzzerClient {
    enum Status: Equatable { case idle, searching, connecting, joined, failed(String) }

    private(set) var status: Status = .idle
    private(set) var seat: Int?
    private(set) var roomName: String?
    private(set) var players: [BuzzerPlayer] = []
    private(set) var canBuzz = false
    private(set) var winnerSeat: Int?
    var displayName = ""

    // The active question (streamed from the TV) so the buzz-winner answers on
    // their OWN device; every phone reads along.
    private(set) var prompt: String?
    private(set) var options: [String] = []
    private(set) var imageURL: URL?        // Picture ID rounds: the image to show on this phone
    private(set) var isAnswering = false   // I won the buzz — my answer buttons are live
    private(set) var myAnswer: Int?        // the option I tapped
    private(set) var resultCorrect: Bool?  // judged outcome for the buzz-winner
    private(set) var resultCorrectIndex: Int?  // revealed answer (highlight it)
    private(set) var lockedOut = false     // I answered wrong this question — no re-buzz
    // Shared-awareness feedback: every phone sees who acted, what they picked,
    // and the points — so it feels like one game everyone's playing together.
    private(set) var buzzedName: String?   // who just buzzed in
    private(set) var resultName: String?   // who answered (from the host's result)
    private(set) var resultPoints: Int?    // points they earned
    private(set) var resultChosen: Int?    // the option they picked
    private(set) var resultTimedOut = false  // a no-winner reveal: clock ran out vs everyone wrong

    private var browser: NWBrowser?
    private var connection: NWConnection?
    private let framer = BuzzerFramer()
    private var code = ""
    /// Stable per-device id (generated once, persisted) — the host keys seats by
    /// this so this DEVICE always resumes its seat + score, name aside.
    private let deviceID = BuzzerClient.loadDeviceID()
    private var intentionalLeave = false
    private var reconnectAttempts = 0

    /// The last room this device joined — pre-filled next time so a recognized
    /// device doesn't have to retype the code (the TV still shows it for new joins).
    static var lastCode: String { UserDefaults.standard.string(forKey: "tidbits.buzzer.lastCode") ?? "" }
    static var lastName: String { UserDefaults.standard.string(forKey: "tidbits.buzzer.lastName") ?? "" }

    var iWon: Bool { winnerSeat != nil && winnerSeat == seat }

    private static func loadDeviceID() -> String {
        let key = "tidbits.buzzer.deviceID"
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
        displayName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        UserDefaults.standard.set(self.code, forKey: "tidbits.buzzer.lastCode")
        UserDefaults.standard.set(displayName, forKey: "tidbits.buzzer.lastName")
        startBrowsing()
    }

    private func startBrowsing() {
        teardownSockets()
        status = .searching
        let browser = NWBrowser(for: .bonjour(type: Buzzer.serviceType, domain: nil),
                                using: BuzzerTransport.parameters(code: self.code))
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
    /// restores this device's seat) — no tap, no re-entering the code. Gives up
    /// only after several tries (the host really went away).
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
        teardownSockets()
        status = .idle; seat = nil; roomName = nil
        players = []; canBuzz = false; winnerSeat = nil
        prompt = nil; options = []; imageURL = nil; isAnswering = false; myAnswer = nil
        resultCorrect = nil; resultCorrectIndex = nil; lockedOut = false
        buzzedName = nil; resultName = nil; resultPoints = nil; resultChosen = nil
    }

    private func teardownSockets() {
        browser?.cancel(); browser = nil
        connection?.cancel(); connection = nil
    }

    // MARK: Buzz

    func buzz() {
        guard canBuzz, let c = connection else { return }
        var m = BuzzerMessage(.buzz); m.stampMillis = BuzzerTransport.nowMillis()
        BuzzerTransport.send(m, over: c)
        canBuzz = false   // optimistic local lock; the host's `awarded` is truth
    }

    /// Submit the buzz-winner's chosen option (answer on your own device).
    func submitAnswer(_ index: Int) {
        guard isAnswering, let c = connection else { return }
        var m = BuzzerMessage(.answer); m.chosenIndex = index
        BuzzerTransport.send(m, over: c)
        myAnswer = index
        isAnswering = false   // the host's `result` is the truth
    }

    // MARK: Discovery → connection

    private func consider(_ results: Set<NWBrowser.Result>) {
        guard connection == nil else { return }
        for r in results {
            if case let .service(name, _, _, _) = r.endpoint,
               name.uppercased().hasSuffix(code) {
                connect(to: r.endpoint)
                return
            }
        }
    }

    private func connect(to endpoint: NWEndpoint) {
        status = .connecting
        let conn = NWConnection(to: endpoint, using: BuzzerTransport.parameters(code: code))
        conn.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                switch state {
                case .ready:    self?.onConnected()
                case .failed:   self?.attemptReconnect()
                default:        break
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
        var join = BuzzerMessage(.join)
        join.displayName = displayName.isEmpty ? nil : displayName
        join.deviceID = deviceID
        BuzzerTransport.send(join, over: c)
    }

    private func receive() {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: Buzzer.maxMessageBytes) { [weak self] data, _, isComplete, error in
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

    private func handle(_ m: BuzzerMessage) {
        switch m.kind {
        case .welcome: seat = m.seat; roomName = m.roomName; status = .joined; reconnectAttempts = 0
        case .roster:  players = m.players ?? players
        case .question:
            // A new question — render it and clear last round's state entirely.
            prompt = m.prompt; options = m.options ?? []
            imageURL = m.imageURL.flatMap(URL.init(string:))
            myAnswer = nil; resultCorrect = nil; resultCorrectIndex = nil
            isAnswering = false; lockedOut = false; winnerSeat = nil
            buzzedName = nil; resultName = nil; resultPoints = nil; resultChosen = nil; resultTimedOut = false
        case .armed:
            // Re-arm on a brand-new question OR after a wrong answer reopened it.
            // Keep the last result text so the reopen reads "X missed — buzz!".
            canBuzz = !lockedOut; winnerSeat = nil; isAnswering = false
        case .awarded:
            winnerSeat = m.winnerSeat; canBuzz = false
            isAnswering = (m.winnerSeat == seat)   // my turn to answer on-device
            buzzedName = players.first { $0.seat == m.winnerSeat }?.name
            resultName = nil; resultChosen = nil; resultCorrect = nil  // clear prior feedback
        case .result:
            resultCorrect = m.correct; resultCorrectIndex = m.correctIndex
            resultName = m.displayName; resultPoints = m.points; resultChosen = m.chosenIndex
            resultTimedOut = m.timedOut ?? false
            isAnswering = false; buzzedName = nil
            if m.winnerSeat == seat && m.correct == false { lockedOut = true }
        case .locked:  canBuzz = false; isAnswering = false
        case .ping:
            guard let c = connection else { return }
            var pong = BuzzerMessage(.pong)
            pong.hostStampMillis = m.hostStampMillis
            pong.stampMillis = BuzzerTransport.nowMillis()
            BuzzerTransport.send(pong, over: c)
        default:
            break
        }
    }
}
#endif
