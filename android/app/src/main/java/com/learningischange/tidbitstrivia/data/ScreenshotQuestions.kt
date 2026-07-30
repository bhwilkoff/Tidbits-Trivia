package com.learningischange.tidbitstrivia.data

/**
 * The screened question set used by store-screenshot runs (docs/STORE-SCREENSHOTS.md,
 * rule R-SHOT-3: **a store frame is never a random draw**). Kotlin mirror of
 * `Core/Store/ScreenshotQuestions.swift` and `StoreScreenshots.SafeQuestions` — the word
 * list and the selection rules are deliberately identical so no platform's listing can
 * regress on its own.
 *
 * Why: a random draw put a Holocaust question into the reveal slot, the single most-viewed
 * frame in a store listing. The owner has ruled that question fine IN THE APP (2026-07-30) —
 * the corpus covers hard history on purpose. This is purely a listing decision: a storefront
 * thumbnail is seen out of context by people who have not chosen to play.
 *
 * Screening alone wasn't enough: the selection also requires a Wikipedia-lead-style
 * explanation (a restatement teaches nothing in the slot whose whole job is showing you
 * learn something) and takes at most one question per category and per prompt-shape (an
 * id-ordered pool produced ten near-identical "which was born first?" questions).
 */
object ScreenshotQuestions {
    /** Keeps a question out of a STORE SCREENSHOT, not out of the app. Broad on purpose: a
     *  false positive costs one candidate out of thousands. */
    private val DISQUALIFYING = listOf(
        "nazi", "holocaust", "genocide", "massacre", "atrocit", "murder", "killed", "killing",
        "war crime", "execut", "slaver", "slave", "rape", "assassin", "terror", "suicide",
        "famine", "lynch", "torture", "concentration camp", "ethnic cleansing", "bomb",
        "casualt", "died", "death", "deaths", "fatal", "shot dead", "abuse",
    )

    fun isSafe(q: Question): Boolean {
        val haystack = (listOf(q.prompt) + q.options + listOf(q.explanation))
            .joinToString(" ").lowercase()
        return DISQUALIFYING.none { haystack.contains(it) }
    }

    private fun hasStory(q: Question): Boolean =
        q.explanation.length >= 80 &&
            (q.explanation.contains(" is a ") || q.explanation.contains(" was a "))

    /** [count] screened, varied questions in a stable order. */
    fun pick(pool: List<Question>, count: Int): List<Question> {
        val candidates = pool
            .filter(::isSafe)
            .filter(::hasStory)
            .filter { it.prompt.length >= 70 }
            .filter { !it.prompt.lowercase().startsWith("in what year") }
            .sortedBy { it.id }

        val chosen = mutableListOf<Question>()
        val usedCategories = mutableSetOf<String>()
        val usedShapes = mutableSetOf<String>()
        // Two passes: one-per-category first for spread, then fill by shape only.
        for (spreadPass in listOf(true, false)) {
            for (q in candidates) {
                if (chosen.size == count) break
                if (chosen.any { it.id == q.id }) continue
                val shape = q.prompt.take(24).lowercase()
                if (shape in usedShapes) continue
                if (spreadPass && q.categoryId in usedCategories) continue
                usedShapes += shape
                usedCategories += q.categoryId
                chosen += q
            }
        }
        return chosen
    }
}
