package com.learningischange.tidbitstrivia.data

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import kotlin.random.Random

/**
 * A saved quiz is the first user-authored object in Tidbits and it is shareable, so it
 * outlives the app version that wrote it and must decode identically on six platforms.
 * These pin docs/QUIZ-CONTRACT.md and assert against the SAME shared fixture the
 * Apple, Windows and web suites read — a drift here is a share link that opens a
 * different quiz on Android.
 */
class SavedQuizTest {

    private fun fixtureText(): String {
        var dir: File? = File(System.getProperty("user.dir") ?: ".").absoluteFile
        repeat(8) {
            val candidate = File(dir, "tools/quiz-wire/golden/quiz-v1.json")
            if (candidate.exists()) return candidate.readText().trim()
            dir = dir?.parentFile
        }
        throw AssertionError("shared quiz wire fixture not found")
    }

    private fun q(id: String) = Question(
        id = id, prompt = "prompt $id", options = listOf("a", "b", "c", "d"), correctIndex = 1,
        categoryId = "arts", difficulty = 3, explanation = "why $id",
        sourceTitle = "title $id", sourceUrl = "https://example.org/$id",
    )

    // MARK: the shared golden

    @Test
    fun `the shared fixture decodes to the expected quiz`() {
        val quiz = SavedQuiz.fromJson(fixtureText())
        assertNotNull(quiz)
        quiz!!
        assertEquals("k7m3qp9x2r", quiz.id)
        assertEquals("Jazz Legends", quiz.title)
        assertEquals("Jazz", quiz.topic)
        assertEquals("uid-1", quiz.creatorId)
        assertEquals("Ben", quiz.creatorName)
        assertEquals("mix", quiz.mode)
        assertEquals(1753900000000L, quiz.createdAtMs)
        assertEquals(3, quiz.entries.size)
        assertEquals("src:desc:Q1", (quiz.entries[0] as QuizEntry.Ref).id)
        val setRef = quiz.entries[2] as QuizEntry.SetRef
        assertEquals("picture", setRef.set)
        assertEquals("src:describe:Ornette_Coleman", setRef.id)
        val inline = (quiz.entries[1] as QuizEntry.Inline).question
        assertEquals("Which Texan city did the group form in?", inline.prompt)
        assertEquals(listOf("Houston", "Dallas", "Austin", "El Paso"), inline.options)
        assertEquals(0, inline.correctIndex)
    }

    /** Re-encoding must reproduce the fixture byte for byte. Two devices saving the
     *  same quiz produce identical bytes, which is what makes the "created or deleted,
     *  never edited in place" merge guard checkable rather than aspirational. */
    @Test
    fun `re-encoding reproduces the fixture exactly`() {
        val text = fixtureText()
        assertEquals(text, SavedQuiz.fromJson(text)!!.toJson())
    }

    /** The inline entry carries an apostrophe and a URL precisely so escaping is
     *  covered — a quiz about "Destiny's Child" must survive the round trip. */
    @Test
    fun `escaping survives the round trip`() {
        val quiz = SavedQuiz.fromJson(fixtureText())!!
        val inline = (quiz.entries[1] as QuizEntry.Inline).question
        assertEquals("Destiny's Child", inline.sourceTitle)
        assertTrue(inline.sourceUrl.contains("Destiny's_Child"))
    }

    // MARK: refs vs inline

    @Test
    fun `corpus questions become refs and live ones inline`() {
        val quiz = SavedQuiz.from(
            listOf(q("src:desc:Q1"), q("live:abc")),
            topic = "Jazz", creatorId = "uid-1", creatorName = "Ben",
        )
        assertTrue(quiz.entries[0] is QuizEntry.Ref)
        assertTrue(quiz.entries[1] is QuizEntry.Inline)
    }

    /** A question's SHAPE identifies its set, so provenance survives without being
     *  threaded through every call site. */
    @Test
    fun `a bundled question is saved as a set ref not a bare ref`() {
        val picture = q("src:describe:Tito").copy(imageUrl = "https://example.org/p.jpg")
        val quiz = SavedQuiz.from(
            listOf(picture, q("src:desc:Q1")),
            topic = "Jazz", creatorId = "uid-1", creatorName = "Ben",
        )
        assertEquals("picture", (quiz.entries[0] as QuizEntry.SetRef).set)
        assertTrue(quiz.entries[1] is QuizEntry.Ref)
    }

    /** The regression: the corpus holds a DIFFERENT question under the same ID, and
     *  it must never be served in the bundled question's place. */
    @Test
    fun `a set ref never falls back to the colliding corpus row`() {
        val quiz = SavedQuiz.fromJson(fixtureText())!!
        val r = quiz.resolve(lookup = { q(it) })
        assertEquals(1, r.missing)          // the set ref stays missing
        assertEquals(2, r.questions.size)   // corpus ref + inline only
    }

