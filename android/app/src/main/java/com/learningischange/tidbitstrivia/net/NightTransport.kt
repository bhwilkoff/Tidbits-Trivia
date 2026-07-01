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

/** A TCP-socket-backed peer, shared by every socket transport (mDNS/TCP today,
 *  Wi-Fi Aware next — both end in a plain TCP stream). Writes go off the caller's
 *  thread; reads run on a daemon thread and report EOF via onEnd. */
internal class SocketPeer(private val socket: java.net.Socket) : NightPeer {
    override val id = "${socket.inetAddress?.hostAddress}:${socket.port}#${System.identityHashCode(socket)}"
    private val out = socket.getOutputStream()
    private val writer = java.util.concurrent.Executors.newSingleThreadExecutor()

    override fun send(frame: ByteArray) {
        writer.execute { runCatching { synchronized(out) { out.write(frame); out.flush() } } }
    }
    override fun close() {
        runCatching { socket.close() }
        runCatching { writer.shutdownNow() }
    }
    fun readLoop(onBytes: (ByteArray) -> Unit, onEnd: () -> Unit) {
        Thread {
            val buf = ByteArray(16 * 1024)
            val ins = runCatching { socket.getInputStream() }.getOrNull()
            if (ins != null) runCatching {
                while (true) { val n = ins.read(buf); if (n < 0) break; onBytes(buf.copyOf(n)) }
            }
            onEnd()
        }.apply { isDaemon = true }.start()
    }
}
