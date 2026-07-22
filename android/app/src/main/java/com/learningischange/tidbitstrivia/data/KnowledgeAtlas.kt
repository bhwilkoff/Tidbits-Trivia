package com.learningischange.tidbitstrivia.data

import java.util.Calendar

/**
 * Feature 4 — Knowledge Atlas (docs/CLUB-FEATURES-BUILD.md). A transparent, interpreted
 * layer over the SAME per-game rows the free Topic Levels / Pie already read
 * (`Store.Rec.categoryId/correct/total`, `ProgressMath.domains`) — additive, never a lock
 * on what's already free (R-MON-1). PURE DERIVATION, no new persistence: Android's
 * `Store.Rec` has carried a game-level epoch (`at`, defaulted to `System.currentTimeMillis()`
 * at write time) since the original Records-history feature — no schema change needed here,
 * unlike the web/Apple ports which had to add it. No opaque "mastery score": every number
 * below is a plain count. Android mirror of Apple's `KnowledgeAtlas.swift` / web's
 * `KnowledgeAtlas` in store.js.
 *
 * A handful of very old persisted records could in principle predate a reliable `at`
 * (`Store.records()` defaults a missing value to `0L`); those are treated as older than
 * the trailing-12-month window — same as any record that's genuinely that old — so they
 * drop out of the Atlas's month math but keep feeding the free lifetime Pie/Levels via
 * [Store.progress] untouched.
 */
object KnowledgeAtlas {
    /** Below this many answers in a window, a read is withheld rather than shown noisy —
     *  "don't flag a domain with <8 answers" (design spec). */
    const val sampleFloor = 8
    /** A domain counts as "strong" in the decay radar's older window at this accuracy or higher. */
    const val strongThreshold = 0.70
    /** A drop of at least this many accuracy points (0..1 scale) counts as decaying, both
     *  for the per-domain trajectory flag and the radar. */
    const val decayDelta = 0.12

    /** One domain's trailing-12-month standing. [recentAccuracy]/[priorAccuracy] are
     *  this-quarter (months 0-2) vs the quarter before (months 3-5); either is null below
     *  [sampleFloor] — an honest "not enough history yet" rather than a noisy arrow. */
    data class DomainAtlasEntry(
        val categoryId: String,
        val correct: Int,
        val total: Int,
        val recentAccuracy: Double?,
        val priorAccuracy: Double?,
    ) {
        val accuracy: Double get() = if (total == 0) 0.0 else correct.toDouble() / total
        val sampleSize: Int get() = total
        /** Recent-quarter minus prior-quarter accuracy, in points (0..1 scale). Null when
         *  either quarter is too thin to read. */
        val trajectoryDelta: Double? get() =
            if (recentAccuracy != null && priorAccuracy != null) recentAccuracy - priorAccuracy else null
        val isDecaying: Boolean get() = (trajectoryDelta ?: 0.0) <= -decayDelta
    }

    /** A domain that was strong 6+ months ago and has since declined — the Decay radar's
     *  "shore it up" list. */
    data class DecayEntry(val categoryId: String, val pastAccuracy: Double, val recentAccuracy: Double) {
        val delta: Double get() = recentAccuracy - pastAccuracy
    }

    private data class Row(val categoryId: String, val correct: Int, val total: Int, val monthsAgo: Int)

    /** Per-domain trailing-12-month standing, domains never played omitted (same
     *  convention as [Store.progress] for the free Pie/Levels). */
    fun domains(store: Store): List<DomainAtlasEntry> {
        val rows = trailingYearRows(store)
        return ProgressMath.domains.mapNotNull { id ->
            val mine = rows.filter { it.categoryId == id }
            if (mine.isEmpty()) return@mapNotNull null
            val correct = mine.sumOf { it.correct }
            val total = mine.sumOf { it.total }
            DomainAtlasEntry(
                categoryId = id, correct = correct, total = total,
                recentAccuracy = quarterAccuracy(mine, 0, 2),
                priorAccuracy = quarterAccuracy(mine, 3, 5),
            )
        }.sortedByDescending { it.total }
    }

    /** Domains strong (>=[strongThreshold]) 6-11 months ago that have since dropped by
     *  >=[decayDelta] in the last 6 months — both windows honest about sample size. */
    fun decayRadar(store: Store): List<DecayEntry> {
        val rows = trailingYearRows(store)
        return ProgressMath.domains.mapNotNull { id ->
            val mine = rows.filter { it.categoryId == id }
            val past = quarterAccuracy(mine, 6, 11) ?: return@mapNotNull null
            val recent = quarterAccuracy(mine, 0, 5) ?: return@mapNotNull null
            if (past < strongThreshold || recent > past - decayDelta) return@mapNotNull null
            DecayEntry(id, past, recent)
        }.sortedBy { it.delta }
    }

    /** A genuine strongest + weakest domain for the non-member teaser (MONETIZATION §4a:
     *  "a real preview, never a nag"). Null until the player has enough history for at
     *  least one honest read. */
    fun previewLine(store: Store): String? {
        val ds = domains(store).filter { it.total >= 3 }.sortedBy { it.accuracy }
        val weakest = ds.firstOrNull() ?: return null
        val wPct = Math.round(weakest.accuracy * 100)
        val wName = Category.byId(weakest.categoryId).name
        val strongest = ds.lastOrNull()
        if (strongest == null || strongest.categoryId == weakest.categoryId) {
            return "$wPct% in $wName so far — Club maps every domain across 12 months and shows what's rising or drifting."
        }
        val sPct = Math.round(strongest.accuracy * 100)
        val sName = Category.byId(strongest.categoryId).name
        return "$sPct% in $sName, $wPct% in $wName — Club maps everything you know and where it's drifting."
    }

    // MARK: - Month bucketing

    private fun monthsAgo(at: Long, now: Long = System.currentTimeMillis()): Int {
        if (at <= 0L) return Int.MAX_VALUE
        val then = Calendar.getInstance().apply { timeInMillis = at }
        val today = Calendar.getInstance().apply { timeInMillis = now }
        val months = (today.get(Calendar.YEAR) - then.get(Calendar.YEAR)) * 12 +
            (today.get(Calendar.MONTH) - then.get(Calendar.MONTH))
        return maxOf(0, months)
    }

    private fun trailingYearRows(store: Store): List<Row> =
        store.records()
            .map { Row(it.categoryId, it.correct, it.total, monthsAgo(it.at)) }
            .filter { it.monthsAgo <= 11 }

    private fun quarterAccuracy(rows: List<Row>, lo: Int, hi: Int): Double? {
        val mine = rows.filter { it.monthsAgo in lo..hi }
        val total = mine.sumOf { it.total }
        if (total < sampleFloor) return null
        val correct = mine.sumOf { it.correct }
        return correct.toDouble() / total
    }
}
