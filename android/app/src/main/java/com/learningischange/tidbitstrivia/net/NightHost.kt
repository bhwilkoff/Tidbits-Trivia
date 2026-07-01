package com.learningischange.tidbitstrivia.net

import android.os.Handler
import android.os.Looper
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.learningischange.tidbitstrivia.data.Question

/**
 * Host side of a Trivia Night (Decision 033) — transport-agnostic. Owns the
 * authoritative roster + standings and paces the night on the human host's
 * behalf (the host is also a player, seat 0). It does NOT judge answers: every
 * device runs its own engine over the identical id-based question list and
 * reports its running total; the host aggregates and paces.
 *
 * Mirrors the Apple `NightHost`. The link-layer is injected as a
 * [NightHostTransport] (mDNS+TCP today; Wi-Fi Aware / BLE later).
 *
 * NOT yet two-device-verified — a hardware pairing test is the gate.
 */
class NightHost(private val transport: NightHostTransport) {
    var roomCode by mutableStateOf(""); private set
    var isListening by mutableStateOf(false); private set
    var lastError by mutableStateOf<String?>(null); private set
    /** Standings, host included. Seat 0 is the host. */
    val players = mutableStateListOf<NightPlayer>()

    val answeredCount: Int get() = players.count { it.answered }
    val everyoneAnswered: Boolean get() = players.isNotEmpty() && players.all { it.answered }
    val leaderSeat: Int? get() = players.maxByOrNull { it.score }?.takeIf { it.score > 0 }?.seat

    private val main = Handler(Looper.getMainLooper())
    private var key = ByteArray(0)

    private class PeerState(val peer: NightPeer, val framer: NightFramer) { var seat: Int? = null }
    private val peers = HashMap<String, PeerState>()
    private var nextSeat = 1
    private val seatByDevice = HashMap<String, Int>()

    // Retained so a device that (re)joins mid-game is caught all the way up.
    private var activePlan: NightPlan? = null
    private var activeIds: List<String> = emptyList()
    private var currentIndex = -1
    private var revealed = false

    companion object { const val HOST_SEAT = 0 }

    fun start(hostName: String) {
        stop()
        roomCode = RoomCode.generate()
        key = RoomCode.key(roomCode)
        val name = hostName.trim().ifEmpty { "Host" }
        players.add(NightPlayer(seat = HOST_SEAT, name = name, isHost = true))
        transport.start(
            roomCode = roomCode,
            onPeer = { p -> main.post { peers[p.id] = PeerState(p, NightFramer(key)); isListening = true } },
            onFrame = { p, bytes -> main.post { peers[p.id]?.let { st -> st.framer.ingest(bytes).forEach { handle(it, st) } } } },
            onDrop = { p -> main.post { peers.remove(p.id) } },   // keep the seat+score for rejoin
        )
        isListening = true
    }

    fun stop() {
        transport.stop()
        peers.values.forEach { it.peer.close() }
        peers.clear(); players.clear(); seatByDevice.clear()
        isListening = false; nextSeat = 1
        activePlan = null; activeIds = emptyList(); currentIndex = -1; revealed = false
        lastError = null
    }

    // ---- Pacing (called by LiveNight on the host's behalf) ----

    /** Ship the whole night to everyone, once, at start — id-based. */
    fun broadcastNight(plan: NightPlan, questions: List<Question>) {
        activePlan = plan; activeIds = questions.map { it.id }
        broadcast(NightMessage(NightKind.night, plan = plan, questionIds = activeIds))
    }

    fun broadcastBegin(index: Int) {
        currentIndex = index; revealed = false
        for (i in players.indices) players[i] = players[i].copy(answered = false)
        broadcast(NightMessage(NightKind.begin, questionIndex = index)); broadcastRoster()
    }

    fun broadcastReveal(index: Int) {
        revealed = true
        broadcast(NightMessage(NightKind.reveal, questionIndex = index))
    }

    fun broadcastFinished() = broadcast(NightMessage(NightKind.finished))

    /** The host (seat 0) locked its own answer — fold it into the standings. */
    fun setHostAnswered(score: Int, correct: Boolean) {
        val i = players.indexOfFirst { it.seat == HOST_SEAT }
        if (i >= 0) players[i] = players[i].copy(score = score, answered = true)
        broadcastRoster()
    }

    fun nameForSeat(seat: Int): String = players.firstOrNull { it.seat == seat }?.name ?: "Player $seat"

    // ---- Message handling ----

    private fun handle(msg: NightMessage, st: PeerState) {
        when (msg.kind) {
            NightKind.join -> {
                val raw = (msg.displayName ?: "").trim()
                val device = msg.deviceID
                val resumed = device?.let { seatByDevice[it] }
                    ?: raw.takeIf { it.isNotEmpty() }?.let { r -> players.firstOrNull { it.seat != HOST_SEAT && it.name.equals(r, true) }?.seat }
                val seat: Int
                if (resumed != null && players.any { it.seat == resumed }) {
                    seat = resumed
                    if (raw.isNotEmpty()) { val i = players.indexOfFirst { it.seat == seat }; if (i >= 0) players[i] = players[i].copy(name = raw) }
                } else {
                    seat = nextSeat++; players.add(NightPlayer(seat = seat, name = raw.ifEmpty { "Player $seat" }))
                }
                if (device != null) seatByDevice[device] = seat
                st.seat = seat
                send(st.peer, NightMessage(NightKind.welcome, seat = seat, roomName = "Tidbits $roomCode"))
                broadcastRoster()
                replayState(st.peer)
            }
            NightKind.answered -> {
                val seat = st.seat ?: return
                val i = players.indexOfFirst { it.seat == seat }
                if (i >= 0) players[i] = players[i].copy(score = msg.score ?: players[i].score, answered = true)
                broadcastRoster()
            }
            NightKind.leave -> { peers.remove(st.peer.id); st.peer.close() }
            else -> {}
        }
    }

    /** Bring a freshly-(re)joined device up to the live state. */
    private fun replayState(peer: NightPeer) {
        val plan = activePlan ?: return
        send(peer, NightMessage(NightKind.night, plan = plan, questionIds = activeIds))
        if (currentIndex >= 0) {
            send(peer, NightMessage(NightKind.begin, questionIndex = currentIndex))
            if (revealed) send(peer, NightMessage(NightKind.reveal, questionIndex = currentIndex))
        }
    }

    // ---- Broadcast ----

    private fun broadcast(m: NightMessage) { peers.values.forEach { send(it.peer, m) } }
    private fun broadcastRoster() = broadcast(NightMessage(NightKind.roster, players = players.toList()))
    private fun send(peer: NightPeer, m: NightMessage) { NightWire.encode(m, key)?.let { peer.send(it) } }
}
