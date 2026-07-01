package com.learningischange.tidbitstrivia.net

/**
 * The seam between the Trivia Night state machine and the link-layer. Each
 * transport (mDNS+TCP now; Wi-Fi Aware / BLE / GitHub later) implements this;
 * the host/client logic and the wire protocol never change. See
 * docs/CROSS-PLATFORM-MULTIPLAYER.md "universal-connectivity question".
 *
 * A "peer" is one connected remote device. Frames are already length+GCM-framed
 * by NightWire/NightFramer — a transport just moves opaque bytes and reports
 * connect/disconnect.
 */
interface NightPeer {
    val id: String
    fun send(frame: ByteArray)
    fun close()
}

/** Host side: advertise a room and accept joiners. */
interface NightHostTransport {
    fun start(roomCode: String, onPeer: (NightPeer) -> Unit, onFrame: (NightPeer, ByteArray) -> Unit, onDrop: (NightPeer) -> Unit)
    fun stop()
}

/** Joiner side: discover a room by code and connect to it. */
interface NightClientTransport {
    fun connect(roomCode: String, onConnected: (NightPeer) -> Unit, onFrame: (ByteArray) -> Unit, onDropped: () -> Unit, onStatus: (String) -> Unit)
    fun disconnect()
}
