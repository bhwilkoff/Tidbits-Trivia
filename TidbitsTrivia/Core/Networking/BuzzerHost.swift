#if os(tvOS)
import Foundation
import Network
import Observation

/// The Apple TV side of the Phase-1 buzzer (Decision 030). Publishes a Bonjour
/// service secured by a room-code PSK, accepts phone connections, owns the
/// authoritative BuzzArbiter, and decides who buzzed first. The TV is the one
/// clock everyone is measured against (Part C fairness rule).
///
/// Build-verified, NOT yet two-device-verified — see BuzzerTransport's note.
/// Not yet wired into a game mode; the lobby view observes it so pairing can be
/// exercised on hardware before "Buzz Night" rides on top.
@Observable
@MainActor
final class BuzzerHost {
    private(set) var roomCode = ""
    private(set) var players: [BuzzerPlayer] = []
    private(set) var isListening = false
    private(set) var currentWinnerSeat: Int?
    private(set) var lastError: String?
    /// The buzz-winner's submitted answer, awaiting the TV's judgement (the TV
    /// holds the question, so it evaluates correctness). nil until they tap.
    private(set) var pendingAnswerSeat: Int?
    private(set) var pendingAnswerIndex: Int?

    private final class Peer {
        let connection: NWConnection
        let framer = BuzzerFramer()
        var seat: Int?
        var pingSentMillis: Double?
        init(_ c: NWConnection) { connection = c }
    }

    private var listener: NWListener?
    private var arbiter = BuzzArbiter()
    private var nextSeat = 1
    private var peers: [ObjectIdentifier: Peer] = [:]
    /// Seats that have already buzzed-and-missed THIS question — a wrong buzz
    /// "opens it to others" (research D2), so the misser is locked out until the
    /// next question, but everyone else can still buzz.
    private var lockedOut: Set<Int> = []

    /// The seat with the most points (nil until someone has scored) — drives the
    /// running "leader" badge on the TV scoreboard.
    var leaderSeat: Int? {
        guard let top = players.max(by: { $0.score < $1.score }), top.score > 0 else { return nil }
        return top.seat
    }

    // MARK: Lifecycle

