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
    // Closest Call (M5): the live slider value + points the last guess earned.
    var currentGuess by mutableDoubleStateOf(0.0)
    var lastGuessPoints by mutableIntStateOf(0)
    // Ordering (Q4): the player's working arrangement + points earned.
    var currentOrder by mutableStateOf<List<String>>(emptyList())
    var lastOrderPoints by mutableIntStateOf(0)
    // Matching (Q5): shuffled values, per-key assignment, selected key, points.
    var matchValues by mutableStateOf<List<String>>(emptyList())
    var matchAssign by mutableStateOf<List<Int?>>(emptyList())
    var matchSelectedKey by mutableStateOf<Int?>(null)
    var lastMatchPoints by mutableIntStateOf(0)
    // Type-the-answer (Q6): the typed input.
    var typedText by mutableStateOf("")
    // Enumeration (Q8): named group indices, canonical names found, last-hit flag.
    var enumFilled by mutableStateOf<Set<Int>>(emptySet())
    var enumNamed by mutableStateOf<List<String>>(emptyList())
    var enumLastHit by mutableStateOf(false)

    var questions: List<Question> = emptyList(); private set
    private var budget = 30.0
    private var qStart = 0L
    private var globalDeadline: Long? = null
    private var recorded = false

    val current: Question? get() = questions.getOrNull(index)
    val correctCount: Int get() = answered.count { it.correct }
    val isLast: Boolean get() = (mode == Mode.CLASSIC || mode == Mode.DAILY || mode == Mode.STAKE || mode == Mode.SWEEP || mode == Mode.PICTURE_ID || mode == Mode.THIS_OR_THAT || mode == Mode.CLOSEST_CALL || mode == Mode.ORDERING || mode == Mode.MATCHING || mode == Mode.TYPE_ANSWER || mode == Mode.ODD_ONE_OUT || mode == Mode.LADDER || mode == Mode.ENUMERATE) && index + 1 >= questions.size
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
            mode == Mode.THIS_OR_THAT -> ThisOrThat.pull(category.id, store.seenSet, mode.count)
            mode == Mode.CLOSEST_CALL -> ClosestCall.pull(category.id, store.seenSet, mode.count)
            mode == Mode.ORDERING -> OrderingSet.pull(category.id, store.seenSet, mode.count)
            mode == Mode.MATCHING -> MatchingSet.pull(category.id, store.seenSet, mode.count)
            mode == Mode.TYPE_ANSWER -> TypeAnswerSet.pull(category.id, store.seenSet, mode.count)
            mode == Mode.ODD_ONE_OUT -> OddOneOutSet.pull("mixed", store.seenSet, mode.count)
            // Small pool (~11) and a REPLAYABLE recall drill — ignore the seen-set.
            mode == Mode.ENUMERATE -> EnumerateSet.pull("mixed", emptySet(), mode.count)
            mode == Mode.LADDER -> {
                val pool = Corpus.pull("mixed", store.seenSet, 80).sortedBy { Difficulty.get(it.sourceTitle) }
                val need = mode.count
                if (pool.size >= need) (0 until need).map { pool[it * (pool.size - 1) / maxOf(1, need - 1)] } else pool
            }
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
        // Spaced re-asking of missed questions (opt-out in Records → Settings).
        // loadStandard only serves the corpus-MCQ modes, so weaving is safe here.
        if (store.reviewEnabled()) {
            val review = store.dueReview(30).mapNotNull { Corpus.byId(it) }
                .filter { category.id == "mixed" || it.categoryId == category.id }
                .take(2)
            pulled = weave(pulled, review)
        }
        return pulled
    }

    /** Interleave due review questions among fresh ones (mirror iOS/web _weave). */
    private fun weave(fresh: List<Question>, review: List<Question>): List<Question> {
        val ids = fresh.map { it.id }.toSet()
        val inject = review.filter { it.id !in ids }.take(maxOf(1, fresh.size / 4))
        if (inject.isEmpty() || fresh.size <= inject.size) return fresh
        val r = fresh.toMutableList()
        inject.forEachIndexed { i, q ->
            r[minOf(r.size - 1, (i + 1) * r.size / (inject.size + 1))] = q
        }
        return r
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
        current?.closest?.let { currentGuess = Math.round((it.min + it.max) / 2).toDouble() }
        current?.ordering?.let { order ->
            var s = order.shuffled()
            var tries = 0; while (s == order && tries++ < 6) s = order.shuffled()
            currentOrder = s
        }
        current?.matching?.let { m ->
            matchValues = m.values.shuffled()
            matchAssign = List(m.keys.size) { null }
            matchSelectedKey = null
        }
        if (current?.accepted != null) typedText = ""
        if (current?.enumerate != null) { enumFilled = emptySet(); enumNamed = emptyList(); enumLastHit = false; typedText = "" }
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
        else { remaining = max(0.0, budget - (now() - qStart) / 1000.0); if (remaining <= 0) { when (mode) { Mode.CLOSEST_CALL -> submitGuess(); Mode.ORDERING -> submitOrder(); Mode.MATCHING -> submitMatch(); Mode.TYPE_ANSWER -> submitText(); Mode.ENUMERATE -> finishEnum(); else -> submit(null) } } }
    }

    fun submitText() {
        if (phase != GamePhase.PLAYING) return
        val q = current ?: return; val acc = q.accepted ?: return
        val correct = TypeMatch.matches(typedText, acc)
        val taken = (now() - qStart) / 1000.0
        answered.add(Answered(q, if (correct) q.correctIndex else -1, correct, taken))
        lastCorrect = correct
        if (correct) { streak++; maxStreak = max(maxStreak, streak); score += Scoring.points(true, taken, mode.perQuestion?.toDouble() ?: 25.0, streak) } else streak = 0
        phase = GamePhase.REVEAL
    }

    // Enumeration (Q8): type a guess; fill the first unfilled group it matches.
    // +1 per fill (count-scored, like Sweep). Returns whether it matched.
    fun submitEnumGuess(text: String): Boolean {
        if (phase != GamePhase.PLAYING) return false
        val spec = current?.enumerate ?: return false
        typedText = ""
        val n = text.trim()
        if (n.isEmpty()) { enumLastHit = false; return false }
        for (i in spec.groups.indices) {
            if (i in enumFilled) continue
            if (TypeMatch.matches(n, spec.groups[i])) {
                enumFilled = enumFilled + i
                enumNamed = enumNamed + (spec.groups[i].firstOrNull() ?: "")
                score += 1
                enumLastHit = true
                if (enumFilled.size == spec.groups.size) finishEnum()
                return true
            }
        }
        enumLastHit = false
        return false
    }
    fun finishEnum() {
        if (phase != GamePhase.PLAYING) return
        val q = current ?: return; val spec = q.enumerate ?: return
        val got = enumFilled.size
        val hit = got > 0 && got * 2 >= spec.groups.size
        answered.add(Answered(q, if (hit) q.correctIndex else -1, hit, budget - remaining))
        lastCorrect = hit
        phase = GamePhase.REVEAL
    }

    fun selectMatchKey(i: Int) {
        if (mode != Mode.MATCHING || phase != GamePhase.PLAYING) return
        matchSelectedKey = if (matchSelectedKey == i) null else i
    }
    fun assignMatchValue(j: Int) {
        if (mode != Mode.MATCHING || phase != GamePhase.PLAYING) return
        val key = matchSelectedKey ?: return
        matchAssign = matchAssign.mapIndexed { i, v -> when { i == key -> j; v == j -> null; else -> v } }
        matchSelectedKey = null
    }
    fun matchedValue(i: Int): String? = matchAssign.getOrNull(i)?.let { matchValues.getOrNull(it) }
    fun submitMatch() {
        if (phase != GamePhase.PLAYING) return
        val q = current ?: return; val m = q.matching ?: return
        var correct = 0
        for (i in m.keys.indices) if (matchedValue(i) == m.values[i]) correct++
        val pts = if (m.keys.isEmpty()) 0 else Math.round(40.0 * correct / m.keys.size).toInt()
        val perfect = correct == m.keys.size
        lastMatchPoints = pts
        val taken = (now() - qStart) / 1000.0
        answered.add(Answered(q, if (perfect) q.correctIndex else -1, perfect, taken))
        lastCorrect = perfect
        if (perfect) { streak++; maxStreak = max(maxStreak, streak) } else streak = 0
        score += pts
        phase = GamePhase.REVEAL
    }

    fun moveOrderItem(i: Int, up: Boolean) {
        if (mode != Mode.ORDERING || phase != GamePhase.PLAYING) return
        val t = if (up) i - 1 else i + 1
        if (t !in currentOrder.indices) return
        currentOrder = currentOrder.toMutableList().also { java.util.Collections.swap(it, i, t) }
    }

    fun submitOrder() {
        if (phase != GamePhase.PLAYING) return
        val q = current ?: return; val correct = q.ordering ?: return
        val rank = correct.withIndex().associate { (i, n) -> n to i }
        var inv = 0
        for (i in currentOrder.indices) for (j in i + 1 until currentOrder.size)
            if ((rank[currentOrder[i]] ?: 0) > (rank[currentOrder[j]] ?: 0)) inv++
        val maxInv = correct.size * (correct.size - 1) / 2
        val pts = if (maxInv == 0) 0 else Math.round(40.0 * (1 - inv.toDouble() / maxInv)).toInt()
        val perfect = inv == 0
        lastOrderPoints = pts
        val taken = (now() - qStart) / 1000.0
        answered.add(Answered(q, if (perfect) q.correctIndex else -1, perfect, taken))
        lastCorrect = perfect
        if (perfect) { streak++; maxStreak = max(maxStreak, streak) } else streak = 0
        score += pts
        phase = GamePhase.REVEAL
    }

    fun setGuess(v: Double) {
        val s = current?.closest ?: return
        if (phase != GamePhase.PLAYING) return
        currentGuess = v.coerceIn(s.min, s.max)
    }

    fun submitGuess() {
        if (phase != GamePhase.PLAYING) return
        val q = current ?: return; val s = q.closest ?: return
        val pts = s.points(currentGuess); val close = s.isClose(currentGuess)
        lastGuessPoints = pts
        val taken = (now() - qStart) / 1000.0
        answered.add(Answered(q, if (close) q.correctIndex else -1, close, taken))
        lastCorrect = close
        if (close) { streak++; maxStreak = max(maxStreak, streak) } else streak = 0
        score += pts
        phase = GamePhase.REVEAL
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
                Mode.LADDER -> Scoring.points(true, taken, mode.perQuestion?.toDouble() ?: budget, streak) + (Difficulty.get(q.sourceTitle) - 1) * 10
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
            store.recordTelemetry(mode, answered.map { it.q to it.chosen })
            store.recordMisses(answered.map { it.q.id to it.correct })   // for spaced review
            if (mode == Mode.STAKE) store.addCalibration(stakeOutcomes.mapValues { it.value[0] to it.value[1] })
        }
    }

    private fun now() = System.currentTimeMillis()
}
