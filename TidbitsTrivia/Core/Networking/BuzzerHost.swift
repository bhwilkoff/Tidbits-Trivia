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

    /// Open buzzing for a question and re-measure round-trips for fairness.
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
        if let seat = peer.seat {
            players.removeAll { $0.seat == seat }
            broadcastRoster()
        }
    }

    // MARK: Message handling

    private func handle(_ msg: BuzzerMessage, from peer: Peer) {
        switch msg.kind {
        case .join:
            let seat = nextSeat; nextSeat += 1
            peer.seat = seat
            let raw = (msg.displayName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            players.append(BuzzerPlayer(seat: seat, name: raw.isEmpty ? "Player \(seat)" : raw))
            var welcome = BuzzerMessage(.welcome)
            welcome.seat = seat; welcome.roomName = "Tidbits \(roomCode)"
            BuzzerTransport.send(welcome, over: peer.connection)
            broadcastRoster()
            ping(peer)

        case .buzz:
            // First effective (RTT-compensated) arrival after arm() wins.
            guard let seat = peer.seat, currentWinnerSeat == nil else { return }
            if let winner = arbiter.registerBuzz(seat: seat, arrivalMillis: BuzzerTransport.nowMillis()) {
                currentWinnerSeat = winner
                arbiter.disarm()
                var awarded = BuzzerMessage(.awarded); awarded.winnerSeat = winner
                broadcast(awarded)
            }

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