    func start() {
        stop()
        roomCode = RoomCode.generate()
        do {
            let listener = try NWListener(using: BuzzerTransport.parameters(code: roomCode))
            listener.service = NWListener.Service(name: "Tidbits-\(roomCode)", type: Buzzer.serviceType)
            listener.newConnectionHandler = { [weak self] conn in
                Task { @MainActor in self?.accept(conn) }
            }
            listener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    switch state {
                    case .ready:            self?.isListening = true
                    case .failed(let e):    self?.lastError = "\(e)"; self?.isListening = false
                    case .cancelled:        self?.isListening = false
                    default:                break
                    }
                }
            }
            self.listener = listener
            listener.start(queue: .main)
        } catch {
            lastError = "\(error)"
        }
    }

    func stop() {
        listener?.cancel(); listener = nil
        for p in peers.values { p.connection.cancel() }
        peers.removeAll(); players.removeAll()
        isListening = false; currentWinnerSeat = nil; nextSeat = 1
    }

    // MARK: Round control (called by a future Buzz Night game mode)

    /// Send the active question (prompt + options) to every phone so the players
    /// read along AND the buzz-winner can answer on their own device. Never
    /// includes the correct index — the host judges the submitted answer.
    func broadcastQuestion(prompt: String, options: [String], index: Int) {
        var m = BuzzerMessage(.question)
        m.prompt = prompt; m.options = options; m.questionIndex = index
        broadcast(m)
    }

    /// Open buzzing for a NEW question: clears the per-question lockout +
    /// pending answer and re-measures round-trips for fairness.
    func beginQuestion(index: Int) {
        lockedOut = []
        pendingAnswerSeat = nil; pendingAnswerIndex = nil
        arm(questionIndex: index)
    }

    /// Open buzzing and re-measure round-trips for fairness.
    func arm(questionIndex: Int) {
        arbiter.arm(); currentWinnerSeat = nil
        var m = BuzzerMessage(.armed); m.questionIndex = questionIndex
        broadcast(m)
        pingAll()
    }

    /// Close buzzing (timeout, or a resolved wrong buzz).
    func lock() {
        arbiter.disarm()
        broadcast(BuzzerMessage(.locked))
    }

    /// The buzz-winner's phone answer was CORRECT (judged by the TV) — award
    /// points, reveal the answer to all phones, close buzzing.
    func acceptAnswer(points: Int, correctIndex: Int) {
        guard let seat = currentWinnerSeat else { return }
        if let i = players.firstIndex(where: { $0.seat == seat }) { players[i].score += points }
        arbiter.disarm()
        pendingAnswerSeat = nil; pendingAnswerIndex = nil
        broadcastRoster()
        var r = BuzzerMessage(.result); r.correct = true; r.correctIndex = correctIndex; r.winnerSeat = seat
        broadcast(r)
        broadcast(BuzzerMessage(.locked))
    }

    /// The buzz-winner's phone answer was WRONG — tell that phone, lock them out
    /// of this question, and re-open buzzing for everyone else (the "wrong buzz
    /// opens it" rule). The correct answer is NOT revealed yet (others can win).
    func rejectAnswerAndReopen() {
        guard let seat = currentWinnerSeat else { return }
        lockedOut.insert(seat)
        var r = BuzzerMessage(.result); r.correct = false; r.winnerSeat = seat
        broadcast(r)
        currentWinnerSeat = nil
        pendingAnswerSeat = nil; pendingAnswerIndex = nil
        arbiter.arm()
        var m = BuzzerMessage(.armed); m.questionIndex = -1
        broadcast(m)
    }

    /// No one answered correctly (timeout / host skip) — reveal to all phones.
    func revealNoWinner(correctIndex: Int) {
        arbiter.disarm()
        currentWinnerSeat = nil
        pendingAnswerSeat = nil; pendingAnswerIndex = nil
        var r = BuzzerMessage(.result); r.correct = false; r.correctIndex = correctIndex
        broadcast(r)
        broadcast(BuzzerMessage(.locked))
    }

    /// Name for a seat (for the TV's "X buzzed!" banner).
    func name(forSeat seat: Int) -> String {
        players.first { $0.seat == seat }?.name ?? "Player \(seat)"
    }

    // MARK: Connections

    private func accept(_ conn: NWConnection) {
        let peer = Peer(conn)
        peers[ObjectIdentifier(conn)] = peer
        conn.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                switch state {
                case .failed, .cancelled: self?.drop(conn)
                default: break
                }
            }
        }
        conn.start(queue: .main)
        receive(on: peer)
    }

    private func receive(on peer: Peer) {
        peer.connection.receive(minimumIncompleteLength: 1, maximumLength: Buzzer.maxMessageBytes) { [weak self] data, _, isComplete, error in
            Task { @MainActor in
                guard let self else { return }
                if let data, !data.isEmpty {
                    for msg in peer.framer.ingest(data) { self.handle(msg, from: peer) }
                }
                if isComplete || error != nil { self.drop(peer.connection); return }
                self.receive(on: peer)
            }
        }
    }

    private func drop(_ conn: NWConnection) {
        guard let peer = peers.removeValue(forKey: ObjectIdentifier(conn)) else { return }
        conn.cancel()
        // Keep the player + their score in the roster so a dropped phone can
        // REJOIN (same name → same seat) and resume where they left off. Only
        // the peer (socket) binding is freed here.
    }

    // MARK: Message handling

    private func handle(_ msg: BuzzerMessage, from peer: Peer) {
        switch msg.kind {
        case .join:
            let raw = (msg.displayName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            // Rejoin: a phone that dropped and comes back with the SAME name
            // resumes its existing seat + score (its peer binding was freed on
            // disconnect, but the player stayed in the roster).
            let existing = raw.isEmpty ? nil : players.first { $0.name.caseInsensitiveCompare(raw) == .orderedSame }
            let seat: Int
            if let existing {
                seat = existing.seat
            } else {
                seat = nextSeat; nextSeat += 1
                players.append(BuzzerPlayer(seat: seat, name: raw.isEmpty ? "Player \(seat)" : raw))
            }
            peer.seat = seat
            var welcome = BuzzerMessage(.welcome)
            welcome.seat = seat; welcome.roomName = "Tidbits \(roomCode)"
            BuzzerTransport.send(welcome, over: peer.connection)
            broadcastRoster()
            ping(peer)

        case .buzz:
            // First effective (RTT-compensated) arrival after arm() wins. A seat
            // that already missed this question is locked out (others can still win).
            guard let seat = peer.seat, currentWinnerSeat == nil, !lockedOut.contains(seat) else { return }
            if let winner = arbiter.registerBuzz(seat: seat, arrivalMillis: BuzzerTransport.nowMillis()) {
                currentWinnerSeat = winner
                arbiter.disarm()
                var awarded = BuzzerMessage(.awarded); awarded.winnerSeat = winner
                broadcast(awarded)
            }

        case .answer:
            // Only the current buzz-winner may answer, once. The TV judges it.
            guard let seat = peer.seat, seat == currentWinnerSeat, pendingAnswerSeat == nil else { return }
            pendingAnswerSeat = seat
            pendingAnswerIndex = msg.chosenIndex

        case .pong:
            if let sent = peer.pingSentMillis, let seat = peer.seat {
                arbiter.observeRoundTrip(seat: seat, rttMillis: BuzzerTransport.nowMillis() - sent)
                peer.pingSentMillis = nil
            }

        default:
            break
        }
    }

    // MARK: Broadcast

    private func broadcast(_ m: BuzzerMessage) {
        for p in peers.values { BuzzerTransport.send(m, over: p.connection) }
    }
    private func broadcastRoster() {
        var m = BuzzerMessage(.roster); m.players = players
        broadcast(m)
    }
    private func ping(_ peer: Peer) {
        peer.pingSentMillis = BuzzerTransport.nowMillis()
        var m = BuzzerMessage(.ping); m.hostStampMillis = peer.pingSentMillis
        BuzzerTransport.send(m, over: peer.connection)
    }
    private func pingAll() {
        for p in peers.values where p.seat != nil { ping(p) }
    }
}
#endif
