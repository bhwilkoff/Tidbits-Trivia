package com.learningischange.tidbitstrivia.ui

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableDoubleStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.learningischange.tidbitstrivia.data.*
import kotlin.math.max

enum class GamePhase { LOADING, PLAYING, REVEAL, FINISHED, ERROR }
enum class AnswerVisual { IDLE, CORRECT, WRONG, DIM }

data class Answered(val q: Question, val chosen: Int?, val correct: Boolean, val taken: Double)

/**
 * The Android game loop — a Compose state holder mirroring the Apple
 * GameEngine. Same scoring, streak, clock, and reveal flow; the UI just
 * observes the snapshot state.
 */
class GameState(
    val mode: Mode,
    val category: Category,
    private val store: Store,
    private val custom: List<Question>?,
    val label: String?,
) {
    var phase by mutableStateOf(GamePhase.LOADING)
    var index by mutableIntStateOf(0)
    var score by mutableIntStateOf(0)
    var streak by mutableIntStateOf(0)
    var maxStreak by mutableIntStateOf(0)
    var remaining by mutableDoubleStateOf(0.0)
    var chosen by mutableStateOf<Int?>(null)
    var lastCorrect by mutableStateOf(false)
    val answered = mutableListOf<Answered>()

    // Stake: the remaining confidence-chip budget + the chip on this question (0 = unset).
    var stakeTiers by mutableStateOf<List<StakeTier>>(emptyList())
    var currentStake by mutableIntStateOf(0)
    val stakeLabel: String get() = stakeTiers.firstOrNull { it.value == currentStake }?.label ?: ""
    // F1 calibration: per-tier [hits, total] for this round.
    private val stakeOutcomes = mutableMapOf<Int, IntArray>()

    var questions: List<Question> = emptyList(); private set
    private var budget = 30.0
    private var qStart = 0L
    private var globalDeadline: Long? = null
    private var recorded = false

    val current: Question? get() = questions.getOrNull(index)
    val correctCount: Int get() = answered.count { it.correct }
    val isLast: Boolean get() = (mode == Mode.CLASSIC || mode == Mode.DAILY || mode == Mode.STAKE || mode == Mode.SWEEP || mode == Mode.PICTURE_ID) && index + 1 >= questions.size
    val progressLabel: String get() = if (mode == Mode.TIME_ATTACK || mode == Mode.SURVIVAL) "#${index + 1}" else "${index + 1} / ${questions.size}"
    val clockFraction: Double get() = if (budget <= 0) 0.0 else (remaining / budget).coerceIn(0.0, 1.0)

    fun answerState(i: Int): AnswerVisual {
        if (phase != GamePhase.REVEAL) return AnswerVisual.IDLE
        val q = current ?: return AnswerVisual.IDLE
        return when {
            i == q.correctIndex -> AnswerVisual.CORRECT
            i == chosen -> AnswerVisual.WRONG
            else -> AnswerVisual.DIM
        }
    }

    suspend fun start() {
        phase = GamePhase.LOADING
        reset()
        val qs = when {
            custom != null -> custom
            mode == Mode.DAILY -> Corpus.daily(dayKey(), 7)
            mode == Mode.PICTURE_ID -> Pictures.pull(category.id, store.seenSet, mode.count)
            else -> loadStandard()
        }
        questions = if (mode.count == 99) qs else qs.take(mode.count)
        store.markSeen(questions.map { it.id })
        if (questions.isEmpty()) { phase = GamePhase.ERROR; return }
        if (mode.globalClock != null) globalDeadline = now() + mode.globalClock * 1000L
        begin()
    }

    suspend fun restart() = start()

    private suspend fun loadStandard(): List<Question> {
        var pulled = Corpus.pull(category.id, store.seenSet, mode.count)
        if (pulled.size < mode.count) {
            val topic = if (category.id == "mixed") "popular" else category.name
            pulled = pulled + Wikipedia.generate(topic, category.id, mode.count - pulled.size)
        }
        return pulled
    }

    private fun reset() {
        index = 0; score = 0; streak = 0; maxStreak = 0; chosen = null
        answered.clear(); globalDeadline = null; recorded = false
        stakeTiers = if (mode == Mode.STAKE) STAKE_BUDGET else emptyList()
        currentStake = 0
    }

    /** Commit a confidence chip to the current question (Stake mode); re-pickable until answered. */
    fun setStake(value: Int) {
        if (mode != Mode.STAKE || phase != GamePhase.PLAYING) return
        val tiers = stakeTiers.map { it.copy() }
        val tier = tiers.firstOrNull { it.value == value } ?: return
        if (tier.remaining <= 0) return
        if (currentStake != 0) tiers.firstOrNull { it.value == currentStake }?.let { it.remaining++ }
        tier.remaining--
        stakeTiers = tiers
        currentStake = value
    }

    private fun begin() {
        chosen = null
        currentStake = 0
        phase = GamePhase.PLAYING
        qStart = now()
        budget = globalRemaining() ?: (mode.perQuestion?.toDouble() ?: 30.0)
        remaining = budget
    }

    private fun globalRemaining(): Double? {
        val d = globalDeadline ?: return null
        return max(0.0, (d - now()) / 1000.0)
    }

    fun tick() {
        if (phase != GamePhase.PLAYING) return
        val g = globalRemaining()
        if (g != null) { remaining = g; if (g <= 0) end() }
        else { remaining = max(0.0, budget - (now() - qStart) / 1000.0); if (remaining <= 0) submit(null) }
    }

    fun submit(choice: Int?) {
        if (phase != GamePhase.PLAYING) return
        // Stake: a chip must be committed before a manual answer (a timeout, choice == null, still resolves).
        if (mode == Mode.STAKE && currentStake == 0 && choice != null) return
        val q = current ?: return
        chosen = choice
        val taken = (now() - qStart) / 1000.0
        val correct = choice == q.correctIndex
        answered.add(Answered(q, choice, correct, taken))
        lastCorrect = correct
        if (mode == Mode.STAKE && currentStake != 0) {
            val o = stakeOutcomes.getOrPut(currentStake) { intArrayOf(0, 0) }
            o[1]++; if (correct) o[0]++
        }
        if (correct) {
            streak++; maxStreak = max(maxStreak, streak)
            // Stake: the reward IS the chip (calibration). Sweep: +1 per correct —
            // the score is the count of the set you filled (no speed bonus). Else speed-aware.
            score += when (mode) {
                Mode.STAKE -> currentStake
                Mode.SWEEP -> 1
                else -> Scoring.points(true, taken, mode.perQuestion?.toDouble() ?: budget, streak)
            }
        } else streak = 0
        phase = GamePhase.REVEAL
    }

    fun advance() {
        if (mode == Mode.SURVIVAL && answered.isNotEmpty() && !answered.last().correct) { end(); return }
        val g = globalRemaining()
        if (g != null && g <= 0) { end(); return }
        index++
        if (index >= questions.size) { end(); return }
        begin()
    }

    private fun end() {
        phase = GamePhase.FINISHED
        if (!recorded) {
            recorded = true
            store.addRecord(Store.Rec(mode.name, category.id, score, correctCount, answered.size, maxStreak, dayKey()))
            if (mode == Mode.STAKE) store.addCalibration(stakeOutcomes.mapValues { it.value[0] to it.value[1] })
        }
    }

    private fun now() = System.currentTimeMillis()
}
