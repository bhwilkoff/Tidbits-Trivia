import Foundation
import Network

/// The default Trivia Night link: Bonjour (DNS-SD) discovery + plain TCP —
/// today's ONLY cross-platform path (Android's `NsdTcpTransport` speaks the
/// same wire). `includePeerToPeer` keeps Apple↔Apple pairing router-free over
/// AWDL; the same service is advertised on the LAN for Android.
///
/// Confidentiality + auth are the app-layer AES-GCM frames produced upstream by
/// `NightTransport` — this file moves opaque bytes only (the `NightPeerLink`
/// contract). Extracted from NightHost/NightClient so Wi-Fi Aware / BLE / remote
/// links can slot in behind the same seam.
enum BonjourTCP {
    static func parameters() -> NWParameters {
        let params = NWParameters.tcp
        params.includePeerToPeer = true
        return params
    }
}

/// One remote device on an `NWConnection`, host or joiner side.
@MainActor
final class ConnectionPeer: NightPeerLink {
    nonisolated let id = UUID().uuidString
    let connection: NWConnection

    init(_ connection: NWConnection) { self.connection = connection }

    func send(_ frame: Data) {
        connection.send(content: frame, completion: .contentProcessed { error in
            if let error { print("[night] send failed: \(error)") }
        })
    }

    func close() { connection.cancel() }

    /// Pump raw bytes to the owner until the stream ends. `onEnd` fires once.
    func readLoop(onBytes: @escaping @MainActor (Data) -> Void, onEnd: @escaping @MainActor () -> Void) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: Night.maxMessageBytes) { [weak self] data, _, isComplete, error in
            Task { @MainActor in
                guard let self else { return }
                if let data, !data.isEmpty { onBytes(data) }
                if isComplete || error != nil { onEnd(); return }
                self.readLoop(onBytes: onBytes, onEnd: onEnd)
            }
        }
    }
}

// MARK: - Host side

@MainActor
final class BonjourHostTransport: NightHostTransport {
    private var listener: NWListener?
    private var peers: [String: ConnectionPeer] = [:]

    func start(roomCode: String,
               onPeer: @escaping @MainActor (any NightPeerLink) -> Void,
               onFrame: @escaping @MainActor (any NightPeerLink, Data) -> Void,
               onDrop: @escaping @MainActor (any NightPeerLink) -> Void,
               onState: @escaping @MainActor (NightHostLinkState) -> Void) {
        stop()
        do {
            let listener = try NWListener(using: BonjourTCP.parameters())
            listener.service = NWListener.Service(name: "Tidbits-\(roomCode)", type: Night.serviceType)
            listener.newConnectionHandler = { [weak self] conn in
                Task { @MainActor in self?.accept(conn, onPeer: onPeer, onFrame: onFrame, onDrop: onDrop) }
            }
            listener.stateUpdateHandler = { state in
                Task { @MainActor in
                    switch state {
                    case .ready:         onState(.ready)
                    case .failed(let e): onState(.failed("\(e)"))
                    case .cancelled:     onState(.stopped)
                    default:             break
                    }
                }
            }
            self.listener = listener
            listener.start(queue: .main)
        } catch {
            onState(.failed("\(error)"))
        }
    }

    func stop() {
        listener?.cancel(); listener = nil
        for p in peers.values { p.close() }
        peers.removeAll()
    }

    private func accept(_ conn: NWConnection,
                        onPeer: @escaping @MainActor (any NightPeerLink) -> Void,
                        onFrame: @escaping @MainActor (any NightPeerLink, Data) -> Void,
                        onDrop: @escaping @MainActor (any NightPeerLink) -> Void) {
        let peer = ConnectionPeer(conn)
        peers[peer.id] = peer
        let drop: @MainActor () -> Void = { [weak self] in
            guard let self, self.peers.removeValue(forKey: peer.id) != nil else { return }
            peer.close()
            onDrop(peer)
        }
        conn.stateUpdateHandler = { state in
            Task { @MainActor in
                if case .failed = state { drop() }
                if case .cancelled = state { drop() }
            }
        }
        conn.start(queue: .main)
        onPeer(peer)
        peer.readLoop(onBytes: { onFrame(peer, $0) }, onEnd: drop)
    }
}

// MARK: - Joiner side

@MainActor
final class BonjourClientTransport: NightClientTransport {
    private var browser: NWBrowser?
    private var peer: ConnectionPeer?
    private var code = ""
    /// Ensures `onDropped` fires at most once per connect() attempt.
    private var dropReported = true

    func connect(roomCode: String,
                 onConnected: @escaping @MainActor (any NightPeerLink) -> Void,
                 onFrame: @escaping @MainActor (Data) -> Void,
                 onDropped: @escaping @MainActor () -> Void,
                 onStatus: @escaping @MainActor (NightClientLinkStatus) -> Void) {
        disconnect()
        code = roomCode.uppercased()
        dropReported = false
        let drop: @MainActor () -> Void = { [weak self] in
            guard let self, !self.dropReported else { return }
            self.dropReported = true
            self.teardown()
            onDropped()
        }
        onStatus(.searching)
        let browser = NWBrowser(for: .bonjour(type: Night.serviceType, domain: nil), using: BonjourTCP.parameters())
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            Task { @MainActor in
                self?.consider(results, onConnected: onConnected, onFrame: onFrame,
                               onDrop: drop, onStatus: onStatus)
            }
        }
        browser.stateUpdateHandler = { state in
            Task { @MainActor in if case .failed = state { drop() } }
        }
        self.browser = browser
        browser.start(queue: .main)
    }

    func disconnect() {
        dropReported = true
        teardown()
    }

    private func teardown() {
        browser?.cancel(); browser = nil
        peer?.close(); peer = nil
    }

    private func consider(_ results: Set<NWBrowser.Result>,
                          onConnected: @escaping @MainActor (any NightPeerLink) -> Void,
                          onFrame: @escaping @MainActor (Data) -> Void,
                          onDrop: @escaping @MainActor () -> Void,
                          onStatus: @escaping @MainActor (NightClientLinkStatus) -> Void) {
        guard peer == nil else { return }
        for r in results {
            if case let .service(name, _, _, _) = r.endpoint, name.uppercased().hasSuffix(code) {
                onStatus(.connecting)
                let conn = NWConnection(to: r.endpoint, using: BonjourTCP.parameters())
                let peer = ConnectionPeer(conn)
                self.peer = peer
                conn.stateUpdateHandler = { [weak self] state in
                    Task { @MainActor in
                        switch state {
                        case .ready:
                            self?.browser?.cancel(); self?.browser = nil
                            onConnected(peer)
                        case .failed:
                            onDrop()
                        default:
                            break
                        }
                    }
                }
                conn.start(queue: .main)
                peer.readLoop(onBytes: onFrame, onEnd: onDrop)
                return
            }
        }
    }
}
