package com.learningischange.tidbitstrivia.net

import android.content.Context
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.net.wifi.WifiManager
import java.net.InetSocketAddress
import java.net.ServerSocket
import java.net.Socket

/**
 * Transport adapter #1: DNS-SD (NsdManager) + plain TCP. This is the PROVEN
 * cross-platform link — Bonjour (Apple) and NsdManager (Android) are the same
 * mDNS/DNS-SD protocol, so an Android device discovers an Apple `_tidbits-night._tcp`
 * host and vice versa, over a shared Wi-Fi router. Confidentiality/auth is the
 * app-layer AES-GCM in NightWire (Android can't speak Apple's GCM-PSK TLS suite).
 *
 * Wi-Fi Aware (no router) is adapter #2; the host/client state machine never
 * changes. NOT yet two-device-verified. `SocketPeer` is shared (NightTransport.kt).
 *
 * Requires NEARBY_WIFI_DEVICES (Android 13+) for discovery; the UI requests it.
 */
class NsdTcpHostTransport(private val context: Context) : NightHostTransport {
    private var server: ServerSocket? = null
    private var nsd: NsdManager? = null
    private var reg: NsdManager.RegistrationListener? = null
    private var running = false
    private val peers = mutableListOf<SocketPeer>()

    override fun start(roomCode: String, onPeer: (NightPeer) -> Unit, onFrame: (NightPeer, ByteArray) -> Unit, onDrop: (NightPeer) -> Unit) {
        running = true
        val ss = ServerSocket(0); server = ss
        val port = ss.localPort
        val manager = context.getSystemService(Context.NSD_SERVICE) as NsdManager
        nsd = manager
        val info = NsdServiceInfo().apply {
            serviceName = "Tidbits-$roomCode"; serviceType = Night.serviceType; setPort(port)
        }
        reg = object : NsdManager.RegistrationListener {
            override fun onServiceRegistered(p0: NsdServiceInfo?) {}
            override fun onRegistrationFailed(p0: NsdServiceInfo?, p1: Int) {}
            override fun onServiceUnregistered(p0: NsdServiceInfo?) {}
            override fun onUnregistrationFailed(p0: NsdServiceInfo?, p1: Int) {}
        }
        runCatching { manager.registerService(info, NsdManager.PROTOCOL_DNS_SD, reg) }

        Thread {
            while (running) {
                val sock = runCatching { ss.accept() }.getOrNull() ?: break
                val peer = SocketPeer(sock)
                synchronized(peers) { peers.add(peer) }
                onPeer(peer)
                peer.readLoop({ onFrame(peer, it) }, { synchronized(peers) { peers.remove(peer) }; onDrop(peer) })
            }
        }.apply { isDaemon = true }.start()
    }

    override fun stop() {
        running = false
        reg?.let { r -> runCatching { nsd?.unregisterService(r) } }; reg = null
        runCatching { server?.close() }; server = null
        synchronized(peers) { peers.forEach { it.close() }; peers.clear() }
    }
}

class NsdTcpClientTransport(private val context: Context) : NightClientTransport {
    private var nsd: NsdManager? = null
    private var discovery: NsdManager.DiscoveryListener? = null
    private var lock: WifiManager.MulticastLock? = null
    private var peer: SocketPeer? = null
    private var resolving = false

    override fun connect(roomCode: String, onConnected: (NightPeer) -> Unit, onFrame: (ByteArray) -> Unit, onDropped: () -> Unit, onStatus: (String) -> Unit) {
        val code = roomCode.uppercase()
        val manager = context.getSystemService(Context.NSD_SERVICE) as NsdManager
        nsd = manager
        val wifi = context.applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
        lock = wifi.createMulticastLock("tidbits-night").apply { setReferenceCounted(true); runCatching { acquire() } }
        onStatus("Looking for the room…")

        discovery = object : NsdManager.DiscoveryListener {
            override fun onDiscoveryStarted(p0: String?) {}
            override fun onDiscoveryStopped(p0: String?) {}
            override fun onStartDiscoveryFailed(p0: String?, p1: Int) { onStatus("Can't search the network") }
            override fun onStopDiscoveryFailed(p0: String?, p1: Int) {}
            override fun onServiceLost(p0: NsdServiceInfo?) {}
            override fun onServiceFound(info: NsdServiceInfo?) {
                val name = info?.serviceName ?: return
                if (name.uppercase().endsWith(code) && !resolving && peer == null) {
                    resolving = true
                    resolve(info, onConnected, onFrame, onDropped, onStatus)
                }
            }
        }
        runCatching { manager.discoverServices(Night.serviceType, NsdManager.PROTOCOL_DNS_SD, discovery) }
    }

    @Suppress("DEPRECATION")   // resolveService covers minSdk 29; registerServiceInfoCallback is API 34+
    private fun resolve(info: NsdServiceInfo, onConnected: (NightPeer) -> Unit, onFrame: (ByteArray) -> Unit, onDropped: () -> Unit, onStatus: (String) -> Unit) {
        nsd?.resolveService(info, object : NsdManager.ResolveListener {
            override fun onResolveFailed(p0: NsdServiceInfo?, p1: Int) { resolving = false }
            override fun onServiceResolved(resolved: NsdServiceInfo?) {
                val host = resolved?.host ?: run { resolving = false; return }
                val port = resolved.port
                onStatus("Connecting…")
                Thread {
                    val sock = Socket()
                    val ok = runCatching { sock.connect(InetSocketAddress(host, port), 5000) }.isSuccess
                    if (!ok) { resolving = false; onStatus("Couldn't connect — retrying"); return@Thread }
                    val p = SocketPeer(sock); peer = p
                    discovery?.let { runCatching { nsd?.stopServiceDiscovery(it) } }
                    onConnected(p)
                    p.readLoop({ onFrame(it) }, { peer = null; onDropped() })
                }.apply { isDaemon = true }.start()
            }
        })
    }

    override fun disconnect() {
        discovery?.let { d -> runCatching { nsd?.stopServiceDiscovery(d) } }; discovery = null
        lock?.let { if (it.isHeld) runCatching { it.release() } }; lock = null
        peer?.close(); peer = null
        resolving = false
    }
}
