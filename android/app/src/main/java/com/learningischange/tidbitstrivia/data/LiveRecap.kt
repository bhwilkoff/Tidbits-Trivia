package com.learningischange.tidbitstrivia.data

import com.learningischange.tidbitstrivia.net.FirebaseNet

/**
 * What a joiner keeps of a live night so the wrap can teach (LIVE-ROOM-CONTRACT
 * "answer + difficulty", 2026-09-09): one entry per revealed question, with the
 * score before it was asked and after it was scored. "Nailed" is decided by the
 * SCORE, not by re-deriving the answer — the host is the scorer, and a typed
 * answer accepted by hand still counts. Mirrors Swift LiveRecapBook / js/liverecap.js.
 */
data class LiveRecapEntry(
    val qid: String, val prompt: String, val answer: String?, val difficulty: Int?,
    val story: String?, val sourceTitle: String?, val sourceUrl: String?,
    val before: Int, var after: Int? = null,
) {
    val nailed: Boolean get() = (after ?: before) > before
    val tough: Boolean get() = nailed && (difficulty ?: 0) >= 4
}

class LiveRecapBook {
    val entries = mutableListOf<LiveRecapEntry>()
    private var openQid: String? = null
    private var scoreAtQuestion = 0

    /** A pub arrived; `score` is the joiner's score right now. */
    fun observe(p: FirebaseNet.LivePub?, score: Int) {
        if (p == null) return
        if (p.qid != openQid) { close(score); openQid = p.qid; scoreAtQuestion = score }
        if (p.phase == "reveal" && entries.none { it.qid == p.qid }) {
            entries += LiveRecapEntry(p.qid, p.prompt, p.answer, p.difficulty, p.story,
                p.source?.title, p.source?.url, scoreAtQuestion)
        }
    }

    /** The night ended, or a score landed at the wrap: settle the last question. */
    fun finish(score: Int) {
        close(score)
        entries.lastOrNull()?.let { it.after = maxOf(it.after ?: score, score) }   // a late score write belongs to the last question
    }

    private fun close(score: Int) {
        entries.firstOrNull { it.qid == openQid && it.after == null }?.after = score
    }

    val tough: List<LiveRecapEntry> get() = entries.filter { it.tough }
    val toRemember: List<LiveRecapEntry> get() = entries.filter { !it.nailed && !it.answer.isNullOrEmpty() }

    companion object {
        fun howDidYouKnowText(e: LiveRecapEntry) =
            "I knew \"${e.prompt}\" at trivia night — it's ${e.answer ?: ""}. How did YOU know that? 🧠"
    }
}
