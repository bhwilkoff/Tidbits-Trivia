package com.learningischange.tidbitstrivia.data

import android.text.format.DateUtils

/**
 * Builds the Tidbits Club EXCLUSIVE Weak-Spot Arena round entirely from the
 * player's own miss history ([Store.missDetails]) — the deeper layer above the
 * free spaced-review weave ([Store.dueReview], PARITY row 214). Transparent by
 * construction: every question carries a plain-language "why you're seeing
 * this" reason, never an opaque model (docs/CLUB-FEATURES-BUILD.md "Feature 1").
 * Android mirror of Apple's `WeakSpotArena.swift` / web's `WeakSpotArena` in
 * `store.js`.
 */
object WeakSpotArena {
    const val ROUND_SIZE = 10
    /** Below this many true misses, the round is topped up from weak categories. */
    const val TRUE_MISS_FLOOR = 4
    /** Target size when topping up with category-fill (not the full 10 — a round
     *  mostly "shoring up X" stops being a *weak-spot* arena). */
    const val FILL_TARGET = 8
    /** Below this many built questions, the caller shows the empty state instead
     *  of starting a round (mirrors iOS/web's ">= 2" floor). */
    const val PLAYABLE_FLOOR = 2

    /** Build one round. Never throws; a thin history just yields a short
     *  (possibly empty) round — the caller shows the "play a few rounds first"
     *  empty state below [PLAYABLE_FLOOR]. */
    fun build(store: Store): WeakSpotRound {
        val misses = store.missDetails()
        val questions = mutableListOf<Question>()
        val reasons = mutableMapOf<String, String>()
        val pickedIds = mutableSetOf<String>()

        for (m in misses) {
            if (questions.size >= ROUND_SIZE) break
            if (m.id in pickedIds) continue
            val q = Corpus.byId(m.id) ?: continue
            questions.add(q)
            pickedIds.add(m.id)
            reasons[q.id] = "Missed ${relative(m.lastSeen)} · ×${m.missCount}"
        }
        val trueMissCount = questions.size

        if (trueMissCount < TRUE_MISS_FLOOR) {
            val weakest = store.progress().filter { it.total >= 3 }
                .sortedBy { if (it.total == 0) 0.0 else it.correct.toDouble() / it.total }
            for (domain in weakest) {
                if (questions.size >= FILL_TARGET) break
                val pool = Corpus.pull(domain.id, pickedIds, FILL_TARGET - questions.size)
                for (q in pool) {
                    if (questions.size >= FILL_TARGET) break
                    if (q.id in pickedIds) continue
                    questions.add(q)
                    pickedIds.add(q.id)
                    reasons[q.id] = "Shoring up ${Category.byId(domain.id).name}"
                }
            }
        }
        return WeakSpotRound(questions, reasons, trueMissCount)
    }

    /** A genuine one-line sample from the player's own misses (MONETIZATION §4a:
     *  "a real preview, never a nag") — the non-member Home-card pitch. Null once
     *  there's no local miss to show (an honest static line covers that case). */
    fun previewLine(store: Store): String? {
        val top = store.missDetails().firstOrNull() ?: return null
        val q = Corpus.byId(top.id) ?: return null
        return "Missed: “${q.prompt}” — Club turns misses like this into a round."
    }

    private fun relative(lastSeen: Long): String {
        if (lastSeen <= 0L) return "a while back"
        return DateUtils.getRelativeTimeSpanString(lastSeen, System.currentTimeMillis(), DateUtils.MINUTE_IN_MILLIS).toString()
    }
}

/** One generated Weak-Spot round: the questions, a why-you're-seeing-this
 *  reason per question ID, and how many are true misses (vs. category-fill) —
 *  the count the round stays honest about its make-up with. */
data class WeakSpotRound(val questions: List<Question>, val reasons: Map<String, String>, val missCount: Int)
