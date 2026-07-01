package com.learningischange.tidbitstrivia.net

import android.content.Context
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.wifi.aware.*
import android.os.Handler
import android.os.HandlerThread
import java.net.InetSocketAddress
import java.net.ServerSocket
import java.net.Socket

/**
 * Transport adapter #2: **Wi-Fi Aware** (NAN) — device-to-device, **no router,
 * no server**. This is the strongest cross-platform link given the iOS 26 floor:
 * Android's `WifiAwareManager` and Apple's new `WiFiAware` framework are the same
 * open standard (docs/CROSS-PLATFORM-MULTIPLAYER.md). Same `NightMessage` state
 * machine + AES-GCM framing ride over it — this file only changes how the socket
 * is discovered + established.
 *
 * The data path is left OPEN (no Wi-Fi-Aware-layer PSK) and confidentiality stays
 * the app-layer AES-GCM keyed by the room code — one less cross-vendor variable.
 * The room code travels in the publish service-specific-info so a subscriber picks
 * the right room.
 *
 * DEVICE-GATED: no emulator has Wi-Fi Aware hardware, so this is compile-verified
 * only; the caller falls back to mDNS+TCP when the feature is absent (see
 * NightTransports.pick*). A real 2-device test is the gate.
 */
private const val WA_SERVICE = "TidbitsNight"   // ≤15 chars, matches the iOS WiFiAwareServices name

fun hasWifiAware(context: Context): Boolean =
    context.packageManager.hasSystemFeature(PackageManager.FEATURE_WIFI_AWARE) &&
        (context.getSystemService(Context.WIFI_AWARE_SERVICE) as? WifiAwareManager)?.isAvailable == true

private fun awareHandler(): Handler {
    val t = HandlerThread("night-wifiaware").apply { start() }
    return Handler(t.looper)
}

class WifiAwareHostTransport(private val context: Context) : NightHostTransport {
    private val cm = context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
    private val handler = awareHandler()
    private var manager: WifiAwareManager? = null
    private var session: WifiAwareSession? = null
    private var publish: PublishDiscoverySession? = null
    private var server: ServerSocket? = null
    private val netCallbacks = mutableListOf<ConnectivityManager.NetworkCallback>()
    private var running = false

    override fun start(roomCode: String, onPeer: (NightPeer) -> Unit, onFrame: (NightPeer, ByteArray) -> Unit, onDrop: (NightPeer) -> Unit) {
        running = true
        val ss = ServerSocket(0); server = ss
        val port = ss.localPort
        // Accept loop — each Wi-Fi Aware peer that connects becomes a SocketPeer.
        Thread {
            while (running) {
                val sock = runCatching { ss.accept() }.getOrNull() ?: break
                val peer = SocketPeer(sock)
                onPeer(peer)
                peer.readLoop({ onFrame(peer, it) }, { onDrop(peer) })
            }
        }.apply { isDaemon = true }.start()

        val mgr = context.getSystemService(Context.WIFI_AWARE_SERVICE) as WifiAwareManager
        manager = mgr
        mgr.attach(object : AttachCallback() {
            override fun onAttached(s: WifiAwareSession) {
                session = s
                val cfg = PublishConfig.Builder()
                    .setServiceName(WA_SERVICE)
                    .setServiceSpecificInfo(roomCode.uppercase().toByteArray())
                    .build()
                s.publish(cfg, object : DiscoverySessionCallback() {
                    override fun onPublishStarted(sess: PublishDiscoverySession) { publish = sess }
                    // A subscriber that matched the room says hello → open a data path to it,
                    // listening on our accept port. The subscriber then connects to us.
                    override fun onMessageReceived(peer: PeerHandle, message: ByteArray?) {
                        val pub = publish ?: return
                        val spec = WifiAwareNetworkSpecifier.Builder(pub, peer).setPort(port).build()
                        val req = NetworkRequest.Builder()
                            .addTransportType(NetworkCapabilities.TRANSPORT_WIFI_AWARE)
                            .setNetworkSpecifier(spec).build()
                        val cb = object : ConnectivityManager.NetworkCallback() {}
                        netCallbacks.add(cb)
                        runCatching { cm.requestNetwork(req, cb) }
                    }
                }, handler)
            }
            override fun onAttachFailed() {}
        }, handler)
    }

