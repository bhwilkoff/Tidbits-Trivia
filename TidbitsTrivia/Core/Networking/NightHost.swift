import Foundation
import Network
import Observation
import CryptoKit

/// The host side of a Trivia Night (Decision 033) — runs on ANY Apple device
/// (iPhone, iPad, Apple TV). Publishes a Bonjour service secured by a room-code
/// PSK, accepts joiners, owns the authoritative roster + standings, and drives
/// the night's pacing on behalf of the human host (who is also a player).
///
/// The host does NOT judge answers — every device runs its own engine over the
/// identical question list and scores itself, reporting its running total. For a
/// friendly living-room game that trust is the right tradeoff (no server, no
/// anti-cheat); the host just aggregates and paces.
///
/// Build-verified, NOT yet two-device-verified — see NightTransport's note.
@Observable
@MainActor
final class NightHost {
    private(set) var roomCode = ""
    private(set) var isListening = false
    private(set) var lastError: String?
    /// The standings, host included. Seat 0 is always the host.
    private(set) var players: [NightPlayer] = []

    /// How many seats have locked an answer for the current question (host too).
    var answeredCount: Int { players.filter(\.answered).count }
    /// Every connected seat has answered — the host can reveal without waiting.
    var everyoneAnswered: Bool { !players.isEmpty && players.allSatisfy(\.answered) }
    var leaderSeat: Int? {
        guard let top = players.max(by: { $0.score < $1.score }), top.score > 0 else { return nil }
        return top.seat
    }

    static let hostSeat = 0

    private final class Peer {
        let connection: NWConnection
        let framer: NightFramer
        var seat: Int?
        init(_ c: NWConnection, key: SymmetricKey) { connection = c; framer = NightFramer(key: key) }
    }

    private var listener: NWListener?
    private var peers: [ObjectIdentifier: Peer] = [:]
    private var nextSeat = 1
    /// deviceID → seat, so a reconnecting device resumes its seat + score.
    private var seatByDevice: [String: Int] = [:]
    /// AES-GCM key derived from the room code (v2 app-layer crypto, not TLS).
    private var key = RoomCode.presharedKey(for: "")

    // The live night, retained so a device that joins (or rejoins) mid-game is
    // caught all the way up: the full question list, where we are, and whether
    // the current question is already revealed.
    private var activePlan: NightPlan?
    private var activeQuestions: [Question]?
    private var currentIndex = -1
    private var revealed = false

    // MARK: Lifecycle

