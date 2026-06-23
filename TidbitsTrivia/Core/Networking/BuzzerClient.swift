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
    private(set) var isAnswering = false   // I won the buzz — my answer buttons are live
    private(set) var myAnswer: Int?        // the option I tapped
    private(set) var resultCorrect: Bool?  // judged outcome for the buzz-winner
    private(set) var resultCorrectIndex: Int?  // revealed answer (highlight it)
    private(set) var lockedOut = false     // I answered wrong this question — no re-buzz

    private var browser: NWBrowser?
    private var connection: NWConnection?
    private let framer = BuzzerFramer()
    private var code = ""

    var iWon: Bool { winnerSeat != nil && winnerSeat == seat }

    // MARK: Join / leave

    func join(code: String, name: String) {
        leave()
        self.code = code.uppercased()
        displayName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        status = .searching
        let browser = NWBrowser(for: .bonjour(type: Buzzer.serviceType, domain: nil),
                                using: BuzzerTransport.parameters(code: self.code))
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            Task { @MainActor in self?.consider(results) }
        }
        browser.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in if case .failed(let e) = state { self?.status = .failed("\(e)") } }
        }
        self.browser = browser
        browser.start(queue: .main)
    }

    func leave() {
        browser?.cancel(); browser = nil
        connection?.cancel(); connection = nil
        status = .idle; seat = nil; roomName = nil
        players = []; canBuzz = false; winnerSeat = nil
        prompt = nil; options = []; isAnswering = false; myAnswer = nil
        resultCorrect = nil; resultCorrectIndex = nil; lockedOut = false
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
                case .ready:         self?.onConnected()
                case .failed(let e): self?.status = .failed("\(e)")
                default:             break
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
        BuzzerTransport.send(join, over: c)
    }

    private func receive() {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: Buzzer.maxMessageBytes) { [weak self] data, _, isComplete, error in
            Task { @MainActor in
                guard let self else { return }
                if let data, !data.isEmpty {
                    for m in self.framer.ingest(data) { self.handle(m) }
                }
                if isComplete || error != nil { self.status = .failed("disconnected"); return }
                self.receive()
            }
        }
    }

    private func handle(_ m: BuzzerMessage) {
        switch m.kind {
        case .welcome: seat = m.seat; roomName = m.roomName; status = .joined
        case .roster:  players = m.players ?? players
        case .question:
            // A new question — render it and clear last round's answer state.
            prompt = m.prompt; options = m.options ?? []
            myAnswer = nil; resultCorrect = nil; resultCorrectIndex = nil
            isAnswering = false; lockedOut = false; winnerSeat = nil
        case .armed:   canBuzz = !lockedOut; winnerSeat = nil; isAnswering = false
        case .awarded:
            winnerSeat = m.winnerSeat; canBuzz = false
            isAnswering = (m.winnerSeat == seat)   // my turn to answer on-device
        case .result:
            resultCorrect = m.correct; resultCorrectIndex = m.correctIndex; isAnswering = false
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