    override fun stop() {
        running = false
        netCallbacks.forEach { runCatching { cm.unregisterNetworkCallback(it) } }; netCallbacks.clear()
        runCatching { publish?.close() }; publish = null
        runCatching { session?.close() }; session = null
        runCatching { server?.close() }; server = null
    }
}

class WifiAwareClientTransport(private val context: Context) : NightClientTransport {
    private val cm = context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
    private val handler = awareHandler()
    private var session: WifiAwareSession? = null
    private var subscribe: SubscribeDiscoverySession? = null
    private var netCallback: ConnectivityManager.NetworkCallback? = null
    private var peer: SocketPeer? = null
    private var connecting = false

    override fun connect(roomCode: String, onConnected: (NightPeer) -> Unit, onFrame: (ByteArray) -> Unit, onDropped: () -> Unit, onStatus: (String) -> Unit) {
        val code = roomCode.uppercase()
        onStatus("Looking nearby (Wi-Fi Aware)…")
        val mgr = context.getSystemService(Context.WIFI_AWARE_SERVICE) as WifiAwareManager
        mgr.attach(object : AttachCallback() {
            override fun onAttached(s: WifiAwareSession) {
                session = s
                val cfg = SubscribeConfig.Builder().setServiceName(WA_SERVICE).build()
                s.subscribe(cfg, object : DiscoverySessionCallback() {
                    override fun onSubscribeStarted(sess: SubscribeDiscoverySession) { subscribe = sess }
                    override fun onServiceDiscovered(peerHandle: PeerHandle, ssi: ByteArray?, matchFilter: List<ByteArray>?) {
                        val found = ssi?.toString(Charsets.UTF_8)?.uppercase() ?: ""
                        val sub = subscribe ?: return
                        if (found != code || connecting || peer != null) return
                        connecting = true
                        // Say hello so the host opens a data path back to us, then request the network.
                        runCatching { sub.sendMessage(peerHandle, 0, code.toByteArray()) }
                        val spec = WifiAwareNetworkSpecifier.Builder(sub, peerHandle).build()
                        val req = NetworkRequest.Builder()
                            .addTransportType(NetworkCapabilities.TRANSPORT_WIFI_AWARE)
                            .setNetworkSpecifier(spec).build()
                        val cb = object : ConnectivityManager.NetworkCallback() {
                            override fun onCapabilitiesChanged(network: Network, caps: NetworkCapabilities) {
                                val info = caps.transportInfo as? WifiAwareNetworkInfo ?: return
                                val addr = info.peerIpv6Addr ?: return
                                if (peer != null) return
                                onStatus("Connecting…")
                                Thread {
                                    val sock = runCatching {
                                        Socket().also { network.bindSocket(it); it.connect(InetSocketAddress(addr, info.port), 5000) }
                                    }.getOrNull() ?: run { connecting = false; return@Thread }
                                    val p = SocketPeer(sock); peer = p
                                    onConnected(p)
                                    p.readLoop({ onFrame(it) }, { peer = null; onDropped() })
                                }.apply { isDaemon = true }.start()
                            }
                        }
                        netCallback = cb
                        runCatching { cm.requestNetwork(req, cb) }
                    }
                }, handler)
            }
            override fun onAttachFailed() { onStatus("Wi-Fi Aware unavailable") }
        }, handler)
    }

    override fun disconnect() {
        netCallback?.let { runCatching { cm.unregisterNetworkCallback(it) } }; netCallback = null
        runCatching { subscribe?.close() }; subscribe = null
        runCatching { session?.close() }; session = null
        peer?.close(); peer = null
        connecting = false
    }
}

/**
 * Which transport to use. **Default = mDNS+TCP** — it is the only path that is
 * cross-platform today: an iPhone host advertises over Bonjour/mDNS and has NO
 * Wi-Fi Aware yet, so auto-selecting Wi-Fi Aware here would make an Android
 * joiner listen on a channel the iPhone never publishes (it just spins on
 * "searching"). Wi-Fi Aware / BLE are BUILT (`WifiAwareTransport`, `BleTransport`)
 * and `hasWifiAware`/`hasBle` gate them, but they stay opt-in until iOS ships its
 * side and we can search all transports in parallel (docs/CROSS-PLATFORM-MULTIPLAYER.md).
 */
object NightTransports {
    fun host(context: Context): NightHostTransport = NsdTcpHostTransport(context.applicationContext)
    fun client(context: Context): NightClientTransport = NsdTcpClientTransport(context.applicationContext)
}
