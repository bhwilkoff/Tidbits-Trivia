package com.learningischange.tidbitstrivia.ui

import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.learningischange.tidbitstrivia.data.*
import com.learningischange.tidbitstrivia.net.*
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch

/**
 * Coordinates a networked Trivia Night (Decision 033) on THIS device — owns the
 * host- or joiner-side transport AND drives the local [GameState], so the live
 * screen just renders the game. Host-paced, everyone-plays: the host builds the
 * night once, ships the question IDS to everyone, and reveals/advances for all;
 * each device scores itself and reports its total. Mirrors the Apple `LiveNight`.
 */
class LiveNight private constructor(
    val role: Role,
    private val store: Store,
    private val context: Context,
    private val rounds: List<Pair<String, Int>>,
    private val categoryId: String,
) {
    enum class Role { HOST, JOINER }
    enum class Stage { LOBBY, PLAYING, FINISHED }

    var stage by mutableStateOf(Stage.LOBBY); private set
    var game by mutableStateOf<GameState?>(null); private set
    var host: NightHost? = null; private set
    var client: NightClient? = null; private set

    private val scope = CoroutineScope(Dispatchers.Main)
    private var pendingBegin: Int? = null

    companion object {
        fun host(store: Store, context: Context, rounds: List<Pair<String, Int>>, categoryId: String, hostName: String): LiveNight {
            val ln = LiveNight(Role.HOST, store, context, rounds, categoryId)
            val h = NightHost(NightTransports.host(context))
            ln.host = h
            h.start(hostName)
            return ln
        }

        fun join(store: Store, context: Context): LiveNight {
            val ln = LiveNight(Role.JOINER, store, context, emptyList(), "mixed")
            val c = NightClient(NightTransports.client(context), store.deviceId())
            ln.client = c
            c.onNight = onNight@{ plan, qs ->
                // On a reconnect the host replays the night; keep the existing game
                // (and its local score) — just jump to the current question via onBegin.
                if (ln.game != null) { ln.stage = Stage.PLAYING; return@onNight }
                val planRounds = plan.rounds.map { it.kind to it.count }
                val tagged = qs.tagRounds(planRounds)
                val g = GameState(Mode.BAR_TRIVIA, Category.byId("mixed"), store, tagged, "Trivia Night", planRounds, hostPaced = true)
                g.onLocalAnswer = { score, correct -> c.reportAnswer(score, correct) }
                ln.game = g
                ln.scope.launch {
                    g.start()
                    ln.pendingBegin?.let { g.goToQuestion(it); ln.pendingBegin = null }
                    ln.stage = Stage.PLAYING
                }
            }
            c.onBegin = { i -> val g = ln.game; if (g != null) g.goToQuestion(i) else ln.pendingBegin = i }
            c.onReveal = { _ -> ln.game?.releaseReveal() }
            c.onFinished = { ln.game?.finishExternally(); ln.stage = Stage.FINISHED }
            return ln
        }
    }

    // ---- Host actions ----

    suspend fun startNight() {
        val h = host ?: return
        val qs = buildNightQuestions(rounds, categoryId, store.seenSet)
        if (qs.isEmpty()) return
        h.broadcastNight(rounds.toNightPlan(), qs)
        val g = GameState(Mode.BAR_TRIVIA, Category.byId(categoryId), store, qs, "Trivia Night", rounds, hostPaced = true)
        g.onLocalAnswer = { score, correct -> h.setHostAnswered(score, correct) }
        game = g
        g.start()
        h.broadcastBegin(0)
        stage = Stage.PLAYING
    }

    /** Host taps Reveal — everyone reveals now. */
    fun reveal() {
        val g = game ?: return
        g.releaseReveal()
        host?.broadcastReveal(g.index)
    }

    /** Host taps Next — advance everyone, or end the night. */
    fun next() {
        val g = game ?: return
        val n = g.index + 1
        if (n >= g.questions.size) { g.finishExternally(); host?.broadcastFinished(); stage = Stage.FINISHED }
        else { g.goToQuestion(n); host?.broadcastBegin(n) }
    }

    // ---- Joiner actions ----

    fun join(code: String, name: String) { store.rememberNight(code, name); client?.join(code, name) }

    // ---- Shared read model (the live screen observes these) ----

    val players: List<NightPlayer> get() = host?.players ?: client?.players ?: emptyList()
    val roomCode: String get() = host?.roomCode ?: (client?.roomName?.substringAfterLast(' ') ?: "")
    val mySeat: Int? get() = if (role == Role.HOST) NightHost.HOST_SEAT else client?.seat
    val answeredCount: Int get() = host?.answeredCount ?: 0
    val everyoneAnswered: Boolean get() = host?.everyoneAnswered ?: false
    val leaderSeat: Int? get() = players.maxByOrNull { it.score }?.takeIf { it.score > 0 }?.seat
    val clientStatus: NightClient.Status? get() = client?.status
    /** A joiner silently re-discovering the room after a drop (mid-night). */
    val reconnecting: Boolean get() = role == Role.JOINER && client?.status == NightClient.Status.searching

    fun end() {
        host?.stop()
        client?.leave()
        stage = Stage.FINISHED
    }
}

private fun List<Pair<String, Int>>.toNightPlan() = NightPlan(map { NightRound(it.first, it.second) })
