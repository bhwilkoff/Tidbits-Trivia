package com.learningischange.tidbitstrivia.net

import android.os.Handler
import android.os.Looper
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.learningischange.tidbitstrivia.data.Question

/**
 * Joiner side of a Trivia Night (Decision 033) — transport-agnostic. Discovers
 * the host by room code, receives the whole (id-based) night, then follows the
 * host's pacing. Plays on its OWN screen and scores itself, reporting only its
 * running total. Mirrors the Apple `NightClient`.
 *
 * NOT yet two-device-verified — a hardware pairing test is the gate.
 */
class NightClient(
    private val transport: NightClientTransport,
    private val deviceId: String,
) {
    enum class Status { idle, searching, connecting, joined, failed }

    var status by mutableStateOf(Status.idle); private set
    var statusMessage by mutableStateOf<String?>(null); private set
    var seat by mutableStateOf<Int?>(null); private set
    var roomName by mutableStateOf<String?>(null); private set
    val players = mutableStateListOf<NightPlayer>()

    // One-shot signals LiveNight wires to the local GameState.
    var onNight: ((NightPlan, List<Question>) -> Unit)? = null
    var onBegin: ((Int) -> Unit)? = null
    var onReveal: ((Int) -> Unit)? = null
    var onFinished: (() -> Unit)? = null

    private val main = Handler(Looper.getMainLooper())
    private var key = ByteArray(0)
    private var framer = NightFramer(ByteArray(32))
    private var displayName = ""
    private var peer: NightPeer? = null

    fun join(code: String, name: String) {
        val c = code.trim().uppercase()
        displayName = name.trim()
        key = RoomCode.key(c)
        framer = NightFramer(key)
        status = Status.searching
        transport.connect(
            roomCode = c,
            onConnected = { p -> main.post { peer = p; status = Status.connecting; sendJoin() } },
            onFrame = { bytes -> main.post { framer.ingest(bytes).forEach { handle(it) } } },
            onDropped = { main.post { if (status != Status.idle) { status = Status.searching } } },
            onStatus = { s -> main.post { statusMessage = s } },
        )
    }

    fun leave() {
        peer?.let { NightWire.encode(NightMessage(NightKind.leave), key)?.let { f -> it.send(f) } }
        transport.disconnect()
        peer = null; status = Status.idle; seat = null; roomName = null; players.clear()
    }

    /** Report a locked answer this question: running total + whether it was right. */
    fun reportAnswer(score: Int, correct: Boolean) {
        val p = peer ?: return
        NightWire.encode(NightMessage(NightKind.answered, score = score, correct = correct), key)?.let { p.send(it) }
    }

    private fun sendJoin() {
        val p = peer ?: return
        val m = NightMessage(NightKind.join, displayName = displayName.ifEmpty { null }, deviceID = deviceId)
        NightWire.encode(m, key)?.let { p.send(it) }
    }

    private fun handle(m: NightMessage) {
        when (m.kind) {
            NightKind.welcome -> { seat = m.seat; roomName = m.roomName; status = Status.joined }
            NightKind.roster -> { players.clear(); m.players?.let { players.addAll(it) } }
            NightKind.night -> { val plan = m.plan; val qs = m.resolveQuestions(); if (plan != null && qs.isNotEmpty()) onNight?.invoke(plan, qs) }
            NightKind.begin -> m.questionIndex?.let { onBegin?.invoke(it) }
            NightKind.reveal -> m.questionIndex?.let { onReveal?.invoke(it) }
            NightKind.finished -> onFinished?.invoke()
            else -> {}
        }
    }
}