    @Test
    fun `a set ref resolves from its own set`() {
        val quiz = SavedQuiz.fromJson(fixtureText())!!
        val r = quiz.resolve(
            lookup = { null },
            setLookup = { set, id -> if (set == "picture") q(id).copy(prompt = "Who is this?") else null },
        )
        assertEquals(1, r.missing)          // only the corpus ref, which has no lookup here
        assertTrue(r.questions.any { it.prompt == "Who is this?" })
    }

    /** A quiz must stay small enough to sync and share for free — refs are what make
     *  that true. */
    @Test
    fun `a ref-only quiz is under a kilobyte`() {
        val quiz = SavedQuiz.from(
            (0 until 20).map { q("src:desc:Q$it") },
            topic = "Space", creatorId = "uid-1", creatorName = "Ben",
        )
        assertTrue(quiz.toJson().length < 1024)
    }

    // MARK: leniency

    @Test
    fun `unknown keys are ignored rather than failing`() {
        val text = fixtureText().trimEnd('}') + ",\"fromV2\":{\"a\":1}}"
        val quiz = SavedQuiz.fromJson(text)
        assertNotNull(quiz)
        assertEquals(3, quiz!!.entries.size)
    }

    @Test
    fun `a malformed entry is skipped not fatal`() {
        val quiz = SavedQuiz.fromJson("""{"id":"abc","by":"u","qs":["src:a",42,["short"],{"s":"picture"},"pic:b"]}""")
        assertEquals(2, quiz!!.entries.size)   // the set-ref missing its `i` is skipped
    }

    @Test
    fun `a quiz with no id or questions is rejected`() {
        assertNull(SavedQuiz.fromJson("""{"by":"u","qs":["a"]}"""))
        assertNull(SavedQuiz.fromJson("""{"id":"abc","by":"u"}"""))
        assertNull(SavedQuiz.fromJson("not json at all"))
    }

    // MARK: resolving — the degrade path

    @Test
    fun `missing refs are reported not substituted`() {
        val quiz = SavedQuiz.from(
            (0 until 8).map { q("src:desc:Q$it") },
            topic = "Space", creatorId = "uid-1", creatorName = "Ben",
        )
        val known = setOf("src:desc:Q0", "src:desc:Q1", "src:desc:Q2", "src:desc:Q3", "src:desc:Q4")
        val r = quiz.resolve { if (it in known) q(it) else null }
        assertEquals(5, r.questions.size)
        assertEquals(3, r.missing)
        assertTrue(r.isPlayable)
        assertFalse(r.isComplete)
    }

    @Test
    fun `too few resolved refs is not playable`() {
        val quiz = SavedQuiz.from(
            (0 until 8).map { q("src:desc:Q$it") },
            topic = "Space", creatorId = "uid-1", creatorName = "Ben",
        )
        assertFalse(quiz.resolve { if (it == "src:desc:Q0") q(it) else null }.isPlayable)
    }

    /** An inline question needs no lookup at all — that is the point of carrying it. */
    @Test
    fun `inline questions survive without the corpus`() {
        val r = SavedQuiz.fromJson(fixtureText())!!.resolve { null }
        assertEquals(1, r.questions.size)
        assertEquals("Which Texan city did the group form in?", r.questions[0].prompt)
        assertEquals(2, r.missing)
    }

    // MARK: ids and titles

    /** The alphabet drops 0/o, 1/l/i and u so an ID read aloud in a pub or typed off a
     *  projector is unambiguous, and a random ID can't spell something unfortunate. */
    @Test
    fun `ids avoid ambiguous characters and are unique`() {
        val rng = Random(7)
        val ids = (0 until 500).map { SavedQuiz.makeId(rng) }
        ids.forEach { id ->
            assertEquals(10, id.length)
            assertTrue(id.all { it in SavedQuiz.ID_ALPHABET })
            assertFalse(id.any { it in "01loiu" })
        }
        assertEquals(ids.size, ids.toSet().size)
    }

    @Test
    fun `titles are trimmed capped and never empty`() {
        assertEquals("Jazz", SavedQuiz.cleanTitle("  Jazz  "))
        assertEquals("Untitled quiz", SavedQuiz.cleanTitle("   "))
        assertEquals("Untitled quiz", SavedQuiz.cleanTitle(null))
        assertEquals(60, SavedQuiz.cleanTitle("x".repeat(200)).length)
    }

    @Test
    fun `a quiz with no title falls back to its topic`() {
        val quiz = SavedQuiz.from(
            listOf(q("src:desc:Q1")), topic = "Volcanoes",
            creatorId = "uid-1", creatorName = "Ben",
        )
        assertEquals("Volcanoes", quiz.title)
    }
}
