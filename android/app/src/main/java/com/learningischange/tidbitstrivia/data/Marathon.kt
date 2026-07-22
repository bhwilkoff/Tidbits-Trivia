package com.learningischange.tidbitstrivia.data

import com.learningischange.tidbitstrivia.BuildConfig
import kotlin.math.max
import kotlin.math.min

/** One question's outcome inside a Marathon run — enough to rebuild the domain
 *  scorecard without re-fetching the corpus (docs/CLUB-FEATURES-BUILD.md "Feature 3").
 *  Android mirror of Apple's `MarathonAnswerRecord` / web's `Marathon.record` payload. */
data class MarathonAnswerRecord(val qid: String, val categoryId: String, val difficulty: Int, val correct: Boolean)

/** The AT-MOST-ONE in-progress Marathon run — the load-bearing new mechanic (resume
 *  across sessions). [ids] is fixed forever at creation, drawn once from [seed] (the
 *  same fnv1a64 rank-and-slice `DailyPick` uses, just keyed by a per-run seed instead
 *  of a calendar day) — a resume always continues into the SAME set. Persisted (via
 *  [Store.saveMarathonRun]) after every single answer so a process death never loses
 *  progress. */
data class MarathonRun(
    val seed: String,
    val ids: List<String>,
    val currentIndex: Int,
    val results: List<MarathonAnswerRecord>,
    val startedAt: Long,
    val lastPlayedAt: Long,
) {
    val total: Int get() = ids.size
}

/** One domain's tally inside a completed Marathon — the scorecard's per-row unit
 *  (mirrors `DomainProgress` but scoped to a single run, not lifetime). */
data class MarathonDomainStat(val categoryId: String, val correct: Int, val total: Int) {
    val accuracy: Double get() = if (total == 0) 0.0 else correct.toDouble() / total
}

/** A completed Marathon — permanent history (docs/CLUB-FEATURES-BUILD.md
 *  "Feature 3"). The scorecard reads straight off this: score, correct/total, and the
 *  per-domain breakdown, plus how it compares to the player's other runs. */
data class MarathonScore(
    val date: Long, val score: Int, val correct: Int, val total: Int,
    val durationSeconds: Double, val domainBreakdown: List<MarathonDomainStat>,
) {
    val accuracy: Double get() = if (total == 0) 0.0 else correct.toDouble() / total
}

/**
 * Generates and resumes the Club-only Marathon run — a 200-question graded endurance
 * test whose value is measured mastery, not volume (docs/CLUB-FEATURES-BUILD.md
 * "Feature 3"). The load-bearing new mechanic is RESUME ACROSS SESSIONS: at most one
 * [MarathonRun] exists at a time ([Store.marathonRun]), its ids are fixed at creation
 * from a stored seed (mirrors the Daily's deterministic rank-and-slice — [stableSeed]),
 * and every answer is persisted immediately ([record]) so a crash/quit never loses progress.
 * Android mirror of Apple's `Marathon.swift` / web's `Marathon` in store.js.
 */
object Marathon {
    const val DEFAULT_LENGTH = 200

    /** DEBUG-only test hook (BuildConfig.DEBUG-gated; set from MainActivity's
     *  `marathon_len` intent extra) so a run can be played to completion on the
     *  emulator. This only ever NARROWS the count below 200 — production (no override
     *  set) always sees the full 200. */
    var debugLengthOverride: Int? = null

    val runLength: Int
        get() {
            val override = if (BuildConfig.DEBUG) debugLengthOverride else null
            return if (override != null && override > 0) min(override, DEFAULT_LENGTH) else DEFAULT_LENGTH
        }

    /** The in-progress run, if any (at most one). */
    fun inProgress(store: Store): MarathonRun? = store.marathonRun()

    /** Start a fresh run, discarding any stale in-progress one first ("Start Over").
     *  The ids are fixed forever at creation from a fresh seed — a resume always
     *  continues into the SAME set. */
    fun startNew(store: Store): MarathonRun {
        store.clearMarathonRun()
        val seed = java.util.UUID.randomUUID().toString()
        val allIds = Corpus.allIds()
        val count = min(runLength, allIds.size)
        val ids = allIds
            .map { id -> stableSeed("marathon:$seed:$id") to id }
            .sortedWith(compareBy({ it.first }, { it.second }))
            .take(count)
            .map { it.second }
        val run = MarathonRun(seed, ids, 0, emptyList(), System.currentTimeMillis(), System.currentTimeMillis())
        store.saveMarathonRun(run)
        return run
    }

    /** The questions remaining for THIS session — from currentIndex to the end (what a
     *  resumed, or fresh, session actually loads into the engine). */
    fun resumeQuestions(run: MarathonRun): List<Question> =
        run.ids.drop(min(run.currentIndex, run.ids.size)).mapNotNull { Corpus.byId(it) }

    /** Persist one answer immediately — called after every submitted answer so a
     *  crash/quit never loses progress (the whole point of Marathon). Returns the
     *  updated run; [Store.saveMarathonRun] has already been written by the time this
     *  returns. */
    fun record(store: Store, run: MarathonRun, answer: MarathonAnswerRecord): MarathonRun {
        val results = run.results + answer
        val updated = run.copy(results = results, currentIndex = results.size, lastPlayedAt = System.currentTimeMillis())
        store.saveMarathonRun(updated)
        return updated
    }

    /** The run just reached its full length — write the permanent [MarathonScore]
     *  (difficulty-weighted score, correct/total, per-domain breakdown, duration) and
     *  clear the in-progress run. */
    fun finish(store: Store, run: MarathonRun): MarathonScore {
        val results = run.results
        val correct = results.count { it.correct }
        // A plain difficulty-weighted score (10 pts x difficulty per correct answer) —
        // transparent by construction, no hidden model (mirrors the Apple reference).
        val score = results.filter { it.correct }.sumOf { it.difficulty * 10 }
        val duration = max(1.0, (System.currentTimeMillis() - run.startedAt) / 1000.0)
        val domainBreakdown = ProgressMath.domains.map { domain ->
            val rows = results.filter { it.categoryId == domain }
            MarathonDomainStat(domain, rows.count { it.correct }, rows.size)
        }
        val entry = MarathonScore(System.currentTimeMillis(), score, correct, results.size, duration, domainBreakdown)
        store.appendMarathonScore(entry)
        store.clearMarathonRun()
        return entry
    }

    /** Past completed runs, most recent first — the permanent Marathon history. */
    fun history(store: Store): List<MarathonScore> = store.marathonHistory()

    /** A real, concrete illustration (MONETIZATION §4a: "a real preview, never a
     *  nag"). Marathon has no free-tier data to draw a genuine sample from (unlike
     *  Weak-Spot/Story Archive, which are built from ordinary free play) — so the
     *  non-member pitch is an honest, specific illustration of the scorecard (mirrors
     *  the Apple/web copy verbatim). */
    fun previewLine(): String =
        "See exactly where you stand — e.g. Geography 91% · History 64% — across a 200-question run you can pause and resume anytime."
}
