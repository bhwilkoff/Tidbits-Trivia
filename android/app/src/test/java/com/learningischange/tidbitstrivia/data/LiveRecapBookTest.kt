package com.learningischange.tidbitstrivia.data

import com.learningischange.tidbitstrivia.net.FirebaseNet
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** The wrap recap: nailed is the host's credit, once per question, a late score settles the last one. */
class LiveRecapBookTest {
    private fun pub(qid: String, phase: String, answer: String? = null, difficulty: Int? = null) = FirebaseNet.LivePub(
        round = 1, roundTitle = "R", qid = qid, qNum = 1, qTotal = 2, phase = phase, prompt = "Q $qid",
        options = null, format = "typeAnswer", answerIndex = null, answer = answer, difficulty = difficulty)

    @Test fun creditDecides() {
        val b = LiveRecapBook()
        b.observe(pub("r0q0", "question"), 0)
        b.observe(pub("r0q0", "reveal", "Keanu Reeves", 4), 0)
        b.observe(pub("r0q1", "question"), 3)
        b.observe(pub("r0q1", "reveal", "Warner Bros.", 2), 3)
        b.observe(pub("end", "ended"), 3); b.finish(3)
        assertEquals(listOf("r0q0"), b.tough.map { it.qid })
        assertEquals(listOf("r0q1"), b.toRemember.map { it.qid })
    }

    @Test fun onceAndLateScore() {
        val b = LiveRecapBook()
        b.observe(pub("r0q0", "question"), 0)
        b.observe(pub("r0q0", "reveal", "A", 5), 0)
        b.observe(pub("r0q0", "reveal", "A", 5), 0)
        b.observe(pub("end", "ended"), 0); b.finish(0)
        assertEquals(1, b.entries.size); assertTrue(b.tough.isEmpty())
        b.finish(2)
        assertEquals(1, b.tough.size); assertTrue(b.toRemember.isEmpty())
    }
}
