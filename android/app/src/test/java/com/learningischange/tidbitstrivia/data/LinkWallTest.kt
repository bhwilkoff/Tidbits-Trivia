package com.learningischange.tidbitstrivia.data

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * Link Wall generator verification (docs/CLUB-FEATURES-BUILD.md "Feature 6" Stage 1.5
 * quality gate) — Android side. Exercises the REAL `LinkWall.puzzle` against the
 * bundled match.json asset (parsed directly from disk — same repo-root-finding trick
 * as [DailyParityTest] — so this runs on the plain JVM, no Android Context/instrumentation
 * needed), for the same 4 spot-check dates used to cross-verify the Apple/web ports.
 * Asserts the content-clean-generator invariants: exactly 4 groups, exactly 4 members
 * each, all 16 tiles distinct, ascending difficulty order.
 */
class LinkWallTest {

    private val days = listOf("2026-07-22", "2026-09-15", "2026-12-25", "2026-11-11")

    private val repo: File by lazy {
        var dir: File? = File("").absoluteFile
        while (dir != null && !File(dir, "tools/daily-parity").isDirectory) dir = dir.parentFile
        requireNotNull(dir) { "repo root not found above ${File("").absolutePath}" }
    }

    /** Minimal match.json row parser — every row is Matching-shaped:
     *  [id, prompt, keys[], values[], categoryId, why, "", ""] (see JsonQuestionSet.load's
     *  Matching branch). Re-derives just enough of [Question] for LinkWall.puzzle. */
    private fun loadMatchQuestions(): List<Question> {
        val text = File(repo, "android/app/src/main/assets/match.json").readText()
        val rows = Json.parseToJsonElement(text).jsonObject["questions"]!!.jsonArray
        return rows.map { el ->
            val a = el.jsonArray
            val keys = a[2].jsonArray.map { it.jsonPrimitive.content }
            val values = a[3].jsonArray.map { it.jsonPrimitive.content }
            Question(
                id = a[0].jsonPrimitive.content, prompt = a[1].jsonPrimitive.content,
                options = keys, correctIndex = 0,
                categoryId = a[4].jsonPrimitive.content, difficulty = 3,
                explanation = a[5].jsonPrimitive.content, sourceTitle = "", sourceUrl = "",
                matching = MatchSpec(keys, values),
            )
        }
    }

    @Test fun cleanPuzzlePerDay() {
        val matchQuestions = loadMatchQuestions()
        assertTrue("match.json too small: ${matchQuestions.size}", matchQuestions.size > 100)

        val out = StringBuilder()
        for (day in days) {
            val puzzle = LinkWall.puzzle(day, matchQuestions)
            assertNotNull("no puzzle for $day", puzzle)
            puzzle!!
            assertEquals("wrong group count for $day", 4, puzzle.groups.size)
            puzzle.groups.forEach { g -> assertEquals("wrong member count for ${g.label} on $day", 4, g.members.size) }
            assertEquals("wrong tile count for $day", 16, puzzle.tiles.size)
            assertEquals("duplicate tiles for $day", 16, puzzle.tiles.toSet().size)
            // Ascending difficulty (yellow=1 easiest ... purple=4 hardest), the
            // Connections convention — LinkWall.puzzle sorts groups this way.
            val diffs = puzzle.groups.map { it.difficulty }
            assertEquals("groups not difficulty-ordered for $day", diffs.sorted(), diffs)

            out.append(day).append('\n')
            puzzle.groups.forEach { g ->
                out.append("  [${g.difficulty}] ${g.label}: ").append(g.members.joinToString(" · ")).append('\n')
            }
        }
        println(out)
    }
}
