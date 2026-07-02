import Foundation
import Observation
import CryptoKit

/// The host side of a Trivia Night (Decision 033) — runs on ANY Apple device
/// (iPhone, iPad, Apple TV). Advertises a room secured by the room-code key,
/// accepts joiners, owns the authoritative roster + standings, and drives the
/// night's pacing on behalf of the human host (who is also a player).
///
/// The host does NOT judge answers — every device runs its own engine over the
/// identical question list and scores itself, reporting its running total. For a
/// friendly living-room game that trust is the right tradeoff (no server, no
/// anti-cheat); the host just aggregates and paces.
///
/// Link-layer-agnostic: all discovery + byte transport lives behind
/// `NightHostTransport` (Bonjour mDNS+TCP by default; Wi-Fi Aware / BLE later).
/// This class owns the protocol, the crypto, and the seat/rejoin model.
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
        let link: any NightPeerLink
        let framer: NightFramer
        var seat: Int?
        init(_ link: any NightPeerLink, key: SymmetricKey) { self.link = link; framer = NightFramer(key: key) }
    }

    private let transport: any NightHostTransport
    private var peers: [String: Peer] = [:]
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

    init(transport: any NightHostTransport = BonjourHostTransport()) {
        self.transport = transport
    }

    // MARK: Lifecycle

    func start(hostName: String, code: String? = nil) {
        stop()
        roomCode = code ?? RoomCode.generate()
        key = RoomCode.presharedKey(for: roomCode)
        let name = hostName.trimmingCharacters(in: .whitespacesAndNewlines)
        players = [NightPlayer(seat: Self.hostSeat, name: name.isEmpty ? "Host" : name, isHost: true)]
        transport.start(
            roomCode: roomCode,
            onPeer: { [weak self] link in self?.accept(link) },
            onFrame: { [weak self] link, bytes in self?.ingest(bytes, from: link) },
            onDrop: { [weak self] link in
                self?.peers.removeValue(forKey: link.id)
                // Keep the player + score in the roster so a dropped device can
                // REJOIN (same deviceID → same seat) and resume.
            },
            onState: { [weak self] state in
                switch state {
                case .ready:         self?.isListening = true
                case .failed(let e): self?.lastError = e; self?.isListening = false
                case .stopped:       self?.isListening = false
                }
            })
    }

    func stop() {
        transport.stop()
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

    private func accept(_ link: any NightPeerLink) {
        peers[link.id] = Peer(link, key: key)
    }

    private func ingest(_ bytes: Data, from link: any NightPeerLink) {
        guard let peer = peers[link.id] else { return }
        for msg in peer.framer.ingest(bytes) { handle(msg, from: peer) }
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
            send(welcome, to: peer)
            broadcastRoster()
            replayState(to: peer)   // catch a mid-night (re)join all the way up

        case .answered:
            guard let seat = peer.seat, let i = players.firstIndex(where: { $0.seat == seat }) else { return }
            players[i].score = msg.score ?? players[i].score
            players[i].answered = true
            broadcastRoster()

        case .leave:
            peers.removeValue(forKey: peer.link.id)
            peer.link.close()

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
        send(n, to: peer)
        if currentIndex >= 0 {
            var b = NightMessage(.begin); b.questionIndex = currentIndex
            send(b, to: peer)
            if revealed {
                var r = NightMessage(.reveal); r.questionIndex = currentIndex
                send(r, to: peer)
            }
        }
    }

    // MARK: Send / broadcast

    private func send(_ m: NightMessage, to peer: Peer) {
        guard let frame = NightTransport.encode(m, key: key) else { return }
        peer.link.send(frame)
    }
    private func broadcast(_ m: NightMessage) {
        guard let frame = NightTransport.encode(m, key: key) else { return }
        for p in peers.values { p.link.send(frame) }
    }
    private func broadcastRoster() {
        var m = NightMessage(.roster); m.players = players
        broadcast(m)
    }
}
