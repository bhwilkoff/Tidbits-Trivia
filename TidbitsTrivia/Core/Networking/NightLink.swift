import Foundation

/// The seam between the Trivia Night state machine and the link-layer — the
/// Swift mirror of Android's `net/NightTransport.kt`. Each transport (Bonjour
/// mDNS+TCP now; Wi-Fi Aware / BLE / remote later) implements these; `NightHost`
/// / `NightClient` and the wire protocol never change. See
/// docs/CROSS-PLATFORM-MULTIPLAYER.md "universal-connectivity question".
///
/// A "peer" is one connected remote device. Frames are already length+GCM-framed
/// by `NightTransport`/`NightFramer` — a transport just moves opaque bytes and
/// reports connect/disconnect. It never sees plaintext or holds the room key.
@MainActor
protocol NightPeerLink: AnyObject {
    var id: String { get }
    func send(_ frame: Data)
    func close()
}

/// Host side: advertise a room and accept joiners.
@MainActor
protocol NightHostTransport: AnyObject {
    func start(roomCode: String,
               onPeer: @escaping @MainActor (any NightPeerLink) -> Void,
               onFrame: @escaping @MainActor (any NightPeerLink, Data) -> Void,
               onDrop: @escaping @MainActor (any NightPeerLink) -> Void,
               onState: @escaping @MainActor (NightHostLinkState) -> Void)
    func stop()
}

/// Joiner side: discover a room by code and connect to it. `onDropped` fires at
/// most once per `connect(...)` attempt (browse failure, connect failure, or
/// stream end) — the client owns the retry policy.
@MainActor
protocol NightClientTransport: AnyObject {
    func connect(roomCode: String,
                 onConnected: @escaping @MainActor (any NightPeerLink) -> Void,
                 onFrame: @escaping @MainActor (Data) -> Void,
                 onDropped: @escaping @MainActor () -> Void,
                 onStatus: @escaping @MainActor (NightClientLinkStatus) -> Void)
    func disconnect()
}

enum NightHostLinkState {
    case ready
    case failed(String)
    case stopped
}

enum NightClientLinkStatus {
    case searching
    case connecting
}