    func start(hostName: String) {
        stop()
        roomCode = RoomCode.generate()
        key = RoomCode.presharedKey(for: roomCode)
        let name = hostName.trimmingCharacters(in: .whitespacesAndNewlines)
        players = [NightPlayer(seat: Self.hostSeat, name: name.isEmpty ? "Host" : name, isHost: true)]
        do {
            let listener = try NWListener(using: NightTransport.parameters())
            listener.service = NWListener.Service(name: "Tidbits-\(roomCode)", type: Night.serviceType)
            listener.newConnectionHandler = { [weak self] conn in
                Task { @MainActor in self?.accept(conn) }
            }
            listener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    switch state {
                    case .ready:         self?.isListening = true
                    case .failed(let e): self?.lastError = "\(e)"; self?.isListening = false
                    case .cancelled:     self?.isListening = false
                    default:             break
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
        peers.removeAll(); players.removeAll(); seatByDevice.removeAll()
        isListening = false; nextSeat = 1
        activePlan = nil; activeQuestions = nil; currentIndex = -1; revealed = false
    }

    // MARK: Pacing (called by LiveNight on the host's behalf)

    /// Ship the whole night to everyone, once, at game start.
    func broadcastNight(plan: NightPlan, questions: [Question]) {
        activePlan = plan; activeQuestions = questions
        var m = NightMessage(.night); m.plan = plan
        m.questionIds = questions.map(\.id); m.questions = questions.map { $0.toWire() }
        broadcast(m)
    }

    /// Move everyone to a question. Clears the per-question "answered" flags so the
    /// host's "k of n answered" readout restarts.
    func broadcastBegin(index: Int) {
        currentIndex = index; revealed = false
        for i in players.indices { players[i].answered = false }
        var m = NightMessage(.begin); m.questionIndex = index
        broadcast(m); broadcastRoster()
    }

    /// Reveal the current question's answer on every device at once.
    func broadcastReveal(index: Int) {
        revealed = true
        var m = NightMessage(.reveal); m.questionIndex = index
        broadcast(m)
    }

    /// End the night — everyone shows the final standings.
    func broadcastFinished() {
        broadcast(NightMessage(.finished))
    }

    /// The host (seat 0) locked its own answer — fold it into the standings.
    func setHostAnswered(score: Int, correct: Bool) {
        if let i = players.firstIndex(where: { $0.seat == Self.hostSeat }) {
            players[i].score = score
            players[i].answered = true
        }
        broadcastRoster()
    }

    func name(forSeat seat: Int) -> String {
        players.first { $0.seat == seat }?.name ?? "Player \(seat)"
    }

    // MARK: Connections

    private func accept(_ conn: NWConnection) {
        let peer = Peer(conn, key: key)
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
        peer.connection.receive(minimumIncompleteLength: 1, maximumLength: Night.maxMessageBytes) { [weak self] data, _, isComplete, error in
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
        // Keep the player + score in the roster so a dropped device can REJOIN
        // (same deviceID → same seat) and resume. Only the socket is freed here.
    }

    // MARK: Message handling

    private func handle(_ msg: NightMessage, from peer: Peer) {
        switch msg.kind {
        case .join:
            let raw = (msg.displayName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let device = msg.deviceID
            // Rejoin by DEVICE first (resume seat + score), else by name, else fresh.
            let resumed: Int? = device.flatMap { seatByDevice[$0] }
                ?? (raw.isEmpty ? nil : players.first { $0.seat != Self.hostSeat && $0.name.caseInsensitiveCompare(raw) == .orderedSame }?.seat)
            let seat: Int
            if let resumed, players.contains(where: { $0.seat == resumed }) {
                seat = resumed
                if !raw.isEmpty, let i = players.firstIndex(where: { $0.seat == seat }) { players[i].name = raw }
            } else {
                seat = nextSeat; nextSeat += 1
                players.append(NightPlayer(seat: seat, name: raw.isEmpty ? "Player \(seat)" : raw))
            }
            if let device { seatByDevice[device] = seat }
            peer.seat = seat
            var welcome = NightMessage(.welcome)
            welcome.seat = seat; welcome.roomName = "Tidbits \(roomCode)"
            NightTransport.send(welcome, over: peer.connection, key: key)
            broadcastRoster()
            replayState(to: peer)   // catch a mid-night (re)join all the way up

        case .answered:
            guard let seat = peer.seat, let i = players.firstIndex(where: { $0.seat == seat }) else { return }
            players[i].score = msg.score ?? players[i].score
            players[i].answered = true
            broadcastRoster()

        case .leave:
            drop(peer.connection)

        default:
            break
        }
    }

    /// Bring a freshly-(re)joined device up to the live state: the whole night,
    /// the current question, and a reveal if this question is already revealed —
    /// so a late arrival lands right IN the game, not on a waiting screen.
    private func replayState(to peer: Peer) {
        guard let plan = activePlan, let questions = activeQuestions else { return }
        var n = NightMessage(.night); n.plan = plan
        n.questionIds = questions.map(\.id); n.questions = questions.map { $0.toWire() }
        NightTransport.send(n, over: peer.connection, key: key)
        if currentIndex >= 0 {
            var b = NightMessage(.begin); b.questionIndex = currentIndex
            NightTransport.send(b, over: peer.connection, key: key)
            if revealed {
                var r = NightMessage(.reveal); r.questionIndex = currentIndex
                NightTransport.send(r, over: peer.connection, key: key)
            }
        }
    }

    // MARK: Broadcast

    private func broadcast(_ m: NightMessage) {
        for p in peers.values { NightTransport.send(m, over: p.connection, key: key) }
    }
    private func broadcastRoster() {
        var m = NightMessage(.roster); m.players = players
        broadcast(m)
    }
}
