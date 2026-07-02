#if canImport(GameKit)
import Foundation
import GameKit

/// Game Center as a Trivia Night link (Decision 039): a `GKMatch` adapter
/// behind the SAME `NightPeerLink` seam the local Bonjour night uses — so the
/// entire proven match machinery (NightHost/NightClient/LiveNight, wire,
/// rejoin) runs unchanged over Apple's matchmade online transport.
///
/// Leadership: GKMatch is symmetric (no host), so every device elects the
/// SAME leader deterministically — the lowest gamePlayerID. The leader runs
/// `NightHost` (via `GameKitHostTransport`); everyone else runs `NightClient`
/// pointed at the leader (via `GameKitClientTransport`).
///
/// Crypto note: the night wire's AES-GCM is keyed by a room code the humans
/// share out-of-band; a GameKit match has no code, and the link is already
/// authenticated + encrypted by Game Center. Both sides therefore use the
/// fixed `Night.gameKitCode` — the app-layer GCM becomes plain framing, which
/// keeps the wire byte-identical to the local night.
@MainActor
final class GameKitSession: NSObject {
    let match: GKMatch
    let leaderID: String
    var isLeader: Bool { GKLocalPlayer.local.gamePlayerID == leaderID }

    /// (player, bytes) for every incoming frame; wired by whichever transport runs.
    var onData: ((GKPlayer, Data) -> Void)?
    var onPlayerConnected: ((GKPlayer) -> Void)?
    var onPlayerDropped: ((GKPlayer) -> Void)?

    init(match: GKMatch) {
        self.match = match
        let ids = ([GKLocalPlayer.local.gamePlayerID] + match.players.map(\.gamePlayerID)).sorted()
        self.leaderID = ids.first ?? GKLocalPlayer.local.gamePlayerID
        super.init()
        match.delegate = self
    }

    var leaderPlayer: GKPlayer? { match.players.first { $0.gamePlayerID == leaderID } }

    func disconnect() {
        match.delegate = nil
        match.disconnect()
    }
}

// GameKit delivers GKMatchDelegate callbacks on the main thread; the
// @preconcurrency conformance keeps the methods MainActor-isolated (runtime-
// checked) without hopping a non-Sendable GKPlayer across regions.
extension GameKitSession: @preconcurrency GKMatchDelegate {
    func match(_ match: GKMatch, didReceive data: Data, fromRemotePlayer player: GKPlayer) {
        onData?(player, data)
    }
    func match(_ match: GKMatch, player: GKPlayer, didChange state: GKPlayerConnectionState) {
        switch state {
        case .connected:    onPlayerConnected?(player)
        case .disconnected: onPlayerDropped?(player)
        default: break
        }
    }
}

/// One remote Game Center player as a night peer.
@MainActor
final class GameKitPeer: NightPeerLink {
    nonisolated let id: String
    let player: GKPlayer
    private weak var match: GKMatch?

    init(player: GKPlayer, match: GKMatch) {
        self.player = player
        self.match = match
        self.id = player.gamePlayerID
    }

    func send(_ frame: Data) {
        try? match?.send(frame, to: [player], dataMode: .reliable)
    }

    func close() { /* GameKit owns connection lifetime; leaving = match.disconnect() */ }
}

/// The LEADER's side: every other match player is a joiner peer.
@MainActor
final class GameKitHostTransport: NightHostTransport {
    private let session: GameKitSession
    private var peers: [String: GameKitPeer] = [:]

    init(session: GameKitSession) { self.session = session }

    func start(roomCode: String,
               onPeer: @escaping @MainActor (any NightPeerLink) -> Void,
               onFrame: @escaping @MainActor (any NightPeerLink, Data) -> Void,
               onDrop: @escaping @MainActor (any NightPeerLink) -> Void,
               onState: @escaping @MainActor (NightHostLinkState) -> Void) {
        session.onData = { [weak self] player, data in
            guard let self else { return }
            if let peer = self.peers[player.gamePlayerID] { onFrame(peer, data) }
        }
        session.onPlayerConnected = { [weak self] player in
            guard let self, self.peers[player.gamePlayerID] == nil else { return }
            let peer = GameKitPeer(player: player, match: self.session.match)
            self.peers[peer.id] = peer
            onPeer(peer)
        }
        session.onPlayerDropped = { [weak self] player in
            guard let self, let peer = self.peers.removeValue(forKey: player.gamePlayerID) else { return }
            onDrop(peer)
        }
        // Matchmade players are usually already connected — seat them now.
        for player in session.match.players {
            let peer = GameKitPeer(player: player, match: session.match)
            peers[peer.id] = peer
            onPeer(peer)
        }
        onState(.ready)
    }

    func stop() {
        peers.removeAll()
        session.disconnect()
    }
}

/// A NON-leader's side: the elected leader is the single peer.
@MainActor
final class GameKitClientTransport: NightClientTransport {
    private let session: GameKitSession
    private var leader: GameKitPeer?

    init(session: GameKitSession) { self.session = session }

    func connect(roomCode: String,
                 onConnected: @escaping @MainActor (any NightPeerLink) -> Void,
                 onFrame: @escaping @MainActor (Data) -> Void,
                 onDropped: @escaping @MainActor () -> Void,
                 onStatus: @escaping @MainActor (NightClientLinkStatus) -> Void) {
        onStatus(.connecting)
        guard let leaderPlayer = session.leaderPlayer else { onDropped(); return }
        let peer = GameKitPeer(player: leaderPlayer, match: session.match)
        leader = peer
        session.onData = { [weak self] player, data in
            guard let self, player.gamePlayerID == self.session.leaderID else { return }
            onFrame(data)
        }
        session.onPlayerDropped = { [weak self] player in
            guard let self, player.gamePlayerID == self.session.leaderID else { return }
            onDropped()
        }
        onConnected(peer)
    }

    func disconnect() {
        leader = nil
        session.disconnect()
    }
}
#endif
